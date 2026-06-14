'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  createOidcFlow,
  getOidcFlow,
  deleteOidcFlow,
  clearOidcFlowStore,
} = require('../lib/oidc-flow-store');

test('createOidcFlow round-trips ios client_kind by state', () => {
  clearOidcFlowStore();
  createOidcFlow({
    state: 'ios-state',
    nonce: 'nonce-ios',
    clientKind: 'ios',
    registerId: 'tablet-550E8400-E29B-41D4-A716-446655440000',
  });
  const flow = getOidcFlow('ios-state');
  assert.equal(flow.clientKind, 'ios');
  assert.equal(flow.registerId, 'tablet-550E8400-E29B-41D4-A716-446655440000');
  deleteOidcFlow('ios-state');
});

test('createOidcFlow round-trips by state (WebView callback without cookie)', () => {
  clearOidcFlowStore();
  createOidcFlow({
    state: 'abc123',
    nonce: 'nonce9',
    clientKind: 'tablet',
    registerId: 'tablet-1',
  });
  const flow = getOidcFlow('abc123');
  assert.equal(flow.nonce, 'nonce9');
  assert.equal(flow.clientKind, 'tablet');
  assert.equal(flow.registerId, 'tablet-1');
  deleteOidcFlow('abc123');
  assert.equal(getOidcFlow('abc123'), null);
});
