'use strict';

const { test, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

const STORE_PATH = path.join(process.cwd(), '.dev-auth-sessions.json');

beforeEach(() => {
  delete require.cache[require.resolve('../lib/awaiting-till-store')];
  delete require.cache[require.resolve('../lib/dev-session-store')];
  process.env.DEV_PERSIST_AUTH_SESSIONS = 'true';
  try {
    fs.unlinkSync(STORE_PATH);
  } catch {
    // ignore
  }
});

afterEach(() => {
  delete process.env.DEV_PERSIST_AUTH_SESSIONS;
  try {
    fs.unlinkSync(STORE_PATH);
  } catch {
    // ignore
  }
});

test('awaiting till draft survives module reload when dev persistence is on', () => {
  const store = require('../lib/awaiting-till-store');
  const token = store.createAwaitingTill({
    claims: { sub: 'user-1', email: 'cashier@example.com' },
    clientKind: 'tablet',
  });
  const draft = store.getAwaitingTill(token);
  assert.equal(draft?.claims?.email, 'cashier@example.com');

  delete require.cache[require.resolve('../lib/awaiting-till-store')];
  const reloaded = require('../lib/awaiting-till-store');
  const restored = reloaded.getAwaitingTill(token);
  assert.equal(restored?.claims?.email, 'cashier@example.com');
  assert.equal(restored?.clientKind, 'tablet');
});
