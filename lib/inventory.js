/** Inventory helpers — retail shelf stock + kitchen bulk (drink consumption). */

function tracksInventory(productRow) {
  return Number(productRow.track_inventory) === 1;
}

function inventoryForProduct(inventoryMap, productId) {
  return inventoryMap.get(Number(productId)) || null;
}

function availableQuantity(productRow, inventoryMap) {
  if (!tracksInventory(productRow)) return Number.POSITIVE_INFINITY;
  const inv = inventoryForProduct(inventoryMap, productRow.id);
  if (!inv) return 0;
  return Number(inv.quantity_on_hand);
}

function isInStock(productRow, inventoryMap) {
  return availableQuantity(productRow, inventoryMap) > 0;
}

function canFulfillQuantity(productRow, inventoryMap, requestedQty) {
  const qty = Number(requestedQty);
  if (!Number.isFinite(qty) || qty < 1) {
    return { ok: false, error: 'quantity must be at least 1' };
  }
  if (!tracksInventory(productRow)) {
    return { ok: true };
  }
  const available = availableQuantity(productRow, inventoryMap);
  if (qty > available) {
    const label = productRow.name || `product ${productRow.id}`;
    return {
      ok: false,
      error: available > 0
        ? `Insufficient stock for ${label} (only ${available} available)`
        : `${label} is out of stock`,
    };
  }
  return { ok: true };
}

function roundQty(n) {
  return Math.round(Number(n) * 1000) / 1000;
}

function consumptionForLine(productRow, rulesByType, quantity) {
  if (!productRow || !rulesByType) return null;
  const rule = rulesByType.get(String(productRow.product_type || '').trim());
  if (!rule) return null;
  const qty = Number(quantity);
  if (!Number.isFinite(qty) || qty < 1) return null;
  const perUnit = Number(rule.quantity_per_unit);
  if (!Number.isFinite(perUnit) || perUnit <= 0) return null;
  return {
    bulkSkuKey: String(rule.bulk_sku_key),
    unit: String(rule.unit || 'oz'),
    amount: roundQty(perUnit * qty),
  };
}

function aggregateBulkConsumption(cartLines, productsById, rulesByType) {
  const totals = new Map();
  for (const line of cartLines) {
    const productId = Number(line.productId ?? line.product_id);
    const product = productsById.get(productId);
    const use = consumptionForLine(product, rulesByType, line.quantity);
    if (!use) continue;
    totals.set(use.bulkSkuKey, roundQty((totals.get(use.bulkSkuKey) || 0) + use.amount));
  }
  return totals;
}

function canFulfillBulkConsumption(cartLines, productsById, rulesByType, bulkMap) {
  const totals = aggregateBulkConsumption(cartLines, productsById, rulesByType);
  for (const [skuKey, needed] of totals.entries()) {
    const bulk = bulkMap.get(skuKey);
    const available = bulk ? Number(bulk.quantity_on_hand) : 0;
    const unit = bulk?.unit || 'oz';
    const label = bulk?.name || skuKey;
    if (needed > available + 0.0005) {
      return {
        ok: false,
        error: available > 0
          ? `Insufficient ${label} (${roundQty(available)} ${unit} on hand, need ${roundQty(needed)} ${unit})`
          : `Insufficient ${label} for bar drinks (need ${roundQty(needed)} ${unit})`,
      };
    }
  }
  return { ok: true };
}

async function loadInventoryMap(ordsGet) {
  const rows = await ordsGet('product_inventory/');
  const map = new Map();
  for (const row of Array.isArray(rows) ? rows : []) {
    map.set(Number(row.product_id), row);
  }
  return map;
}

async function loadBulkInventoryMap(ordsGet) {
  const rows = await ordsGet('bulk_inventory/');
  const map = new Map();
  for (const row of Array.isArray(rows) ? rows : []) {
    map.set(String(row.sku_key), row);
  }
  return map;
}

async function loadConsumptionRulesMap(ordsGet) {
  const rows = await ordsGet('inventory_consumption_rules/');
  const map = new Map();
  for (const row of Array.isArray(rows) ? rows : []) {
    map.set(String(row.product_type), row);
  }
  return map;
}

async function getProductInventoryRow(ordsGet, productId) {
  const filter = encodeURIComponent(JSON.stringify({ product_id: { $eq: Number(productId) } }));
  const rows = await ordsGet(`product_inventory/?q=${filter}`);
  return Array.isArray(rows) && rows.length > 0 ? rows[0] : null;
}

async function getBulkInventoryRow(ordsGet, skuKey) {
  const filter = encodeURIComponent(JSON.stringify({ sku_key: { $eq: String(skuKey) } }));
  const rows = await ordsGet(`bulk_inventory/?q=${filter}`);
  return Array.isArray(rows) && rows.length > 0 ? rows[0] : null;
}

