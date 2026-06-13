'use strict';

/** True when OIDC sub/email matches the shift owner (handles email-as-sub in older rows). */
function cashierMatchesShift(shift, { sub, email } = {}) {
  if (!shift) return false;
  const claimSub = String(sub || '').trim().toLowerCase();
  const claimEmail = String(email || '').trim().toLowerCase();
  const openSub = String(shift.cashierSub || '').trim().toLowerCase();
  const openEmail = String(shift.cashierEmail || '').trim().toLowerCase();
  if (!claimSub && !claimEmail) return false;

  const candidates = [claimSub, claimEmail].filter(Boolean);
  const stored = [openSub, openEmail].filter(Boolean);
  return candidates.some((c) => stored.includes(c));
}

module.exports = { cashierMatchesShift };
