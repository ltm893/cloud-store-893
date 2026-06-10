'use strict';

const { test, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const { isSupervisorIdentity } = require('../lib/supervisor-auth');

const PIN_FALLBACK_KEY = 'CASHIER_SUPERVISOR_PIN_IS_SUPERVISOR';
const GROUP_KEY = 'IDP_SUPERVISOR_GROUP';

const saved = {};

afterEach(() => {
  for (const key of [PIN_FALLBACK_KEY, GROUP_KEY]) {
    if (saved[key] === undefined) delete process.env[key];
    else process.env[key] = saved[key];
  }
});

function setEnv(key, value) {
  if (!(key in saved)) saved[key] = process.env[key];
  if (value === undefined) delete process.env[key];
  else process.env[key] = value;
}

test('isSupervisorIdentity rejects null identity', () => {
  assert.equal(isSupervisorIdentity(null), false);
});

test('isSupervisorIdentity accepts OIDC group membership', () => {
  setEnv(GROUP_KEY, 'store-supervisors');
  assert.equal(
    isSupervisorIdentity({
      sub: 'supervisor-1',
      email: 'sup@example.com',
      groups: ['store-cashiers', 'store-supervisors'],
      auth: 'oidc',
    }),
    true,
  );
});

test('isSupervisorIdentity rejects OIDC user without supervisor group', () => {
  setEnv(GROUP_KEY, 'store-supervisors');
  assert.equal(
    isSupervisorIdentity({
      sub: 'cashier-1',
      email: 'cashier@example.com',
      groups: ['store-cashiers'],
      auth: 'oidc',
    }),
    false,
  );
});

test('isSupervisorIdentity accepts PIN admin when supervisor PIN fallback is enabled', () => {
  setEnv(GROUP_KEY, 'store-supervisors');
  setEnv(PIN_FALLBACK_KEY, 'true');
  assert.equal(
    isSupervisorIdentity({
      sub: null,
      email: null,
      groups: [],
      auth: 'pin',
    }),
    true,
  );
});

test('isSupervisorIdentity rejects PIN admin when supervisor PIN fallback is disabled', () => {
  setEnv(GROUP_KEY, 'store-supervisors');
  setEnv(PIN_FALLBACK_KEY, 'false');
  assert.equal(
    isSupervisorIdentity({
      sub: null,
      email: null,
      groups: [],
      auth: 'pin',
    }),
    false,
  );
});

test('isSupervisorIdentity rejects OIDC identity with empty groups and no PIN fallback', () => {
  setEnv(GROUP_KEY, 'store-supervisors');
  delete process.env[PIN_FALLBACK_KEY];
  assert.equal(
    isSupervisorIdentity({
      sub: 'user-1',
      email: 'user@example.com',
      groups: [],
      auth: 'oidc',
    }),
    false,
  );
});

test('isSupervisorIdentity honors custom supervisor group name', () => {
  setEnv(GROUP_KEY, 'floor-managers');
  assert.equal(
    isSupervisorIdentity({
      sub: 'mgr-1',
      email: 'mgr@example.com',
      groups: ['floor-managers'],
      auth: 'oidc',
    }),
    true,
  );
  assert.equal(
    isSupervisorIdentity({
      sub: 'sup-1',
      email: 'sup@example.com',
      groups: ['store-supervisors'],
      auth: 'oidc',
    }),
    false,
  );
});
