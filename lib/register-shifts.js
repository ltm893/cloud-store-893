const ORDS_PATH = 'register_shifts';

const SHIFT_STATUS = {
  OPEN: 'open',
  CLOSED: 'closed',
};

function mapShiftRow(row) {
  if (!row || typeof row !== 'object') return null;
  const openedAt = row.opened_at ? new Date(row.opened_at) : null;
  return {
    id: Number(row.id),
    registerId: row.register_id ?? null,
    cashierSub: row.cashier_sub,
    cashierEmail: row.cashier_email ?? null,
    cashMode: row.cash_mode,
    expectedOpeningFloat:
      row.expected_opening_float == null ? null : Number(row.expected_opening_float),
    openingCountedFloat:
      row.opening_counted_float == null ? null : Number(row.opening_counted_float),
    openingVariance: row.opening_variance == null ? null : Number(row.opening_variance),
    approvalRequestToken: row.approval_request_token ?? null,
    openedAt: openedAt && !Number.isNaN(openedAt.getTime()) ? openedAt.toISOString() : null,
    status: row.status,
  };
}

/**
 * @param {{ ordsGet: Function, ordsPost: Function, ordsTimestamp: Function }} helpers
 */
function createRegisterShiftStore(helpers) {
  const { ordsGet, ordsPost, ordsTimestamp } = helpers;

  async function createFromApproval(approval) {
    if (!approval?.cashierSub) {
      throw new Error('Cannot open register shift without cashier identity');
    }

    const body = {
      register_id: approval.registerId ?? null,
      cashier_sub: approval.cashierSub,
      cashier_email: approval.cashierEmail ?? null,
      cash_mode: approval.cashMode || 'credit_only',
      expected_opening_float: approval.expectedOpeningFloat ?? null,
      opening_counted_float: approval.openingCountedFloat ?? null,
      opening_variance: approval.openingVariance ?? null,
      opening_denominations: approval.openingDenominations
        ? JSON.stringify(approval.openingDenominations)
        : null,
      approval_request_token: approval.requestToken ?? null,
      opened_at: ordsTimestamp(),
      status: SHIFT_STATUS.OPEN,
    };

    await ordsPost(`${ORDS_PATH}/`, body);
    const rows = await ordsGet(`${ORDS_PATH}/?q=${encodeURIComponent(JSON.stringify({
      approval_request_token: { $eq: approval.requestToken },
    }))}`);
    const row = Array.isArray(rows) ? rows[0] : null;
    return mapShiftRow(row);
  }

  return {
    SHIFT_STATUS,
    mapShiftRow,
    createFromApproval,
  };
}

module.exports = {
  SHIFT_STATUS,
  mapShiftRow,
  createRegisterShiftStore,
};
