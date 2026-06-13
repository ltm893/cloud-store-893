'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createTillStore, makeRegisterInUseError } = require('../lib/tills');

function mockStore(rows = []) {
  let nextId = 100;
  const table = [...rows];

  return createTillStore({
    ordsGet: async (path) => {
      if (path.includes('?q=')) {
        const q = JSON.parse(decodeURIComponent(path.split('?q=')[1]));
        return table.filter((row) => {
          if (q.register_id?.$eq && row.register_id !== q.register_id.$eq) return false;
          if (q.status?.$eq && row.status !== q.status.$eq) return false;
          if (q.open_approval_token?.$eq && row.open_approval_token !== q.open_approval_token.$eq) {
            return false;
          }
          return true;
        });
      }
      const id = Number(path.split('/').pop());
      return table.find((row) => row.id === id) || null;
    },
    ordsPost: async (_path, body) => {
      const row = { id: nextId++, ...body };
      table.push(row);
      return row;
    },
    ordsPut: async (path, body) => {
      const id = Number(path.split('/').pop());
      const row = table.find((r) => r.id === id);
      if (row) Object.assign(row, body);
      return row;
    },
    ordsTimestamp: () => '2026-06-11T12:00:00Z',
  });
}

test('assertRegisterAvailable allows sign-in when register is free', async () => {
  const store = mockStore();
  const open = await store.assertRegisterAvailable('tablet-1', 'sub-a');
  assert.equal(open, null);
});

test('assertRegisterAvailable blocks a different cashier on the same register', async () => {
  const store = mockStore([
    {
      id: 1,
      register_id: 'tablet-1',
      cashier_sub: 'sub-a',
      cashier_email: 'alice@example.com',
      status: 'active',
    },
  ]);

  await assert.rejects(
    () => store.assertRegisterAvailable('tablet-1', 'sub-b'),
    (err) => err.code === 'REGISTER_IN_USE' && err.status === 409,
  );
});

test('assertRegisterAvailable allows the same cashier to resume', async () => {
  const store = mockStore([
    {
      id: 1,
      register_id: 'tablet-1',
      cashier_sub: 'sub-a',
      status: 'active',
    },
  ]);

  const open = await store.assertRegisterAvailable('tablet-1', 'sub-a');
  assert.equal(open.id, 1);
});

test('closeTill marks till closed', async () => {
  const store = mockStore([
    {
      id: 7,
      register_id: 'tablet-1',
      cashier_sub: 'sub-a',
      status: 'active',
    },
  ]);

  const closed = await store.closeTill(7);
  assert.equal(closed.status, 'closed');
  const active = await store.findActiveTillForRegister('tablet-1');
  assert.equal(active, null);
});

test('makeRegisterInUseError includes cashier email when present', () => {
  const err = makeRegisterInUseError({
    cashierEmail: 'alice@example.com',
    cashierSub: 'sub-a',
  });
  assert.match(err.message, /alice@example.com/);
  assert.equal(err.status, 409);
});

test('findResumableActiveTill resumes orphan active till for same cashier', async () => {
  const store = mockStore([
    {
      id: 12,
      register_id: null,
      cashier_sub: 'ltm893@icloud.com',
      cashier_email: 'ltm893@icloud.com',
      till_type: 'credit_only',
      status: 'active',
      opened_at: '2026-06-11T10:00:00Z',
    },
  ]);

  const open = await store.findResumableActiveTill('tablet-abc', {
    sub: 'oracle-sub-123',
    email: 'ltm893@icloud.com',
  });
  assert.equal(open.id, 12);

  const backfilled = await store.backfillRegisterId(12, 'tablet-abc');
  assert.equal(backfilled.registerId, 'tablet-abc');
});
