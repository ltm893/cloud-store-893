const { requireSupervisor } = require('./supervisor-auth');
const { asyncHandler } = require('./async-handler');

function registerSupervisorRoutes(app, { loginApprovalStore }) {
  if (!loginApprovalStore) {
    throw new Error('registerSupervisorRoutes requires loginApprovalStore');
  }

  app.get('/api/admin/login-approvals', requireSupervisor, asyncHandler(async (req, res) => {
    const status = String(req.query.status || 'pending').trim().toLowerCase();
    if (status !== 'pending') {
      return res.status(400).json({ error: 'Only status=pending is supported' });
    }

    const limitRaw = Number(req.query.limit);
    const limit = Number.isFinite(limitRaw) && limitRaw > 0 ? Math.min(limitRaw, 100) : 50;

    await loginApprovalStore.expireStaleRows();
    const items = await loginApprovalStore.listPending({ limit });
    return res.json({ items });
  }));

  app.post('/api/admin/login-approvals/:requestToken/approve', requireSupervisor, asyncHandler(async (req, res) => {
    const requestToken = String(req.params.requestToken || '').trim();
    if (!requestToken) {
      return res.status(400).json({ error: 'requestToken is required' });
    }

    const approved = await loginApprovalStore.approve(requestToken, req.supervisorClaims);
    return res.json({
      ok: true,
      status: approved.status,
      requestToken: approved.requestToken,
      cashierEmail: approved.cashierEmail,
      approvedBy: approved.resolvedByEmail,
      approvedAt: approved.resolvedAt,
    });
  }));

  app.post('/api/admin/login-approvals/:requestToken/deny', requireSupervisor, asyncHandler(async (req, res) => {
    const requestToken = String(req.params.requestToken || '').trim();
    if (!requestToken) {
      return res.status(400).json({ error: 'requestToken is required' });
    }

    const reason = req.body?.reason;
    const denied = await loginApprovalStore.deny(requestToken, req.supervisorClaims, reason);
    return res.json({
      ok: true,
      status: denied.status,
      requestToken: denied.requestToken,
      cashierEmail: denied.cashierEmail,
      reason: denied.denyReason,
      deniedBy: denied.resolvedByEmail,
      deniedAt: denied.resolvedAt,
    });
  }));
}

module.exports = { registerSupervisorRoutes };
