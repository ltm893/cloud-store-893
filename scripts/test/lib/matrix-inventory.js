'use strict';

/** Seed.sql retail starting levels by product_type (scripts/db/seed.sql §25). */
const SEED_STOCK_BY_TYPE = {
  'coffee beans': 30,
  'go cups': 20,
  clothes: 10,
  water: 48,
};

const BULK_KITCHEN_BEANS_SEED = 8000;
const BULK_OZ_PER_DRINK = 1.5;

const MADE_COFFEE_KEYS = new Set([
  'espresso',
  'houseDrip',
  'latte',
  'cappuccino',
  'coldBrew',
]);

/** Matrix catalog keys → seed product_type (made coffee uses bulk, not retail shelf). */
const PRODUCT_KEY_TYPES = {
  espresso: 'made coffee',
  houseDrip: 'made coffee',
  latte: 'made coffee',
  cappuccino: 'made coffee',
  coldBrew: 'made coffee',
  water16: 'water',
  waterGallon: 'water',
  sparkling: 'water',
  hoodie: 'clothes',
  tee: 'clothes',
  beans: 'coffee beans',
  tumbler: 'go cups',
  coldCup: 'go cups',
};

function sumQtyByKey(scenarioGroups) {
  const totals = new Map();
  for (const scenarios of scenarioGroups) {
    for (const scenario of scenarios) {
      for (const [key, qty] of scenario.lines) {
        totals.set(key, (totals.get(key) || 0) + qty);
      }
    }
  }
  return totals;
}

function madeCoffeeUnits(consumedByKey) {
  let units = 0;
  for (const key of MADE_COFFEE_KEYS) {
    units += consumedByKey.get(key) || 0;
  }
  return units;
}

function retailKeysInMatrix(consumedByKey) {
  return [...consumedByKey.keys()].filter((key) => {
    const type = PRODUCT_KEY_TYPES[key];
    return type && type !== 'made coffee' && SEED_STOCK_BY_TYPE[type] != null;
  });
}

function expectedPostRetailOnHand(key, consumedByKey) {
  const type = PRODUCT_KEY_TYPES[key];
  const baseline = SEED_STOCK_BY_TYPE[type];
  if (baseline == null) return null;
  return baseline - (consumedByKey.get(key) || 0);
}

function expectedPostBulkBeans(consumedByKey) {
  const ozUsed = madeCoffeeUnits(consumedByKey) * BULK_OZ_PER_DRINK;
  return BULK_KITCHEN_BEANS_SEED - ozUsed;
}

function matrixSalesWithMadeCoffee(scenarioGroups) {
  let count = 0;
  for (const scenarios of scenarioGroups) {
    for (const scenario of scenarios) {
      if (scenario.lines.some(([key]) => MADE_COFFEE_KEYS.has(key))) {
        count += 1;
      }
    }
  }
  return count;
}

function matrixRetailSaleItemCount(consumedByKey) {
  let total = 0;
  for (const [key, qty] of consumedByKey) {
    if (MADE_COFFEE_KEYS.has(key)) continue;
    total += qty;
  }
  return total;
}

function matrixRetailLineCount(scenarioGroups) {
  let count = 0;
  for (const scenarios of scenarioGroups) {
    for (const scenario of scenarios) {
      for (const [key] of scenario.lines) {
        if (!MADE_COFFEE_KEYS.has(key)) count += 1;
      }
    }
  }
  return count;
}

function matrixSaleItemLineCount(scenarioGroups) {
  let count = 0;
  for (const scenarios of scenarioGroups) {
    for (const scenario of scenarios) {
      count += scenario.lines.length;
    }
  }
  return count;
}

function matrixSaleItemUnitCount(scenarioGroups) {
  let total = 0;
  for (const scenarios of scenarioGroups) {
    for (const scenario of scenarios) {
      for (const [, qty] of scenario.lines) {
        total += qty;
      }
    }
  }
  return total;
}

module.exports = {
  SEED_STOCK_BY_TYPE,
  BULK_KITCHEN_BEANS_SEED,
  BULK_OZ_PER_DRINK,
  MADE_COFFEE_KEYS,
  PRODUCT_KEY_TYPES,
  sumQtyByKey,
  madeCoffeeUnits,
  retailKeysInMatrix,
  expectedPostRetailOnHand,
  expectedPostBulkBeans,
  matrixSalesWithMadeCoffee,
  matrixRetailSaleItemCount,
  matrixRetailLineCount,
  matrixSaleItemLineCount,
  matrixSaleItemUnitCount,
};
