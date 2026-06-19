'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  formatOrderNumber,
  parseOrderNumber,
  allocateOrderNumber,
  isDuplicateOrderNumberError,
} = require('../lib/order-number');

test('formatOrderNumber zero-pads to 7 digits', () => {
  assert.equal(formatOrderNumber(1), '0000001');
  assert.equal(formatOrderNumber(9999999), '9999999');
});

test('parseOrderNumber requires exactly 7 digits', () => {
  assert.equal(parseOrderNumber('0000042'), '0000042');
  assert.throws(() => parseOrderNumber(''), /order_number is required/);
  assert.throws(() => parseOrderNumber('POS-1'), /exactly 7 digits/);
  assert.throws(() => parseOrderNumber('12345678'), /exactly 7 digits/);
});

test('allocateOrderNumber returns next sequential value', async () => {
  const ordsGet = async (path) => {
    assert.equal(path, 'sales/');
    return [
      { order_number: '0000001' },
      { order_number: '0000010' },
      { order_number: '0000005' },
    ];
  };
  const next = await allocateOrderNumber({ ordsGet });
  assert.equal(next, '0000011');
});

test('allocateOrderNumber starts at 0000001 on empty sales', async () => {
  const next = await allocateOrderNumber({ ordsGet: async () => [] });
  assert.equal(next, '0000001');
});

test('isDuplicateOrderNumberError detects unique constraint failures', () => {
  assert.equal(isDuplicateOrderNumberError(new Error('ORA-00001 unique constraint')), true);
  assert.equal(isDuplicateOrderNumberError(new Error('connection failed')), false);
});
