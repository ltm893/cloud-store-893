const {
  loadClientConfig,
  isPosIdpEnabled,
  allowPinWithIdp,
  appPublicUrl,
  callbackPathFromRedirectUri,
  registerOidcBrowserFlow,
  verifyBearer,
} = require('./oidc-core');
const {
  isSupervisorApprovalEnabled,
  normalizeGroups,
} = require('./login-approval');

function getPosConfig() {
  return loadClientConfig('POS', `${appPublicUrl()}/oauth/callback`);
}

function registerPosOidc(app, sessionApi, { loginApprovalStore } = {}) {
  const cfg = getPosConfig();
  if (!cfg) return;

  registerOidcBrowserFlow(app, {
    cfg,
    loginPath: '/oauth/login',
    callbackPath: callbackPathFromRedirectUri(cfg.redirectUri),
    successRedirect: '/',
    onAuthenticated: async (req, res, { claims }) => {
      const email = claims.email || claims.preferred_username || null;

      if (isSupervisorApprovalEnabled()) {
        if (!loginApprovalStore) {
          console.error('CASHIER_SUPERVISOR_APPROVAL is enabled but loginApprovalStore is missing');
          return res.status(500).send('Supervisor approval is not configured');
        }

        try {
          sessionApi.clearSessionCookie(res);
          const created = await loginApprovalStore.createRequest({
            claims,
            registerId: req.query?.register_id || null,
            clientKind: req.query?.client_kind || 'web',
          });
          sessionApi.setPendingCookie(res, created.requestToken);
          return res.redirect(302, '/?approval=pending');
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
