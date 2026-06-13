const ORDS_PATH = 'pos_sessions';

const POS_STATUS = {
  ACTIVE: 'active',
  ENDED: 'ended',
};

function mapPosSessionRow(row) {
  if (!row || typeof row !== 'object') return null;
  const startedAt = row.started_at ? new Date(row.started_at) : null;
  const endedAt = row.ended_at ? new Date(row.ended_at) : null;
  return {
    id: Number(row.id),
    registerId: row.register_id ?? null,
    cashierSub: row.cashier_sub,
    cashierEmail: row.cashier_email ?? null,
    status: row.status,
    startedAt: startedAt && !Number.isNaN(startedAt.getTime()) ? startedAt.toISOString() : null,
    endedAt: endedAt && !Number.isNaN(endedAt.getTime()) ? endedAt.toISOString() : null,
  };
}

function rowToOrdPutBody(row, patch) {
  return {
    register_id: patch.register_id ?? row.register_id ?? null,
    cashier_sub: row.cashier_sub,
    cashier_email: row.cashier_email ?? null,
    status: patch.status ?? row.status,
    started_at: row.started_at,
    ended_at: patch.ended_at ?? row.ended_at ?? null,
  };
}

/**
 * @param {{ ordsGet: Function, ordsPost: Function, ordsPut: Function, ordsTimestamp: Function }} helpers
 */
function createPosSessionStore(helpers) {
  const { ordsGet, ordsPost, ordsPut, ordsTimestamp } = helpers;

  async function getRawById(posSessionId) {
    const id = Number(posSessionId);
    if (!Number.isFinite(id) || id <= 0) return null;
    const row = await ordsGet(`${ORDS_PATH}/${id}`);
    return row && typeof row === 'object' ? row : null;
  }

  async function getById(posSessionId) {
    return mapPosSessionRow(await getRawById(posSessionId));
  }

  async function create({ registerId = null, cashierSub, cashierEmail = null }) {
    const trimmedSub = cashierSub ? String(cashierSub).trim() : '';
    if (!trimmedSub) {
      throw new Error('Cannot create POS session without cashier identity');
    }

    const body = {
      register_id: registerId ? String(registerId).trim() : null,
      cashier_sub: trimmedSub,
      cashier_email: cashierEmail ?? null,
      status: POS_STATUS.ACTIVE,
      started_at: ordsTimestamp(),
    };

    await ordsPost(`${ORDS_PATH}/`, body);
    const rows = await ordsGet(`${ORDS_PATH}/?q=${encodeURIComponent(JSON.stringify({
      cashier_sub: { $eq: trimmedSub },
      status: { $eq: POS_STATUS.ACTIVE },
    }))}`);
    const list = Array.isArray(rows) ? rows : [];
    list.sort((a, b) => String(b.started_at).localeCompare(String(a.started_at)));
    return mapPosSessionRow(list[0]);
  }

  async function end(posSessionId) {
    const id = Number(posSessionId);
    if (!Number.isFinite(id) || id <= 0) return null;
    const row = await getRawById(id);
    if (!row) return null;
    await ordsPut(`${ORDS_PATH}/${id}`, rowToOrdPutBody(row, {
      status: POS_STATUS.ENDED,
      ended_at: ordsTimestamp(),
    }));
    return getById(id);
  }

  return {
    POS_STATUS,
    mapPosSessionRow,
    getById,
    create,
    end,
  };
}

module.exports = {
  POS_STATUS,
  mapPosSessionRow,
  createPosSessionStore,
};
