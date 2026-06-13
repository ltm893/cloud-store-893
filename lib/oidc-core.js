const crypto = require('crypto');
const { jwtVerify, createLocalJWKSet } = require('jose');
const { parseCookies } = require('./session-cookies');
const { normalizeGroups } = require('./login-approval');
const { createOidcFlow, getOidcFlow, deleteOidcFlow } = require('./oidc-flow-store');

const discoveryCache = new Map();
const jwksDocCache = new Map();

function appPublicUrl() {
  const raw = process.env.APP_PUBLIC_URL || `http://127.0.0.1:${process.env.PORT || 3000}`;
  return raw.replace(/\/$/, '');
}

function publicUrlFromRequestEnabled() {
  const raw = String(process.env.APP_PUBLIC_URL_FROM_REQUEST || '').toLowerCase();
  return raw === 'true' || raw === '1' || raw === 'yes';
}

/** Use Host header for OAuth redirect_uri when APP_PUBLIC_URL_FROM_REQUEST=true (OCI ephemeral IP). */
function resolveAppPublicUrl(req) {
  if (publicUrlFromRequestEnabled() && req) {
    const host = req.get('host');
    if (host) {
      const protoHeader = req.headers['x-forwarded-proto'];
      const proto = protoHeader
        ? String(protoHeader).split(',')[0].trim()
        : req.secure
          ? 'https'
          : 'http';
      return `${proto}://${host}`.replace(/\/$/, '');
    }
  }
  return appPublicUrl();
}

function allowPinWithIdp() {
  const raw = String(process.env.IDP_ALLOW_PIN ?? 'true').toLowerCase();
  return raw !== 'false' && raw !== '0';
}

/**
 * @param {'POS'|'ADMIN'} role
 * @param {string} defaultRedirectUri
 */
function loadClientConfig(role, defaultRedirectUri) {
  const issuer =
    process.env[`IDP_${role}_ISSUER`] ||
    (role === 'POS' ? process.env.IDP_ISSUER : null);
  const clientId = process.env[`IDP_${role}_CLIENT_ID`];
  const clientSecret = process.env[`IDP_${role}_CLIENT_SECRET`];
  if (!issuer || !clientId || !clientSecret) return null;

  const redirectUri =
    process.env[`IDP_${role}_REDIRECT_URI`] ||
    defaultRedirectUri;

  return {
    role,
    issuer: issuer.replace(/\/$/, ''),
    clientId,
    clientSecret,
    redirectUri,
  };
}

function isPosIdpEnabled() {
  return loadClientConfig('POS', `${appPublicUrl()}/oauth/callback`) !== null;
}

function isAdminIdpEnabled() {
  return loadClientConfig('ADMIN', `${appPublicUrl()}/oauth/admin/callback`) !== null;
}

async function discover(issuer) {
  const cached = discoveryCache.get(issuer);
  if (cached && cached.expires > Date.now()) return cached.doc;

  const url = `${issuer}/.well-known/openid-configuration`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`OIDC discovery failed (${res.status})`);
  const doc = await res.json();
  discoveryCache.set(issuer, { doc, expires: Date.now() + 60 * 60 * 1000 });
  return doc;
}

async function fetchJwksDocument(jwksUri, accessToken) {
  const headers = {};
  if (accessToken) {
    headers.Authorization = `Bearer ${accessToken}`;
  }
  const res = await fetch(jwksUri, { headers });
  if (!res.ok) {
    const detail = await res.text().catch(() => '');
    throw new Error(
      `JWKS HTTP ${res.status}${detail ? `: ${detail.slice(0, 200)}` : ''}`,
    );
  }
  return res.json();
}

/**
 * Oracle IDCS JWKS often includes key_ops ["encrypt","verify"]. Node Web Crypto rejects
 * importing RSASSA-PKCS1-v1_5 keys with "encrypt" in key_ops — strip so jose derives verify-only.
 */
function sanitizeJwksForSignatureVerify(doc) {
  if (!doc || !Array.isArray(doc.keys)) return doc;
  return {
    keys: doc.keys
      .filter((jwk) => jwk && jwk.use !== 'enc')
      .map((jwk) => {
        const clean = { ...jwk };
        delete clean.key_ops;
        if (clean.use && clean.use !== 'sig') {
          delete clean.use;
        }
        return clean;
      }),
  };
}

/**
 * Oracle IDCS often returns 401 on jwks_uri unless the tenant enables public
 * "Access Signing Certificate" or the caller sends Authorization: Bearer <access_token>.
 */
