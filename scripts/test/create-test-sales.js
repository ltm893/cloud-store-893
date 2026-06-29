#!/usr/bin/env node
/**
 * Create one or more real test sales via POST /api/checkout.
 *
 * Usage:
 *   npm run create:test-sales
 *   npm run create:test-sales -- --count 30 --yes
 *   BASE_URL=http://127.0.0.1:3000 node scripts/test/create-test-sales.js --product-id 5
 *
 * Requires: running server and CASHIER_PIN (completes PIN unlock + credit-only till open when configured).
 * Mutates the shared cart and Autonomous DB (sales, sale_items, sale_payments, inventory).
 */

require('dotenv').config({ quiet: true });

const readline = require('node:readline/promises');
const { stdin: input, stdout: output } = require('node:process');

function usage() {
  console.log(`Usage: create-test-sales.js [options]

Options:
  --base-url URL         API base (default: BASE_URL env or http://127.0.0.1:3000)
  --count N              Number of sales to create (default: 1)
  --product-id ID        Product to sell each time (default: first GET /api/products row)
  --payment-method M     card or cash (default: card)
  --customer-id ID       Optional linked customer on checkout
  --register-id ID       Tablet register for till open (default: tablet-create-test-sales)
  --yes                  Skip destructive confirmation prompt
  --json                 Print results as JSON on stdout
  -h, --help             Show this help

Environment:
  CASHIER_PIN            PIN for POST /api/cashier/unlock (default: 8930)
  ADMIN_PIN              Supervisor PIN when till open needs approval (default: CASHIER_PIN)
  REGISTER_ID            Tablet register id for till open (default: tablet-create-test-sales)
`);
}

function parseArgs(argv) {
  const opts = {
    baseUrl: process.env.BASE_URL || `http://127.0.0.1:${process.env.PORT || 3000}`,
    count: 1,
    productId: null,
    paymentMethod: 'card',
    customerId: null,
    registerId: process.env.REGISTER_ID || 'tablet-create-test-sales',
    yes: false,
    json: false,
    help: false,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '-h' || arg === '--help') {
      opts.help = true;
      continue;
    }
    if (arg === '--yes') {
      opts.yes = true;
      continue;
    }
    if (arg === '--json') {
      opts.json = true;
      continue;
    }
    const next = argv[i + 1];
    if (arg === '--base-url' && next) {
      opts.baseUrl = next;
      i += 1;
      continue;
    }
    if (arg === '--count' && next) {
      opts.count = Number(next);
      i += 1;
      continue;
    }
    if (arg === '--product-id' && next) {
      opts.productId = Number(next);
      i += 1;
      continue;
    }
    if (arg === '--payment-method' && next) {
      opts.paymentMethod = String(next).trim().toLowerCase();
      i += 1;
      continue;
    }
    if (arg === '--customer-id' && next) {
      opts.customerId = Number(next);
      i += 1;
      continue;
    }
    if (arg === '--register-id' && next) {
      opts.registerId = String(next).trim();
      i += 1;
      continue;
    }
    throw new Error(`Unknown argument: ${arg}`);
  }

  if (!Number.isFinite(opts.count) || opts.count < 1 || !Number.isInteger(opts.count)) {
    throw new Error('--count must be a positive integer');
  }
  if (opts.productId != null && (!Number.isFinite(opts.productId) || opts.productId < 1)) {
    throw new Error('--product-id must be a positive number');
  }
  if (opts.customerId != null && (!Number.isFinite(opts.customerId) || opts.customerId < 1)) {
    throw new Error('--customer-id must be a positive number');
  }
  if (!['card', 'cash'].includes(opts.paymentMethod)) {
    throw new Error('--payment-method must be card or cash');
  }
  if (!opts.registerId.startsWith('tablet-')) {
    throw new Error('--register-id must start with "tablet-"');
  }

  opts.baseUrl = opts.baseUrl.replace(/\/$/, '');
  return opts;
}

