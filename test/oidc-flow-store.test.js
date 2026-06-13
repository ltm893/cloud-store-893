'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  createOidcFlow,
  getOidcFlow,
  deleteOidcFlow,
  clearOidcFlowStore,
} = require('../lib/oidc-flow-store');

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