async function getSigningKeys(jwksUri, accessToken) {
  const cached = jwksDocCache.get(jwksUri);
  if (cached && cached.expires > Date.now()) {
    return createLocalJWKSet(cached.doc);
  }

  let doc;
  try {
    doc = await fetchJwksDocument(jwksUri, accessToken);
  } catch (authErr) {
    if (accessToken) {
      try {
        doc = await fetchJwksDocument(jwksUri);
      } catch {
        throw authErr;
      }
    } else {
      throw new Error(
        `${authErr.message}. Oracle IDCS: enable Settings → Default Settings → Access Signing Certificate, or ensure the token response includes access_token.`,
      );
    }
  }

  jwksDocCache.set(jwksUri, { doc: sanitizeJwksForSignatureVerify(doc), expires: Date.now() + 60 * 60 * 1000 });
  return createLocalJWKSet(jwksDocCache.get(jwksUri).doc);
}

/** If ID token lacks groups, try Oracle userinfo (needs groups scope + IdCS claim config). */
async function enrichClaimsWithGroups(cfg, claims, accessToken) {
  if (normalizeGroups(claims).length > 0) return claims;
  if (!accessToken) return claims;

  const doc = await discover(cfg.issuer);
  if (!doc.userinfo_endpoint) return claims;

  const res = await fetch(doc.userinfo_endpoint, {
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!res.ok) {
    console.error(`userinfo failed (${res.status})`);
    return claims;
  }

  const userinfo = await res.json();
  const groups = normalizeGroups(userinfo);
  if (!groups.length) return claims;
  return { ...claims, groups };
}

async function buildAuthorizeUrl(cfg, { state, nonce, prompt } = {}) {
  const doc = await discover(cfg.issuer);
  const params = new URLSearchParams({
    client_id: cfg.clientId,
    response_type: 'code',
    redirect_uri: cfg.redirectUri,
    scope: process.env.IDP_SCOPES || 'openid profile email groups',
    state,
    nonce,
  });
  const promptValue =
    prompt ||
    (cfg.role === 'ADMIN'
      ? process.env.IDP_ADMIN_PROMPT
      : process.env.IDP_POS_PROMPT) ||
    '';
  if (String(promptValue).trim()) {
    params.set('prompt', String(promptValue).trim());
  }
  return `${doc.authorization_endpoint}?${params}`;
}

async function exchangeCode(cfg, code) {
  const doc = await discover(cfg.issuer);
  const body = new URLSearchParams({
    grant_type: 'authorization_code',
    code,
    redirect_uri: cfg.redirectUri,
    client_id: cfg.clientId,
    client_secret: cfg.clientSecret,
  });

  const res = await fetch(doc.token_endpoint, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  });

  if (!res.ok) {
    const detail = await res.text().catch(() => '');
    throw new Error(`Token exchange failed (${res.status})${detail ? `: ${detail}` : ''}`);
  }
  return res.json();
}

async function verifyJwt(cfg, token, { idToken = false, accessToken } = {}) {
  const doc = await discover(cfg.issuer);
  const jwks = await getSigningKeys(doc.jwks_uri, accessToken);
  // Oracle IDCS: discovery "issuer" is https://identity.oraclecloud.com/
  // while IDP_*_ISSUER is the idcs host used to fetch discovery.
  const tokenIssuer = doc.issuer || cfg.issuer;
  const issuers = [tokenIssuer, cfg.issuer].filter(
    (v, i, arr) => v && arr.indexOf(v) === i,
  );
  const { payload } = await jwtVerify(token, jwks, { issuer: issuers });
  if (idToken) {
    const aud = payload.aud;
    const audOk = Array.isArray(aud)
      ? aud.includes(cfg.clientId)
      : aud === cfg.clientId;
    const azpOk = payload.azp === cfg.clientId;
    if (!audOk && !azpOk) {
      throw new Error(
        `Unexpected JWT audience (aud=${JSON.stringify(aud)}, azp=${payload.azp || ''}, expected ${cfg.clientId})`,
      );
    }
  }
  return payload;
}

function signInFailureMessage(err) {
  const debug = String(process.env.IDP_SIGNIN_DEBUG || '').toLowerCase();
  if (debug === 'true' || debug === '1' || debug === 'yes') {
    return `Sign-in failed: ${err.message}`;
  }
  return 'Sign-in failed';
}

function flowCookieName(role) {
  return `oidc_${role.toLowerCase()}_flow`;
}

function parseFlowCookie(req, role) {
  const raw = parseCookies(req)[flowCookieName(role)];
  if (!raw) return null;
  try {
    return JSON.parse(Buffer.from(raw, 'base64url').toString('utf8'));
  } catch {
    return null;
  }
}

function setFlowCookie(res, role, data) {
  const val = Buffer.from(JSON.stringify(data), 'utf8').toString('base64url');
  const secure = String(process.env.CASHIER_SESSION_SECURE || '').toLowerCase() === 'true';
  res.setHeader(
    'Set-Cookie',
    `${flowCookieName(role)}=${val}; Path=/; HttpOnly; SameSite=Lax; Max-Age=600${secure ? '; Secure' : ''}`,
  );
}

