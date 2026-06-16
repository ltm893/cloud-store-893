const crypto = require('crypto');
const {
  CASH_MODE,
  tillFieldsForApproval,
  getExpectedOpeningFloat,
  isCashTillConfigured,
} = require('./cash-till-config');

const ORDS_PATH = 'till_open_approvals';

const STATUS = {
  PENDING: 'pending',
  APPROVED: 'approved',
  DENIED: 'denied',
  EXPIRED: 'expired',
  CANCELLED: 'cancelled',
};

const TERMINAL_STATUSES = new Set([
  STATUS.APPROVED,
  STATUS.DENIED,
  STATUS.EXPIRED,
  STATUS.CANCELLED,
]);

function isSupervisorApprovalEnabled() {
  const raw = String(process.env.CASHIER_SUPERVISOR_APPROVAL || '').toLowerCase();
  return raw === 'true' || raw === '1' || raw === 'yes';
}

function getApprovalTtlSec() {
  const raw = Number(process.env.CASHIER_APPROVAL_TTL_SEC || 300);
  if (!Number.isFinite(raw) || raw < 30) return 300;
  return Math.floor(raw);
}

function getCashierGroupName() {
  const raw = String(process.env.IDP_POS_CASHIER_GROUP || 'store-cashiers').trim();
  return raw || null;
}

function normalizeGroups(claims) {
  if (!claims || typeof claims !== 'object') return [];
  const raw = claims.groups ?? claims.group ?? claims.grp;
  if (Array.isArray(raw)) {
    return raw
      .map((g) => {
        if (g && typeof g === 'object') {
          return String(g.name || g.display || g.value || g.id || '').trim();
        }
        return String(g).trim();
      })
      .filter(Boolean);
  }
  if (typeof raw === 'string' && raw.trim()) return [raw.trim()];
  return [];
}

function claimsDisplayName(claims) {
  if (!claims || typeof claims !== 'object') return null;
  return (
    claims.name ||
    claims.preferred_username ||
    claims.email ||
    null
  );
}

function claimsEmail(claims) {
  if (!claims || typeof claims !== 'object') return null;
  const candidates = [claims.email, claims.preferred_username, claims.upn, claims.unique_name];
  for (const candidate of candidates) {
    const value = String(candidate || '').trim();
    if (value.includes('@')) return value;
  }
  return null;
}

function identityFromCashierSub(cashierSub) {
  const sub = String(cashierSub || '').trim();
  if (sub.includes('@')) return sub;
  return null;
}

function identityFromApproval(approval) {
  if (!approval) return { email: null, name: null };
  const email =
    approval.cashierEmail ||
    identityFromCashierSub(approval.cashierSub) ||
    null;
  const name =
    approval.cashierName ||
    email ||
    (approval.cashierSub ? String(approval.cashierSub).trim() : null);
  return { email, name };
}

function supervisorFromClaims(claims) {
  return {
    sub: String(claims?.sub || '').trim(),
    email: claimsEmail(claims),
  };
}

function parseOpeningDenominations(raw) {
  if (!raw) return null;
  if (typeof raw === 'object') return raw;
  try {
    return JSON.parse(String(raw));
  } catch {
    return null;
  }
}

function mapRow(row) {
  if (!row || typeof row !== 'object') return null;
  const expiresAt = row.expires_at ? new Date(row.expires_at) : null;
  const requestedAt = row.requested_at ? new Date(row.requested_at) : null;
  const resolvedAt = row.resolved_at ? new Date(row.resolved_at) : null;
  const tillSubmittedAt = row.till_submitted_at ? new Date(row.till_submitted_at) : null;
  const expiresMs = expiresAt && !Number.isNaN(expiresAt.getTime()) ? expiresAt.getTime() : null;
  const secondsRemaining =
    expiresMs == null ? null : Math.max(0, Math.ceil((expiresMs - Date.now()) / 1000));

  return {
    id: Number(row.id),
    requestToken: row.request_token,
    status: row.status,
    cashierSub: row.cashier_sub,
    cashierEmail: row.cashier_email ?? null,
    cashierName: row.cashier_name ?? null,
    registerId: row.register_id ?? null,
    clientKind: row.client_kind ?? null,
    requestedAt: requestedAt && !Number.isNaN(requestedAt.getTime()) ? requestedAt.toISOString() : null,
    expiresAt: expiresAt && !Number.isNaN(expiresAt.getTime()) ? expiresAt.toISOString() : null,
    resolvedAt: resolvedAt && !Number.isNaN(resolvedAt.getTime()) ? resolvedAt.toISOString() : null,
    resolvedBySub: row.resolved_by_sub ?? null,
    resolvedByEmail: row.resolved_by_email ?? null,
    denyReason: row.deny_reason ?? null,
    posSessionId: row.pos_session_id == null ? null : Number(row.pos_session_id),
    cashMode: row.till_type ?? row.cash_mode ?? null,
    expectedOpeningFloat:
      row.expected_opening_float == null ? null : Number(row.expected_opening_float),
    openingCountedFloat:
      row.opening_counted_float == null ? null : Number(row.opening_counted_float),
    openingVariance: row.opening_variance == null ? null : Number(row.opening_variance),
    openingDenominations: parseOpeningDenominations(row.opening_denominations),
    tillSubmittedAt:
      tillSubmittedAt && !Number.isNaN(tillSubmittedAt.getTime())
        ? tillSubmittedAt.toISOString()
        : null,
    secondsRemaining,
  };
}

