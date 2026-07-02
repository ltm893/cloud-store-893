const test = require('node:test');
const assert = require('node:assert/strict');
const {
  tracksInventory,
  availableQuantity,
  isInStock,
  canFulfillQuantity,
  aggregateBulkConsumption,
  canFulfillBulkConsumption,
  consumptionForLine,
  mapProductForCashier,
} = require('../lib/inventory');

const inventoryMap = new Map([
  [10, { product_id: 10, quantity_on_hand: 3, reorder_point: 1 }],
  [11, { product_id: 11, quantity_on_hand: 0, reorder_point: 2 }],
]);

test('tracksInventory respects track_inventory flag and product_type fallback', () => {
  assert.equal(tracksInventory({ track_inventory: 1 }), true);
  assert.equal(tracksInventory({ track_inventory: 0 }), false);
  assert.equal(tracksInventory({ track_inventory: 0, product_type: 'water' }), true);
  assert.equal(tracksInventory({ track_inventory: 0, product_type: 'made coffee' }), false);
});

test('availableQuantity is unlimited when not tracked', () => {
  assert.equal(availableQuantity({ id: 1, track_inventory: 0 }, inventoryMap), Number.POSITIVE_INFINITY);
});

test('availableQuantity uses on-hand count when tracked', () => {
  assert.equal(availableQuantity({ id: 10, track_inventory: 1 }, inventoryMap), 3);
  assert.equal(availableQuantity({ id: 99, track_inventory: 1 }, inventoryMap), 0);
});

test('isInStock is false at zero on-hand', () => {
  assert.equal(isInStock({ id: 10, track_inventory: 1 }, inventoryMap), true);
  assert.equal(isInStock({ id: 11, track_inventory: 1 }, inventoryMap), false);
  assert.equal(isInStock({ id: 1, track_inventory: 0 }, inventoryMap), true);
});

test('canFulfillQuantity blocks over-allocation', () => {
  const product = { id: 10, name: 'Beans', track_inventory: 1 };
  assert.equal(canFulfillQuantity(product, inventoryMap, 2).ok, true);
  const blocked = canFulfillQuantity(product, inventoryMap, 5);
  assert.equal(blocked.ok, false);
  assert.match(blocked.error, /only 3 available/);
  assert.equal(blocked.maxOrderable, 3);
});

test('mapProductForCashier exposes quantity for tracked SKUs', () => {
  const inStock = mapProductForCashier(
    { id: 10, barcode: 'x', name: 'Beans', price: 10, sale_price: null, track_inventory: 1 },
    inventoryMap,
  );
  assert.equal(inStock.inStock, true);
  assert.equal(inStock.quantityOnHand, 3);

  const out = mapProductForCashier(
    { id: 11, barcode: 'y', name: 'Cup', price: 5, sale_price: null, track_inventory: 1 },
    inventoryMap,
  );
  assert.equal(out.inStock, false);
  assert.equal(out.quantityOnHand, 0);

  const untracked = mapProductForCashier(
    { id: 1, barcode: 'z', name: 'Drip', price: 4, sale_price: null, track_inventory: 0 },
    inventoryMap,
  );
  assert.equal(untracked.inStock, true);
  assert.equal(untracked.quantityOnHand, null);
});

test('consumptionForLine applies product_type rule', () => {
  const rules = new Map([
    ['made coffee', { bulk_sku_key: 'kitchen_beans', quantity_per_unit: 1.5, unit: 'oz' }],
  ]);
  const latte = { product_type: 'made coffee', name: 'Latte' };
  const use = consumptionForLine(latte, rules, 2);
  assert.equal(use.bulkSkuKey, 'kitchen_beans');
  assert.equal(use.amount, 3);
});

test('canFulfillBulkConsumption blocks when kitchen beans insufficient', () => {
  const rules = new Map([
    ['made coffee', { bulk_sku_key: 'kitchen_beans', quantity_per_unit: 1.5, unit: 'oz' }],
  ]);
  const productsById = new Map([
    [1, { id: 1, product_type: 'made coffee', name: 'Latte' }],
  ]);
  const bulkMap = new Map([
    ['kitchen_beans', { sku_key: 'kitchen_beans', name: 'Kitchen beans', quantity_on_hand: 2, unit: 'oz' }],
  ]);
  const blocked = canFulfillBulkConsumption(
    [{ productId: 1, quantity: 2 }],
    productsById,
    rules,
    bulkMap,
  );
  assert.equal(blocked.ok, false);
  assert.match(blocked.error, /Kitchen beans/);

  const ok = canFulfillBulkConsumption(
    [{ productId: 1, quantity: 1 }],
    productsById,
    rules,
    bulkMap,
  );
  assert.equal(ok.ok, true);
  assert.equal(aggregateBulkConsumption([{ productId: 1, quantity: 1 }], productsById, rules).get('kitchen_beans'), 1.5);
});

test('aggregateBulkConsumption sums multiple drink lines', () => {
  const rules = new Map([
    ['made coffee', { bulk_sku_key: 'kitchen_beans', quantity_per_unit: 1.5, unit: 'oz' }],
  ]);
  const productsById = new Map([
    [1, { id: 1, product_type: 'made coffee', name: 'Latte' }],
    [2, { id: 2, product_type: 'made coffee', name: 'Espresso' }],
  ]);
  const lines = [
    { productId: 1, quantity: 2 },
    { productId: 2, quantity: 1 },
  ];
  const totals = aggregateBulkConsumption(lines, productsById, rules);
  assert.equal(totals.size, 1);
  assert.equal(totals.get('kitchen_beans'), 4.5);
});

test('aggregateBulkConsumption ignores retail-only cart lines', () => {
  const rules = new Map([
    ['made coffee', { bulk_sku_key: 'kitchen_beans', quantity_per_unit: 1.5, unit: 'oz' }],
  ]);
  const productsById = new Map([
    [10, { id: 10, product_type: 'retail', name: 'Hoodie' }],
    [11, { id: 11, product_type: 'retail', name: 'Mug' }],
  ]);
  const totals = aggregateBulkConsumption(
    [
      { productId: 10, quantity: 1 },
      { productId: 11, quantity: 2 },
    ],
    productsById,
    rules,
  );
  assert.equal(totals.size, 0);
});

test('aggregateBulkConsumption mixes drinks and retail in one cart', () => {
  const rules = new Map([
    ['made coffee', { bulk_sku_key: 'kitchen_beans', quantity_per_unit: 1.5, unit: 'oz' }],
  ]);
  const productsById = new Map([
    [1, { id: 1, product_type: 'made coffee', name: 'Latte' }],
    [10, { id: 10, product_type: 'retail', name: 'Hoodie' }],
  ]);
  const totals = aggregateBulkConsumption(
    [
      { productId: 1, quantity: 2 },
      { productId: 10, quantity: 1 },
    ],
    productsById,
    rules,
  );
  assert.equal(totals.size, 1);
  assert.equal(totals.get('kitchen_beans'), 3);
});
