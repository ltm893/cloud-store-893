const test = require('node:test');
const assert = require('node:assert/strict');
const {
  mapProductForInventoryLookup,
  lookupProductByQuery,
} = require('../lib/inventory');

test('mapProductForInventoryLookup includes stock metadata', () => {
  const product = {
    id: 42,
    barcode: '12345',
    name: 'Test Ale',
    product_type: 'beer',
    manufacturer: 'Brew Co',
    price: 9.99,
    sale_price: null,
    track_inventory: 1,
    tax_exempt: 0,
  };
  const inventoryMap = new Map([
    [42, { product_id: 42, quantity_on_hand: 3, reorder_point: 5 }],
  ]);

  const out = mapProductForInventoryLookup(product, inventoryMap);
  assert.equal(out.id, 42);
  assert.equal(out.name, 'Test Ale');
  assert.equal(out.quantityOnHand, 3);
  assert.equal(out.trackInventory, true);
  assert.equal(out.productType, 'beer');
  assert.equal(out.manufacturer, 'Brew Co');
  assert.equal(out.reorderPoint, 5);
  assert.equal(out.lowStock, true);
});

test('lookupProductByQuery rejects empty query', async () => {
  const result = await lookupProductByQuery(async () => [], '   ');
  assert.equal(result.status, 400);
  assert.equal(result.body.error, 'q is required');
});

test('lookupProductByQuery finds product by id', async () => {
  const product = {
    id: 7,
    barcode: '999',
    name: 'Cider',
    price: 4.5,
    sale_price: null,
    track_inventory: 0,
    tax_exempt: 0,
  };
  const calls = [];
  const ordsGet = async (path) => {
    calls.push(path);
    if (path.startsWith('products/?q=')) {
      return [product];
    }
    if (path === 'product_inventory/') {
      return [];
    }
    return [];
  };

  const result = await lookupProductByQuery(ordsGet, '7');
  assert.equal(result.status, 200);
  assert.equal(result.body.id, 7);
  assert.equal(result.body.name, 'Cider');
  assert.ok(calls.some((p) => p.startsWith('products/?q=')));
});

test('lookupProductByQuery returns 404 when not found', async () => {
  const ordsGet = async () => [];
  const result = await lookupProductByQuery(ordsGet, '404missing');
  assert.equal(result.status, 404);
  assert.equal(result.body.error, 'Product not found');
  assert.equal(result.body.query, '404missing');
});
