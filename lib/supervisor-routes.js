const { requireSupervisor } = require('./supervisor-auth');

function sendApprovalError(res, err) {
  const status = Number(err?.status) || 500;
  const body = { error: err?.message || 'Request failed' };
  if (err?.code) body.code = err.code;
  return res.status(status).json(body);
}

function registerSupervisorRoutes(app, { loginApprovalStore }) {
  if (!loginApprovalStore) {
    throw new Error('registerSupervisorRoutes requires loginApprovalStore');
  }

  app.get('/api/admin/login-approvals', requireSupervisor, async (req, res) => {
    try {
      const status = String(req.query.status || 'pending').trim().toLowerCase();
      if (status !== 'pending') {
        return res.status(400).json({ error: 'Only status=pending is supported' });
      }

      const limitRaw = Number(req.query.limit);
      const limit = Number.isFinite(limitRaw) && limitRaw > 0 ? Math.min(limitRaw, 100) : 50;

      await loginApprovalStore.expireStaleRows();
      const items = await loginApprovalStore.listPending({ limit });
      return res.json({ items });
    } catch (err) {
      console.error(err.message);
      return res.status(500).json({ error: err.message });
    }
  });

  app.post('/api/admin/login-approvals/:requestToken/approve', requireSupervisor, async (req, res) => {
    try {
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
    } catch (err) {
      console.error(err.message);
      return sendApprovalError(res, err);
    }
  });

  app.post('/api/admin/login-approvals/:requestToken/deny', requireSupervisor, async (req, res) => {
    try {
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
    } catch (err) {
      console.error(err.message);
      return sendApprovalError(res, err);
    }
  });
}

module.exports = { registerSupervisorRoutes };
