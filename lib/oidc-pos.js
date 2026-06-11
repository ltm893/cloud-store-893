const {
  loadClientConfig,
  isPosIdpEnabled,
  allowPinWithIdp,
  resolveAppPublicUrl,
  registerOidcBrowserFlow,
  verifyBearer,
} = require('./oidc-core');
const {
  isSupervisorApprovalEnabled,
  normalizeGroups,
  claimsDisplayName,
  claimsEmail,
} = require('./login-approval');
const { CASH_MODE, isCashTillConfigured } = require('./cash-till-config');
const { createAwaitingTill } = require('./awaiting-till-store');

function getPosConfig(req) {
  const base = resolveAppPublicUrl(req);
  return loadClientConfig('POS', `${base}/oauth/callback`);
}

function registerPosOidc(app, sessionApi, { loginApprovalStore } = {}) {
  if (!getPosConfig()) return;

  registerOidcBrowserFlow(app, {
    getCfg: (req) => getPosConfig(req),
    loginPath: '/oauth/login',
    callbackPath: '/oauth/callback',
    successRedirect: '/',
    onAuthenticated: async (req, res, { claims, flow }) => {
      const email = claimsEmail(claims);
      const name = claimsDisplayName(claims);
      const registerId = flow?.registerId || req.query?.register_id || null;
      const clientKind = flow?.clientKind || req.query?.client_kind || 'web';

      if (isCashTillConfigured()) {
        sessionApi.clearSessionCookie(res);
        sessionApi.clearPendingCookie(res);
        const token = createAwaitingTill({
          claims,
          registerId,
          clientKind,
        });
        sessionApi.setAwaitingTillCookie(res, token);
        return res.redirect(302, '/?awaiting_till=1');
      }

      if (isSupervisorApprovalEnabled()) {
        if (!loginApprovalStore) {
          console.error('CASHIER_SUPERVISOR_APPROVAL is enabled but loginApprovalStore is missing');
          return res.status(500).send('Supervisor approval is not configured');
        }

        try {
          sessionApi.clearSessionCookie(res);
          const created = await loginApprovalStore.createRequest({
            claims,
            registerId,
            clientKind,
            till: { cashMode: CASH_MODE.CREDIT_ONLY },
          });
          if (created.reused) {
            console.log(
              'Reusing pending login approval for %s (%s)',
              created.cashierEmail || created.cashierSub,
              created.requestToken,
            );
          }
          sessionApi.setPendingCookie(res, created.requestToken);
          const tokenQ = encodeURIComponent(created.requestToken);
          return res.redirect(302, `/?approval=pending&request_token=${tokenQ}`);
        } catch (err) {
          console.error(err.message);
          const status = Number(err.status) || 500;
          const message = err.message || 'Sign-in failed';
          return res.status(status).send(message);
        }
      }

      const sessionId = sessionApi.createSession({
        sub: claims.sub,
        email,
        name,
        auth: 'oidc',
        groups: normalizeGroups(claims),
      });
      sessionApi.setSessionCookie(res, sessionId);
    },
  });
}

async function tryBearerAuth(req, cfg) {
  return verifyBearer(cfg, req.headers.authorization);
}

module.exports = {
  getPosConfig,
  isPosIdpEnabled,
  allowPinWithIdp,
  registerPosOidc,
  tryBearerAuth,
};
