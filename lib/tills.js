const { cashierMatchesShift: cashierMatchesTill } = require('./cashier-identity-match');

const ORDS_PATH = 'tills';

const TILL_STATUS = {
  ACTIVE: 'active',
  IN_PROGRESS: 'in_progress',
  CLOSED: 'closed',
};

function mapTillRow(row) {
  if (!row || typeof row !== 'object') return null;
  const openedAt = row.opened_at ? new Date(row.opened_at) : null;
  return {
    id: Number(row.id),
    posSessionId: Number(row.pos_session_id),
    registerId: row.register_id ?? null,
    cashierSub: row.cashier_sub,
    cashierEmail: row.cashier_email ?? null,
    tillType: row.till_type,
    cashMode: row.till_type,
    expectedOpeningFloat:
      row.expected_opening_float == null ? null : Number(row.expected_opening_float),
    openingCountedFloat:
      row.opening_counted_float == null ? null : Number(row.opening_counted_float),
    openingVariance: row.opening_variance == null ? null : Number(row.opening_variance),
    openApprovalToken: row.open_approval_token ?? null,
    cashSales: row.cash_sales == null ? 0 : Number(row.cash_sales),
    creditSales: row.credit_sales == null ? 0 : Number(row.credit_sales),
    openedAt: openedAt && !Number.isNaN(openedAt.getTime()) ? openedAt.toISOString() : null,
    status: row.status,
  };
}

function rowToOrdPutBody(row, patch) {
  return {
    pos_session_id: row.pos_session_id,
    register_id: patch.register_id ?? row.register_id ?? null,
    cashier_sub: row.cashier_sub,
    cashier_email: row.cashier_email ?? null,
    till_type: row.till_type,
    expected_opening_float: row.expected_opening_float ?? null,
    opening_counted_float: row.opening_counted_float ?? null,
    opening_variance: row.opening_variance ?? null,
    opening_denominations: row.opening_denominations ?? null,
    open_approval_token: row.open_approval_token ?? null,
    cash_sales: patch.cash_sales ?? row.cash_sales ?? 0,
    credit_sales: patch.credit_sales ?? row.credit_sales ?? 0,
    opened_at: row.opened_at,
    closed_at: patch.closed_at ?? row.closed_at ?? null,
    status: patch.status ?? row.status,
  };
}

function makeRegisterInUseError(activeTill) {
  const who = activeTill?.cashierEmail || activeTill?.cashierSub || 'another cashier';
  const err = new Error(
    `This tablet is in use by ${who}. They must sign off before you can sign in.`,
  );
  err.status = 409;
  err.code = 'REGISTER_IN_USE';
  return err;
}

function makeActiveTillOnOtherRegisterError(till) {
  const device = till?.registerId ? String(till.registerId) : 'another device';
  const err = new Error(
    `You already have an active till (#${till.id}) on ${device}. Close that till before opening a new one.`,
  );
  err.status = 409;
  err.code = 'ACTIVE_TILL_EXISTS';
  err.tillId = till.id;
  err.registerId = till.registerId ?? null;
  return err;
}

function makeMultipleActiveTillsError(tills) {
  const ids = tills.map((till) => `#${till.id}`).join(', ');
  const err = new Error(
    `You have ${tills.length} active tills (${ids}). Close duplicate tills before opening a new one.`,
  );
  err.status = 409;
  err.code = 'MULTIPLE_ACTIVE_TILLS';
  err.tillIds = tills.map((till) => till.id);
  return err;
}

/**
 * @param {{ ordsGet: Function, ordsPost: Function, ordsPut: Function, ordsTimestamp: Function }} helpers
 */
