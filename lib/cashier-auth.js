const { createSessionStore } = require('./session-store');
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
  identityFromApproval,
  identityFromCashierSub,
  claimsDisplayName,
  claimsEmail,
} = require('./login-approval');
const { sendApprovalError } = require('./approval-errors');
const { parseCookies } = require('./session-cookies');
const {
  CASH_MODE,
  isCashTillConfigured,
  getDenominations,
  parseTillSubmit,
  tillConfigPayload,
  tillFieldsFromApproval,
  sessionAllowsCashPayments,
} = require('./cash-till-config');
const {
  createAwaitingTill,
  getAwaitingTill,
  deleteAwaitingTill,
} = require('./awaiting-till-store');

const COOKIE_NAME = 'cashier_session';
const PENDING_COOKIE_NAME = 'cashier_pending';
const AWAITING_TILL_COOKIE_NAME = 'cashier_awaiting_till';
const AWAITING_TILL_TTL_SEC = 30 * 60;

const cashierStore = createSessionStore({
  cookieName: COOKIE_NAME,
  storeKey: 'cashier',
  useAppendHeader: true,
  secure: () => String(process.env.CASHIER_SESSION_SECURE || '').toLowerCase() === 'true',
});

const {
  sessions,
  createSession,
  setSessionCookie,
  clearSessionCookie,
  getSessionId,
  isValidSession,
  deleteSession,
  applySetCookie,
  cookieExtraFlags,
  touchSessions,
} = cashierStore;

function getPendingToken(req) {
  return parseCookies(req)[PENDING_COOKIE_NAME] || null;
}

function setPendingCookie(res, requestToken) {
  const maxAge = getApprovalTtlSec();
  applySetCookie(
    res,
    `${PENDING_COOKIE_NAME}=${encodeURIComponent(requestToken)}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${maxAge}${cookieExtraFlags()}`,
  );
}

function clearPendingCookie(res) {
  applySetCookie(
    res,
    `${PENDING_COOKIE_NAME}=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0${cookieExtraFlags()}`,
  );
}

function getAwaitingTillToken(req) {
  return parseCookies(req)[AWAITING_TILL_COOKIE_NAME] || null;
}

function setAwaitingTillCookie(res, token) {
  applySetCookie(
    res,
    `${AWAITING_TILL_COOKIE_NAME}=${encodeURIComponent(token)}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${AWAITING_TILL_TTL_SEC}${cookieExtraFlags()}`,
  );
}

function clearAwaitingTillCookie(res) {
  applySetCookie(
    res,
    `${AWAITING_TILL_COOKIE_NAME}=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0${cookieExtraFlags()}`,
  );
}

function approvalLikeFromTill(till) {
  return {
    cashMode: till.cashMode,
    expectedOpeningFloat: till.expectedOpeningFloat ?? null,
    openingCountedFloat: till.countedTotal ?? null,
    openingVariance: till.openingVariance ?? null,
    openingDenominations: till.denominations ?? null,
  };
}

async function maybeCreateRegisterShift(registerShiftStore, approvalLike) {
  if (!registerShiftStore) return null;
  try {
    const shift = await registerShiftStore.createFromApproval(approvalLike);
    return shift?.id ?? null;
  } catch (err) {
    console.error('[register-shift] create failed:', err.message);
    return null;
  }
}

