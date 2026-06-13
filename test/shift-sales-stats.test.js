'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createShiftSalesStats } = require('../lib/shift-sales-stats');

test('summarizeShiftSales counts transactions and sums sale totals', () => {
  const shiftSalesStats = createShiftSalesStats({ ordsGet: async () => [] });
  const stats = shiftSalesStats.summarizeShiftSales({
    sales: [{ total: 12.5 }, { total: 7.25 }, { total: null }],
    payments: [],
  });
  assert.equal(stats.transaction_count, 3);
  assert.equal(stats.sales_total, 19.75);
  assert.equal(stats.cash_total, 0);
  assert.equal(stats.credit_total, 0);
});

test('summarizeShiftSales splits cash and credit from payment lines', () => {
  const shiftSalesStats = createShiftSalesStats({ ordsGet: async () => [] });
  const stats = shiftSalesStats.summarizeShiftSales({
    sales: [{ total: 35 }],
    payments: [
      { payment_method: 'cash', amount: 20 },
      { payment_method: 'card', amount: 10 },
      { payment_method: 'card', amount: 5 },
    ],
  });
  assert.equal(stats.transaction_count, 1);
  assert.equal(stats.sales_total, 35);
  assert.equal(stats.cash_total, 20);
  assert.equal(stats.credit_total, 15);
});

test('statsForShift queries sales and payments by shift', async () => {
  const calls = [];
  const shiftSalesStats = createShiftSalesStats({
    ordsGet: async (path) => {
      calls.push(path);
      if (path.startsWith('sales/')) {
        return [{ order_number: 'POS-1', total: 25 }];
      }
      if (path.includes('POS-1')) {
        return [
          { payment_method: 'cash', amount: 10 },
          { payment_method: 'card', amount: 15 },
        ];
      }
      return [];
    },
  });

  const stats = await shiftSalesStats.statsForShift(42);
  assert.equal(stats.transaction_count, 1);
  assert.equal(stats.sales_total, 25);
  assert.equal(stats.cash_total, 10);
  assert.equal(stats.credit_total, 15);
  assert.equal(calls.length, 2);
  assert.match(calls[0], /till_id/);
  assert.match(calls[1], /POS-1/);
});

test('attachStatsToShifts enriches each shift row', async () => {
  const shiftSalesStats = createShiftSalesStats({
    ordsGet: async (path) => {
      if (path.startsWith('sales/')) {
        if (path.includes('1')) {
          return [{ order_number: 'POS-A', total: 3 }];
        }
        if (path.includes('2')) {
          return [
            { order_number: 'POS-B', total: 4 },
            { order_number: 'POS-C', total: 6 },
          ];
        }
      }
      if (path.includes('POS-A')) {
        return [{ payment_method: 'card', amount: 3 }];
      }
      if (path.includes('POS-B')) {
        return [{ payment_method: 'cash', amount: 4 }];
      }
      if (path.includes('POS-C')) {
        return [{ payment_method: 'card', amount: 6 }];
      }
      return [];
    },
  });

  const rows = await shiftSalesStats.attachStatsToShifts([
    { id: 1, cashier_email: 'a@example.com' },
    { id: 2, cashier_email: 'b@example.com' },
  ]);

  assert.equal(rows[0].transaction_count, 1);
  assert.equal(rows[0].sales_total, 3);
  assert.equal(rows[0].cash_total, 0);
  assert.equal(rows[0].credit_total, 3);
  assert.equal(rows[1].transaction_count, 2);
  assert.equal(rows[1].sales_total, 10);
  assert.equal(rows[1].cash_total, 4);
  assert.equal(rows[1].credit_total, 6);
});
