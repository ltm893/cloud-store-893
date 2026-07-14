'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const { parsePath, buildWhere } = require('../lib/pg/ords-shim');

describe('pg ords-shim parsePath', () => {
  it('parses collection path', () => {
    const p = parsePath('products/');
    assert.equal(p.resource, 'products');
    assert.equal(p.id, null);
  });

  it('parses item path with numeric id', () => {
    const p = parsePath('cart_items/42');
    assert.equal(p.resource, 'cart_items');
    assert.equal(p.id, '42');
  });

  it('parses string pk path', () => {
    const p = parsePath('bulk_inventory/kitchen_beans');
    assert.equal(p.resource, 'bulk_inventory');
    assert.equal(p.id, 'kitchen_beans');
  });

  it('parses q filter limit offset order', () => {
    const filter = encodeURIComponent(JSON.stringify({ barcode: { $eq: 'x' } }));
    const p = parsePath(`products/?q=${filter}&limit=20&offset=5&order=created_at:desc`);
    assert.deepEqual(p.filter, { barcode: { $eq: 'x' } });
    assert.equal(p.limit, 20);
    assert.equal(p.offset, 5);
    assert.equal(p.order, 'created_at:desc');
  });
});

describe('pg ords-shim buildWhere', () => {
  it('builds $eq ANDs', () => {
    const { clause, values } = buildWhere({
      status: { $eq: 'active' },
      register_id: { $eq: 'reg-1' },
    });
    assert.equal(clause, 'WHERE "status" = $1 AND "register_id" = $2');
    assert.deepEqual(values, ['active', 'reg-1']);
  });
});
