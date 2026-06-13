'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  resolveReportRange,
  summarizeSalesRows,
  summarizeInventoryActivity,
} = require('../lib/store-reports');

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
    [{ total: 10, order_number: 'A' }, { total: 5, order_number: 'B', member_discount_pre_tax: 1 }],
    new Map([
      ['A', [{ payment_method: 'cash', amount: 10 }]],
      ['B', [{ payment_method: 'card', amount: 5 }]],
    ]),
  );
  assert.equal(summary.transaction_count, 2);
  assert.equal(summary.sales_total, 15);
  assert.equal(summary.cash_total, 10);
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
