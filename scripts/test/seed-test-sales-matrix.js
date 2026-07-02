#!/usr/bin/env node
/**
 * Seed a full matrix of test sales across till modes and checkout patterns.
 *
 * Runs 20 sales on a credit-only till (card only), then 20 on a cash+credit till
 * (card, cash, and split; walk-in and linked-customer variants).
 *
 * Usage:
 *   npm run seed:test-sales-matrix
 *   npm run seed:test-sales-matrix -- --yes
 *
 * Requires: npm run dev:up (or running server), CASHIER_PIN, ADMIN_PIN for inventory preflight.
 * Resets matrix SKU stock to seed.sql baselines before sales (skip with --no-inventory-top-up).
 */

require('dotenv').config({ quiet: true });

const readline = require('node:readline/promises');
const { stdin: input, stdout: output } = require('node:process');
const {
  roundMoney,
  computeRegisterTotalFromLines,
  computeCollectedTotal,
  remainingCashAmountDue,
  posRatesFromEnv,
} = require('../../lib/pos-pricing');
const { resolveCheckoutSettlement } = require('../../lib/checkout-settlement');
const {
  CookieJar,
  api,
  signInCashier,
  signOffCashier,
  clearCart,
  addCartLine,
  fetchCartPreview,
  checkout,
} = require('./lib/pos-api-client');
const {
  SEED_STOCK_BY_TYPE,
  BULK_KITCHEN_BEANS_SEED,
  PRODUCT_KEY_TYPES,
  sumQtyByKey,
  retailKeysInMatrix,
} = require('./lib/matrix-inventory');

const PRODUCT_BARCODES = {
  espresso: '872000000005',
  houseDrip: '872000000001',
  latte: '872000000002',
  cappuccino: '872000000003',
  coldBrew: '872000000004',
  water16: '872000000401',
  waterGallon: '872000000404',
  sparkling: '872000000403',
  hoodie: '872000000303',
  beans: '872000000103',
  tee: '872000000301',
  tumbler: '872000000201',
  coldCup: '872000000203',
};

/** @typedef {'card'|'cash'|'split'} PaymentKind */
/** @typedef {{ id: string, payment: PaymentKind, linked: boolean, lines: Array<[keyof typeof PRODUCT_BARCODES, number]>, cashChange?: boolean }} SaleScenario */

const CREDIT_ONLY_SCENARIOS = /** @type {SaleScenario[]} */ ([
  { id: 'C01', payment: 'card', linked: false, lines: [['espresso', 1]] },
  { id: 'C02', payment: 'card', linked: false, lines: [['water16', 1]] },
  { id: 'C03', payment: 'card', linked: false, lines: [['coldBrew', 1]] },
  { id: 'C04', payment: 'card', linked: false, lines: [['espresso', 1], ['water16', 1]] },
  { id: 'C05', payment: 'card', linked: false, lines: [['latte', 2]] },
  { id: 'C06', payment: 'card', linked: false, lines: [['hoodie', 1]] },
  { id: 'C07', payment: 'card', linked: false, lines: [['beans', 1]] },
  { id: 'C08', payment: 'card', linked: false, lines: [['tumbler', 1], ['beans', 1]] },
  { id: 'C09', payment: 'card', linked: false, lines: [['waterGallon', 1]] },
  { id: 'C10', payment: 'card', linked: false, lines: [['cappuccino', 1]] },
  { id: 'C11', payment: 'card', linked: true, lines: [['espresso', 1]] },
  { id: 'C12', payment: 'card', linked: true, lines: [['water16', 2]] },
  { id: 'C13', payment: 'card', linked: true, lines: [['beans', 1]] },
  { id: 'C14', payment: 'card', linked: true, lines: [['espresso', 1], ['water16', 1]] },
  { id: 'C15', payment: 'card', linked: true, lines: [['latte', 1], ['sparkling', 1]] },
  { id: 'C16', payment: 'card', linked: true, lines: [['hoodie', 1]] },
  { id: 'C17', payment: 'card', linked: true, lines: [['tee', 1]] },
  { id: 'C18', payment: 'card', linked: true, lines: [['coldBrew', 1], ['coldCup', 1]] },
  { id: 'C19', payment: 'card', linked: true, lines: [['houseDrip', 1], ['waterGallon', 1]] },
  { id: 'C20', payment: 'card', linked: true, lines: [['espresso', 1], ['sparkling', 1], ['water16', 1]] },
]);

