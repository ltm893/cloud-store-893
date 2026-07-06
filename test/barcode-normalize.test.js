'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { ean13CheckDigit, barcodeLookupCandidates } = require('../lib/barcode-normalize');

test('ean13CheckDigit for Crystal Spring water', () => {
  assert.equal(ean13CheckDigit('872000000402'), '1');
});

test('barcodeLookupCandidates maps scanned EAN-13 to 12-digit catalog value', () => {
  const candidates = barcodeLookupCandidates('8720000004021');
  assert.ok(candidates.includes('8720000004021'));
  assert.ok(candidates.includes('872000000402'));
});

test('barcodeLookupCandidates maps 12-digit catalog to scanned EAN-13', () => {
  const candidates = barcodeLookupCandidates('872000000402');
  assert.ok(candidates.includes('872000000402'));
  assert.ok(candidates.includes('8720000004021'));
});

test('barcodeLookupCandidates handles UPC-A with leading zero EAN-13', () => {
  const upc = '012345678905';
  const candidates = barcodeLookupCandidates(`0${upc}`);
  assert.ok(candidates.includes(`0${upc}`));
  assert.ok(candidates.includes(upc));
});

test('barcodeLookupCandidates preserves non-numeric values', () => {
  assert.deepEqual(barcodeLookupCandidates('SKU-ABC'), ['SKU-ABC']);
});
