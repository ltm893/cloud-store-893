'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { cashierMatchesShift } = require('../lib/cashier-identity-match');

test('cashierMatchesShift matches sub or email across stored formats', () => {
  const shift = { cashierSub: 'ltm893@icloud.com', cashierEmail: 'ltm893@icloud.com' };
  assert.equal(cashierMatchesShift(shift, { sub: 'opaque-oracle-sub', email: 'ltm893@icloud.com' }), true);
  assert.equal(cashierMatchesShift(shift, { sub: 'ltm893@icloud.com' }), true);
  assert.equal(cashierMatchesShift(shift, { sub: 'other@example.com', email: 'other@example.com' }), false);
});
