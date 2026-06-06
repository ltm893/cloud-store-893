const crypto = require('crypto');
const { cashierPin } = require('./cashier-auth');
const { parseCookies } = require('./session-cookies');
const { restoreSessions, persistSessions } = require('./dev-session-store');
const {
  isAdminIdpEnabled,
  registerAdminOidc,
  tryBearerAuth,
  getAdminConfig,
} = require('./oidc-admin');
const { allowPinWithIdp } = require('./oidc-core');
const { isSupervisorApprovalEnabled } = require('./login-approval');
const { isSupervisorPinFallbackEnabled } = require('./supervisor-config');

const COOKIE_NAME = 'admin_session';
const SESSION_MS = 8 * 60 * 60 * 1000;
const sessions = new Map();
const STORE_KEY = 'admin';

function touchSessions() {
  persistSessions(STORE_KEY, sessions);
}

const sessionApi = {
  createSession,
  setSessionCookie,
  clearSessionCookie,
  getSessionId,
  isValidSession,
};

function adminPin() {
  return String(process.env.ADMIN_PIN || cashierPin()).trim();
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
    touchSessions();
    return false;
  }
  return true;
}

restoreSessions(STORE_KEY, sessions, isValidSession);

function createSession(meta = {}) {
  const id = crypto.randomBytes(24).toString('hex');
  sessions.set(id, { created: Date.now(), auth: 'pin', ...meta });
  touchSessions();
  return id;
}

function setSessionCookie(res, sessionId) {
  const maxAge = Math.floor(SESSION_MS / 1000);
  res.setHeader(
    'Set-Cookie',
    `${COOKIE_NAME}=${encodeURIComponent(sessionId)}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${maxAge}`,
  );
}

function clearSessionCookie(res) {
  res.setHeader('Set-Cookie', `${COOKIE_NAME}=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0`);
}

function isPublicAdminApi(req) {
  return req.method === 'POST' && req.path === '/login';
}

async function hasAdminAccess(req) {
  if (isValidSession(getSessionId(req))) return true;
  const cfg = getAdminConfig();
  if (!cfg) return false;
  const claims = await tryBearerAuth(req, cfg);
  return Boolean(claims);
}

async function requireAdminSession(req, res, next) {
  if (isPublicAdminApi(req)) return next();
  if (req.method === 'GET' && (req.path === '/session' || req.path === '/session/')) {
    const ok = isValidSession(getSessionId(req));
    const idp = isAdminIdpEnabled();
    const supervisorApprovalEnabled = isSupervisorApprovalEnabled();
    let isSupervisor = false;
    if (ok) {
      const { resolveSupervisorIdentity, isSupervisorIdentity } = require('./supervisor-auth');
      const identity = await resolveSupervisorIdentity(req);
      isSupervisor = isSupervisorIdentity(identity);
    }
    const payload = {
      ok,
      idpEnabled: idp,
      idpLoginUrl: idp ? '/oauth/admin/login' : null,
      pinAllowed: allowPinWithIdp(),
      supervisorApprovalEnabled,
      isSupervisor,
    };
    if (ok) {
      const session = sessions.get(getSessionId(req));
      const debug = String(process.env.IDP_SIGNIN_DEBUG || '').toLowerCase();
      if (debug === 'true' || debug === '1' || debug === 'yes') {
        payload.sessionGroups = Array.isArray(session?.groups) ? session.groups : [];
      }
    }
    return res.json(payload);
  }
  if (await hasAdminAccess(req)) return next();
  return res.status(401).json({ error: 'Admin sign-in required' });
}

async function protectAdminPages(req, res, next) {
  const path = req.path || '/';
  if (path === '/login.html' || path.startsWith('/login')) return next();
  if (path === '/admin-orientation.js') return next();
  if (await hasAdminAccess(req)) return next();
  if (path === '/' || path === '/index.html' || path === '') {
    return res.redirect(302, '/admin/login.html');
  }
  return res.status(401).send('Admin sign-in required. <a href="/admin/login.html">Sign in</a>');
}

function getAdminSession(req) {
  const id = getSessionId(req);
  if (!id || !isValidSession(id)) return null;
  return sessions.get(id) || null;
}

function registerAdminAuth(app) {
  registerAdminOidc(app, sessionApi);

  app.post('/api/admin/login', (req, res) => {
    const pin = String(req.body?.pin ?? '').trim();
    if (!pin || pin !== adminPin()) {
      return res.status(401).json({ error: 'Invalid admin PIN' });
    }
    const meta = { auth: 'pin' };
    if (isSupervisorPinFallbackEnabled()) {
      meta.sub = 'local-admin-pin-supervisor';
      meta.email = 'admin-pin@local';
    }
    const sessionId = createSession(meta);
    setSessionCookie(res, sessionId);
    return res.json({ ok: true });
  });

  app.post('/api/admin/logout', (req, res) => {
    const id = getSessionId(req);
    if (id) sessions.delete(id);
    touchSessions();
    clearSessionCookie(res);
    return res.json({ ok: true });
  });
}

module.exports = {
  registerAdminAuth,
  requireAdminSession,
  protectAdminPages,
  isAdminIdpEnabled,
  getAdminSession,
};
