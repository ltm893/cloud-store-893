'use strict';

const { test, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const { isSupervisorPinFallbackEnabled } = require('../lib/supervisor-config');

const ENV_KEY = 'CASHIER_SUPERVISOR_PIN_IS_SUPERVISOR';
const previous = process.env[ENV_KEY];

afterEach(() => {
  if (previous === undefined) delete process.env[ENV_KEY];
  else process.env[ENV_KEY] = previous;
});

test('isSupervisorPinFallbackEnabled is false by default', () => {
  delete process.env[ENV_KEY];
  assert.equal(isSupervisorPinFallbackEnabled(), false);
});

test('isSupervisorPinFallbackEnabled accepts true/1/yes', () => {
  for (const value of ['true', 'TRUE', '1', 'yes']) {
    process.env[ENV_KEY] = value;
    assert.equal(isSupervisorPinFallbackEnabled(), true, `expected true for ${value}`);
  }
});

test('isSupervisorPinFallbackEnabled rejects other values', () => {
  process.env[ENV_KEY] = 'false';
  assert.equal(isSupervisorPinFallbackEnabled(), false);
});
