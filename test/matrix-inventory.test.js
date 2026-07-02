'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');

const {
  sumQtyByKey,
  expectedPostRetailOnHand,
  expectedPostBulkBeans,
  matrixSalesWithMadeCoffee,
  matrixRetailSaleItemCount,
  matrixRetailLineCount,
  matrixSaleItemLineCount,
  matrixSaleItemUnitCount,
} = require('../scripts/test/lib/matrix-inventory');

/** Keep in sync with scripts/test/seed-test-sales-matrix.js scenario tables. */
const CREDIT_ONLY = [
  { lines: [['espresso', 1]] },
  { lines: [['water16', 1]] },
  { lines: [['coldBrew', 1]] },
  { lines: [['espresso', 1], ['water16', 1]] },
  { lines: [['latte', 2]] },
  { lines: [['hoodie', 1]] },
  { lines: [['beans', 1]] },
  { lines: [['tumbler', 1], ['beans', 1]] },
  { lines: [['waterGallon', 1]] },
  { lines: [['cappuccino', 1]] },
  { lines: [['espresso', 1]] },
  { lines: [['water16', 2]] },
  { lines: [['beans', 1]] },
  { lines: [['espresso', 1], ['water16', 1]] },
  { lines: [['latte', 1], ['sparkling', 1]] },
  { lines: [['hoodie', 1]] },
  { lines: [['tee', 1]] },
  { lines: [['coldBrew', 1], ['coldCup', 1]] },
  { lines: [['houseDrip', 1], ['waterGallon', 1]] },
  { lines: [['espresso', 1], ['sparkling', 1], ['water16', 1]] },
];

const CASH_AND_CREDIT = [
  { lines: [['espresso', 1]] },
  { lines: [['water16', 1]] },
  { lines: [['coldBrew', 1]] },
  { lines: [['latte', 1]] },
  { lines: [['beans', 1]] },
  { lines: [['espresso', 1], ['water16', 1]] },
  { lines: [['espresso', 1]] },
  { lines: [['water16', 2]] },
  { lines: [['hoodie', 1]] },
  { lines: [['coldBrew', 1], ['sparkling', 1]] },
  { lines: [['espresso', 1]] },
  { lines: [['tee', 1]] },
  { lines: [['latte', 2]] },
  { lines: [['waterGallon', 1]] },
  { lines: [['latte', 1]] },
  { lines: [['hoodie', 1]] },
  { lines: [['espresso', 1], ['water16', 1]] },
  { lines: [['beans', 1]] },
  { lines: [['coldBrew', 1], ['tumbler', 1]] },
  { lines: [['houseDrip', 1], ['sparkling', 1], ['water16', 1]] },
];

const BARCODE_BY_KEY = {
  water16: '872000000401',
  waterGallon: '872000000404',
  sparkling: '872000000403',
  hoodie: '872000000303',
  tee: '872000000301',
  beans: '872000000103',
  tumbler: '872000000201',
  coldCup: '872000000203',
};

/** Expected post-matrix on_hand — must match verify-test-sales-matrix.sql §5. */
const SQL_POST_RETAIL = {
  '872000000303': 6,
  '872000000301': 8,
  '872000000401': 36,
  '872000000404': 45,
  '872000000403': 44,
  '872000000103': 25,
  '872000000201': 18,
  '872000000203': 19,
};

const consumed = sumQtyByKey([CREDIT_ONLY, CASH_AND_CREDIT]);

test('matrix retail post-stock matches verify-test-sales-matrix.sql', () => {
  for (const [key, barcode] of Object.entries(BARCODE_BY_KEY)) {
    const expected = expectedPostRetailOnHand(key, consumed);
    assert.equal(
      expected,
      SQL_POST_RETAIL[barcode],
      `${key} (${barcode}) post on_hand`,
    );
  }
});

test('matrix bulk beans post-stock matches verify-test-sales-matrix.sql', () => {
  assert.equal(expectedPostBulkBeans(consumed), 7962.5);
});

test('matrix movement counts match verify-test-sales-matrix.sql', () => {
  const groups = [CREDIT_ONLY, CASH_AND_CREDIT];
  assert.equal(matrixRetailSaleItemCount(consumed), 33);
  assert.equal(matrixRetailLineCount(groups), 31);
  assert.equal(matrixSaleItemLineCount(groups), 54);
  assert.equal(matrixSaleItemUnitCount(groups), 58);
  assert.equal(matrixSalesWithMadeCoffee(groups), 23);
});
