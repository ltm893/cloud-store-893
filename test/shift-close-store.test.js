'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createShiftCloseStore } = require('../lib/shift-close-store');
const { createTillStore } = require('../lib/tills');
const { createShiftCloseCash } = require('../lib/shift-close-cash');

function mockDeps(rows = []) {
  const table = [...rows];
  let nextId = 200;

  const ordsGet = async (path) => {
    if (path.includes('?q=')) {
      const q = JSON.parse(decodeURIComponent(path.split('?q=')[1]));
      const matches = table.filter((row) => {
        if (q.till_id?.$eq != null && Number(row.till_id) !== Number(q.till_id.$eq)) return false;
        if (q.status?.$eq && row.status !== q.status.$eq) return false;
        if (q.close_token?.$eq && row.close_token !== q.close_token.$eq) return false;
        return true;
      });
      return matches;
    }
    const id = Number(path.split('/').pop());
    return table.find((row) => row.id === id) || null;
  };

  const ordsPost = async (_path, body) => {
    const row = { id: nextId++, ...body };
    table.push(row);
    return row;
  };

  const ordsPut = async (path, body) => {
    const id = Number(path.split('/').pop());
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

  return { store, table };
}

test('findLatestForTill returns most recent close request for till', async () => {
  const { store } = mockDeps([
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
  ]);

  const latest = await store.findLatestForTill(23);
  assert.equal(latest.closeToken, 'newer');
  assert.equal(latest.status, 'approved');
});

test('findPendingForTill ignores approved rows', async () => {
  const { store } = mockDeps([
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
  ]);

  const pending = await store.findPendingForTill(23);
  assert.equal(pending, null);
  const latest = await store.findLatestForTill(23);
  assert.equal(latest.status, 'approved');
});
