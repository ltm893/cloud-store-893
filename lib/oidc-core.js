const crypto = require('crypto');
const { jwtVerify, createRemoteJWKSet } = require('jose');
const { parseCookies } = require('./session-cookies');

const discoveryCache = new Map();
const jwksCache = new Map();

function appPublicUrl() {
  const raw = process.env.APP_PUBLIC_URL || `http://127.0.0.1:${process.env.PORT || 3000}`;
  return raw.replace(/\/$/, '');
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

function getJwks(jwksUri) {
  let set = jwksCache.get(jwksUri);
  if (!set) {
    set = createRemoteJWKSet(new URL(jwksUri));
    jwksCache.set(jwksUri, set);
  }
  return set;
}

async function buildAuthorizeUrl(cfg, { state, nonce }) {
  const doc = await discover(cfg.issuer);
  const params = new URLSearchParams({
    client_id: cfg.clientId,
    response_type: 'code',
    redirect_uri: cfg.redirectUri,
    scope: process.env.IDP_SCOPES || 'openid profile email',
    state,
    nonce,
  });
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

async function verifyJwt(cfg, token, { idToken = false } = {}) {
  const doc = await discover(cfg.issuer);
  const jwks = getJwks(doc.jwks_uri);
  const { payload } = await jwtVerify(token, jwks, {
    issuer: cfg.issuer,
    audience: idToken ? cfg.clientId : undefined,
  });
  return payload;
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

function createOidcCallbackHandler({ cfg, successRedirect, onAuthenticated }) {
  return async (req, res) => {
    const errParam = req.query.error;
    if (errParam) {
      clearFlowCookie(res, cfg.role);
      return res.status(401).send(`Sign-in cancelled: ${errParam}`);
    }

    const flow = parseFlowCookie(req, cfg.role);
    clearFlowCookie(res, cfg.role);
    if (!flow || req.query.state !== flow.state) {
      return res.status(400).send('Invalid sign-in state');
    }

    const code = req.query.code;
    if (!code) return res.status(400).send('Missing authorization code');

    try {
      const tokens = await exchangeCode(cfg, String(code));
      if (!tokens.id_token) throw new Error('No id_token in token response');
      const claims = await verifyJwt(cfg, tokens.id_token, { idToken: true });
      if (claims.nonce && claims.nonce !== flow.nonce) {
        throw new Error('Invalid ID token nonce');
      }
      await onAuthenticated(req, res, { claims, tokens });
      return res.redirect(302, successRedirect);
    } catch (err) {
      console.error(err.message);
      return res.status(500).send('Sign-in failed');
    }
  };
}

/**
 * Register browser OIDC login + callback for one client (POS or ADMIN).
 */
function registerOidcBrowserFlow(app, {
  cfg,
  loginPath,
  callbackPath,
  successRedirect,
  onAuthenticated,
}) {
  app.get(loginPath, async (req, res) => {
    try {
      const state = newState();
      const nonce = newNonce();
      setFlowCookie(res, cfg.role, { state, nonce });
      const url = await buildAuthorizeUrl(cfg, { state, nonce });
      return res.redirect(302, url);
    } catch (err) {
      console.error(err.message);
      return res.status(500).send('OIDC login failed to start');
    }
  });

  const handleCallback = createOidcCallbackHandler({ cfg, successRedirect, onAuthenticated });
  const path = callbackPath || callbackPathFromRedirectUri(cfg.redirectUri);

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
    return await verifyJwt(cfg, token, { idToken: false });
  } catch {
    return null;
  }
}

module.exports = {
  appPublicUrl,
  allowPinWithIdp,
  loadClientConfig,
  isPosIdpEnabled,
  isAdminIdpEnabled,
  callbackPathFromRedirectUri,
  registerOidcBrowserFlow,
  verifyBearer,
};