async function resolveCashierIdentity(session, loginApprovalStore) {
  if (!session || typeof session !== 'object') {
    return { email: null, name: null, user: null };
  }

  let email = session.email ?? null;
  let name = session.name ?? null;

  if ((!email || !name) && session.approvalRequestToken && loginApprovalStore) {
    try {
      const approval = await loginApprovalStore.findByToken(session.approvalRequestToken);
      if (approval) {
        const fromApproval = identityFromApproval(approval);
        if (!email) email = fromApproval.email;
        if (!name) name = fromApproval.name;
      }
    } catch (err) {
      console.error('[cashier-identity] token lookup failed:', err.message);
    }
  }

  if ((!email || !name) && session.sub && loginApprovalStore?.findLatestIdentityForCashier) {
    try {
      const approval = await loginApprovalStore.findLatestIdentityForCashier(session.sub);
      if (approval) {
        const fromApproval = identityFromApproval(approval);
        if (!email) email = fromApproval.email;
        if (!name) name = fromApproval.name;
      }
    } catch (err) {
      console.error('[cashier-identity] sub lookup failed:', err.message);
    }
  }

  if (!email) email = identityFromCashierSub(session.sub);
  if (!name && email) name = email;

  const trimmedEmail = email ? String(email).trim() : '';
  const trimmedName = name ? String(name).trim() : '';
  const user = trimmedEmail || trimmedName || (session.auth === 'pin' ? 'Cashier' : null);

  console.log(
    '[cashier-identity] email=%s name=%s user=%s auth=%s sub=%s token=%s',
    trimmedEmail || 'null',
    trimmedName || 'null',
    user || 'null',
    session.auth || 'null',
    session.sub ? 'yes' : 'no',
    session.approvalRequestToken ? 'yes' : 'no',
  );

  if (user && session) {
    if (!session.email && trimmedEmail) session.email = trimmedEmail;
    if (!session.name && trimmedName) session.name = trimmedName;
    touchSessions();
  }

  return {
    email: trimmedEmail || null,
    name: trimmedName || null,
    user,
  };
}

/**
 * After supervisor approval — issue cashier_session (used by poll route in step 5).
 */
async function issueCashierSessionAfterApproval(
  res,
  approval,
  supervisorClaims = null,
  registerShiftStore = null,
) {
  const fromApproval = identityFromApproval(approval);
  const tillFields = tillFieldsFromApproval(approval);
  const shiftId = await maybeCreateRegisterShift(registerShiftStore, approval);
  const sessionId = createSession({
    auth: approval.cashierSub === 'pin:cashier' ? 'pin' : 'oidc',
    sub: approval.cashierSub,
    email: fromApproval.email,
    name: fromApproval.name,
    groups: [],
    approvalRequestToken: approval.requestToken,
    approvedBy: supervisorClaims?.email || approval.resolvedByEmail || null,
    approvedAt: approval.resolvedAt,
    shiftId,
    ...tillFields,
  });
  clearPendingCookie(res);
  clearAwaitingTillCookie(res);
  setSessionCookie(res, sessionId);
  return sessionId;
}

async function issueCashierSessionFromTill(
  res,
  { auth, sub, email, name, till },
  registerShiftStore = null,
) {
  const approvalLike = {
    cashierSub: sub,
    cashierEmail: email,
    cashMode: till.cashMode,
    expectedOpeningFloat: till.expectedOpeningFloat ?? null,
    openingCountedFloat: till.countedTotal ?? null,
    openingVariance: till.openingVariance ?? null,
    openingDenominations: till.denominations ?? null,
    requestToken: null,
  };
  const tillFields = tillFieldsFromApproval(approvalLike);
  const shiftId = await maybeCreateRegisterShift(registerShiftStore, approvalLike);
  const sessionId = createSession({
    auth,
    sub,
    email,
    name,
    groups: [],
    shiftId,
    ...tillFields,
  });
  clearAwaitingTillCookie(res);
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
  setAwaitingTillCookie,
  clearAwaitingTillCookie,
};

function cashierPin() {
  return String(process.env.CASHIER_PIN || '8930').trim();
}

function isPublicCashierApi(req) {
  const path = req.path || '';
  if (path === '/api/cashier/unlock' && req.method === 'POST') return true;
  if (path === '/api/cashier/logout' && req.method === 'POST') return true;
  if (path === '/api/cashier/session' && req.method === 'GET') return true;
  if (path === '/api/cashier/till/config' && req.method === 'GET') return true;
  if (path === '/api/cashier/approval/till' && req.method === 'POST') return true;
  if (path === '/api/cashier/approval/till/cancel' && req.method === 'POST') return true;
  if (path === '/api/cashier/approval/status' && req.method === 'GET') return true;
  if (path === '/api/cashier/approval/cancel' && req.method === 'POST') return true;
  if (path === '/api/cashier/approval/request' && req.method === 'POST') return true;
  return false;
}

