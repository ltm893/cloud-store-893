const crypto = require('crypto');
const { CASH_MODE, parseTillSubmit, getDenominations } = require('./cash-till-config');
const { getApprovalTtlSec } = require('./login-approval');
const { TILL_STATUS } = require('./tills');

const ORDS_PATH = 'till_close_approvals';

const STATUS = {
  PENDING: 'pending',
  APPROVED: 'approved',
  DENIED: 'denied',
  CANCELLED: 'cancelled',
};

function makeError(message, code, status = 400) {
  const err = new Error(message);
  err.code = code;
  err.status = status;
  return err;
}

function rowToOrdPutBody(row, patch) {
  return {
    close_token: row.close_token,
    till_id: row.till_id,
    register_id: row.register_id ?? null,
    cashier_sub: row.cashier_sub,
    cashier_email: row.cashier_email ?? null,
    cashier_name: row.cashier_name ?? null,
    till_type: row.till_type ?? row.cash_mode,
    expected_close_float: row.expected_close_float ?? null,
    counted_close_float: row.counted_close_float ?? null,
    close_variance: row.close_variance ?? null,
    close_denominations: row.close_denominations ?? null,
    cash_sales_total: row.cash_sales_total ?? null,
    change_given_total: row.change_given_total ?? null,
    opening_counted_float: row.opening_counted_float ?? null,
    status: patch.status ?? row.status,
    requested_at: row.requested_at,
    expires_at: row.expires_at,
    resolved_at: patch.resolved_at ?? row.resolved_at ?? null,
    resolved_by_sub: patch.resolved_by_sub ?? row.resolved_by_sub ?? null,
    resolved_by_email: patch.resolved_by_email ?? row.resolved_by_email ?? null,
    deny_reason: patch.deny_reason ?? row.deny_reason ?? null,
  };
}

function mapRow(row) {
  if (!row || typeof row !== 'object') return null;
  const expiresAt = row.expires_at ? new Date(row.expires_at) : null;
  const requestedAt = row.requested_at ? new Date(row.requested_at) : null;
  const resolvedAt = row.resolved_at ? new Date(row.resolved_at) : null;
  const expiresMs = expiresAt && !Number.isNaN(expiresAt.getTime()) ? expiresAt.getTime() : null;
  const secondsRemaining =
    expiresMs == null ? null : Math.max(0, Math.ceil((expiresMs - Date.now()) / 1000));

  let closeDenominations = null;
  if (row.close_denominations) {
    try {
      closeDenominations = JSON.parse(String(row.close_denominations));
    } catch {
      closeDenominations = null;
    }
  }

  return {
    id: Number(row.id),
    closeToken: row.close_token,
    tillId: Number(row.till_id),
    shiftId: Number(row.till_id),
    registerId: row.register_id ?? null,
    cashierSub: row.cashier_sub,
    cashierEmail: row.cashier_email ?? null,
    cashierName: row.cashier_name ?? null,
    cashMode: row.till_type ?? row.cash_mode,
    tillType: row.till_type ?? row.cash_mode,
    expectedCloseFloat: row.expected_close_float == null ? null : Number(row.expected_close_float),
    countedCloseFloat: row.counted_close_float == null ? null : Number(row.counted_close_float),
    closeVariance: row.close_variance == null ? null : Number(row.close_variance),
    closeDenominations,
    cashSalesTotal: row.cash_sales_total == null ? null : Number(row.cash_sales_total),
    changeGivenTotal: row.change_given_total == null ? null : Number(row.change_given_total),
    openingCountedFloat: row.opening_counted_float == null ? null : Number(row.opening_counted_float),
    status: row.status,
    requestedAt: requestedAt && !Number.isNaN(requestedAt.getTime()) ? requestedAt.toISOString() : null,
    expiresAt: expiresAt && !Number.isNaN(expiresAt.getTime()) ? expiresAt.toISOString() : null,
    resolvedAt: resolvedAt && !Number.isNaN(resolvedAt.getTime()) ? resolvedAt.toISOString() : null,
    resolvedBySub: row.resolved_by_sub ?? null,
    resolvedByEmail: row.resolved_by_email ?? null,
    denyReason: row.deny_reason ?? null,
    secondsRemaining,
  };
}

