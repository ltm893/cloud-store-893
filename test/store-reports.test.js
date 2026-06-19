'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  resolveReportRange,
  summarizeSalesRows,
  summarizeInventoryActivity,
  createStoreReports,
} = require('../lib/store-reports');
const { parseOrderNumber } = require('../lib/order-number');

test('resolveReportRange daily uses anchor UTC day', () => {
  const range = resolveReportRange('daily', '2026-06-13');
  assert.equal(range.label, '2026-06-13');
  assert.equal(range.start, '2026-06-13T00:00:00.000Z');
  assert.equal(range.end, '2026-06-14T00:00:00.000Z');
});

test('resolveReportRange weekly starts on Monday containing anchor', () => {
  const range = resolveReportRange('weekly', '2026-06-13');
  assert.equal(range.label, 'Week of 2026-06-08');
  assert.equal(range.start, '2026-06-08T00:00:00.000Z');
  assert.equal(range.end, '2026-06-15T00:00:00.000Z');
});

test('resolveReportRange monthly covers calendar month', () => {
  const range = resolveReportRange('monthly', '2026-06-13');
  assert.equal(range.label, '2026-06');
  assert.equal(range.start, '2026-06-01T00:00:00.000Z');
  assert.equal(range.end, '2026-07-01T00:00:00.000Z');
});

test('summarizeSalesRows totals transactions and payment split', () => {
  const summary = summarizeSalesRows(
    [
      { total: 21.25, register_total: 21.26, order_number: 'A' },
      { total: 5, order_number: 'B', member_discount_pre_tax: 1 },
    ],
    new Map([
      ['A', [{ payment_method: 'cash', amount: 21.25 }]],
      ['B', [{ payment_method: 'card', amount: 5 }]],
    ]),
  );
  assert.equal(summary.transaction_count, 2);
  assert.equal(summary.sales_total, 26.25);
  assert.equal(summary.register_total, 26.26);
  assert.equal(summary.cash_rounding_total, 0.01);
  assert.equal(summary.cash_total, 21.25);
  assert.equal(summary.credit_total, 5);
  assert.equal(summary.member_discount_total, 1);
});

test('summarizeInventoryActivity aggregates movement reasons in range', () => {
  const range = resolveReportRange('daily', '2026-06-13');
  const activity = summarizeInventoryActivity(
    [
      { created_at: '2026-06-13T10:00:00Z', delta: 10, reason: 'receive', product_id: 1 },
      { created_at: '2026-06-13T11:00:00Z', delta: -2, reason: 'sale', product_id: 1 },
      { created_at: '2026-06-12T11:00:00Z', delta: -1, reason: 'sale', product_id: 1 },
    ],
    range,
  );
  assert.equal(activity.received, 10);
  assert.equal(activity.sold, 2);
  assert.equal(activity.net_product_units, 8);
});

test('parseOrderNumber requires a non-empty value', () => {
  assert.throws(() => parseOrderNumber(''), /order_number is required/);
  assert.equal(parseOrderNumber('0000001'), '0000001');
});

test('buildOrderDetailsByOrderNumber assembles touchpoints for an order', async () => {
  const ordsGet = async (path) => {
    if (path.startsWith('sales/?q=')) {
      return [{
        id: 10,
        order_number: '0000100',
        total: 21.25,
        register_total: 21.25,
        cash_due: 21.25,
        payment_method: 'split',
        customer_id: 2,
        subtotal_pre_member: 20,
        member_discount_pre_tax: 2,
        linked_893: 1,
        till_id: 5,
        created_at: '2026-06-13T12:00:00Z',
      }];
    }
    if (path.startsWith('sale_items/?q=')) {
      return [{
        id: 1,
        order_number: '0000100',
        product_id: 4,
        quantity: 2,
        unit_price: 10,
        line_total: 20,
      }];
    }
    if (path.startsWith('sale_payments/?q=')) {
      return [{
        id: 1,
        order_number: '0000100',
        sequence_number: 1,
        payment_method: 'card',
        amount: 10,
        created_at: '2026-06-13T12:00:01Z',
      }];
    }
    if (path.startsWith('inventory_movements/?q=')) {
      return [{
        id: 9,
        order_number: '0000100',
        product_id: 4,
        delta: -2,
        quantity_after: 8,
        reason: 'sale',
        created_at: '2026-06-13T12:00:02Z',
      }];
    }
    if (path === 'products/') {
      return [{ id: 4, name: 'Cold Brew', barcode: '872000000004', product_type: 'made coffee' }];
    }
    if (path === 'bulk_inventory/') return [];
    if (path === 'customers/2') {
      return { id: 2, name: 'Alex Rivera', email: 'alex@example.com' };
    }
    if (path === 'tills/5') {
      return {
        id: 5,
        pos_session_id: 7,
        register_id: 'tablet-abc',
        till_type: 'cash',
        cashier_sub: 'sub-1',
        cashier_email: 'cashier@example.com',
        opened_at: '2026-06-13T08:00:00Z',
        status: 'open',
        open_approval_token: 'tok-open-1',
      };
    }
    if (path === 'pos_sessions/7') {
      return {
        id: 7,
        register_id: 'tablet-abc',
        status: 'active',
        started_at: '2026-06-13T08:00:00Z',
      };
    }
    if (path.startsWith('till_open_approvals/?q=')) {
      return [{
        request_token: 'tok-open-1',
        status: 'approved',
        requested_at: '2026-06-13T07:59:00Z',
        resolved_at: '2026-06-13T08:00:00Z',
        resolved_by_email: 'supervisor@example.com',
      }];
    }
    throw new Error(`Unexpected ORDS GET ${path}`);
  };

  const reports = createStoreReports({ ordsGet });
  const report = await reports.buildOrderDetailsByOrderNumber({ order_number: '0000100' });

  assert.equal(report.query, 'OrderDetailsByOrdernumber');
  assert.equal(report.sale.order_number, '0000100');
  assert.equal(report.customer.name, 'Alex Rivera');
  assert.equal(report.items.length, 1);
  assert.equal(report.payments.length, 1);
  assert.equal(report.inventory_movements.length, 1);
  assert.equal(report.till.id, 5);
  assert.equal(report.pos_session.id, 7);
  assert.equal(report.till_open_approval.status, 'approved');
  assert.ok(report.touchpoints.some((row) => row.touchpoint === 'SALE'));
  assert.ok(report.touchpoints.some((row) => row.touchpoint === 'CUSTOMER'));
  assert.ok(report.touchpoints.some((row) => row.touchpoint === 'PAYMENT'));
  assert.ok(report.touchpoints.some((row) => row.touchpoint === 'INVENTORY'));
  assert.ok(report.touchpoints.some((row) => row.touchpoint === 'TILL'));
});

test('buildOrderDetailsByOrderNumber returns 404 when order is missing', async () => {
  const reports = createStoreReports({
    ordsGet: async (path) => (path.startsWith('sales/?q=') ? [] : []),
  });
  await assert.rejects(
    () => reports.buildOrderDetailsByOrderNumber({ order_number: '9999998' }),
    /Order not found/,
  );
});
