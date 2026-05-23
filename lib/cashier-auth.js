const crypto = require('crypto');
const { parseCookies } = require('./session-cookies');
const {
  isPosIdpEnabled,
  allowPinWithIdp,
  registerPosOidc,
  tryBearerAuth,
  getPosConfig,
} = require('./oidc-pos');

const COOKIE_NAME = 'cashier_session';
const SESSION_MS = 8 * 60 * 60 * 1000;
const sessions = new Map();

const sessionApi = {
  createSession,
  setSessionCookie,
  clearSessionCookie,
  getSessionId,
  isValidSession,
};

function cashierPin() {
  return String(process.env.CASHIER_PIN || '8930').trim();
}

function sessionCookieFlags() {
  const secure = String(process.env.CASHIER_SESSION_SECURE || '').toLowerCase() === 'true';
  return secure ? '; Secure' : '';
}

function getSessionId(req) {
  return parseCookies(req)[COOKIE_NAME] || null;
}

function isValidSession(id) {
  if (!id) return false;
  const entry = sessions.get(id);
  if (!entry) return false;
  if (Date.now() - entry.created > SESSION_MS) {
    sessions.delete(id);
    return false;
  }
  return true;
}

function createSession(meta = {}) {
  const id = crypto.randomBytes(24).toString('hex');
  sessions.set(id, { created: Date.now(), auth: 'pin', ...meta });
  return id;
}

function setSessionCookie(res, sessionId) {
  const maxAge = Math.floor(SESSION_MS / 1000);
  res.setHeader(
    'Set-Cookie',
    `${COOKIE_NAME}=${encodeURIComponent(sessionId)}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${maxAge}${sessionCookieFlags()}`,
  );
}

function clearSessionCookie(res) {
  res.setHeader(
    'Set-Cookie',
    `${COOKIE_NAME}=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0${sessionCookieFlags()}`,
  );
}

function isPublicCashierApi(req) {
  const path = req.path || '';
  if (path === '/api/cashier/unlock' && req.method === 'POST') return true;
  if (path === '/api/cashier/logout' && req.method === 'POST') return true;
  if (path === '/api/cashier/session' && req.method === 'GET') return true;
  return false;
}

function isPublicPosRead(req) {
  return req.method === 'GET' && (req.path === '/api/products' || req.path === '/api/products/');
}

async function hasCashierAccess(req) {
  if (isValidSession(getSessionId(req))) return true;
  const cfg = getPosConfig();
  if (!cfg) return false;
  const claims = await tryBearerAuth(req, cfg);
  return Boolean(claims);
}

async function requireCashierSession(req, res, next) {
  if (await hasCashierAccess(req)) return next();
  return res.status(401).json({ error: 'Cashier sign-in required' });
}

async function requireCashierForPosApi(req, res, next) {
  const path = req.path || '';
  if (!path.startsWith('/api/')) return next();
  if (path.startsWith('/api/admin')) return next();
  if (isPublicCashierApi(req)) return next();
  if (isPublicPosRead(req)) return next();
  return requireCashierSession(req, res, next);
}

function sessionStatusPayload(req) {
  const ok = isValidSession(getSessionId(req));
  const idp = isPosIdpEnabled();
  return {
    ok,
    auth: ok ? sessions.get(getSessionId(req))?.auth || 'pin' : null,
    idpEnabled: idp,
    idpLoginUrl: idp ? '/oauth/login' : null,
    pinAllowed: !idp || allowPinWithIdp(),
  };
}

function registerCashierAuth(app) {
  registerPosOidc(app, sessionApi);

  app.post('/api/cashier/unlock', (req, res) => {
    if (isPosIdpEnabled() && !allowPinWithIdp()) {
      return res.status(403).json({ error: 'PIN sign-in disabled; use IdP login' });
    }
    const pin = String(req.body?.pin ?? '').trim();
    if (!pin || pin !== cashierPin()) {
      return res.status(401).json({ error: 'Invalid PIN' });
    }
    const sessionId = createSession({ auth: 'pin' });
    setSessionCookie(res, sessionId);
    return res.json({ ok: true });
  });

  app.get('/api/cashier/session', (req, res) => {
    return res.json(sessionStatusPayload(req));
  });

  app.post('/api/cashier/logout', (req, res) => {
    const id = getSessionId(req);
    if (id) sessions.delete(id);
    clearSessionCookie(res);
    return res.json({ ok: true });
  });
}

module.exports = {
  cashierPin,
  registerCashierAuth,
  requireCashierForPosApi,
  requireCashierSession,
  isPosIdpEnabled,
};
