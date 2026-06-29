'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

const mmdPath = path.join(__dirname, '..', 'public', 'shared', 'data-model.mmd');

test('data-model.mmd exists and defines core ER entities', () => {
  const mmd = fs.readFileSync(mmdPath, 'utf8');
  assert.match(mmd, /^erDiagram/m);
  assert.match(mmd, /products/);
  assert.match(mmd, /sales/);
  assert.match(mmd, /tills/);
  assert.match(mmd, /product_inventory/);
});