const CASH_AND_CREDIT_SCENARIOS = /** @type {SaleScenario[]} */ ([
  { id: 'A01', payment: 'card', linked: false, lines: [['espresso', 1]] },
  { id: 'A02', payment: 'card', linked: false, lines: [['water16', 1]] },
  { id: 'A03', payment: 'card', linked: false, lines: [['coldBrew', 1]] },
  { id: 'A04', payment: 'card', linked: true, lines: [['latte', 1]] },
  { id: 'A05', payment: 'card', linked: true, lines: [['beans', 1]] },
  { id: 'A06', payment: 'card', linked: true, lines: [['espresso', 1], ['water16', 1]] },
  { id: 'A07', payment: 'cash', linked: false, lines: [['espresso', 1]] },
  { id: 'A08', payment: 'cash', linked: false, lines: [['water16', 2]] },
  { id: 'A09', payment: 'cash', linked: false, lines: [['hoodie', 1]] },
  { id: 'A10', payment: 'cash', linked: false, lines: [['coldBrew', 1], ['sparkling', 1]] },
  { id: 'A11', payment: 'cash', linked: true, lines: [['espresso', 1]] },
  { id: 'A12', payment: 'cash', linked: true, lines: [['tee', 1]] },
  { id: 'A13', payment: 'cash', linked: true, lines: [['latte', 2]] },
  { id: 'A14', payment: 'cash', linked: true, lines: [['waterGallon', 1]], cashChange: true },
  { id: 'A15', payment: 'split', linked: false, lines: [['latte', 1]] },
  { id: 'A16', payment: 'split', linked: false, lines: [['hoodie', 1]] },
  { id: 'A17', payment: 'split', linked: false, lines: [['espresso', 1], ['water16', 1]] },
  { id: 'A18', payment: 'split', linked: true, lines: [['beans', 1]] },
  { id: 'A19', payment: 'split', linked: true, lines: [['coldBrew', 1], ['tumbler', 1]] },
  { id: 'A20', payment: 'split', linked: true, lines: [['houseDrip', 1], ['sparkling', 1], ['water16', 1]] },
]);

function usage() {
  console.log(`Usage: seed-test-sales-matrix.js [options]

Options:
  --base-url URL           API base (default: http://127.0.0.1:\${PORT||3000})
  --yes                    Skip destructive confirmation
  --no-inventory-top-up    Skip retail/bulk preflight (may 409 if stock depleted)
  --json                   JSON summary on stdout
  -h, --help               Show help

Runs 40 sales total: 20 credit-only till (card), 20 cash+credit till (card/cash/split).
Preflight (default): reset matrix SKU stock to seed.sql levels via admin inventory APIs.
`);
}

function parseArgs(argv) {
  const opts = {
    baseUrl: process.env.BASE_URL || `http://127.0.0.1:${process.env.PORT || 3000}`,
    yes: false,
    json: false,
    help: false,
    noInventoryTopUp: false,
  };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '-h' || arg === '--help') { opts.help = true; continue; }
    if (arg === '--yes') { opts.yes = true; continue; }
    if (arg === '--json') { opts.json = true; continue; }
    if (arg === '--no-inventory-top-up') { opts.noInventoryTopUp = true; continue; }
    if (arg === '--base-url' && argv[i + 1]) {
      opts.baseUrl = argv[++i];
      continue;
    }
    throw new Error(`Unknown argument: ${arg}`);
  }
  opts.baseUrl = opts.baseUrl.replace(/\/$/, '');
  return opts;
}

function logStep(opts, message) {
  if (!opts.json) console.log(message);
}

async function confirmDestructive(baseUrl) {
  console.log('');
  console.log('  ******************************************************************');
  console.log('  * DESTRUCTIVE — creates 40 real sales (2 till sessions × 20)     *');
  console.log(`  * Server: ${baseUrl}`);
  console.log('  * Clears shared cart between each sale.                          *');
  console.log('  ******************************************************************');
  console.log('');
  const rl = readline.createInterface({ input, output });
  const reply = await rl.question('  Type yes to continue: ');
  rl.close();
  if (String(reply).trim().toLowerCase() !== 'yes') {
    console.error('Aborted.');
    process.exit(1);
  }
  console.log('');
}

async function loadCatalog(jar, baseUrl) {
  const products = await api(jar, baseUrl, 'GET', '/api/products');
  const byBarcode = new Map();
  const byKey = new Map();
  for (const [key, barcode] of Object.entries(PRODUCT_BARCODES)) {
    const row = products.find((p) => String(p.barcode) === barcode);
    if (!row) {
      throw new Error(`Seed product missing for key ${key} (barcode ${barcode})`);
    }
    byBarcode.set(barcode, row);
    byKey.set(key, row);
  }
  return { byKey, products };
}