class CookieJar {
  constructor() {
    this.cookies = new Map();
  }

  ingest(response) {
    const setCookie = typeof response.headers.getSetCookie === 'function'
      ? response.headers.getSetCookie()
      : [];
    for (const line of setCookie) {
      const [pair] = line.split(';');
      const eq = pair.indexOf('=');
      if (eq <= 0) continue;
      const name = pair.slice(0, eq).trim();
      const value = pair.slice(eq + 1).trim();
      this.cookies.set(name, value);
    }
  }

  header() {
    return [...this.cookies.entries()].map(([name, value]) => `${name}=${value}`).join('; ');
  }
}

async function api(jar, baseUrl, method, path, body) {
  const headers = { Accept: 'application/json' };
  const cookie = jar.header();
  if (cookie) headers.Cookie = cookie;
  if (body !== undefined) headers['Content-Type'] = 'application/json';

  const res = await fetch(`${baseUrl}${path}`, {
    method,
    headers,
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  jar.ingest(res);

  const text = await res.text();
  let data = null;
  if (text) {
    try {
      data = JSON.parse(text);
    } catch {
      data = text;
    }
  }

  if (!res.ok) {
    const msg = (data && typeof data === 'object' && data.error) ? data.error : text || res.statusText;
    const err = new Error(`${method} ${path} → ${res.status}: ${msg}`);
    err.status = res.status;
    err.body = data;
    throw err;
  }

  return data;
}

async function confirmDestructive(count, baseUrl) {
  console.log('');
  console.log('  ******************************************************************');
  console.log('  * DESTRUCTIVE — creates real sales in Autonomous DB              *');
  console.log('  *                                                                *');
  console.log(`  * Server: ${baseUrl.padEnd(52).slice(0, 52)} *`);
  console.log(`  * Sales to create: ${String(count).padEnd(43).slice(0, 43)} *`);
  console.log('  * Clears the shared cart first, then checkout per sale.          *');
  console.log('  * Do not run against production.                                 *');
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

function logStep(opts, message) {
  if (!opts.json) console.log(message);
}

async function approvePendingLogin(adminJar, baseUrl, requestToken, adminPin) {
  await api(adminJar, baseUrl, 'POST', '/api/admin/login', { pin: adminPin });
  await api(
    adminJar,
    baseUrl,
    'POST',
    `/api/admin/login-approvals/${encodeURIComponent(requestToken)}/approve`,
    {},
  );
}

async function completeTillOpen(jar, baseUrl, { adminPin }, opts) {
  logStep(opts, 'OK   opening till (credit_only / no cash today)');
  const tillResult = await api(jar, baseUrl, 'POST', '/api/cashier/approval/till', {
    cashMode: 'credit_only',
  });

  if (tillResult?.pending && tillResult?.requestToken) {
    logStep(opts, 'OK   supervisor approval required — approving with ADMIN_PIN');
    const adminJar = new CookieJar();
    await approvePendingLogin(adminJar, baseUrl, tillResult.requestToken, adminPin);
    const status = await api(jar, baseUrl, 'GET', '/api/cashier/approval/status');
    if (!status?.ok) {
      throw new Error('Supervisor approval completed but cashier session was not issued');
    }
    return status;
  }

  return tillResult;
}

async function ensureCashierSession(jar, baseUrl, { pin, adminPin, registerId }, opts) {
  let session = await api(jar, baseUrl, 'GET', '/api/cashier/session');
  if (session?.ok) {
    logStep(opts, 'OK   cashier session already active');
    return session;
  }

  if (session?.awaitingTill) {
    await completeTillOpen(jar, baseUrl, { adminPin }, opts);
    session = await api(jar, baseUrl, 'GET', '/api/cashier/session');
    if (session?.ok) {
      logStep(opts, 'OK   cashier session ready (till open)');
      return session;
    }
    throw new Error('Till open submitted but cashier session is still not active');
  }

  if (session?.supervisorApprovalRequired && !session?.pinAllowed) {
    throw new Error(
      'Cashier sign-in required; supervisor approval / Oracle sign-in is enabled (PIN unlock disabled)',
    );
  }

  logStep(opts, 'OK   PIN unlock');
  await api(jar, baseUrl, 'POST', '/api/cashier/unlock', {
    pin,
    clientKind: 'tablet',
    registerId,
  });

  session = await api(jar, baseUrl, 'GET', '/api/cashier/session');
  if (session?.ok) {
    logStep(opts, 'OK   cashier session ready');
    return session;
  }

  if (session?.awaitingTill || session?.cashTillEnabled) {
    await completeTillOpen(jar, baseUrl, { adminPin }, opts);
    session = await api(jar, baseUrl, 'GET', '/api/cashier/session');
  }

  if (!session?.ok) {
    const detail = session?.pending
      ? 'supervisor approval is still pending'
      : 'sign-in did not complete';
    throw new Error(`Cashier session not active after unlock and till open (${detail})`);
  }

  logStep(opts, 'OK   cashier session ready');
  return session;
}

async function resolveProductId(jar, baseUrl, productId) {
  if (productId != null) return productId;
  const products = await api(jar, baseUrl, 'GET', '/api/products');
  if (!Array.isArray(products) || products.length === 0) {
    throw new Error('No products returned from GET /api/products');
  }
  return Number(products[0].id);
}

async function clearCart(jar, baseUrl) {
  const cart = await api(jar, baseUrl, 'GET', '/api/cart');
  const items = Array.isArray(cart?.items) ? cart.items : [];
  for (const item of items) {
    await api(jar, baseUrl, 'DELETE', `/api/cart/${item.id}`);
  }
}

async function createOneSale(jar, baseUrl, { productId, paymentMethod, customerId }) {
  await api(jar, baseUrl, 'POST', '/api/cart', { productId });
  const checkoutBody = { paymentMethod };
  if (customerId != null) checkoutBody.customerId = customerId;
  return api(jar, baseUrl, 'POST', '/api/checkout', checkoutBody);
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (opts.help) {
    usage();
    return;
  }

  const pin = process.env.CASHIER_PIN || '8930';
  const adminPin = process.env.ADMIN_PIN || pin;
  const jar = new CookieJar();

  if (!opts.yes) {
    await confirmDestructive(opts.count, opts.baseUrl);
  }

  const session = await ensureCashierSession(
    jar,
    opts.baseUrl,
    { pin, adminPin, registerId: opts.registerId },
    opts,
  );
  if (opts.paymentMethod === 'cash' && session.cashEnabled === false) {
    throw new Error(
      'Cash payments are disabled for this shift (credit_only till). Use --payment-method card.',
    );
  }
  const productId = await resolveProductId(jar, opts.baseUrl, opts.productId);
  await clearCart(jar, opts.baseUrl);

  const results = [];
  for (let i = 0; i < opts.count; i += 1) {
    const sale = await createOneSale(jar, opts.baseUrl, {
      productId,
      paymentMethod: opts.paymentMethod,
      customerId: opts.customerId,
    });
    results.push({
      index: i + 1,
      orderNumber: sale.orderNumber,
      total: sale.total,
      paymentMethod: sale.paymentMethod,
      itemCount: sale.itemCount,
    });
    if (!opts.json) {
      console.log(
        `OK   sale ${i + 1}/${opts.count}: order ${sale.orderNumber} total ${sale.total} (${sale.paymentMethod})`,
      );
    }
  }

  if (opts.json) {
    process.stdout.write(`${JSON.stringify({ productId, sales: results }, null, 2)}\n`);
  } else {
    console.log('');
    console.log(`== done: ${results.length} sale(s), product_id=${productId} ==`);
  }
}

main().catch((err) => {
  console.error(`FAIL ${err.message}`);
  process.exit(1);
});
