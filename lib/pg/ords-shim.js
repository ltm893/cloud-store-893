'use strict';

const { Pool, types } = require('pg');

// NUMERIC → number (ORDS returned JSON numbers)
types.setTypeParser(1700, (val) => (val === null ? null : parseFloat(val)));

const PK_COLUMNS = {
  products: 'id',
  customers: 'id',
  cart_items: 'id',
  cart_view: 'id',
  sales: 'id',
  sale_items: 'id',
  sale_payments: 'id',
  product_inventory: 'product_id',
  bulk_inventory: 'sku_key',
  inventory_consumption_rules: 'product_type',
  inventory_movements: 'id',
  inventory_status_view: 'product_id',
  tills: 'id',
  till_open_approvals: 'id',
  till_close_approvals: 'id',
  pos_sessions: 'id',
};

const READ_ONLY = new Set(['cart_view', 'inventory_status_view']);

/** ORDS accepts ISO-8601 with Z; rejects milliseconds (e.g. .000Z). */
function ordsTimestamp(date = new Date()) {
  return date.toISOString().replace(/\.\d{3}Z$/, 'Z');
}

function normalizeValue(v) {
  if (v instanceof Date) {
    return v.toISOString().replace(/\.\d{3}Z$/, 'Z');
  }
  return v;
}

function normalizeRow(row) {
  if (!row || typeof row !== 'object') return row;
  const out = {};
  for (const [k, v] of Object.entries(row)) {
    out[k] = normalizeValue(v);
  }
  return out;
}

function normalizeRows(rows) {
  return rows.map(normalizeRow);
}

