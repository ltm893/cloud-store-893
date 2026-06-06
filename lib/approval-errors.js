'use strict';

function sendApprovalError(res, err) {
  const status = Number(err?.status) || 500;
  const body = { error: err?.message || 'Request failed' };
  if (err?.code) body.code = err.code;
  return res.status(status).json(body);
}

module.exports = { sendApprovalError };
