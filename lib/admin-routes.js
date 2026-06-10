const { ADMIN_TABLES } = require('./admin-tables');
const { asyncHandler } = require('./async-handler');
const {
  getBulkInventoryRow,
  getProductInventoryRow,
  recordBulkMovement,
  recordInventoryMovement,
  roundQty,
} = require('./inventory');

function tableMeta(name, cfg) {
  return {
    name,
    label: cfg.label,
    readOnly: !!cfg.readOnly,
    columns: cfg.columns,
    create: cfg.create || [],
    idColumn: cfg.idColumn || 'id',
    readOnlyColumns: cfg.readOnlyColumns || [],
  };
}

function normalizeBody(body, createFields) {
  const out = {};
  for (const key of createFields) {
    if (body[key] === undefined) continue;
    if (body[key] === '' || body[key] === null) {
      out[key] = null;
    } else if ([
      'price',
      'sale_price',
      'total',
      'subtotal_pre_member',
      'member_discount_pre_tax',
      'unit_price',
      'line_total',
      'quantity',
      'product_id',
      'customer_id',
      'linked_893',
      'track_inventory',
      'quantity_on_hand',
      'reorder_point',
      'delta',
      'quantity_after',
      'low_stock',
      'quantity_per_unit',
    ].includes(key)) {
      const n = Number(body[key]);
      out[key] = Number.isNaN(n) ? body[key] : n;
    } else {
      out[key] = body[key];
    }
  }
  return out;
}

function normalizeAdminRow(row, cfg) {
  if (!row || typeof row !== 'object') return row;
  const idColumn = cfg.idColumn || 'id';
  if (row.id != null || row[idColumn] == null) return row;
  return { ...row, id: row[idColumn] };
}

function normalizeAdminRows(rows, cfg) {
  return (Array.isArray(rows) ? rows : []).map((row) => normalizeAdminRow(row, cfg));
}