function parsePath(path) {
  const raw = String(path || '').replace(/^\//, '');
  const [pathPart, queryString = ''] = raw.split('?');
  const segments = pathPart.split('/').filter(Boolean);
  const resource = segments[0] || '';
  const id = segments.length > 1 ? segments.slice(1).join('/') : null;

  const params = new URLSearchParams(queryString);
  let filter = null;
  const q = params.get('q');
  if (q) {
    try {
      filter = JSON.parse(q);
    } catch {
      throw new Error(`Invalid ORDS filter JSON: ${q}`);
    }
  }

  const limit = params.has('limit') ? Number(params.get('limit')) : null;
  const offset = params.has('offset') ? Number(params.get('offset')) : null;
  const order = params.get('order'); // e.g. created_at:desc

  return { resource, id, filter, limit, offset, order };
}

function buildWhere(filter, startIndex = 1) {
  if (!filter || typeof filter !== 'object') {
    return { clause: '', values: [], nextIndex: startIndex };
  }
  const parts = [];
  const values = [];
  let i = startIndex;
  for (const [field, cond] of Object.entries(filter)) {
    if (!/^[a-z_][a-z0-9_]*$/i.test(field)) {
      throw new Error(`Unsafe filter field: ${field}`);
    }
    if (cond && typeof cond === 'object' && Object.prototype.hasOwnProperty.call(cond, '$eq')) {
      parts.push(`"${field}" = $${i}`);
      values.push(cond.$eq);
      i += 1;
    } else {
      throw new Error(`Unsupported filter operator for ${field}: ${JSON.stringify(cond)}`);
    }
  }
  return {
    clause: parts.length ? `WHERE ${parts.join(' AND ')}` : '',
    values,
    nextIndex: i,
  };
}

function buildOrder(order) {
  if (!order) return '';
  const [col, dirRaw] = String(order).split(':');
  if (!/^[a-z_][a-z0-9_]*$/i.test(col)) {
    throw new Error(`Unsafe order column: ${col}`);
  }
  const dir = String(dirRaw || 'asc').toLowerCase() === 'desc' ? 'DESC' : 'ASC';
  return `ORDER BY "${col}" ${dir}`;
}

function quoteIdent(name) {
  if (!/^[a-z_][a-z0-9_]*$/i.test(name)) {
    throw new Error(`Unsafe identifier: ${name}`);
  }
  return `"${name}"`;
}

function sslOption(connectionString) {
  if (process.env.PGSSLMODE === 'disable' || process.env.DATABASE_SSL === 'false') {
    return false;
  }
  if (process.env.DATABASE_SSL === 'true' || /rds\.amazonaws\.com|amazonaws\.com/.test(connectionString || '')) {
    return { rejectUnauthorized: false };
  }
  return undefined;
}

function resolveConnectionString(options = {}) {
  if (options.connectionString) return options.connectionString;
  if (process.env.DATABASE_URL) return process.env.DATABASE_URL;
  const host = process.env.PGHOST || process.env.DB_HOST;
  const user = process.env.PGUSER || process.env.DB_USER;
  const password = process.env.PGPASSWORD || process.env.DB_PASSWORD;
  const database = process.env.PGDATABASE || process.env.DB_NAME;
  const port = process.env.PGPORT || process.env.DB_PORT || '5432';
  if (host && user && database) {
    const enc = encodeURIComponent(password || '');
    return `postgresql://${encodeURIComponent(user)}:${enc}@${host}:${port}/${database}`;
  }
  return null;
}

/**
 * Postgres AutoREST-compatible client matching createOrdsClient surface.
 * @param {string|object} connectionStringOrOptions
 */
function createPgOrdsClient(connectionStringOrOptions) {
  const opts =
    typeof connectionStringOrOptions === 'string'
      ? { connectionString: connectionStringOrOptions }
      : connectionStringOrOptions || {};

  const connectionString = resolveConnectionString(opts);
  if (!connectionString) {
    throw new Error('DATABASE_URL (or PG* connection env) is required for postgres backend');
  }

  const pool =
    opts.pool ||
    new Pool({
      connectionString,
      ssl: sslOption(connectionString),
    });

  async function query(text, params) {
    const result = await pool.query(text, params);
    return result;
  }

  async function ordsGet(path) {
    const { resource, id, filter, limit, offset, order } = parsePath(path);
    if (!resource || !PK_COLUMNS[resource]) {
      throw new Error(`Unknown resource: ${resource}`);
    }
    const table = quoteIdent(resource);
    const pk = PK_COLUMNS[resource];

    if (id != null && id !== '') {
      const result = await query(`SELECT * FROM ${table} WHERE ${quoteIdent(pk)} = $1`, [coerceId(pk, id)]);
      if (!result.rows.length) {
        throw new Error(`ORDS GET ${path} → 404`);
      }
      return normalizeRow(result.rows[0]);
    }

    const where = buildWhere(filter);
    const orderSql = buildOrder(order);
    let sql = `SELECT * FROM ${table} ${where.clause} ${orderSql}`.trim();
    const values = [...where.values];
    let next = where.nextIndex;
    if (limit != null && Number.isFinite(limit)) {
      sql += ` LIMIT $${next}`;
      values.push(limit);
      next += 1;
    }
    if (offset != null && Number.isFinite(offset)) {
      sql += ` OFFSET $${next}`;
      values.push(offset);
    }
    const result = await query(sql, values);
    return normalizeRows(result.rows);
  }

  async function ordsTryGet(path) {
    try {
      return await ordsGet(path);
    } catch (err) {
      if (String(err.message).includes('→ 404')) return null;
      throw err;
    }
  }

  async function ordsPost(path, body) {
    const { resource } = parsePath(path);
    if (!resource || !PK_COLUMNS[resource]) {
      throw new Error(`Unknown resource: ${resource}`);
    }
    if (READ_ONLY.has(resource)) {
      throw new Error(`ORDS POST ${path} → 405: read-only`);
    }
    const table = quoteIdent(resource);
    const cols = Object.keys(body || {}).filter((c) => /^[a-z_][a-z0-9_]*$/i.test(c));
    if (!cols.length) {
      throw new Error(`ORDS POST ${path}: empty body`);
    }
    const colSql = cols.map(quoteIdent).join(', ');
    const placeholders = cols.map((_, i) => `$${i + 1}`).join(', ');
    const values = cols.map((c) => body[c]);
    const result = await query(
      `INSERT INTO ${table} (${colSql}) VALUES (${placeholders}) RETURNING *`,
      values
    );
    return normalizeRow(result.rows[0]);
  }

  async function ordsPut(path, body) {
    const { resource, id } = parsePath(path);
    if (!resource || !PK_COLUMNS[resource] || id == null || id === '') {
      throw new Error(`ORDS PUT requires resource/id: ${path}`);
    }
    if (READ_ONLY.has(resource)) {
      throw new Error(`ORDS PUT ${path} → 405: read-only`);
    }
    const table = quoteIdent(resource);
    const pk = PK_COLUMNS[resource];
    const cols = Object.keys(body || {}).filter(
      (c) => c !== pk && /^[a-z_][a-z0-9_]*$/i.test(c)
    );
    if (!cols.length) {
      throw new Error(`ORDS PUT ${path}: empty body`);
    }
    const sets = cols.map((c, i) => `${quoteIdent(c)} = $${i + 1}`).join(', ');
    const values = cols.map((c) => body[c]);
    values.push(coerceId(pk, id));
    const result = await query(
      `UPDATE ${table} SET ${sets} WHERE ${quoteIdent(pk)} = $${cols.length + 1} RETURNING *`,
      values
    );
    if (!result.rows.length) {
      throw new Error(`ORDS PUT ${path} → 404`);
    }
    return normalizeRow(result.rows[0]);
  }

  async function ordsDelete(path) {
    const { resource, id } = parsePath(path);
    if (!resource || !PK_COLUMNS[resource] || id == null || id === '') {
      throw new Error(`ORDS DELETE requires resource/id: ${path}`);
    }
    if (READ_ONLY.has(resource)) {
      throw new Error(`ORDS DELETE ${path} → 405: read-only`);
    }
    const table = quoteIdent(resource);
    const pk = PK_COLUMNS[resource];
    const result = await query(`DELETE FROM ${table} WHERE ${quoteIdent(pk)} = $1`, [
      coerceId(pk, id),
    ]);
    if (result.rowCount === 0) {
      throw new Error(`ORDS DELETE ${path} → 404`);
    }
  }

  return {
    ordsGet,
    ordsTryGet,
    ordsPost,
    ordsPut,
    ordsDelete,
    ordsTimestamp,
    pool,
    async end() {
      await pool.end();
    },
  };
}

function coerceId(pk, id) {
  const decoded = decodeURIComponent(String(id));
  if (pk === 'sku_key' || pk === 'product_type') {
    return decoded;
  }
  const n = Number(decoded);
  return Number.isFinite(n) ? n : decoded;
}

module.exports = {
  createPgOrdsClient,
  ordsTimestamp,
  parsePath,
  buildWhere,
  PK_COLUMNS,
};
