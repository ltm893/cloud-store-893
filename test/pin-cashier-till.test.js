'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createTillStore } = require('../lib/tills');
const {
  resumeActiveTillSession,
  findResumableTillForIdentity,
  findOpenTillForSession,
  attachTillToSession,
} = require('../lib/cashier-auth');

function mockTillStore(rows = []) {
  let nextId = 100;
  const table = [...rows];

  return createTillStore({
    ordsGet: async (path) => {
      if (path.includes('?q=')) {
        const q = JSON.parse(decodeURIComponent(path.split('?q=')[1]));
        return table.filter((row) => {
          if (q.register_id?.$eq && row.register_id !== q.register_id.$eq) return false;
          if (q.status?.$eq && row.status !== q.status.$eq) return false;
          if (q.cashier_sub?.$eq && row.cashier_sub !== q.cashier_sub.$eq) return false;
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

function mockPosSessionStore() {
  let nextId = 500;
  return {
    async create({ registerId, cashierSub }) {
      return {
        id: nextId++,
        registerId,
        cashierSub,
        status: 'active',
      };
    },
  };
}

function mockRes() {
  const headers = {};
  return {
    headers,
    setHeader(name, value) {
      headers[name] = value;
    },
    appendHeader(name, value) {
      const prev = headers[name];
      if (prev === undefined) {
        headers[name] = value;
        return;
      }
      headers[name] = Array.isArray(prev) ? [...prev, value] : [prev, value];
    },
  };
}

test('findResumableTillForIdentity returns pin cashier till on register', async () => {
  const tillStore = mockTillStore([
    {
      id: 64,
      register_id: 'tablet-ipad',
      cashier_sub: 'pin:cashier',
      till_type: 'credit_only',
      status: 'active',
    },
  ]);

  const till = await findResumableTillForIdentity(tillStore, 'tablet-ipad', { pinAuth: true });
  assert.equal(till?.id, 64);
});

test('findOpenTillForSession links register till when session lacks tillId', async () => {
  const tillStore = mockTillStore([
    {
      id: 77,
      register_id: 'tablet-ipad',
      cashier_sub: 'pin:cashier',
      till_type: 'credit_only',
      status: 'active',
    },
  ]);

  const session = { sub: 'pin:cashier', email: null, auth: 'pin' };
  const till = await findOpenTillForSession(session, tillStore, null, 'tablet-ipad');
  assert.equal(till?.id, 77);
  attachTillToSession(session, till);
  assert.equal(session.tillId, 77);
  assert.equal(session.cashMode, 'credit_only');
});

test('resumeActiveTillSession issues cashier session for pin till resume', async () => {
  const tillStore = mockTillStore([
    {
      id: 64,
      register_id: 'tablet-ipad',
      cashier_sub: 'pin:cashier',
      till_type: 'credit_only',
      status: 'active',
    },
  ]);
  const posSessionStore = mockPosSessionStore();
  const res = mockRes();

  const till = await findResumableTillForIdentity(tillStore, 'tablet-ipad', { pinAuth: true });
  const payload = await resumeActiveTillSession(
    res,
    till,
    { registerId: 'tablet-ipad', pinAuth: true },
    posSessionStore,
  );

  assert.equal(payload.ok, true);
  assert.equal(payload.resumed, true);
  assert.equal(payload.tillId, 64);
  assert.equal(payload.cashMode, 'credit_only');
  assert.ok(res.headers['Set-Cookie'] || res.headers['set-cookie']);
});