function registerAdminRoutes(app, helpers) {
  const { ordsGet, ordsPost, ordsPut, ordsDelete, ordsTimestamp } = helpers;

  app.get('/api/admin/meta', (_req, res) => {
    res.json(Object.entries(ADMIN_TABLES).map(([name, cfg]) => tableMeta(name, cfg)));
  });

  app.post('/api/admin/inventory/receive', asyncHandler(async (req, res) => {
    const productId = Number(req.body?.productId);
    const quantity = Number(req.body?.quantity);
    const note = req.body?.note ? String(req.body.note).trim() : null;
    if (!Number.isFinite(productId) || productId < 1) {
      return res.status(400).json({ error: 'productId is required' });
    }
    if (!Number.isFinite(quantity) || quantity < 1) {
      return res.status(400).json({ error: 'quantity must be at least 1' });
    }
    const product = await ordsGet(`products/${productId}`);
    if (!product || Number(product.id) !== productId) {
      return res.status(404).json({ error: 'Product not found' });
    }
    if (Number(product.track_inventory) !== 1) {
      return res.status(400).json({ error: 'Product does not track inventory' });
    }
    const quantityOnHand = await recordInventoryMovement(helpers, {
      productId,
      delta: quantity,
      reason: 'receive',
      note,
    });
    res.status(201).json({ ok: true, productId, quantityOnHand });
  }));

  app.post('/api/admin/inventory/adjust', asyncHandler(async (req, res) => {
    const productId = Number(req.body?.productId);
    const delta = Number(req.body?.delta);
    const note = req.body?.note ? String(req.body.note).trim() : null;
    if (!Number.isFinite(productId) || productId < 1) {
      return res.status(400).json({ error: 'productId is required' });
    }
    if (!Number.isFinite(delta) || delta === 0) {
      return res.status(400).json({ error: 'delta must be a non-zero number' });
    }
    const product = await ordsGet(`products/${productId}`);
    if (!product || Number(product.id) !== productId) {
      return res.status(404).json({ error: 'Product not found' });
    }
    if (Number(product.track_inventory) !== 1) {
      return res.status(400).json({ error: 'Product does not track inventory' });
    }
    try {
      const quantityOnHand = await recordInventoryMovement(helpers, {
        productId,
        delta,
        reason: 'adjust',
        note,
      });
      res.status(201).json({ ok: true, productId, quantityOnHand });
    } catch (err) {
      if (String(err.message).includes('Insufficient stock')) {
        return res.status(409).json({ error: err.message });
      }
      throw err;
    }
  }));

  app.post('/api/admin/inventory/set-count', asyncHandler(async (req, res) => {
    const productId = Number(req.body?.productId);
    const quantity = Number(req.body?.quantity);
    const note = req.body?.note ? String(req.body.note).trim() : null;
    if (!Number.isFinite(productId) || productId < 1) {
      return res.status(400).json({ error: 'productId is required' });
    }
    if (!Number.isFinite(quantity) || quantity < 0) {
      return res.status(400).json({ error: 'quantity must be zero or greater' });
    }
    const product = await ordsGet(`products/${productId}`);
    if (!product || Number(product.id) !== productId) {
      return res.status(404).json({ error: 'Product not found' });
    }
    if (Number(product.track_inventory) !== 1) {
      return res.status(400).json({ error: 'Product does not track inventory' });
    }
    const row = await getProductInventoryRow(ordsGet, productId);
    const current = row ? Number(row.quantity_on_hand) : 0;
    const delta = quantity - current;
    if (delta === 0) {
      return res.json({ ok: true, productId, quantityOnHand: current, unchanged: true });
    }
    try {
      const quantityOnHand = await recordInventoryMovement(helpers, {
        productId,
        delta,
        reason: 'count',
        note,
      });
      res.status(201).json({ ok: true, productId, quantityOnHand });
    } catch (err) {
      if (String(err.message).includes('Insufficient stock')) {
        return res.status(409).json({ error: err.message });
      }
      throw err;
    }
  }));

  app.post('/api/admin/inventory/bulk/receive', asyncHandler(async (req, res) => {
    const skuKey = String(req.body?.skuKey || '').trim();
    const quantity = Number(req.body?.quantity);
    const note = req.body?.note ? String(req.body.note).trim() : null;
    if (!skuKey) {
      return res.status(400).json({ error: 'skuKey is required' });
    }
    if (!Number.isFinite(quantity) || quantity <= 0) {
      return res.status(400).json({ error: 'quantity must be greater than zero' });
    }
    const row = await getBulkInventoryRow(ordsGet, skuKey);
    if (!row) {
      return res.status(404).json({ error: 'Bulk SKU not found' });
    }
    const quantityOnHand = await recordBulkMovement(helpers, {
      skuKey,
      delta: quantity,
      reason: 'receive',
      note,
    });
    res.status(201).json({ ok: true, skuKey, quantityOnHand });
  }));

  app.post('/api/admin/inventory/bulk/adjust', asyncHandler(async (req, res) => {
    const skuKey = String(req.body?.skuKey || '').trim();
    const delta = Number(req.body?.delta);
    const note = req.body?.note ? String(req.body.note).trim() : null;
    if (!skuKey) {
      return res.status(400).json({ error: 'skuKey is required' });
    }
    if (!Number.isFinite(delta) || delta === 0) {
      return res.status(400).json({ error: 'delta must be a non-zero number' });
    }
    const row = await getBulkInventoryRow(ordsGet, skuKey);
    if (!row) {
      return res.status(404).json({ error: 'Bulk SKU not found' });
    }
    try {
      const quantityOnHand = await recordBulkMovement(helpers, {
        skuKey,
        delta,
        reason: 'adjust',
        note,
      });
      res.status(201).json({ ok: true, skuKey, quantityOnHand });
    } catch (err) {
      if (String(err.message).includes('Insufficient')) {
        return res.status(409).json({ error: err.message });
      }
      throw err;
    }
  }));

  app.post('/api/admin/inventory/bulk/set-count', asyncHandler(async (req, res) => {
    const skuKey = String(req.body?.skuKey || '').trim();
    const quantity = Number(req.body?.quantity);
    const note = req.body?.note ? String(req.body.note).trim() : null;
    if (!skuKey) {
      return res.status(400).json({ error: 'skuKey is required' });
    }
    if (!Number.isFinite(quantity) || quantity < 0) {
      return res.status(400).json({ error: 'quantity must be zero or greater' });
    }
    const row = await getBulkInventoryRow(ordsGet, skuKey);
    if (!row) {
      return res.status(404).json({ error: 'Bulk SKU not found' });
    }
    const current = Number(row.quantity_on_hand);
    const delta = roundQty(quantity - current);
    if (delta === 0) {
      return res.json({ ok: true, skuKey, quantityOnHand: current, unchanged: true });
    }
    try {
      const quantityOnHand = await recordBulkMovement(helpers, {
        skuKey,
        delta,
        reason: 'count',
        note,
      });
      res.status(201).json({ ok: true, skuKey, quantityOnHand });
    } catch (err) {
      if (String(err.message).includes('Insufficient')) {
        return res.status(409).json({ error: err.message });
      }
      throw err;
    }
  }));

  app.get('/api/admin/:table', asyncHandler(async (req, res) => {
    const cfg = ADMIN_TABLES[req.params.table];
    if (!cfg) return res.status(404).json({ error: 'Unknown table' });
    const rows = await ordsGet(`${cfg.ords}/`);
    res.json(normalizeAdminRows(rows, cfg));
  }));

  app.get('/api/admin/:table/:id', asyncHandler(async (req, res) => {
    const cfg = ADMIN_TABLES[req.params.table];
    if (!cfg) return res.status(404).json({ error: 'Unknown table' });
    const row = await ordsGet(`${cfg.ords}/${req.params.id}`);
    res.json(normalizeAdminRow(row, cfg));
  }));

  app.post('/api/admin/:table', asyncHandler(async (req, res) => {
    const cfg = ADMIN_TABLES[req.params.table];
    if (!cfg) return res.status(404).json({ error: 'Unknown table' });
    if (cfg.readOnly) return res.status(405).json({ error: 'Table is read-only' });
    const fields = cfg.create?.length ? cfg.create : cfg.columns.filter((c) => c !== 'id');
    let body = normalizeBody(req.body || {}, fields);
    if (cfg.defaultsOnCreate) {
      body = { ...cfg.defaultsOnCreate({ ordsTimestamp }), ...body };
    }
    const created = await ordsPost(`${cfg.ords}/`, body);
    res.status(201).json(normalizeAdminRow(created, cfg));
  }));

  app.put('/api/admin/:table/:id', asyncHandler(async (req, res) => {
    const cfg = ADMIN_TABLES[req.params.table];
    if (!cfg) return res.status(404).json({ error: 'Unknown table' });
    if (cfg.readOnly) return res.status(405).json({ error: 'Table is read-only' });
    const existing = await ordsGet(`${cfg.ords}/${req.params.id}`);
    const readOnly = new Set(cfg.readOnlyColumns || []);
    const fields = cfg.columns.filter((c) => c !== 'id' && !readOnly.has(c));
    const body = normalizeBody(req.body || {}, fields);
    const payload = { ...existing, ...body };
    delete payload.id;
    const updated = await ordsPut(`${cfg.ords}/${req.params.id}`, payload);
    res.json(normalizeAdminRow(updated, cfg));
  }));

  app.delete('/api/admin/:table/:id', asyncHandler(async (req, res) => {
    const cfg = ADMIN_TABLES[req.params.table];
    if (!cfg) return res.status(404).json({ error: 'Unknown table' });
    if (cfg.readOnly) return res.status(405).json({ error: 'Table is read-only' });
    await ordsDelete(`${cfg.ords}/${req.params.id}`);
    res.status(204).end();
  }));
}

module.exports = { registerAdminRoutes, ADMIN_TABLES };
