'use strict';

function isSupervisorPinFallbackEnabled() {
  const raw = String(process.env.CASHIER_SUPERVISOR_PIN_IS_SUPERVISOR || '').toLowerCase();
  return raw === 'true' || raw === '1' || raw === 'yes';
}

module.exports = { isSupervisorPinFallbackEnabled };
