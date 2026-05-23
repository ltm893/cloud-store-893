const {
  loadClientConfig,
  isPosIdpEnabled,
  allowPinWithIdp,
  appPublicUrl,
  callbackPathFromRedirectUri,
  registerOidcBrowserFlow,
  verifyBearer,
} = require('./oidc-core');

function getPosConfig() {
  return loadClientConfig('POS', `${appPublicUrl()}/oauth/callback`);
}

function registerPosOidc(app, sessionApi) {
  const cfg = getPosConfig();
  if (!cfg) return;

  registerOidcBrowserFlow(app, {
    cfg,
    loginPath: '/oauth/login',
    callbackPath: callbackPathFromRedirectUri(cfg.redirectUri),
    successRedirect: '/',
    onAuthenticated: async (req, res, { claims }) => {
      const sessionId = sessionApi.createSession({
        sub: claims.sub,
        email: claims.email || claims.preferred_username || null,
        auth: 'oidc',
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
