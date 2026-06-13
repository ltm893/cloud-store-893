'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createShiftCloseCash } = require('../lib/shift-close-cash');

test('computeExpectedClose sums opening, cash sales, and change', async () => {
  const shiftCloseCash = createShiftCloseCash({
    ordsGet: async (path) => {
      if (path.startsWith('sales/')) {
        return [{ order_number: 'POS-1' }, { order_number: 'POS-2' }];
      }
      if (path.includes('POS-1')) {
        return [
          { payment_method: 'cash', amount: 20, change_given: 1 },
          { payment_method: 'card', amount: 5, change_given: null },
        ];
      }
      if (path.includes('POS-2')) {
        return [{ payment_method: 'cash', amount: 10, change_given: 0 }];
      }
      return [];
    },
  });

  const result = await shiftCloseCash.computeExpectedClose({
    id: 9,
    openingCountedFloat: 200,
    cashMode: 'cash_and_credit',
  });

  assert.equal(result.openingCountedFloat, 200);
  assert.equal(result.cashSalesTotal, 30);
  assert.equal(result.changeGivenTotal, 1);
  assert.equal(result.expectedClose, 229);
});
