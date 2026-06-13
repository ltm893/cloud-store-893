const { requireSupervisor } = require('./supervisor-auth');
const { asyncHandler } = require('./async-handler');

function registerSupervisorRoutes(app, { loginApprovalStore, shiftCloseStore }) {
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
      cashierName: approved.cashierName,
      cashMode: approved.cashMode ?? null,
      expectedOpeningFloat: approved.expectedOpeningFloat ?? null,
      openingCountedFloat: approved.openingCountedFloat ?? null,
      openingVariance: approved.openingVariance ?? null,
      approvedBy: approved.resolvedByEmail,
      approvedAt: approved.resolvedAt,
    });
  }));

  if (shiftCloseStore) {
    app.get('/api/admin/shift-closes', requireSupervisor, asyncHandler(async (req, res) => {
      const status = String(req.query.status || 'pending').trim().toLowerCase();
      if (status !== 'pending') {
        return res.status(400).json({ error: 'Only status=pending is supported' });
      }
      const limitRaw = Number(req.query.limit);
      const limit = Number.isFinite(limitRaw) && limitRaw > 0 ? Math.min(limitRaw, 100) : 50;
      const items = await shiftCloseStore.listPending({ limit });
      return res.json({ items });
    }));

    app.post('/api/admin/shift-closes/:closeToken/approve', requireSupervisor, asyncHandler(async (req, res) => {
      const closeToken = String(req.params.closeToken || '').trim();
      if (!closeToken) return res.status(400).json({ error: 'closeToken is required' });
      const approved = await shiftCloseStore.approve(closeToken, req.supervisorClaims);
      return res.json({
        ok: true,
        status: approved.status,
        closeToken: approved.closeToken,
        cashierEmail: approved.cashierEmail,
        cashierName: approved.cashierName,
        cashMode: approved.cashMode,
        expectedCloseFloat: approved.expectedCloseFloat,
        countedCloseFloat: approved.countedCloseFloat,
        closeVariance: approved.closeVariance,
        approvedBy: approved.resolvedByEmail,
        approvedAt: approved.resolvedAt,
      });
    }));

    app.post('/api/admin/shift-closes/:closeToken/deny', requireSupervisor, asyncHandler(async (req, res) => {
      const closeToken = String(req.params.closeToken || '').trim();
      if (!closeToken) return res.status(400).json({ error: 'closeToken is required' });
      const reason = req.body?.reason;
      const denied = await shiftCloseStore.deny(closeToken, req.supervisorClaims, reason);
      return res.json({
        ok: true,
        status: denied.status,
        closeToken: denied.closeToken,
        cashierEmail: denied.cashierEmail,
        cashierName: denied.cashierName,
        cashMode: denied.cashMode,
        reason: denied.denyReason,
        deniedBy: denied.resolvedByEmail,
        deniedAt: denied.resolvedAt,
      });
    }));
  }

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
      cashierName: denied.cashierName,
      cashMode: denied.cashMode ?? null,
      expectedOpeningFloat: denied.expectedOpeningFloat ?? null,
      openingCountedFloat: denied.openingCountedFloat ?? null,
      openingVariance: denied.openingVariance ?? null,
      reason: denied.denyReason,
      deniedBy: denied.resolvedByEmail,
      deniedAt: denied.resolvedAt,
    });
  }));
}

module.exports = { registerSupervisorRoutes };