function makeError(message, code, status = 400) {
  const err = new Error(message);
  err.code = code;
  err.status = status;
  return err;
}

function assertCashierClaims(claims) {
  const sub = String(claims?.sub || '').trim();
  if (!sub) throw makeError('Missing cashier identity (sub)', 'MISSING_SUB', 400);

  const requiredGroup = getCashierGroupName();
  if (!requiredGroup) return sub;

  const groups = normalizeGroups(claims);
  // Skip when IdP has not yet been configured to emit group claims.
  if (groups.length === 0) return sub;

  if (!groups.includes(requiredGroup)) {
    throw makeError(`Cashier must belong to group ${requiredGroup}`, 'CASHIER_GROUP', 403);
  }
  return sub;
}

function assertSupervisorClaims(supervisor) {
  const sub = String(supervisor?.sub || '').trim();
  if (!sub) throw makeError('Missing supervisor identity (sub)', 'MISSING_SUPERVISOR', 400);
  return sub;
}

function isExpiredRow(row) {
  if (!row?.expires_at) return false;
  const expiresAt = new Date(row.expires_at);
  if (Number.isNaN(expiresAt.getTime())) return false;
  return expiresAt.getTime() <= Date.now();
}

function rowToOrdPutBody(row, patch) {
  return {
    request_token: row.request_token,
    status: patch.status ?? row.status,
    cashier_sub: row.cashier_sub,
    cashier_email: row.cashier_email ?? null,
    cashier_name: row.cashier_name ?? null,
    register_id: row.register_id ?? null,
    client_kind: row.client_kind ?? null,
    requested_at: row.requested_at,
    expires_at: patch.expires_at ?? row.expires_at,
    resolved_at: patch.resolved_at ?? row.resolved_at ?? null,
    resolved_by_sub: patch.resolved_by_sub ?? row.resolved_by_sub ?? null,
    resolved_by_email: patch.resolved_by_email ?? row.resolved_by_email ?? null,
    deny_reason: patch.deny_reason ?? row.deny_reason ?? null,
    pos_session_id: patch.pos_session_id ?? row.pos_session_id ?? null,
    till_type: patch.till_type ?? row.till_type ?? row.cash_mode ?? null,
    expected_opening_float:
      patch.expected_opening_float ?? row.expected_opening_float ?? null,
    opening_counted_float:
      patch.opening_counted_float ?? row.opening_counted_float ?? null,
    opening_variance: patch.opening_variance ?? row.opening_variance ?? null,
    opening_denominations:
      patch.opening_denominations ?? row.opening_denominations ?? null,
    till_submitted_at: patch.till_submitted_at ?? row.till_submitted_at ?? null,
  };
}

/**
 * ORDS-backed login approval store (Model B).
 * @param {{ ordsGet: Function, ordsPost: Function, ordsPut: Function, ordsTryGet?: Function, ordsTimestamp: Function }} helpers
 */
