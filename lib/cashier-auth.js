const crypto = require('crypto');
const { parseCookies } = require('./session-cookies');
const { restoreSessions, persistSessions } = require('./dev-session-store');
const {
  isPosIdpEnabled,
  allowPinWithIdp,
  registerPosOidc,
  tryBearerAuth,
  getPosConfig,
} = require('./oidc-pos');
const {
  isSupervisorApprovalEnabled,
  getApprovalTtlSec,
  STATUS,
} = require('./login-approval');

const COOKIE_NAME = 'cashier_session';
const PENDING_COOKIE_NAME = 'cashier_pending';
const SESSION_MS = 8 * 60 * 60 * 1000;
const sessions = new Map();
const STORE_KEY = 'cashier';

function touchSessions() {
  persistSessions(STORE_KEY, sessions);
}

function sessionCookieFlags() {
  const secure = String(process.env.CASHIER_SESSION_SECURE || '').toLowerCase() === 'true';
  return secure ? '; Secure' : '';
}

function getSessionId(req) {
  return parseCookies(req)[COOKIE_NAME] || null;
}

function getPendingToken(req) {
  return parseCookies(req)[PENDING_COOKIE_NAME] || null;
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

function appendSetCookie(res, value) {
  res.appendHeader('Set-Cookie', value);
}

function setSessionCookie(res, sessionId) {
  const maxAge = Math.floor(SESSION_MS / 1000);
  appendSetCookie(
    res,
    `${COOKIE_NAME}=${encodeURIComponent(sessionId)}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${maxAge}${sessionCookieFlags()}`,
  );
}

function clearSessionCookie(res) {
  appendSetCookie(
    res,
    `${COOKIE_NAME}=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0${sessionCookieFlags()}`,
  );
}

function setPendingCookie(res, requestToken) {
  const maxAge = getApprovalTtlSec();
  appendSetCookie(
    res,
    `${PENDING_COOKIE_NAME}=${encodeURIComponent(requestToken)}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${maxAge}${sessionCookieFlags()}`,
  );
}

function clearPendingCookie(res) {
  appendSetCookie(
    res,
    `${PENDING_COOKIE_NAME}=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0${sessionCookieFlags()}`,
  );
}

/**
 * After supervisor approval — issue cashier_session (used by poll route in step 5).
 */
function issueCashierSessionAfterApproval(res, approval, supervisorClaims = null) {
  const sessionId = createSession({
    auth: 'oidc',
    sub: approval.cashierSub,
    email: approval.cashierEmail,
    groups: [],
    approvalRequestToken: approval.requestToken,
    approvedBy: supervisorClaims?.email || approval.resolvedByEmail || null,
    approvedAt: approval.resolvedAt,
  });
  clearPendingCookie(res);
  setSessionCookie(res, sessionId);
  return sessionId;
}

const sessionApi = {
  createSession,
  setSessionCookie,
  clearSessionCookie,
  getSessionId,
  isValidSession,
  setPendingCookie,
  clearPendingCookie,
  getPendingToken,
};

function cashierPin() {
  return String(process.env.CASHIER_PIN || '8930').trim();
}

function isPublicCashierApi(req) {
  const path = req.path || '';
  if (path === '/api/cashier/unlock' && req.method === 'POST') return true;
  if (path === '/api/cashier/logout' && req.method === 'POST') return true;
  if (path === '/api/cashier/session' && req.method === 'GET') return true;
  if (path === '/api/cashier/approval/status' && req.method === 'GET') return true;
  if (path === '/api/cashier/approval/cancel' && req.method === 'POST') return true;
  if (path === '/api/cashier/approval/request' && req.method === 'POST') return true;
  return false;
}

function sendCashierApprovalError(res, err) {
  const status = Number(err?.status) || 500;
  const body = { error: err?.message || 'Request failed' };
  if (err?.code) body.code = err.code;
  return res.status(status).json(body);
}

async function resolvePendingApproval(req, loginApprovalStore) {
  if (!isSupervisorApprovalEnabled()) {
    const err = new Error('Supervisor approval is not enabled');
    err.status = 404;
    err.code = 'APPROVAL_DISABLED';
    throw err;
  }
  if (!loginApprovalStore) {
    const err = new Error('Login approval store is not configured');
    err.status = 500;
    throw err;
  }

  if (isValidSession(getSessionId(req))) {
    return { alreadySignedIn: true, session: sessions.get(getSessionId(req)) };
  }

  let requestToken = getPendingToken(req);
  let approval = null;

  if (requestToken) {
    approval = await loginApprovalStore.findByToken(requestToken);
  }

  const cfg = getPosConfig();
  const bearerClaims = cfg ? await tryBearerAuth(req, cfg) : null;

  if (!approval && bearerClaims?.sub) {
    const pendingForCashier = await loginApprovalStore.listPending({
      cashierSub: String(bearerClaims.sub),
      limit: 1,
    });
    approval = pendingForCashier[0] || null;
    requestToken = approval?.requestToken || null;
  }

  if (!approval || !requestToken) {
    const err = new Error('No pending login approval');
    err.status = 401;
    err.code = 'NO_PENDING';
    throw err;
  }

  if (bearerClaims?.sub && approval.cashierSub && String(bearerClaims.sub) !== String(approval.cashierSub)) {
    const err = new Error('Pending approval belongs to another cashier');
    err.status = 403;
    err.code = 'WRONG_CASHIER';
    throw err;
  }

  return { requestToken, approval, bearerClaims };
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

async function sessionStatusPayload(req, res, loginApprovalStore) {
  const supervisorApprovalRequired = isSupervisorApprovalEnabled();
  const idp = isPosIdpEnabled();
  const base = {
    supervisorApprovalRequired,
    idpEnabled: idp,
    idpLoginUrl: idp ? '/oauth/login' : null,
    pinAllowed: (!idp || allowPinWithIdp()) && !supervisorApprovalRequired,
  };

  const sessionId = getSessionId(req);
  if (sessionId && !isValidSession(sessionId)) {
    clearSessionCookie(res);
  }

  if (isValidSession(sessionId)) {
    const session = sessions.get(sessionId);
    return {
      ok: true,
      auth: session?.auth || 'pin',
      email: session?.email ?? null,
      approvedBy: session?.approvedBy ?? null,
      approvedAt: session?.approvedAt ?? null,
      ...base,
    };
  }

  const pendingToken = getPendingToken(req);
  if (pendingToken && loginApprovalStore) {
    const approval = await loginApprovalStore.findByToken(pendingToken);
    if (approval?.status === STATUS.PENDING) {
      return {
        ok: false,
        pending: true,
        approval: {
          requestToken: approval.requestToken,
          status: approval.status,
          expiresAt: approval.expiresAt,
          cashierEmail: approval.cashierEmail,
          secondsRemaining: approval.secondsRemaining,
        },
        ...base,
      };
    }
    if (approval && approval.status !== STATUS.PENDING) {
      clearPendingCookie(res);
    }
  }

  return {
    ok: false,
    pending: false,
    ...base,
  };
}

function registerCashierAuth(app, { loginApprovalStore } = {}) {
  registerPosOidc(app, sessionApi, { loginApprovalStore });

  app.post('/api/cashier/unlock', (req, res) => {
    if (isSupervisorApprovalEnabled()) {
      return res.status(403).json({
        error: 'Supervisor approval required; use Oracle sign-in (/oauth/login)',
      });
    }
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

  app.get('/api/cashier/session', async (req, res) => {
    try {
      const payload = await sessionStatusPayload(req, res, loginApprovalStore);
      return res.json(payload);
    } catch (err) {
      console.error(err.message);
      return res.status(500).json({ error: err.message });
    }
  });

  app.get('/api/cashier/approval/status', async (req, res) => {
    try {
      const ctx = await resolvePendingApproval(req, loginApprovalStore);
      if (ctx.alreadySignedIn) {
        return res.json({
          status: 'approved',
          ok: true,
          alreadySignedIn: true,
          email: ctx.session?.email ?? null,
        });
      }

      const { approval } = ctx;

      if (approval.status === STATUS.PENDING) {
        return res.json({
          status: STATUS.PENDING,
          expiresAt: approval.expiresAt,
          secondsRemaining: approval.secondsRemaining,
        });
      }

      if (approval.status === STATUS.APPROVED) {
        issueCashierSessionAfterApproval(res, approval);
        return res.json({
          status: STATUS.APPROVED,
          ok: true,
          approvedBy: approval.resolvedByEmail,
          approvedAt: approval.resolvedAt,
        });
      }

      clearPendingCookie(res);
      return res.json({
        status: approval.status,
        ok: false,
        reason: approval.denyReason || null,
      });
    } catch (err) {
      console.error(err.message);
      return sendCashierApprovalError(res, err);
    }
  });

  app.post('/api/cashier/approval/request', async (req, res) => {
    try {
      if (!isSupervisorApprovalEnabled()) {
        return res.status(404).json({ error: 'Supervisor approval is not enabled' });
      }
      if (!loginApprovalStore) {
        return res.status(500).json({ error: 'Login approval store is not configured' });
      }

      const cfg = getPosConfig();
      if (!cfg) {
        return res.status(403).json({ error: 'POS IdP is not configured' });
      }

      const claims = await tryBearerAuth(req, cfg);
      if (!claims) {
        return res.status(401).json({ error: 'Valid POS bearer token required' });
      }

      if (isValidSession(getSessionId(req))) {
        return res.status(409).json({ error: 'Cashier session already active' });
      }

      const created = await loginApprovalStore.createRequest({
        claims,
        registerId: req.body?.registerId ?? null,
        clientKind: req.body?.clientKind || 'tablet',
      });
      setPendingCookie(res, created.requestToken);

      return res.status(202).json({
        pending: true,
        requestToken: created.requestToken,
        status: created.status,
        expiresAt: created.expiresAt,
        pollUrl: '/api/cashier/approval/status',
      });
    } catch (err) {
      console.error(err.message);
      return sendCashierApprovalError(res, err);
    }
  });

  app.post('/api/cashier/approval/cancel', async (req, res) => {
    try {
      const ctx = await resolvePendingApproval(req, loginApprovalStore);
      if (ctx.alreadySignedIn) {
        return res.json({ ok: true, status: 'approved', alreadySignedIn: true });
      }

      const cancelled = await loginApprovalStore.cancel(ctx.requestToken);
      clearPendingCookie(res);
      return res.json({ ok: true, status: cancelled.status });
    } catch (err) {
      console.error(err.message);
      return sendCashierApprovalError(res, err);
    }
  });

  app.post('/api/cashier/logout', (req, res) => {
    const id = getSessionId(req);
    if (id) sessions.delete(id);
    touchSessions();
    clearSessionCookie(res);
    clearPendingCookie(res);
    return res.json({ ok: true });
  });
}

module.exports = {
  COOKIE_NAME,
  PENDING_COOKIE_NAME,
  cashierPin,
  registerCashierAuth,
  requireCashierForPosApi,
  requireCashierSession,
  isPosIdpEnabled,
  getPendingToken,
  setPendingCookie,
  clearPendingCookie,
  issueCashierSessionAfterApproval,
  sessionStatusPayload,
};
