'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  isProductTaxExempt,
  resolveCartLineTaxExempt,
} = require('../lib/inventory');

test('isProductTaxExempt accepts Oracle 0/1 and bool forms', () => {
  assert.equal(isProductTaxExempt({ tax_exempt: 1 }), true);
  assert.equal(isProductTaxExempt({ tax_exempt: '1' }), true);
  assert.equal(isProductTaxExempt({ tax_exempt: true }), true);
  assert.equal(isProductTaxExempt({ tax_exempt: 0 }), false);
  assert.equal(isProductTaxExempt({ tax_exempt: false }), false);
  assert.equal(isProductTaxExempt({}), false);
});

test('resolveCartLineTaxExempt falls back to products when cart_view omits tax_exempt', () => {
  const cartRow = { product_id: 17, tax_exempt: null };
  const product = { id: 17, tax_exempt: 1 };
  assert.equal(resolveCartLineTaxExempt(cartRow, product), true);
});

test('resolveCartLineTaxExempt prefers cart_view when present', () => {
  const cartRow = { product_id: 17, tax_exempt: 0 };
  const product = { id: 17, tax_exempt: 1 };
  assert.equal(resolveCartLineTaxExempt(cartRow, product), false);
});