function clearFlowCookie(res, role) {
  const secure = String(process.env.CASHIER_SESSION_SECURE || '').toLowerCase() === 'true';
  res.setHeader(
    'Set-Cookie',
    `${flowCookieName(role)}=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0${secure ? '; Secure' : ''}`,
  );
}

function newState() {
  return crypto.randomBytes(16).toString('hex');
}

function newNonce() {
  return crypto.randomBytes(16).toString('hex');
}

function callbackPathFromRedirectUri(redirectUri) {
  const pathname = new URL(redirectUri).pathname;
  return pathname || '/';
}

function resolveOidcFlow(req, role, stateParam) {
  const state = String(stateParam || '').trim();
  if (!state) return null;

  const fromCookie = parseFlowCookie(req, role);
  if (fromCookie?.state === state) return fromCookie;

  return getOidcFlow(state);
}

function createOidcCallbackHandler({ cfg, successRedirect, onAuthenticated }) {
  return async (req, res) => {
    const errParam = req.query.error;
    if (errParam) {
      clearFlowCookie(res, cfg.role);
      deleteOidcFlow(req.query.state);
      return res.status(401).send(`Sign-in cancelled: ${errParam}`);
    }

    const stateParam = String(req.query.state || '');
    const flow = resolveOidcFlow(req, cfg.role, stateParam);
    clearFlowCookie(res, cfg.role);
    deleteOidcFlow(stateParam);
    if (!flow || flow.state !== stateParam) {
      return res.status(400).send('Invalid sign-in state');
    }

    const code = req.query.code;
    if (!code) return res.status(400).send('Missing authorization code');

    try {
      const tokens = await exchangeCode(cfg, String(code));
      if (!tokens.id_token) throw new Error('No id_token in token response');
      const claims = await enrichClaimsWithGroups(
        cfg,
        await verifyJwt(cfg, tokens.id_token, {
          idToken: true,
          accessToken: tokens.access_token,
        }),
        tokens.access_token,
      );
      if (claims.nonce && claims.nonce !== flow.nonce) {
        throw new Error('Invalid ID token nonce');
      }
      await onAuthenticated(req, res, { claims, tokens, flow });
      if (res.headersSent) return;
      return res.redirect(302, successRedirect);
    } catch (err) {
      console.error(err.message);
      return res.status(500).send(signInFailureMessage(err));
    }
  };
}

/**
 * Register browser OIDC login + callback for one client (POS or ADMIN).
 */
function registerOidcBrowserFlow(app, {
  getCfg,
  loginPath,
  callbackPath,
  successRedirect,
  onAuthenticated,
}) {
  app.get(loginPath, async (req, res) => {
    try {
      const cfg = getCfg(req);
      if (!cfg) return res.status(500).send('OIDC is not configured');
      const state = newState();
      const nonce = newNonce();
      const clientKind =
        typeof req.query.client_kind === 'string' ? req.query.client_kind.trim() : null;
      const registerId =
        typeof req.query.register_id === 'string' ? req.query.register_id.trim() : null;
      const flow = { state, nonce, clientKind, registerId };
      createOidcFlow(flow);
      setFlowCookie(res, cfg.role, flow);
      const prompt =
        typeof req.query.prompt === 'string' ? req.query.prompt : undefined;
      const url = await buildAuthorizeUrl(cfg, { state, nonce, prompt });
      return res.redirect(302, url);
    } catch (err) {
      console.error(err.message);
      return res.status(500).send('OIDC login failed to start');
    }
  });

  const handleCallback = async (req, res) => {
    const cfg = getCfg(req);
    if (!cfg) return res.status(500).send('OIDC is not configured');
    return createOidcCallbackHandler({ cfg, successRedirect, onAuthenticated })(req, res);
  };
  const path = callbackPath;

  if (path === '/') {
    app.get('/', (req, res, next) => {
      if (req.query.code) return handleCallback(req, res);
      return next();
    });
  } else {
    app.get(path, handleCallback);
  }
}

async function verifyBearer(cfg, authorizationHeader) {
  if (!authorizationHeader || !authorizationHeader.startsWith('Bearer ')) return null;
  const token = authorizationHeader.slice(7).trim();
  if (!token) return null;
  try {
    return await verifyJwt(cfg, token, { idToken: false, accessToken: token });
  } catch {
    return null;
  }
}

module.exports = {
  appPublicUrl,
  resolveAppPublicUrl,
  publicUrlFromRequestEnabled,
  allowPinWithIdp,
  loadClientConfig,
  isPosIdpEnabled,
  isAdminIdpEnabled,
  callbackPathFromRedirectUri,
  registerOidcBrowserFlow,
  signInFailureMessage,
  verifyBearer,
};