function createTillStore(helpers) {
  const { ordsGet, ordsPost, ordsPut, ordsTimestamp } = helpers;

  async function findActiveTillForRegister(registerId) {
    const trimmed = registerId ? String(registerId).trim() : '';
    if (!trimmed) return null;
    const rows = await ordsGet(`${ORDS_PATH}/?q=${encodeURIComponent(JSON.stringify({
      register_id: { $eq: trimmed },
      status: { $eq: TILL_STATUS.ACTIVE },
    }))}`);
    const row = Array.isArray(rows) ? rows[0] : null;
    return mapTillRow(row);
  }

  async function findActiveTillsForCashier({ sub, email } = {}) {
    const identity = { sub, email };
    const rows = await ordsGet(`${ORDS_PATH}/?q=${encodeURIComponent(JSON.stringify({
      status: { $eq: TILL_STATUS.ACTIVE },
    }))}`);
    return (Array.isArray(rows) ? rows : [])
      .map(mapTillRow)
      .filter((till) => till && cashierMatchesTill(till, identity));
  }

  async function findResumableActiveTill(registerId, { sub, email } = {}) {
    const trimmedRegister = registerId ? String(registerId).trim() : '';
    const openForCashier = await findActiveTillsForCashier({ sub, email });

    if (!openForCashier.length) return null;

    if (openForCashier.length > 1) {
      throw makeMultipleActiveTillsError(openForCashier);
    }

    const till = openForCashier[0];
    if (!trimmedRegister) return till;

    if (!till.registerId || till.registerId === trimmedRegister) {
      return till.registerId
        ? till
        : await backfillRegisterId(till.id, trimmedRegister);
    }

    throw makeActiveTillOnOtherRegisterError(till);
  }

  async function backfillRegisterId(tillId, registerId) {
    const trimmed = registerId ? String(registerId).trim() : '';
    if (!trimmed) return getTillById(tillId);
    return putTillRow(tillId, { register_id: trimmed });
  }

  async function assertRegisterAvailable(registerId, cashierSub, cashierEmail = null) {
    const trimmedRegister = registerId ? String(registerId).trim() : '';
    const trimmedSub = cashierSub ? String(cashierSub).trim() : '';
    if (!trimmedRegister || !trimmedSub) return null;

    const active = await findActiveTillForRegister(trimmedRegister);
    if (!active) return null;
    if (cashierMatchesTill(active, { sub: trimmedSub, email: cashierEmail })) return active;
    throw makeRegisterInUseError(active);
  }

  async function getRawTillById(tillId) {
    const id = Number(tillId);
    if (!Number.isFinite(id) || id <= 0) return null;
    const row = await ordsGet(`${ORDS_PATH}/${id}`);
    if (!row || typeof row !== 'object') return null;
    return row;
  }

  async function getTillById(tillId) {
    return mapTillRow(await getRawTillById(tillId));
  }

  async function putTillRow(tillId, patch) {
    const id = Number(tillId);
    if (!Number.isFinite(id) || id <= 0) return null;
    const row = await getRawTillById(id);
    if (!row) return null;
    await ordsPut(`${ORDS_PATH}/${id}`, rowToOrdPutBody(row, patch));
    return getTillById(id);
  }

  async function setTillStatus(tillId, status) {
    return putTillRow(tillId, { status });
  }

  async function closeTill(tillId, { cashSales = null, creditSales = null } = {}) {
    const patch = {
      status: TILL_STATUS.CLOSED,
      closed_at: ordsTimestamp(),
    };
    if (cashSales != null) patch.cash_sales = cashSales;
    if (creditSales != null) patch.credit_sales = creditSales;
    return putTillRow(tillId, patch);
  }

  async function createFromApproval(approval, posSessionId) {
    if (!approval?.cashierSub) {
      throw new Error('Cannot open till without cashier identity');
    }
    const posId = Number(posSessionId);
    if (!Number.isFinite(posId) || posId <= 0) {
      throw new Error('Cannot open till without active POS session');
    }

    const registerId = approval.registerId ? String(approval.registerId).trim() : null;
    const existing = await assertRegisterAvailable(
      registerId,
      approval.cashierSub,
      approval.cashierEmail,
    );
    if (existing?.id) return existing;

    const resumed = await findResumableActiveTill(registerId, {
      sub: approval.cashierSub,
      email: approval.cashierEmail,
    });
    if (resumed?.id) return resumed;

    const body = {
      pos_session_id: posId,
      register_id: registerId,
      cashier_sub: approval.cashierSub,
      cashier_email: approval.cashierEmail ?? null,
      till_type: approval.cashMode || approval.tillType || 'credit_only',
      expected_opening_float: approval.expectedOpeningFloat ?? null,
      opening_counted_float: approval.openingCountedFloat ?? null,
      opening_variance: approval.openingVariance ?? null,
      opening_denominations: approval.openingDenominations
        ? JSON.stringify(approval.openingDenominations)
        : null,
      open_approval_token: approval.requestToken ?? null,
      cash_sales: 0,
      credit_sales: 0,
      opened_at: ordsTimestamp(),
      status: TILL_STATUS.ACTIVE,
    };

    await ordsPost(`${ORDS_PATH}/`, body);
    const rows = await ordsGet(`${ORDS_PATH}/?q=${encodeURIComponent(JSON.stringify({
      open_approval_token: { $eq: approval.requestToken },
    }))}`);
    const row = Array.isArray(rows) ? rows[0] : null;
    if (row) return mapTillRow(row);

    if (registerId) {
      return findActiveTillForRegister(registerId);
    }
    return null;
  }

  return {
    TILL_STATUS,
    mapTillRow,
    findActiveTillForRegister,
    findActiveTillsForCashier,
    findResumableActiveTill,
    backfillRegisterId,
    assertRegisterAvailable,
    getTillById,
    setTillStatus,
    closeTill,
    createFromApproval,
  };
}

module.exports = {
  TILL_STATUS,
  mapTillRow,
  makeRegisterInUseError,
  makeActiveTillOnOtherRegisterError,
  makeMultipleActiveTillsError,
  createTillStore,
};