async function loadMemberCustomer(jar, baseUrl) {
  const customers = await api(jar, baseUrl, 'GET', '/api/customers');
  const member = customers.find((c) => c.is893 || c.memberCode === 'JR-893');
  if (!member) {
    throw new Error('No linked member customer in DB (expected Alex Rivera / JR-893)');
  }
  return member;
}

async function ensureMatrixInventory(baseUrl, catalog, adminPin, opts) {
  if (opts.noInventoryTopUp) {
    logStep(opts, 'SKIP inventory preflight (--no-inventory-top-up)');
    return;
  }

  const consumed = sumQtyByKey([CREDIT_ONLY_SCENARIOS, CASH_AND_CREDIT_SCENARIOS]);
  const adminJar = new CookieJar();
  await api(adminJar, baseUrl, 'POST', '/api/admin/login', { pin: adminPin });

  logStep(opts, '');
  logStep(opts, '== inventory preflight (seed.sql baselines) ==');

  for (const key of retailKeysInMatrix(consumed)) {
    const product = catalog.byKey.get(key);
    const type = PRODUCT_KEY_TYPES[key];
    const target = SEED_STOCK_BY_TYPE[type];
    if (!product?.id || target == null) continue;

    try {
      await api(adminJar, baseUrl, 'POST', '/api/admin/inventory/set-count', {
        productId: product.id,
        quantity: target,
        note: 'seed-test-sales-matrix preflight',
      });
      logStep(opts, `OK   stock ${key} → ${target}`);
    } catch (err) {
      const hint = product.quantityOnHand == null
        ? ' (product may lack track_inventory=1 or product_inventory — run scripts/db/seed.sql or backfill)'
        : '';
      throw new Error(`inventory preflight failed for ${key}: ${err.message}${hint}`);
    }
  }

  await api(adminJar, baseUrl, 'POST', '/api/admin/inventory/bulk/set-count', {
    skuKey: 'kitchen_beans',
    quantity: BULK_KITCHEN_BEANS_SEED,
    note: 'seed-test-sales-matrix preflight',
  });
  logStep(opts, `OK   bulk kitchen_beans → ${BULK_KITCHEN_BEANS_SEED} oz`);
}

function cartLinesFromPreview(cartPreview) {
  return cartPreview.items.map((it) => ({
    lineSubtotalPayable: it.lineSubtotalPayable,
    taxExempt: !!it.taxExempt,
  }));
}

function buildCheckoutBody(cartPreview, scenario, rates, session) {
  const customerId = scenario.linked ? cartPreview._customerId : null;
  const lines = cartLinesFromPreview(cartPreview);
  const registerTotal = computeRegisterTotalFromLines(
    lines,
    rates.salesFeeRate,
    rates.taxRate,
  );
  const collected = computeCollectedTotal(registerTotal);

  const withCustomer = (body) => {
    if (customerId != null) body.customerId = customerId;
    return body;
  };

  if (scenario.payment === 'card') {
    return withCustomer({ paymentMethod: 'card' });
  }

  if (scenario.payment === 'cash') {
    if (!session.cashEnabled) {
      throw new Error(`Scenario ${scenario.id} requires cash-enabled till`);
    }
    if (scenario.cashChange) {
      const tenderedAmount = roundMoney(collected + 5);
      const changeGiven = roundMoney(tenderedAmount - collected);
      const settlement = resolveCheckoutSettlement({
        cartItems: lines,
        paymentMethod: 'cash',
        rawPayments: [{
          method: 'cash',
          amount: collected,
          tenderedAmount,
          changeGiven,
        }],
        clientCheckoutTotal: null,
        ...rates,
      });
      if (settlement.error) throw new Error(settlement.error);
      return withCustomer({ payments: settlement.payments });
    }
    return withCustomer({ paymentMethod: 'cash' });
  }

  if (!session.cashEnabled) {
    throw new Error(`Scenario ${scenario.id} split tender requires cash-enabled till`);
  }

  const cardAmount = roundMoney(Math.min(5, Math.max(1, collected * 0.45)));
  const cashDue = remainingCashAmountDue(registerTotal, cardAmount);
  const settlement = resolveCheckoutSettlement({
    cartItems: lines,
    paymentMethod: 'split',
    rawPayments: [
      { method: 'card', amount: cardAmount, tenderedAmount: cardAmount },
      { method: 'cash', amount: cashDue, tenderedAmount: cashDue },
    ],
    clientCheckoutTotal: null,
    ...rates,
  });
  if (settlement.error) throw new Error(settlement.error);

  return withCustomer({ payments: settlement.payments });
}

