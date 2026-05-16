const { ADMIN_TABLES } = require('./admin-tables');

function tableMeta(name, cfg) {
  return {
    name,
    label: cfg.label,
    readOnly: !!cfg.readOnly,
    columns: cfg.columns,
    create: cfg.create || [],
  };
}

function normalizeBody(body, createFields) {
  const out = {};
  for (const key of createFields) {
    if (body[key] === undefined) continue;
    if (body[key] === '' || body[key] === null) {
      out[key] = null;
    } else if (['price', 'sale_price', 'total', 'subtotal_pre_member', 'member_discount_pre_tax', 'unit_price', 'line_total', 'quantity', 'product_id', 'customer_id', 'linked_893'].includes(key)) {
      const n = Number(body[key]);
      out[key] = Number.isNaN(n) ? body[key] : n;
    } else {
      out[key] = body[key];
    }
  }
  return out;
}

function registerAdminRoutes(app, helpers) {
  const { ordsGet, ordsPost, ordsPut, ordsDelete, ordsTimestamp } = helpers;

  app.get('/api/admin/meta', (_req, res) => {
    res.json(Object.entries(ADMIN_TABLES).map(([name, cfg]) => tableMeta(name, cfg)));
  });

  app.get('/api/admin/:table', async (req, res) => {
    const cfg = ADMIN_TABLES[req.params.table];
    if (!cfg) return res.status(404).json({ error: 'Unknown table' });
    try {
      const rows = await ordsGet(`${cfg.ords}/`);
      res.json(rows);
    } catch (err) {
      console.error(err.message);
      res.status(500).json({ error: err.message });
    }
  });

  app.get('/api/admin/:table/:id', async (req, res) => {
    const cfg = ADMIN_TABLES[req.params.table];
    if (!cfg) return res.status(404).json({ error: 'Unknown table' });
    try {
      const row = await ordsGet(`${cfg.ords}/${req.params.id}`);
      res.json(row);
    } catch (err) {
      console.error(err.message);
      res.status(500).json({ error: err.message });
    }
  });

  app.post('/api/admin/:table', async (req, res) => {
    const cfg = ADMIN_TABLES[req.params.table];
    if (!cfg) return res.status(404).json({ error: 'Unknown table' });
    if (cfg.readOnly) return res.status(405).json({ error: 'Table is read-only' });
    try {
      const fields = cfg.create?.length ? cfg.create : cfg.columns.filter((c) => c !== 'id');
      let body = normalizeBody(req.body || {}, fields);
      if (cfg.defaultsOnCreate) {
        body = { ...cfg.defaultsOnCreate({ ordsTimestamp }), ...body };
      }
      const created = await ordsPost(`${cfg.ords}/`, body);
      res.status(201).json(created);
    } catch (err) {
      console.error(err.message);
      res.status(500).json({ error: err.message });
    }
  });

  app.put('/api/admin/:table/:id', async (req, res) => {
    const cfg = ADMIN_TABLES[req.params.table];
    if (!cfg) return res.status(404).json({ error: 'Unknown table' });
    if (cfg.readOnly) return res.status(405).json({ error: 'Table is read-only' });
    try {
      const fields = cfg.columns.filter((c) => c !== 'id');
      const body = normalizeBody(req.body || {}, fields);
      const updated = await ordsPut(`${cfg.ords}/${req.params.id}`, body);
      res.json(updated);
    } catch (err) {
      console.error(err.message);
      res.status(500).json({ error: err.message });
    }
  });

  app.delete('/api/admin/:table/:id', async (req, res) => {
    const cfg = ADMIN_TABLES[req.params.table];
    if (!cfg) return res.status(404).json({ error: 'Unknown table' });
    if (cfg.readOnly) return res.status(405).json({ error: 'Table is read-only' });
    try {
      await ordsDelete(`${cfg.ords}/${req.params.id}`);
      res.status(204).end();
    } catch (err) {
      console.error(err.message);
      res.status(500).json({ error: err.message });
    }
  });
}

module.exports = { registerAdminRoutes, ADMIN_TABLES };