/**
 * @param {{ ordsGet: Function, ordsPost: Function, ordsPut: Function, ordsTimestamp: Function, shiftCloseCash: object, tillStore: object }} deps
 */
function createTillCloseStore(deps) {
  const { ordsGet, ordsPost, ordsPut, ordsTimestamp, shiftCloseCash, tillStore } = deps;

  async function findRawByToken(closeToken) {
    const rows = await ordsGet(
      `${ORDS_PATH}/?q=${encodeURIComponent(JSON.stringify({ close_token: { $eq: closeToken } }))}`,
    );
    return Array.isArray(rows) ? rows[0] : null;
  }

  async function findByToken(closeToken) {
    const row = await findRawByToken(closeToken);
    return mapRow(row);
  }

  async function findPendingForTill(tillId) {
    const rows = await ordsGet(
      `${ORDS_PATH}/?q=${encodeURIComponent(JSON.stringify({
        till_id: { $eq: Number(tillId) },
        status: { $eq: STATUS.PENDING },
      }))}`,
    );
    const row = Array.isArray(rows) ? rows[0] : null;
    return mapRow(row);
  }

  async function findLatestForTill(tillId) {
    const rows = await ordsGet(
      `${ORDS_PATH}/?q=${encodeURIComponent(JSON.stringify({
        till_id: { $eq: Number(tillId) },
      }))}`,
    );
    const mapped = (Array.isArray(rows) ? rows : []).map(mapRow).filter(Boolean);
    mapped.sort((a, b) => String(b.requestedAt).localeCompare(String(a.requestedAt)));
    return mapped[0] ?? null;
  }

  async function listPending({ limit = 50 } = {}) {
    const rows = await ordsGet(
      `${ORDS_PATH}/?q=${encodeURIComponent(JSON.stringify({ status: { $eq: STATUS.PENDING } }))}`,
    );
    const mapped = (Array.isArray(rows) ? rows : []).map(mapRow).filter(Boolean);
    mapped.sort((a, b) => String(a.requestedAt).localeCompare(String(b.requestedAt)));
    return mapped.slice(0, limit);
  }

  async function createCloseRequest({ till, cashierEmail, cashierName, body }) {
    if (!till?.id) throw makeError('Active till is required', 'NO_TILL', 400);
    if (till.status !== TILL_STATUS.ACTIVE && till.status !== TILL_STATUS.IN_PROGRESS) {
      throw makeError('Till is not active', 'TILL_NOT_ACTIVE', 409);
    }

    const existing = await findPendingForTill(till.id);
    if (existing) return existing;

    const cashMode = String(till.cashMode || till.tillType || '').trim();
    const isCreditOnly = cashMode === CASH_MODE.CREDIT_ONLY;
    const cashTotals = isCreditOnly
      ? {
          openingCountedFloat: null,
          cashSalesTotal: 0,
          changeGivenTotal: 0,
          expectedClose: 0,
        }
      : await shiftCloseCash.computeExpectedClose(till);

    let countedCloseFloat = null;
    let closeDenominations = null;
    let closeVariance = null;

    if (isCreditOnly) {
      const mode = String(body?.cashMode || CASH_MODE.CREDIT_ONLY).trim();
      if (mode !== CASH_MODE.CREDIT_ONLY) {
        throw makeError('credit_only close required for credit-only tills', 'INVALID_CLOSE_MODE', 400);
      }
    } else {
      const tillSubmit = parseTillSubmit(body, getDenominations());
      if (tillSubmit.cashMode !== CASH_MODE.CASH_AND_CREDIT) {
        throw makeError('Closing cash till requires denomination count', 'CLOSE_COUNT_REQUIRED', 400);
      }
      countedCloseFloat = tillSubmit.countedTotal;
      closeDenominations = tillSubmit.denominations;
      closeVariance = shiftCloseCash.closeVariance(countedCloseFloat, cashTotals.expectedClose);
    }

    const closeToken = crypto.randomBytes(24).toString('hex');
    const ttlSec = getApprovalTtlSec();
    const requestedAt = ordsTimestamp();
    const expiresAt = ordsTimestamp(new Date(Date.now() + ttlSec * 1000));

    await ordsPost(`${ORDS_PATH}/`, {
      close_token: closeToken,
      till_id: till.id,
      register_id: till.registerId ?? null,
      cashier_sub: till.cashierSub,
      cashier_email: cashierEmail ?? till.cashierEmail ?? null,
      cashier_name: cashierName ?? null,
      till_type: cashMode,
      expected_close_float: cashTotals.expectedClose,
      counted_close_float: countedCloseFloat,
      close_variance: closeVariance,
      close_denominations: closeDenominations ? JSON.stringify(closeDenominations) : null,
      cash_sales_total: cashTotals.cashSalesTotal,
      change_given_total: cashTotals.changeGivenTotal,
      opening_counted_float: cashTotals.openingCountedFloat,
      status: STATUS.PENDING,
      requested_at: requestedAt,
      expires_at: expiresAt,
    });

    await tillStore.setTillStatus(till.id, TILL_STATUS.IN_PROGRESS);

    const created = await findByToken(closeToken);
    if (!created) throw makeError('Failed to load created till close request', 'CREATE_FAILED', 500);
    return created;
  }

  async function approve(closeToken, supervisorClaims) {
    const row = await findRawByToken(closeToken);
    if (!row) throw makeError('Close request not found', 'NOT_FOUND', 404);
    if (row.status !== STATUS.PENDING) {
      throw makeError(`Close request is ${row.status}`, 'NOT_PENDING', 409);
    }

    const supervisorSub = String(supervisorClaims?.sub || '').trim();
    const supervisorEmail = String(supervisorClaims?.email || '').trim() || null;
    await ordsPut(
      `${ORDS_PATH}/${row.id}`,
      rowToOrdPutBody(row, {
        status: STATUS.APPROVED,
        resolved_at: ordsTimestamp(),
        resolved_by_sub: supervisorSub || null,
        resolved_by_email: supervisorEmail,
      }),
    );

    const stats = await shiftCloseCash.summarizeTillSales(row.till_id);
    await tillStore.closeTill(row.till_id, {
      cashSales: stats.cashTotal,
      creditSales: stats.creditTotal,
    });
    return findByToken(closeToken);
  }

  async function deny(closeToken, supervisorClaims, reason) {
    const row = await findRawByToken(closeToken);
    if (!row) throw makeError('Close request not found', 'NOT_FOUND', 404);
    if (row.status !== STATUS.PENDING) {
      throw makeError(`Close request is ${row.status}`, 'NOT_PENDING', 409);
    }

    const supervisorSub = String(supervisorClaims?.sub || '').trim();
    const supervisorEmail = String(supervisorClaims?.email || '').trim() || null;
    await ordsPut(
      `${ORDS_PATH}/${row.id}`,
      rowToOrdPutBody(row, {
        status: STATUS.DENIED,
        resolved_at: ordsTimestamp(),
        resolved_by_sub: supervisorSub || null,
        resolved_by_email: supervisorEmail,
        deny_reason: reason ? String(reason).trim().slice(0, 500) : null,
      }),
    );

    await tillStore.setTillStatus(row.till_id, TILL_STATUS.ACTIVE);
    return findByToken(closeToken);
  }

  async function cancelForTill(tillId) {
    const pending = await findPendingForTill(tillId);
    if (!pending) return null;
    const row = await findRawByToken(pending.closeToken);
    if (!row) return null;
    await ordsPut(
      `${ORDS_PATH}/${row.id}`,
      rowToOrdPutBody(row, {
        status: STATUS.CANCELLED,
        resolved_at: ordsTimestamp(),
      }),
    );
    await tillStore.setTillStatus(tillId, TILL_STATUS.ACTIVE);
    return findByToken(pending.closeToken);
  }

  return {
    STATUS,
    shiftCloseCash,
    mapRow,
    findByToken,
    findPendingForTill,
    findLatestForTill,
    findPendingForShift: findPendingForTill,
    findLatestForShift: findLatestForTill,
    listPending,
    createCloseRequest,
    approve,
    deny,
    cancelForTill,
    cancelForShift: cancelForTill,
  };
}

module.exports = {
  STATUS,
  createTillCloseStore,
  createShiftCloseStore: createTillCloseStore,
};