async function runScenario(jar, baseUrl, scenario, ctx) {
  const { catalog, memberCustomer, rates, session, opts } = ctx;
  await clearCart(jar, baseUrl);

  for (const [key, qty] of scenario.lines) {
    const product = catalog.byKey.get(key);
    if (!product) {
      throw new Error(`Unknown product key in ${scenario.id}: ${key}`);
    }
    await addCartLine(jar, baseUrl, product.id, qty);
  }

  const customerId = scenario.linked ? memberCustomer.id : null;
  const cartPreview = await fetchCartPreview(jar, baseUrl, customerId);
  cartPreview._customerId = customerId;

  const checkoutBody = buildCheckoutBody(cartPreview, scenario, rates, session);
  const sale = await checkout(jar, baseUrl, checkoutBody);

  const result = {
    scenarioId: scenario.id,
    tillMode: ctx.tillMode,
    payment: scenario.payment,
    linked: scenario.linked,
    orderNumber: sale.orderNumber,
    total: sale.total,
    paymentMethod: sale.paymentMethod,
    customerId: sale.customerId ?? null,
    lines: scenario.lines.map(([key, qty]) => ({ key, qty })),
  };

  logStep(
    opts,
    `OK   ${ctx.tillMode} ${scenario.id} ${scenario.payment}${scenario.linked ? ' linked' : ''}`
      + ` → ${sale.orderNumber} $${sale.total} (${sale.paymentMethod})`,
  );
  return result;
}

async function runBatch({
  jar,
  baseUrl,
  opts,
  tillMode,
  cashMode,
  registerId,
  scenarios,
  catalog,
  rates,
  pin,
  adminPin,
  openingFloat,
}) {
  logStep(opts, '');
  logStep(opts, `== ${tillMode} till (${cashMode}) register ${registerId} ==`);

  const session = await signInCashier(
    jar,
    baseUrl,
    { pin, adminPin, registerId, cashMode, openingFloat },
    (msg) => logStep(opts, `OK   ${msg}`),
  );

  if (cashMode === 'credit_only' && session.cashEnabled) {
    throw new Error('Expected credit-only till but session has cash enabled');
  }
  if (cashMode === 'cash_and_credit' && !session.cashEnabled) {
    throw new Error('Expected cash+credit till but cash is disabled on session');
  }

  const memberCustomer = await loadMemberCustomer(jar, baseUrl);

  const results = [];
  for (const scenario of scenarios) {
    if (cashMode === 'credit_only' && scenario.payment !== 'card') {
      throw new Error(`Invalid scenario ${scenario.id} for credit-only till`);
    }
    results.push(await runScenario(jar, baseUrl, scenario, {
      catalog,
      memberCustomer,
      rates,
      session,
      opts,
      tillMode,
    }));
  }

  await signOffCashier(
    jar,
    baseUrl,
    registerId,
    (msg) => logStep(opts, `OK   ${msg}`),
  );
  return results;
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (opts.help) {
    usage();
    return;
  }

  const pin = process.env.CASHIER_PIN || '8930';
  const adminPin = process.env.ADMIN_PIN || pin;
  const openingFloat = Number(process.env.OPENING_CASH_FLOAT || 200);
  const rates = posRatesFromEnv();

  if (!opts.yes) {
    await confirmDestructive(opts.baseUrl);
  }

  const jar = new CookieJar();
  const catalog = await loadCatalog(jar, opts.baseUrl);
  await ensureMatrixInventory(opts.baseUrl, catalog, adminPin, opts);

  const creditOnly = await runBatch({
    jar,
    baseUrl: opts.baseUrl,
    opts,
    tillMode: 'credit-only',
    cashMode: 'credit_only',
    registerId: 'tablet-seed-credit-only',
    scenarios: CREDIT_ONLY_SCENARIOS,
    catalog,
    rates,
    pin,
    adminPin,
    openingFloat,
  });

  const cashAndCredit = await runBatch({
    jar,
    baseUrl: opts.baseUrl,
    opts,
    tillMode: 'cash+credit',
    cashMode: 'cash_and_credit',
    registerId: 'tablet-seed-cash-credit',
    scenarios: CASH_AND_CREDIT_SCENARIOS,
    catalog,
    rates,
    pin,
    adminPin,
    openingFloat,
  });

  const summary = {
    totalSales: creditOnly.length + cashAndCredit.length,
    creditOnlyTill: creditOnly,
    cashAndCreditTill: cashAndCredit,
  };

  if (opts.json) {
    process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);
  } else {
    console.log('');
    console.log(`== done: ${summary.totalSales} sales (20 credit-only + 20 cash+credit) ==`);
  }
}

main().catch((err) => {
  console.error(`FAIL ${err.message}`);
  process.exit(1);
});
