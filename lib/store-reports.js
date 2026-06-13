const { createTillSalesStats } = require('./shift-sales-stats');

const REPORT_PERIODS = ['daily', 'weekly', 'monthly'];
const MS_PER_DAY = 86_400_000;

function roundMoney(n) {
  return Math.round(Number(n) * 100) / 100;
}

function formatAnchorUtc(date) {
  const y = date.getUTCFullYear();
  const m = String(date.getUTCMonth() + 1).padStart(2, '0');
  const d = String(date.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

function parseAnchorDate(anchor) {
  if (!anchor) return formatAnchorUtc(new Date());
  const value = String(anchor).trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    const err = new Error('anchor must be YYYY-MM-DD');
    err.status = 400;
    throw err;
  }
  const [y, m, d] = value.split('-').map(Number);
  if (m < 1 || m > 12 || d < 1 || d > 31) {
    const err = new Error('anchor must be a valid calendar date');
    err.status = 400;
    throw err;
  }
  return value;
}

function normalizePeriod(period) {
  const value = String(period || 'daily').trim().toLowerCase();
  if (!REPORT_PERIODS.includes(value)) {
    const err = new Error(`period must be one of: ${REPORT_PERIODS.join(', ')}`);
    err.status = 400;
    throw err;
  }
  return value;
}

/**
 * Calendar ranges in UTC (anchor date is interpreted as a UTC calendar day).
 */
function resolveReportRange(period, anchor) {
  const normalizedPeriod = normalizePeriod(period);
  const anchorDate = parseAnchorDate(anchor);
  const [y, m, d] = anchorDate.split('-').map(Number);
  const anchorMs = Date.UTC(y, m - 1, d);

  let startMs;
  let endMs;
  let label;

  if (normalizedPeriod === 'daily') {
    startMs = anchorMs;
    endMs = anchorMs + MS_PER_DAY;
    label = anchorDate;
  } else if (normalizedPeriod === 'weekly') {
    const weekday = new Date(anchorMs).getUTCDay();
    const daysFromMonday = (weekday + 6) % 7;
    startMs = anchorMs - daysFromMonday * MS_PER_DAY;
    endMs = startMs + 7 * MS_PER_DAY;
    label = `Week of ${formatAnchorUtc(new Date(startMs))}`;
  } else {
    startMs = Date.UTC(y, m - 1, 1);
    endMs = Date.UTC(y, m, 1);
    label = `${y}-${String(m).padStart(2, '0')}`;
  }

  return {
    period: normalizedPeriod,
    anchor: anchorDate,
    label,
    timezone: 'UTC',
    start: new Date(startMs).toISOString(),
    end: new Date(endMs).toISOString(),
    startMs,
    endMs,
  };
}

function timestampMs(value) {
  if (!value) return null;
  const ms = new Date(value).getTime();
  return Number.isFinite(ms) ? ms : null;
}

function inRange(ms, range) {
  return ms != null && ms >= range.startMs && ms < range.endMs;
}

function dayKeyUtc(ms) {
  const date = new Date(ms);
  return formatAnchorUtc(date);
}

async function listAllRows(ordsGet, path) {
  const rows = await ordsGet(`${path}/`);
  return Array.isArray(rows) ? rows : [];
}

function summarizePayments(payments) {
  let cashTotal = 0;
  let creditTotal = 0;
  for (const payment of payments) {
    const amount = Number(payment?.amount) || 0;
    const method = String(payment.payment_method || '').toLowerCase();
    if (method === 'cash') cashTotal += amount;
    else if (method === 'card') creditTotal += amount;
  }
  return {
    cash_total: roundMoney(cashTotal),
    credit_total: roundMoney(creditTotal),
  };
}

function summarizeSalesRows(sales, paymentsByOrder) {
  const salesList = Array.isArray(sales) ? sales : [];
  let salesTotal = 0;
  let memberDiscountTotal = 0;
  const payments = [];

  for (const sale of salesList) {
    salesTotal += Number(sale?.total) || 0;
    memberDiscountTotal += Number(sale?.member_discount_pre_tax) || 0;
    const orderPayments = paymentsByOrder.get(sale.order_number) || [];
    payments.push(...orderPayments);
  }

  const payTotals = summarizePayments(payments);
  return {
    transaction_count: salesList.length,
    sales_total: roundMoney(salesTotal),
    member_discount_total: roundMoney(memberDiscountTotal),
    ...payTotals,
  };
}

function bucketSalesByDay(sales, range) {
  const buckets = new Map();
  let cursor = range.startMs;
  while (cursor < range.endMs) {
    buckets.set(dayKeyUtc(cursor), {
      date: dayKeyUtc(cursor),
      transaction_count: 0,
      sales_total: 0,
    });
    cursor += MS_PER_DAY;
  }

  for (const sale of sales) {
    const ms = timestampMs(sale?.created_at);
    if (!inRange(ms, range)) continue;
    const key = dayKeyUtc(ms);
    const bucket = buckets.get(key);
    if (!bucket) continue;
    bucket.transaction_count += 1;
    bucket.sales_total = roundMoney(bucket.sales_total + (Number(sale?.total) || 0));
  }

  return [...buckets.values()];
}

function aggregateTopProducts(saleItems, productsById, limit = 10) {
  const totals = new Map();
  for (const line of saleItems) {
    const productId = Number(line?.product_id);
    if (!Number.isFinite(productId) || productId <= 0) continue;
    const qty = Number(line?.quantity) || 0;
    const revenue = Number(line?.line_total) || 0;
    const prev = totals.get(productId) || { product_id: productId, quantity: 0, revenue: 0 };
    prev.quantity += qty;
    prev.revenue = roundMoney(prev.revenue + revenue);
    totals.set(productId, prev);
  }

  return [...totals.values()]
    .sort((a, b) => b.revenue - a.revenue || b.quantity - a.quantity)
    .slice(0, limit)
    .map((row) => {
      const product = productsById.get(row.product_id);
      return {
        ...row,
        name: product?.name ?? `Product #${row.product_id}`,
        barcode: product?.barcode ?? null,
      };
    });
}

function summarizeInventoryActivity(movements, range) {
  const activity = {
    received: 0,
    sold: 0,
    adjusted: 0,
    bulk_received: 0,
    bulk_sold: 0,
    bulk_adjusted: 0,
    net_product_units: 0,
    net_bulk_units: 0,
  };

  for (const row of movements) {
    const ms = timestampMs(row?.created_at);
    if (!inRange(ms, range)) continue;
    const delta = Number(row?.delta) || 0;
    const reason = String(row?.reason || '').toLowerCase();
    const isBulk = row?.bulk_sku_key != null && String(row.bulk_sku_key).trim() !== '';

    if (isBulk) {
      if (reason === 'receive') activity.bulk_received += delta;
      else if (reason === 'sale') activity.bulk_sold += Math.abs(delta);
      else if (reason === 'adjust' || reason === 'count') activity.bulk_adjusted += delta;
      activity.net_bulk_units = roundMoney(activity.net_bulk_units + delta);
      continue;
    }

    if (reason === 'receive') activity.received += delta;
    else if (reason === 'sale') activity.sold += Math.abs(delta);
    else if (reason === 'adjust' || reason === 'count') activity.adjusted += delta;
    activity.net_product_units += delta;
  }

  activity.net_product_units = roundMoney(activity.net_product_units);
  activity.net_bulk_units = roundMoney(activity.net_bulk_units);
  return activity;
}

/**
 * @param {{ ordsGet: Function }} helpers
 */
function createStoreReports(helpers) {
  const { ordsGet } = helpers;
  const tillSalesStats = createTillSalesStats({ ordsGet });

  async function buildSalesReport({ period = 'daily', anchor = null } = {}) {
    const range = resolveReportRange(period, anchor);
    const [sales, salePayments, saleItems, products] = await Promise.all([
      listAllRows(ordsGet, 'sales'),
      listAllRows(ordsGet, 'sale_payments'),
      listAllRows(ordsGet, 'sale_items'),
      listAllRows(ordsGet, 'products'),
    ]);

    const salesInRange = sales.filter((sale) => inRange(timestampMs(sale?.created_at), range));
    const orderSet = new Set(salesInRange.map((sale) => sale.order_number));
    const paymentsByOrder = new Map();
    for (const payment of salePayments) {
      if (!orderSet.has(payment.order_number)) continue;
      const list = paymentsByOrder.get(payment.order_number) || [];
      list.push(payment);
      paymentsByOrder.set(payment.order_number, list);
    }

    const itemsInRange = saleItems.filter((line) => orderSet.has(line.order_number));
    const productsById = new Map(products.map((p) => [Number(p.id), p]));

    const summary = summarizeSalesRows(salesInRange, paymentsByOrder);
    const report = {
      kind: 'sales',
      generatedAt: new Date().toISOString(),
      range,
      summary: {
        ...summary,
        items_sold: itemsInRange.reduce((sum, line) => sum + (Number(line.quantity) || 0), 0),
      },
      top_products: aggregateTopProducts(itemsInRange, productsById),
    };

    if (range.period !== 'daily') {
      report.by_day = bucketSalesByDay(salesInRange, range);
    }

    return report;
  }

  async function buildInventoryReport({ period = 'daily', anchor = null } = {}) {
    const range = resolveReportRange(period, anchor);
    const [inventoryStatus, movements, bulkInventory] = await Promise.all([
      listAllRows(ordsGet, 'inventory_status_view'),
      listAllRows(ordsGet, 'inventory_movements'),
      listAllRows(ordsGet, 'bulk_inventory'),
    ]);

    const tracked = inventoryStatus.filter((row) => Number(row.quantity_on_hand) >= 0);
    const lowStock = tracked.filter((row) => Number(row.low_stock) === 1);
    const activity = summarizeInventoryActivity(movements, range);

    const periodMovements = movements.filter((row) => inRange(timestampMs(row?.created_at), range));

    return {
      kind: 'inventory',
      generatedAt: new Date().toISOString(),
      range,
      snapshot: {
        tracked_skus: tracked.length,
        low_stock_count: lowStock.length,
        total_units_on_hand: tracked.reduce((sum, row) => sum + (Number(row.quantity_on_hand) || 0), 0),
        bulk_skus: bulkInventory.length,
        bulk_units_on_hand: bulkInventory.reduce(
          (sum, row) => sum + (Number(row.quantity_on_hand) || 0),
          0,
        ),
      },
      activity,
      low_stock: lowStock.map((row) => ({
        product_id: row.product_id,
        name: row.name,
        barcode: row.barcode,
        quantity_on_hand: Number(row.quantity_on_hand) || 0,
        reorder_point: Number(row.reorder_point) || 0,
      })),
      recent_movements: periodMovements
        .sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)))
        .slice(0, 50)
        .map((row) => ({
          id: row.id,
          product_id: row.product_id ?? null,
          bulk_sku_key: row.bulk_sku_key ?? null,
          delta: Number(row.delta) || 0,
          quantity_after: row.quantity_after == null ? null : Number(row.quantity_after),
          reason: row.reason,
          order_number: row.order_number ?? null,
          note: row.note ?? null,
          created_at: row.created_at,
        })),
    };
  }

  return {
    REPORT_PERIODS,
    resolveReportRange,
    buildSalesReport,
    buildInventoryReport,
    summarizeSalesRows,
    summarizeInventoryActivity,
  };
}

module.exports = {
  REPORT_PERIODS,
  MS_PER_DAY,
  roundMoney,
  parseAnchorDate,
  normalizePeriod,
  resolveReportRange,
  summarizeSalesRows,
  summarizeInventoryActivity,
  createStoreReports,
};