function getActiveCashierSession(req) {
  const sessionId = getSessionId(req);
  if (!isValidSession(sessionId)) return null;
  return sessions.get(sessionId) || null;
}

function cashierSessionPayloadFields(session) {
  const tillFields = tillFieldsFromApproval(
    session?.cashMode
      ? {
          cashMode: session.cashMode,
          expectedOpeningFloat: session.expectedOpeningFloat,
          openingCountedFloat: session.openingCountedFloat,
        }
      : null,
  );
  if (session?.cashEnabled !== undefined && session?.cashEnabled !== null) {
    tillFields.cashEnabled = Boolean(session.cashEnabled);
  }
  if (session?.shiftId != null) {
    tillFields.shiftId = session.shiftId;
  }
  return tillFields;
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
    ...tillConfigPayload(),
  };

  const sessionId = getSessionId(req);
  if (sessionId && !isValidSession(sessionId)) {
    clearSessionCookie(res);
  }

  if (isValidSession(sessionId)) {
    const session = sessions.get(sessionId);
    const identity = await resolveCashierIdentity(session, loginApprovalStore);
    return {
      ok: true,
      auth: session?.auth || 'pin',
      sub: session?.sub ?? null,
      email: identity.email,
      name: identity.name,
      user: identity.user,
      cashierEmail: identity.email,
      approvedBy: session?.approvedBy ?? null,
      approvedAt: session?.approvedAt ?? null,
      ...cashierSessionPayloadFields(session),
      ...base,
    };
  }

  const awaitingTillToken = getAwaitingTillToken(req);
  if (awaitingTillToken) {
    if (getAwaitingTill(awaitingTillToken)) {
      return {
        ok: false,
        awaitingTill: true,
        ...base,
      };
    }
    clearAwaitingTillCookie(res);
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
          cashierName: approval.cashierName,
          secondsRemaining: approval.secondsRemaining,
          cashMode: approval.cashMode,
          expectedOpeningFloat: approval.expectedOpeningFloat,
          openingCountedFloat: approval.openingCountedFloat,
          openingVariance: approval.openingVariance,
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

function registerCashierAuth(app, { loginApprovalStore, registerShiftStore } = {}) {
  registerPosOidc(app, sessionApi, { loginApprovalStore });

  app.get('/api/cashier/till/config', (req, res) => {
    return res.json(tillConfigPayload());
  });

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

    if (isCashTillConfigured()) {
      const token = createAwaitingTill({
        pinAuth: true,
        clientKind: req.body?.clientKind || 'tablet',
      });
      setAwaitingTillCookie(res, token);
      return res.json({ ok: true, awaitingTill: true, ...tillConfigPayload() });
    }

    const sessionId = createSession({
      auth: 'pin',
      sub: 'pin:cashier',
      name: 'Cashier',
      ...tillFieldsFromApproval(null),
    });
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
          email: approval.cashierEmail ?? null,
          cashierEmail: approval.cashierEmail ?? null,
          name: approval.cashierName ?? null,
          cashierName: approval.cashierName ?? null,
          cashMode: approval.cashMode ?? null,
          expectedOpeningFloat: approval.expectedOpeningFloat ?? null,
          openingCountedFloat: approval.openingCountedFloat ?? null,
          openingVariance: approval.openingVariance ?? null,
          openingDenominations: approval.openingDenominations ?? null,
        });
      }

      if (approval.status === STATUS.APPROVED) {
        await issueCashierSessionAfterApproval(res, approval, null, registerShiftStore);
        return res.json({
          status: STATUS.APPROVED,
          ok: true,
          email: approval.cashierEmail ?? null,
          cashierEmail: approval.cashierEmail ?? null,
          name: approval.cashierName ?? null,
          cashierName: approval.cashierName ?? null,
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
      return sendApprovalError(res, err);
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

      if (isCashTillConfigured()) {
        const token = createAwaitingTill({
          claims,
          registerId: req.body?.registerId ?? null,
          clientKind: req.body?.clientKind || 'tablet',
        });
        setAwaitingTillCookie(res, token);
        return res.status(202).json({
          awaitingTill: true,
          ...tillConfigPayload(),
        });
      }

      const created = await loginApprovalStore.createRequest({
        claims,
        registerId: req.body?.registerId ?? null,
        clientKind: req.body?.clientKind || 'tablet',
        till: { cashMode: CASH_MODE.CREDIT_ONLY },
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
      return sendApprovalError(res, err);
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
      return sendApprovalError(res, err);
    }
  });

  app.post('/api/cashier/approval/till', async (req, res) => {
    try {
      if (!isCashTillConfigured()) {
        return res.status(404).json({ error: 'Opening cash float is not configured' });
      }

      const awaitingToken = getAwaitingTillToken(req);
      const draft = awaitingToken ? getAwaitingTill(awaitingToken) : null;
      if (!draft) {
        if (awaitingToken) clearAwaitingTillCookie(res);
        return res.status(401).json({
          error: 'Sign-in step expired — sign in with Oracle again',
          code: 'AWAITING_TILL_EXPIRED',
        });
      }

      const till = parseTillSubmit(req.body, getDenominations());

      if (isSupervisorApprovalEnabled()) {
        if (!loginApprovalStore) {
          return res.status(500).json({ error: 'Login approval store is not configured' });
        }

        const created = await loginApprovalStore.createRequest({
          claims: draft.claims,
          registerId: draft.registerId,
          clientKind: draft.clientKind,
          till,
          pinAuth: draft.pinAuth,
        });
        deleteAwaitingTill(awaitingToken);
        clearAwaitingTillCookie(res);
        setPendingCookie(res, created.requestToken);

        return res.status(202).json({
          pending: true,
          requestToken: created.requestToken,
          status: created.status,
          expiresAt: created.expiresAt,
          cashMode: created.cashMode,
          openingCountedFloat: created.openingCountedFloat,
          openingVariance: created.openingVariance,
          pollUrl: '/api/cashier/approval/status',
        });
      }

      const sub = draft.pinAuth ? 'pin:cashier' : String(draft.claims?.sub || '').trim();
      const email = draft.pinAuth ? null : claimsEmail(draft.claims);
      const name = draft.pinAuth ? 'Cashier' : claimsDisplayName(draft.claims);
      await issueCashierSessionFromTill(
        res,
        {
          auth: draft.pinAuth ? 'pin' : 'oidc',
          sub,
          email,
          name,
          till,
        },
        registerShiftStore,
      );
      deleteAwaitingTill(awaitingToken);

      return res.json({
        ok: true,
        cashMode: till.cashMode,
        cashEnabled: tillFieldsFromApproval(approvalLikeFromTill(till)).cashEnabled,
      });
    } catch (err) {
      console.error(err.message);
      const status = Number(err.status) || 500;
      return res.status(status).json({ error: err.message });
    }
  });

  app.post('/api/cashier/approval/till/cancel', (req, res) => {
    const awaitingToken = getAwaitingTillToken(req);
    if (awaitingToken) {
      deleteAwaitingTill(awaitingToken);
    }
    clearAwaitingTillCookie(res);
    return res.json({ ok: true });
  });

  app.post('/api/cashier/logout', (req, res) => {
    const awaitingToken = getAwaitingTillToken(req);
    if (awaitingToken) {
      deleteAwaitingTill(awaitingToken);
    }
    deleteSession(getSessionId(req));
    clearSessionCookie(res);
    clearPendingCookie(res);
    clearAwaitingTillCookie(res);
    return res.json({ ok: true });
  });
}

module.exports = {
  COOKIE_NAME,
  PENDING_COOKIE_NAME,
  AWAITING_TILL_COOKIE_NAME,
  cashierPin,
  registerCashierAuth,
  requireCashierForPosApi,
  requireCashierSession,
  isPosIdpEnabled,
  getPendingToken,
  setPendingCookie,
  clearPendingCookie,
  setAwaitingTillCookie,
  clearAwaitingTillCookie,
  getActiveCashierSession,
  sessionAllowsCashPayments,
  issueCashierSessionAfterApproval,
  sessionStatusPayload,
};