function createLoginApprovalStore(helpers) {
  const { ordsGet, ordsPost, ordsPut, ordsTimestamp } = helpers;

  async function fetchRowsByQuery(filter) {
    const q = encodeURIComponent(JSON.stringify(filter));
    const rows = await ordsGet(`${ORDS_PATH}/?q=${q}`);
    return Array.isArray(rows) ? rows : [];
  }

  async function findRawByToken(requestToken) {
    const token = String(requestToken || '').trim();
    if (!token) return null;
    const rows = await fetchRowsByQuery({ request_token: { $eq: token } });
    return rows[0] || null;
  }

  async function markExpired(row) {
    if (!row || row.status !== STATUS.PENDING) return mapRow(row);
    const body = rowToOrdPutBody(row, {
      status: STATUS.EXPIRED,
      resolved_at: ordsTimestamp(),
    });
    await ordsPut(`${ORDS_PATH}/${row.id}`, body);
    return mapRow({ ...row, status: STATUS.EXPIRED, resolved_at: body.resolved_at });
  }

  async function resolveRow(row) {
    if (!row) return null;
    if (row.status === STATUS.PENDING && isExpiredRow(row)) {
      return markExpired(row);
    }
    return mapRow(row);
  }

  async function findByToken(requestToken) {
    const row = await findRawByToken(requestToken);
    if (!row) return null;
    return resolveRow(row);
  }

  async function listPending({ cashierSub = null, limit = 50 } = {}) {
    const rows = await fetchRowsByQuery({ status: { $eq: STATUS.PENDING } });
    let mapped = [];
    for (const row of rows) {
      mapped.push(await resolveRow(row));
    }
    mapped = mapped.filter((row) => row && row.status === STATUS.PENDING);
    if (cashierSub) {
      mapped = mapped.filter((row) => row.cashierSub === cashierSub);
    }
    mapped.sort((a, b) => String(a.requestedAt).localeCompare(String(b.requestedAt)));
    return mapped.slice(0, limit);
  }

  async function expireStaleRows() {
    const rows = await fetchRowsByQuery({ status: { $eq: STATUS.PENDING } });
    let expiredCount = 0;
    for (const row of rows) {
      if (isExpiredRow(row)) {
        await markExpired(row);
        expiredCount += 1;
      }
    }
    return expiredCount;
  }

  async function createRequest({
    claims,
    registerId = null,
    clientKind = 'web',
    till = null,
    pinAuth = false,
    posSessionId = null,
  }) {
    await expireStaleRows();

    const tillSubmittedAt = ordsTimestamp();
    const resolvedTill =
      till ||
      (isCashTillConfigured()
        ? null
        : { cashMode: CASH_MODE.CREDIT_ONLY });

    const cashierSub = pinAuth
      ? 'pin:cashier'
      : assertCashierClaims(claims);
    const existing = await listPending({ cashierSub, limit: 1 });
    if (existing.length > 0) {
      if (resolvedTill) {
        const raw = await findRawByToken(existing[0].requestToken);
        if (raw) {
          const body = rowToOrdPutBody(raw, {
            ...tillFieldsForApproval(resolvedTill),
            till_submitted_at: tillSubmittedAt,
          });
          await ordsPut(`${ORDS_PATH}/${raw.id}`, body);
          const updated = await findByToken(existing[0].requestToken);
          if (updated) {
            return { ...updated, reused: true };
          }
        }
      }
      return { ...existing[0], reused: true };
    }

    const requestToken = crypto.randomBytes(24).toString('hex');
    const ttlSec = getApprovalTtlSec();
    const requestedAt = ordsTimestamp();
    const expiresAt = ordsTimestamp(new Date(Date.now() + ttlSec * 1000));

    const body = {
      request_token: requestToken,
      status: STATUS.PENDING,
      pos_session_id: posSessionId == null ? null : Number(posSessionId),
      cashier_sub: cashierSub,
      cashier_email: pinAuth
        ? null
        : claimsEmail(claims) || identityFromCashierSub(cashierSub),
      cashier_name: pinAuth
        ? 'Cashier'
        : claimsDisplayName(claims) || identityFromCashierSub(cashierSub) || cashierSub,
      register_id: registerId ? String(registerId).trim() : null,
      client_kind: clientKind ? String(clientKind).trim() : null,
      requested_at: requestedAt,
      expires_at: expiresAt,
      till_submitted_at: resolvedTill ? tillSubmittedAt : null,
      ...tillFieldsForApproval(resolvedTill),
    };

    if (!resolvedTill && isCashTillConfigured()) {
      throw makeError('Opening till count is required before supervisor approval', 'TILL_REQUIRED', 400);
    }

    if (!resolvedTill && !isCashTillConfigured()) {
      body.till_type = CASH_MODE.CREDIT_ONLY;
    }

    await ordsPost(`${ORDS_PATH}/`, body);
    const created = await findByToken(requestToken);
    if (!created) {
      throw makeError('Failed to load created login approval request', 'CREATE_FAILED', 500);
    }
    return created;
  }

  async function approve(requestToken, supervisorClaims) {
    assertSupervisorClaims(supervisorClaims);
    const supervisor = supervisorFromClaims(supervisorClaims);

    const row = await findRawByToken(requestToken);
    if (!row) throw makeError('Login approval request not found', 'NOT_FOUND', 404);

    const current = await resolveRow(row);
    if (current.status === STATUS.APPROVED) return current;
    if (current.status !== STATUS.PENDING) {
      throw makeError(`Request is already ${current.status}`, 'NOT_PENDING', 409);
    }

    const resolvedAt = ordsTimestamp();
    const body = rowToOrdPutBody(row, {
      status: STATUS.APPROVED,
      resolved_at: resolvedAt,
      resolved_by_sub: supervisor.sub,
      resolved_by_email: supervisor.email,
      deny_reason: null,
    });
    await ordsPut(`${ORDS_PATH}/${row.id}`, body);
    return findByToken(requestToken);
  }

  async function deny(requestToken, supervisorClaims, reason = null) {
    assertSupervisorClaims(supervisorClaims);
    const supervisor = supervisorFromClaims(supervisorClaims);

    const row = await findRawByToken(requestToken);
    if (!row) throw makeError('Login approval request not found', 'NOT_FOUND', 404);

    const current = await resolveRow(row);
    if (current.status === STATUS.DENIED) return current;
    if (current.status !== STATUS.PENDING) {
      throw makeError(`Request is already ${current.status}`, 'NOT_PENDING', 409);
    }

    const denyReason = reason ? String(reason).trim().slice(0, 500) : 'Denied by supervisor';
    const body = rowToOrdPutBody(row, {
      status: STATUS.DENIED,
      resolved_at: ordsTimestamp(),
      resolved_by_sub: supervisor.sub,
      resolved_by_email: supervisor.email,
      deny_reason: denyReason,
    });
    await ordsPut(`${ORDS_PATH}/${row.id}`, body);
    return findByToken(requestToken);
  }

  async function cancel(requestToken) {
    const row = await findRawByToken(requestToken);
    if (!row) throw makeError('Login approval request not found', 'NOT_FOUND', 404);

    const current = await resolveRow(row);
    if (current.status === STATUS.CANCELLED) return current;
    if (current.status !== STATUS.PENDING) {
      throw makeError(`Request is already ${current.status}`, 'NOT_PENDING', 409);
    }

    const body = rowToOrdPutBody(row, {
      status: STATUS.CANCELLED,
      resolved_at: ordsTimestamp(),
      deny_reason: 'cancelled_by_cashier',
    });
    await ordsPut(`${ORDS_PATH}/${row.id}`, body);
    return findByToken(requestToken);
  }

  async function cancelPendingForCashier(cashierSub) {
    const sub = String(cashierSub || '').trim();
    if (!sub) return 0;
    const rows = await listPending({ cashierSub: sub, limit: 20 });
    let cancelled = 0;
    for (const row of rows) {
      try {
        await cancel(row.requestToken);
        cancelled += 1;
      } catch (err) {
        if (Number(err.status) !== 404 && Number(err.status) !== 400) {
          console.warn('cancelPendingForCashier', err.message);
        }
      }
    }
    return cancelled;
  }

  async function findLatestIdentityForCashier(cashierSub) {
    const sub = String(cashierSub || '').trim();
    if (!sub) return null;

    const rows = await fetchRowsByQuery({ cashier_sub: { $eq: sub } });
    const sorted = rows
      .filter((row) => row.status === STATUS.APPROVED || row.status === STATUS.PENDING)
      .sort((a, b) => String(b.requested_at || '').localeCompare(String(a.requested_at || '')));

    for (const row of sorted) {
      const mapped = await resolveRow(row);
      if (
        mapped?.cashierEmail ||
        mapped?.cashierName ||
        identityFromCashierSub(mapped?.cashierSub)
      ) {
        return mapped;
      }
    }
    return null;
  }

  async function probeTillColumns() {
    const rows = await fetchRowsByQuery({ status: { $eq: STATUS.PENDING } });
    const sample = rows[0] || null;
    if (!sample) {
      return { ok: true, note: 'no pending rows to inspect' };
    }
    if (!Object.prototype.hasOwnProperty.call(sample, 'cash_mode')) {
      return {
        ok: false,
        message:
          'login_approval_requests is missing till columns in ORDS. Run ./scripts/migrate-login-approval-till.sh then deny stale pending logins.',
      };
    }
    return { ok: true };
  }

  return {
    STATUS,
    TERMINAL_STATUSES,
    findByToken,
    findLatestIdentityForCashier,
    listPending,
    expireStaleRows,
    createRequest,
    approve,
    deny,
    cancel,
    cancelPendingForCashier,
    mapRow,
    probeTillColumns,
  };
}

module.exports = {
  ORDS_PATH,
  STATUS,
  TERMINAL_STATUSES,
  isSupervisorApprovalEnabled,
  getApprovalTtlSec,
  getCashierGroupName,
  normalizeGroups,
  claimsDisplayName,
  claimsEmail,
  identityFromApproval,
  identityFromCashierSub,
  supervisorFromClaims,
  mapRow,
  parseOpeningDenominations,
  createLoginApprovalStore,
};
