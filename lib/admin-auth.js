const crypto = require('crypto');
const { cashierPin } = require('./cashier-auth');

const COOKIE_NAME = 'admin_session';
const SESSION_MS = 8 * 60 * 60 * 1000;
const sessions = new Map();

function adminPin() {
  return String(process.env.ADMIN_PIN || cashierPin()).trim();
}

function parseCookies(req) {
  const out = {};
  const raw = req.headers.cookie || '';
  for (const part of raw.split(';')) {
    const idx = part.indexOf('=');
    if (idx === -1) continue;
    const key = part.slice(0, idx).trim();
    const val = part.slice(idx + 1).trim();
    if (key) out[key] = decodeURIComponent(val);
  }
  return out;
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

function createSession() {
  const id = crypto.randomBytes(24).toString('hex');
  sessions.set(id, { created: Date.now() });
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

function requireAdminSession(req, res, next) {
  if (isPublicAdminApi(req)) return next();
  if (req.method === 'GET' && (req.path === '/session' || req.path === '/session/')) {
    return res.json({ ok: isValidSession(getSessionId(req)) });
  }
  if (isValidSession(getSessionId(req))) return next();
  return res.status(401).json({ error: 'Admin sign-in required' });
}

function protectAdminPages(req, res, next) {
  const path = req.path || '/';
  if (path === '/login.html' || path.startsWith('/login')) return next();
  if (isValidSession(getSessionId(req))) return next();
  if (path === '/' || path === '/index.html' || path === '') {
    return res.redirect(302, '/admin/login.html');
  }
  return res.status(401).send('Admin sign-in required. <a href="/admin/login.html">Sign in</a>');
}

function registerAdminAuth(app) {
  app.post('/api/admin/login', (req, res) => {
    const pin = String(req.body?.pin ?? '').trim();
    if (!pin || pin !== adminPin()) {
      return res.status(401).json({ error: 'Invalid admin PIN' });
    }
    const sessionId = createSession();
    setSessionCookie(res, sessionId);
    return res.json({ ok: true });
  });

  app.post('/api/admin/logout', (req, res) => {
    const id = getSessionId(req);
    if (id) sessions.delete(id);
    clearSessionCookie(res);
    return res.json({ ok: true });
  });
}

module.exports = {
  registerAdminAuth,
  requireAdminSession,
  protectAdminPages,
};
