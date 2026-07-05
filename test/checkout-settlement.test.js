'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { resolveCheckoutSettlement } = require('../lib/checkout-settlement');

const rates = { salesFeeRate: 0, taxRate: 0.06 };

function cartLine(amount, taxExempt = false) {
  return { lineSubtotalPayable: amount, taxExempt };
}

test('cash-only checkout records nickel-rounded total', () => {
  const result = resolveCheckoutSettlement({
    cartItems: [cartLine(20)],
    paymentMethod: 'cash',
    rawPayments: null,
    clientCheckoutTotal: 21.2,
    ...rates,
  });
  assert.equal(result.error, undefined);
  assert.equal(result.registerTotal, 21.2);
  assert.equal(result.cashDue, 21.2);
  assert.equal(result.recordedTotal, 21.2);
  assert.equal(result.payments[0].amount, 21.2);
});

test('cash-only checkout rounds down when register total has pennies', () => {
  const result = resolveCheckoutSettlement({
    cartItems: [cartLine(20.06)],
    paymentMethod: 'cash',
    rawPayments: null,
    clientCheckoutTotal: null,
    ...rates,
  });
  assert.equal(result.registerTotal, 21.26);
  assert.equal(result.cashDue, 21.25);
  assert.equal(result.recordedTotal, 21.25);
});

test('card-only checkout rounds down when register total has pennies', () => {
  const result = resolveCheckoutSettlement({
    cartItems: [cartLine(20.06)],
    paymentMethod: 'card',
    rawPayments: null,
    clientCheckoutTotal: null,
    ...rates,
  });
  assert.equal(result.registerTotal, 21.26);
  assert.equal(result.cashDue, null);
  assert.equal(result.recordedTotal, 21.25);
  assert.equal(result.payments[0].amount, 21.25);
});

test('card-only checkout stays exact when already on nickel', () => {
  const result = resolveCheckoutSettlement({
    cartItems: [cartLine(20)],
    paymentMethod: 'card',
    rawPayments: null,
    clientCheckoutTotal: null,
    ...rates,
  });
  assert.equal(result.registerTotal, 21.2);
  assert.equal(result.cashDue, null);
  assert.equal(result.recordedTotal, 21.2);
});

test('split tender rounds cash remainder to nickel', () => {
  const result = resolveCheckoutSettlement({
    cartItems: [cartLine(9.49)],
    paymentMethod: 'split',
    rawPayments: [
      { method: 'card', amount: 5, tenderedAmount: 5 },
      { method: 'cash', amount: 5.05, tenderedAmount: 5.05 },
    ],
    clientCheckoutTotal: 10.06,
    ...rates,
  });
  assert.equal(result.registerTotal, 10.06);
  assert.equal(result.cashDue, 5.05);
  assert.equal(result.recordedTotal, 10.05);
});

test('split payments must match expected collected total', () => {
  const result = resolveCheckoutSettlement({
    cartItems: [cartLine(20.06)],
    paymentMethod: 'split',
    rawPayments: [
      { method: 'card', amount: 10, tenderedAmount: 10 },
      { method: 'cash', amount: 11.2, tenderedAmount: 11.2 },
    ],
    clientCheckoutTotal: null,
    ...rates,
  });
  assert.equal(result.error, 'Split payments must equal total 21.25');
});

test('mixed tax-exempt cart charges tax only on taxable lines', () => {
  const result = resolveCheckoutSettlement({
    cartItems: [cartLine(10), cartLine(5, true)],
    paymentMethod: 'cash',
    rawPayments: null,
    clientCheckoutTotal: 15.6,
    ...rates,
  });
  assert.equal(result.error, undefined);
  assert.equal(result.registerTotal, 15.6);
  assert.equal(result.recordedTotal, 15.6);
});
