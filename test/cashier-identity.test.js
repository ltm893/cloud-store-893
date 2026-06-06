'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  identityFromCashierSub,
  identityFromApproval,
  claimsEmail,
  claimsDisplayName,
} = require('../lib/login-approval');

test('identityFromCashierSub returns email-shaped sub', () => {
  assert.equal(identityFromCashierSub('cashier@example.com'), 'cashier@example.com');
});

test('identityFromCashierSub ignores non-email sub', () => {
  assert.equal(identityFromCashierSub('uuid-subject-id'), null);
  assert.equal(identityFromCashierSub(''), null);
  assert.equal(identityFromCashierSub(null), null);
});

test('identityFromApproval prefers cashierEmail and cashierName', () => {
  assert.deepEqual(
    identityFromApproval({
      cashierEmail: 'a@b.com',
      cashierSub: 'other-sub',
      cashierName: 'Alice',
    }),
    { email: 'a@b.com', name: 'Alice' },
  );
});

test('identityFromApproval falls back to email-shaped cashierSub', () => {
  assert.deepEqual(
    identityFromApproval({
      cashierEmail: null,
      cashierSub: 'cashier@example.com',
      cashierName: null,
    }),
    { email: 'cashier@example.com', name: 'cashier@example.com' },
  );
});

test('identityFromApproval returns nulls for empty approval', () => {
  assert.deepEqual(identityFromApproval(null), { email: null, name: null });
});

test('claimsEmail finds email from preferred_username', () => {
  assert.equal(claimsEmail({ preferred_username: 'user@example.com' }), 'user@example.com');
});

test('claimsEmail ignores non-email preferred_username', () => {
  assert.equal(claimsEmail({ preferred_username: 'not-an-email' }), null);
});

test('claimsDisplayName prefers name then preferred_username', () => {
  assert.equal(claimsDisplayName({ name: 'Alice', preferred_username: 'bob' }), 'Alice');
  assert.equal(claimsDisplayName({ preferred_username: 'bob@example.com' }), 'bob@example.com');
});
