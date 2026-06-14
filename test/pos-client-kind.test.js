'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  POS_CLIENT_KIND,
  normalizePosClientKind,
  isNativePosClient,
  cashierResumeRedirectQuery,
  normalizeRegisterId,
  isValidRegisterId,
  assertValidNativeRegisterContext,
} = require('../lib/pos-client-kind');

test('normalizePosClientKind lowercases and trims', () => {
  assert.equal(normalizePosClientKind(' IOS '), 'ios');
  assert.equal(normalizePosClientKind(''), null);
  assert.equal(normalizePosClientKind(null), null);
});

test('isNativePosClient includes tablet and ios only', () => {
  assert.equal(isNativePosClient('tablet'), true);
  assert.equal(isNativePosClient('ios'), true);
  assert.equal(isNativePosClient('IOS'), true);
  assert.equal(isNativePosClient('web'), false);
  assert.equal(isNativePosClient(null), false);
});

test('cashierResumeRedirectQuery uses cashier_resume for native clients', () => {
  assert.equal(cashierResumeRedirectQuery('tablet'), 'cashier_resume=1');
  assert.equal(cashierResumeRedirectQuery('ios'), 'cashier_resume=1');
  assert.equal(cashierResumeRedirectQuery('web'), 'resumed=1');
  assert.equal(cashierResumeRedirectQuery(null), 'resumed=1');
});

test('isValidRegisterId requires tablet- prefix', () => {
  assert.equal(isValidRegisterId('tablet-abc123'), true);
  assert.equal(isValidRegisterId('tablet-550E8400-E29B-41D4-A716-446655440000'), true);
  assert.equal(isValidRegisterId('tablet-unknown'), true);
  assert.equal(isValidRegisterId('tablet-'), false);
  assert.equal(isValidRegisterId('ios-abc'), false);
  assert.equal(isValidRegisterId(''), false);
  assert.equal(isValidRegisterId(null), false);
});

test('normalizeRegisterId trims', () => {
  assert.equal(normalizeRegisterId('  tablet-x  '), 'tablet-x');
  assert.equal(normalizeRegisterId(''), null);
});

test('assertValidNativeRegisterContext rejects bad register_id for ios', () => {
  assert.throws(
    () => assertValidNativeRegisterContext({ clientKind: 'ios', registerId: 'ipad-1' }),
    (err) => err.code === 'INVALID_REGISTER_ID' && err.status === 400,
  );
});

test('assertValidNativeRegisterContext allows valid ios register_id', () => {
  assert.doesNotThrow(() =>
    assertValidNativeRegisterContext({
      clientKind: POS_CLIENT_KIND.IOS,
      registerId: 'tablet-550E8400-E29B-41D4-A716-446655440000',
    }),
  );
});

test('assertValidNativeRegisterContext skips web and omitted register_id', () => {
  assert.doesNotThrow(() => assertValidNativeRegisterContext({ clientKind: 'web' }));
  assert.doesNotThrow(() => assertValidNativeRegisterContext({ clientKind: 'ios' }));
});
