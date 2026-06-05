const {
  loadClientConfig,
  isAdminIdpEnabled,
  resolveAppPublicUrl,
  registerOidcBrowserFlow,
  verifyBearer,
} = require('./oidc-core');
const { normalizeGroups } = require('./login-approval');

function getAdminConfig(req) {
  const base = resolveAppPublicUrl(req);
  return loadClientConfig('ADMIN', `${base}/oauth/admin/callback`);
}

function registerAdminOidc(app, sessionApi) {
  if (!getAdminConfig()) return;

  registerOidcBrowserFlow(app, {
    getCfg: (req) => getAdminConfig(req),
    loginPath: '/oauth/admin/login',
    callbackPath: '/oauth/admin/callback',
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
