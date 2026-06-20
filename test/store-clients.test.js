'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { getStoreClients } = require('../lib/store-clients');

test('getStoreClients lists register and admin device groups', () => {
  const clients = getStoreClients();
  assert.equal(clients.register.title, 'Cash register');
  assert.equal(clients.admin.title, 'Admin console');
  assert.ok(clients.register.clients.some((c) => c.name === 'Android tablet'));
  assert.ok(clients.register.clients.some((c) => c.name === 'iPad'));
  assert.ok(clients.admin.clients.some((c) => c.name === 'iPhone'));
  assert.ok(clients.admin.clients.some((c) => c.name === 'Web'));
  assert.ok(clients.admin.clients.some((c) => c.name === 'Android'));
});
