'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  roundMoney,
  roundToNickel,
  computeRegisterTotal,
  computeCashAmountDue,
  remainingCashAmountDue,
  posRatesFromEnv,
} = require('../lib/pos-pricing');

test('roundToNickel floors to nearest five cents', () => {
  assert.equal(roundToNickel(19.06), 19.05);
  assert.equal(roundToNickel(19.08), 19.05);
  assert.equal(roundToNickel(19.0), 19.0);
  assert.equal(roundToNickel(19.04), 19.0);
});

test('computeRegisterTotal applies fee and tax', () => {
  const total = computeRegisterTotal(20, 0, 0.06);
  assert.equal(total, 21.2);
});

test('computeCashAmountDue rounds register total to nickel', () => {
  assert.equal(computeCashAmountDue(21.26), 21.25);
});

test('remainingCashAmountDue rounds split remainder from collected total', () => {
  assert.equal(remainingCashAmountDue(10.06, 5), 5.05);
});

test('computeCollectedTotal matches nickel floor', () => {
  const { computeCollectedTotal } = require('../lib/pos-pricing');
  assert.equal(computeCollectedTotal(21.26), 21.25);
});

test('posRatesFromEnv defaults match tablet config', () => {
  const rates = posRatesFromEnv({});
  assert.equal(rates.salesFeeRate, 0);
  assert.equal(rates.taxRate, 0.06);
});

test('roundMoney normalizes to two decimal places', () => {
  assert.equal(roundMoney(1.234), 1.23);
});
