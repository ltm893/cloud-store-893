'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createTillSaleGuard, MSG_FORCE_CLOSED } = require('../lib/till-sale-guard');
const { createShiftCloseStore } = require('../lib/shift-close-store');
const { createTillStore } = require('../lib/tills');
const { createShiftCloseCash } = require('../lib/shift-close-cash');
const { POS_STATUS } = require('../lib/pos-sessions');

function mockDeps({ tills = [], closes = [], posSessions = {} } = {}) {
  const tillTable = [...tills];
  const closeTable = [...closes];
  let nextCloseId = 200;

  const ordsGet = async (path) => {
    const table = path.startsWith('tills/') ? tillTable : closeTable;

    if (path.includes('?q=')) {
      const q = JSON.parse(decodeURIComponent(path.split('?q=')[1]));
      const matches = table.filter((row) => {
        if (q.till_id?.$eq != null && Number(row.till_id) !== Number(q.till_id.$eq)) return false;
        if (q.status?.$eq && row.status !== q.status.$eq) return false;
        return true;
      });
      return matches;
    }

    const id = Number(path.split('/').pop());
    if (path.startsWith('tills/')) {
      return tillTable.find((row) => row.id === id) || null;
    }
    if (path.startsWith('till_close_approvals/')) {
      return closeTable.find((row) => row.id === id) || null;
    }
    return null;
  };

  const ordsPost = async (path, body) => {
    const row = { id: nextCloseId++, ...body };
    if (path.startsWith('till_close_approvals')) {
      closeTable.push(row);
    } else {
      tillTable.push(row);
    }
    return row;
  };

  const ordsPut = async (path, body) => {
    const id = Number(path.split('/').pop());
    const table = path.startsWith('tills/') ? tillTable : closeTable;
    const row = table.find((r) => r.id === id);
    if (row) Object.assign(row, body);
    return row;
  };

  const tillStore = createTillStore({
    ordsGet,
    ordsPost,
    ordsPut,
    ordsTimestamp: () => '2026-06-11T12:00:00Z',
  });

  const shiftCloseStore = createShiftCloseStore({
    ordsGet,
    ordsPost,
    ordsPut,
    ordsTimestamp: () => '2026-06-11T12:00:00Z',
    shiftCloseCash: createShiftCloseCash({ ordsGet: async () => [] }),
    tillStore,
  });

  const posSessionStore = {
    async getById(id) {
      return posSessions[id] ?? null;
    },
  };

  return { tillStore, shiftCloseStore, posSessionStore };
}

test('assertOpenForSale allows active till and POS session', async () => {
  const { tillStore, shiftCloseStore, posSessionStore } = mockDeps({
    tills: [{ id: 10, register_id: 'reg-1', status: 'active' }],
    posSessions: {
      99: { id: 99, status: POS_STATUS.ACTIVE },
    },
  });

  const guard = createTillSaleGuard({
    tillStore,
    posSessionStore,
    shiftCloseStore,
    getActiveCashierSession: () => ({ tillId: 10, posSessionId: 99 }),
  });

  const result = await guard.assertOpenForSale({});
  assert.equal(result.ok, true);
});

test('assertOpenForSale rejects force-closed till with supervisor message', async () => {
  const { tillStore, shiftCloseStore, posSessionStore } = mockDeps({
    tills: [{ id: 10, register_id: 'reg-1', status: 'closed' }],
    closes: [
      {
        id: 1,
        till_id: 10,
        status: 'force_closed',
        decided_at: '2026-06-11T13:00:00Z',
      },
    ],
    posSessions: {
      99: { id: 99, status: POS_STATUS.ENDED },
    },
  });

  const guard = createTillSaleGuard({
    tillStore,
    posSessionStore,
    shiftCloseStore,
    getActiveCashierSession: () => ({ tillId: 10, posSessionId: 99 }),
  });

  const result = await guard.assertOpenForSale({});
  assert.equal(result.ok, false);
  assert.equal(result.status, 403);
  assert.equal(result.code, 'TILL_FORCE_CLOSED');
  assert.equal(result.error, MSG_FORCE_CLOSED);
  assert.equal(result.tillClosedBySupervisor, true);
});

test('sessionFlags reports blocked sale for force-closed till', async () => {
  const { tillStore, shiftCloseStore, posSessionStore } = mockDeps({
    tills: [{ id: 10, register_id: 'reg-1', status: 'closed' }],
    closes: [
      {
        id: 1,
        till_id: 10,
        status: 'force_closed',
        decided_at: '2026-06-11T13:00:00Z',
      },
    ],
  });

  const guard = createTillSaleGuard({
    tillStore,
    posSessionStore,
    shiftCloseStore,
    getActiveCashierSession: () => ({ tillId: 10, posSessionId: 99 }),
  });

  const flags = await guard.sessionFlags({ tillId: 10, posSessionId: 99 });
  assert.equal(flags.tillOpenForSales, false);
  assert.equal(flags.tillClosedBySupervisor, true);
  assert.equal(flags.saleBlockedMessage, MSG_FORCE_CLOSED);
  assert.equal(flags.saleBlockedCode, 'TILL_FORCE_CLOSED');
});
