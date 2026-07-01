'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createShiftCloseStore } = require('../lib/shift-close-store');
const { createTillStore } = require('../lib/tills');
const { createShiftCloseCash } = require('../lib/shift-close-cash');

function mockDeps({ tills = [], closes = [] } = {}) {
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
        if (q.close_token?.$eq && row.close_token !== q.close_token.$eq) return false;
        if (q.register_id?.$eq && row.register_id !== q.register_id.$eq) return false;
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
    if (path.startsWith('till_close_approvals')) {
      const row = { id: nextCloseId++, ...body };
      closeTable.push(row);
      return row;
    }
    const row = { id: nextCloseId++, ...body };
    tillTable.push(row);
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

  const store = createShiftCloseStore({
    ordsGet,
    ordsPost,
    ordsPut,
    ordsTimestamp: () => '2026-06-11T12:00:00Z',
    shiftCloseCash: createShiftCloseCash({ ordsGet: async () => [] }),
    tillStore,
  });

  return { store, tillTable, closeTable };
}

test('findLatestForTill returns most recent close request for till', async () => {
  const { store } = mockDeps({
    closes: [
      {
        id: 1,
        close_token: 'older',
        till_id: 23,
        cashier_sub: 'sub-a',
        till_type: 'credit_only',
        status: 'denied',
        requested_at: '2026-06-10T10:00:00Z',
        expires_at: '2026-06-10T10:05:00Z',
      },
      {
        id: 2,
        close_token: 'newer',
        till_id: 23,
        cashier_sub: 'sub-a',
        till_type: 'credit_only',
        status: 'approved',
        requested_at: '2026-06-11T12:00:00Z',
        expires_at: '2026-06-11T12:05:00Z',
      },
    ],
  });

  const latest = await store.findLatestForTill(23);
  assert.equal(latest.closeToken, 'newer');
  assert.equal(latest.status, 'approved');
});

test('findPendingForTill ignores approved rows', async () => {
  const { store } = mockDeps({
    closes: [
      {
        id: 2,
        close_token: 'newer',
        till_id: 23,
        cashier_sub: 'sub-a',
        till_type: 'credit_only',
        status: 'approved',
        requested_at: '2026-06-11T12:00:00Z',
        expires_at: '2026-06-11T12:05:00Z',
      },
    ],
  });

  const pending = await store.findPendingForTill(23);
  assert.equal(pending, null);
  const latest = await store.findLatestForTill(23);
  assert.equal(latest.status, 'approved');
});

test('forceClose closes active till and writes force_closed audit row', async () => {
  const { store, tillTable, closeTable } = mockDeps({
    tills: [
      {
        id: 10,
        pos_session_id: 5,
        register_id: 'tablet-1',
        cashier_sub: 'sub-a',
        cashier_email: 'cashier@example.com',
        till_type: 'credit_only',
        status: 'active',
        opened_at: '2026-06-11T08:00:00Z',
        cash_sales: 0,
        credit_sales: 0,
      },
    ],
  });

  const result = await store.forceClose(10, { sub: 'sup-1', email: 'sup@example.com' }, {
    reason: 'Abandoned tablet',
  });

  assert.equal(result.till.status, 'closed');
  assert.equal(result.till.id, 10);
  assert.equal(result.audit.status, 'force_closed');
  assert.equal(result.audit.denyReason, 'Abandoned tablet');
  assert.equal(result.audit.resolvedByEmail, 'sup@example.com');

  const tillRow = tillTable.find((row) => row.id === 10);
  assert.equal(tillRow.status, 'closed');
  assert.ok(tillRow.closed_at);

  const auditRow = closeTable.find((row) => row.status === 'force_closed');
  assert.equal(auditRow.till_id, 10);
});

test('forceClose rejects already closed till', async () => {
  const { store } = mockDeps({
    tills: [
      {
        id: 11,
        pos_session_id: 6,
        register_id: 'tablet-2',
        cashier_sub: 'sub-b',
        till_type: 'credit_only',
        status: 'closed',
        opened_at: '2026-06-11T08:00:00Z',
      },
    ],
  });

  await assert.rejects(
    () => store.forceClose(11, { sub: 'sup-1', email: 'sup@example.com' }),
    (err) => err.code === 'NOT_OPEN',
  );
});
