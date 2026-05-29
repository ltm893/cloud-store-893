const { getAdminSession } = require('./admin-auth');
const { getAdminConfig, tryBearerAuth } = require('./oidc-admin');
const { normalizeGroups, claimsEmail } = require('./login-approval');

function getSupervisorGroupName() {
  const raw = String(process.env.IDP_SUPERVISOR_GROUP || 'store-supervisors').trim();
  return raw || null;
}

function isSupervisorPinFallbackEnabled() {
  const raw = String(process.env.CASHIER_SUPERVISOR_PIN_IS_SUPERVISOR || '').toLowerCase();
  return raw === 'true' || raw === '1' || raw === 'yes';
}

function sessionToSupervisorIdentity(session) {
  if (!session) return null;
  return {
    sub: session.sub || null,
    email: session.email || null,
    groups: Array.isArray(session.groups) ? session.groups : [],
    auth: session.auth || null,
  };
}

function claimsToSupervisorIdentity(claims) {
  if (!claims) return null;
  return {
    sub: String(claims.sub || '').trim() || null,
    email: claimsEmail(claims),
    groups: normalizeGroups(claims),
    auth: 'oidc',
  };
}

function isSupervisorIdentity(identity) {
  if (!identity) return false;

  const requiredGroup = getSupervisorGroupName();
  if (!requiredGroup) return true;

  const groups = identity.groups || [];
  if (groups.length > 0) {
    return groups.includes(requiredGroup);
  }

  if (identity.auth === 'pin' && isSupervisorPinFallbackEnabled()) {
    return true;
  }

  return false;
}

async function resolveSupervisorIdentity(req) {
  const session = getAdminSession(req);
  if (session) return sessionToSupervisorIdentity(session);

  const cfg = getAdminConfig();
  if (!cfg) return null;
  const claims = await tryBearerAuth(req, cfg);
  return claimsToSupervisorIdentity(claims);
}

function supervisorClaimsFromIdentity(identity) {
  if (!identity) return null;
  const sub =
    identity.sub ||
    (identity.auth === 'pin' && isSupervisorPinFallbackEnabled() ? 'local-admin-pin-supervisor' : null);
  const email =
    identity.email ||
    (identity.auth === 'pin' && isSupervisorPinFallbackEnabled() ? 'admin-pin@local' : null);
  return {
    sub,
    email,
    groups: identity.groups || [],
  };
}

async function requireSupervisor(req, res, next) {
  try {
    const identity = await resolveSupervisorIdentity(req);
    if (!identity) {
      return res.status(401).json({ error: 'Admin sign-in required' });
    }
    if (!isSupervisorIdentity(identity)) {
      return res.status(403).json({ error: 'Supervisor privileges required' });
    }
    req.supervisorClaims = supervisorClaimsFromIdentity(identity);
    return next();
  } catch (err) {
    console.error(err.message);
    return res.status(500).json({ error: err.message });
  }
}

module.exports = {
  getSupervisorGroupName,
  isSupervisorPinFallbackEnabled,
  isSupervisorIdentity,
  resolveSupervisorIdentity,
  supervisorClaimsFromIdentity,
  requireSupervisor,
};
