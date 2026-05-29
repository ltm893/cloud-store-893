const {
  loadClientConfig,
  isAdminIdpEnabled,
  appPublicUrl,
  callbackPathFromRedirectUri,
  registerOidcBrowserFlow,
  verifyBearer,
} = require('./oidc-core');
const { normalizeGroups } = require('./login-approval');

function getAdminConfig() {
  return loadClientConfig('ADMIN', `${appPublicUrl()}/oauth/admin/callback`);
}

function registerAdminOidc(app, sessionApi) {
  const cfg = getAdminConfig();
  if (!cfg) return;

  registerOidcBrowserFlow(app, {
    cfg,
    loginPath: '/oauth/admin/login',
    callbackPath: callbackPathFromRedirectUri(cfg.redirectUri),
    successRedirect: '/admin/',
    onAuthenticated: async (req, res, { claims }) => {
      const sessionId = sessionApi.createSession({
        sub: claims.sub,
        email: claims.email || claims.preferred_username || null,
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
  getAdminConfig,
  isAdminIdpEnabled,
  registerAdminOidc,
  tryBearerAuth,
};
