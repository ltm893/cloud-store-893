'use strict';

const { test, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const {
  CASH_MODE,
  isCashTillConfigured,
  getExpectedOpeningFloat,
  sumDenominations,
  parseTillSubmit,
  sessionAllowsCashPayments,
  openingVariance,
  getDenominations,
} = require('../lib/cash-till-config');

const FLOAT_KEY = 'OPENING_CASH_FLOAT';
const saved = {};

afterEach(() => {
  if (saved[FLOAT_KEY] === undefined) delete process.env[FLOAT_KEY];
  else process.env[FLOAT_KEY] = saved[FLOAT_KEY];
});

function saveFloat() {
  saved[FLOAT_KEY] = process.env[FLOAT_KEY];
}

test('isCashTillConfigured is false when OPENING_CASH_FLOAT unset', () => {
  saveFloat();
  delete process.env[FLOAT_KEY];
  assert.equal(isCashTillConfigured(), false);
});

test('getExpectedOpeningFloat parses dollars', () => {
  saveFloat();
  process.env[FLOAT_KEY] = '200.00';
  assert.equal(getExpectedOpeningFloat(), 200);
});

test('sumDenominations totals bill and coin counts', () => {
  const denominations = getDenominations();
  const total = sumDenominations(denominations, { '20': 10, '1': 0 });
  assert.equal(total, 200);
});

test('parseTillSubmit accepts credit_only', () => {
  const till = parseTillSubmit({ cashMode: CASH_MODE.CREDIT_ONLY }, getDenominations());
  assert.equal(till.cashMode, CASH_MODE.CREDIT_ONLY);
});

test('parseTillSubmit validates counted total against denominations', () => {
  saveFloat();
  process.env[FLOAT_KEY] = '200.00';
  const till = parseTillSubmit(
    {
      cashMode: CASH_MODE.CASH_AND_CREDIT,
      denominations: { '20': 10 },
      countedTotal: 200,
    },
    getDenominations(),
  );
  assert.equal(till.countedTotal, 200);
  assert.equal(till.openingVariance, 0);
});

test('parseTillSubmit rejects mismatched counted total', () => {
  assert.throws(
    () =>
      parseTillSubmit(
        {
          cashMode: CASH_MODE.CASH_AND_CREDIT,
          denominations: { '20': 10 },
          countedTotal: 199,
        },
        getDenominations(),
      ),
    /does not match/,
  );
});

test('openingVariance computes difference', () => {
  assert.equal(openingVariance(198.5, 200), -1.5);
});

test('sessionAllowsCashPayments when till not configured', () => {
  saveFloat();
  delete process.env[FLOAT_KEY];
  assert.equal(sessionAllowsCashPayments({}), true);
});

test('sessionAllowsCashPayments when shift is credit only', () => {
  saveFloat();
  process.env[FLOAT_KEY] = '200';
  assert.equal(sessionAllowsCashPayments({ cashEnabled: false }), false);
  assert.equal(sessionAllowsCashPayments({ cashEnabled: true }), true);
});