async function recordInventoryMovement(helpers, {
  productId,
  delta,
  reason,
  orderNumber = null,
  note = null,
}) {
  const { ordsGet, ordsPost, ordsPut, ordsTimestamp } = helpers;
  const pid = Number(productId);
  const change = Number(delta);
  if (!Number.isFinite(pid) || !Number.isFinite(change) || change === 0) {
    throw new Error('Invalid inventory movement');
  }

  let row = await getProductInventoryRow(ordsGet, pid);
  if (!row) {
    if (change < 0) {
      throw new Error('No inventory record for product');
    }
    await ordsPost('product_inventory/', {
      product_id: pid,
      quantity_on_hand: 0,
      reorder_point: 0,
      updated_at: ordsTimestamp(),
    });
    row = await getProductInventoryRow(ordsGet, pid);
    if (!row) {
      throw new Error('Failed to create inventory record');
    }
  }

  const current = Number(row.quantity_on_hand);
  const quantityAfter = current + change;
  if (quantityAfter < 0) {
    throw new Error('Insufficient stock');
  }

  await ordsPut(`product_inventory/${pid}`, {
    product_id: pid,
    quantity_on_hand: quantityAfter,
    reorder_point: Number(row.reorder_point) || 0,
    updated_at: ordsTimestamp(),
  });

  await ordsPost('inventory_movements/', {
    product_id: pid,
    delta: change,
    quantity_after: quantityAfter,
    reason,
    order_number: orderNumber,
    note,
    created_at: ordsTimestamp(),
  });

  return quantityAfter;
}

async function recordBulkMovement(helpers, {
  skuKey,
  delta,
  reason,
  orderNumber = null,
  note = null,
}) {
  const { ordsGet, ordsPost, ordsPut, ordsTimestamp } = helpers;
  const key = String(skuKey);
  const change = Number(delta);
  if (!key || !Number.isFinite(change) || change === 0) {
    throw new Error('Invalid bulk inventory movement');
  }

  let row = await getBulkInventoryRow(ordsGet, key);
  if (!row) {
    if (change < 0) {
      throw new Error('No bulk inventory record');
    }
    await ordsPost('bulk_inventory/', {
      sku_key: key,
      name: key,
      quantity_on_hand: 0,
      unit: 'oz',
      reorder_point: 0,
      updated_at: ordsTimestamp(),
    });
    row = await getBulkInventoryRow(ordsGet, key);
    if (!row) {
      throw new Error('Failed to create bulk inventory record');
    }
  }

  const current = Number(row.quantity_on_hand);
  const quantityAfter = roundQty(current + change);
  if (quantityAfter < -0.0005) {
    throw new Error('Insufficient bulk stock');
  }

  await ordsPut(`bulk_inventory/${key}`, {
    sku_key: key,
    name: row.name,
    quantity_on_hand: quantityAfter,
    unit: row.unit,
    reorder_point: Number(row.reorder_point) || 0,
    updated_at: ordsTimestamp(),
  });

  await ordsPost('inventory_movements/', {
    bulk_sku_key: key,
    delta: change,
    quantity_after: quantityAfter,
    reason,
    order_number: orderNumber,
    note,
    created_at: ordsTimestamp(),
  });

  return quantityAfter;
}

async function applyBulkConsumptionForSale(helpers, {
  cartLines,
  productsById,
  rulesByType,
  orderNumber,
}) {
  const totals = aggregateBulkConsumption(cartLines, productsById, rulesByType);
  const results = [];
  for (const [skuKey, amount] of totals.entries()) {
    if (amount <= 0) continue;
    const bulk = (await loadBulkInventoryMap(helpers.ordsGet)).get(skuKey);
    const unit = bulk?.unit || 'oz';
    const after = await recordBulkMovement(helpers, {
      skuKey,
      delta: -amount,
      reason: 'consume',
      orderNumber,
      note: `Bar drinks consumed ${roundQty(amount)} ${unit}`,
    });
    results.push({ skuKey, amount, quantityAfter: after });
  }
  return results;
}

function isOnSaleProduct(productRow) {
  const list = Number(productRow.price);
  const saleRaw = productRow.sale_price;
  if (saleRaw === null || saleRaw === undefined || saleRaw === '') return false;
  const sale = Number(saleRaw);
  return Number.isFinite(sale) && sale > 0 && sale < list;
}

function mapProductForCashier(productRow, inventoryMap) {
  const regularPrice = roundMoney(Number(productRow.price));
  const onSale = isOnSaleProduct(productRow);
  const salePrice = onSale ? roundMoney(Number(productRow.sale_price)) : null;
  const tracked = tracksInventory(productRow);
  const quantityOnHand = tracked
    ? availableQuantity(productRow, inventoryMap)
    : null;
  return {
    id: Number(productRow.id),
    barcode: productRow.barcode,
    name: productRow.name,
    regularPrice,
    salePrice: onSale ? salePrice : null,
    onSale,
    inStock: tracked ? quantityOnHand > 0 : true,
    quantityOnHand: tracked ? quantityOnHand : null,
  };
}

function roundMoney(n) {
  return Math.round(n * 100) / 100;
}

module.exports = {
  tracksInventory,
  availableQuantity,
  isInStock,
  canFulfillQuantity,
  consumptionForLine,
  aggregateBulkConsumption,
  canFulfillBulkConsumption,
  loadInventoryMap,
  loadBulkInventoryMap,
  loadConsumptionRulesMap,
  getProductInventoryRow,
  getBulkInventoryRow,
  recordInventoryMovement,
  recordBulkMovement,
  applyBulkConsumptionForSale,
  mapProductForCashier,
  roundQty,
};
