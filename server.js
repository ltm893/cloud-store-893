require('dotenv').config();
const express = require('express');
const app = express();
const PORT = process.env.PORT || 3000;

const ORDS_BASE = process.env.ORDS_BASE_URL;

if (!ORDS_BASE) {
  console.error('❌ ORDS_BASE_URL is not set. Create a .env file — see .env.example');
  process.exit(1);
}

app.use(express.json());

const { getBuildInfo } = require('./lib/build-info');

app.get('/api/build-info', (req, res) => {
  res.json(getBuildInfo());
});

const { registerSystemsRoutes } = require('./lib/systems-routes');
registerSystemsRoutes(app);

// ── ORDS client ───────────────────────────────────────────────────────────

const { createOrdsClient } = require('./lib/ords-client');
const { asyncHandler } = require('./lib/async-handler');
const {
  ordsGet,
  ordsTryGet,
  ordsPost,
  ordsPut,
  ordsDelete,
  ordsTimestamp,
} = createOrdsClient(ORDS_BASE);

const { createLoginApprovalStore } = require('./lib/login-approval');
const loginApprovalStore = createLoginApprovalStore({
  ordsGet,
  ordsPost,
  ordsPut,
  ordsTimestamp,
});

const { createTillStore } = require('./lib/tills');
const tillStore = createTillStore({
  ordsGet,
  ordsPost,
  ordsPut,
  ordsTimestamp,
});

const { createPosSessionStore } = require('./lib/pos-sessions');
const posSessionStore = createPosSessionStore({
  ordsGet,
  ordsPost,
  ordsPut,
  ordsTimestamp,
});

const { createShiftCloseCash } = require('./lib/shift-close-cash');
const shiftCloseCash = createShiftCloseCash({ ordsGet });
const { createTillCloseStore } = require('./lib/shift-close-store');
const shiftCloseStore = createTillCloseStore({
  ordsGet,
  ordsPost,
  ordsPut,
  ordsTimestamp,
  shiftCloseCash,
  tillStore,
});

const {
  registerCashierAuth,
  requireCashierForPosApi,
  getActiveCashierSession,
  sessionAllowsCashPayments,
} = require('./lib/cashier-auth');
const {
  resolveCheckoutSettlement,
  normalizePaymentMethod,
} = require('./lib/checkout-settlement');
const {
  allocateOrderNumber,
  isDuplicateOrderNumberError,
} = require('./lib/order-number');
const { posRatesFromEnv } = require('./lib/pos-pricing');

const POS_RATES = posRatesFromEnv();

/** Post sales row; retry without cash-rounding columns when DB migration is not applied yet. */
async function postSaleRow(payload) {
  try {
    await ordsPost('sales/', payload);
  } catch (err) {
    const msg = String(err?.message || err);
    const missingRoundingColumns = /00904|invalid identifier|register_total|cash_due/i.test(msg);
    if (!missingRoundingColumns || payload.register_total == null) throw err;
    const { register_total, cash_due, ...legacy } = payload;
    await ordsPost('sales/', legacy);
  }
}

const { registerAdminAuth, requireAdminSession, protectAdminPages } = require('./lib/admin-auth');
registerCashierAuth(app, { loginApprovalStore, tillStore, posSessionStore, shiftCloseStore, ordsGet });
registerAdminAuth(app);
app.use('/admin', protectAdminPages);
app.use('/api/admin', requireAdminSession);
app.use(requireCashierForPosApi);

app.use('/admin', (req, res, next) => {
  if (/\.(?:js|css|html)$/.test(req.path)) {
    res.set('Cache-Control', 'no-cache, no-store, must-revalidate');
    res.set('Pragma', 'no-cache');
  }
  next();
});

app.use(express.static('public'));

// ── Pricing (pre-tax): public shelf/sale totals vs linked customer (10% off pre-tax) ─

function roundMoney(n) {
  return Math.round(Number(n) * 100) / 100;
}

function normalizeCheckoutTotal(rawTotal) {
  if (rawTotal == null) return null;
  const checkoutTotal = roundMoney(rawTotal);
  if (!Number.isFinite(checkoutTotal) || checkoutTotal <= 0) {
    return { error: 'checkoutTotal must be greater than zero' };
  }
  return { checkoutTotal };
}

function serializePaymentMethod(paymentMethod, payments) {
  if (!payments || payments.length === 0) {
    return normalizePaymentMethod(paymentMethod);
  }
  if (payments.length === 1) {
    return payments[0].method;
  }
  return 'split';
}

function isOnSale(row) {
  const list = Number(row.price);
  const saleRaw = row.sale_price;
  if (saleRaw === null || saleRaw === undefined || saleRaw === '') return false;
  const sale = Number(saleRaw);
  return Number.isFinite(sale) && sale > 0 && sale < list;
}

function unitPricePublic(row) {
  const list = Number(row.price);
  return roundMoney(isOnSale(row) ? Number(row.sale_price) : list);
}

/** Linked customer: sale lines pay sale_price × 0.9; non-sale lines pay regular price × 0.9 */
function unitPricePay893(row) {
  const list = Number(row.price);
  if (isOnSale(row)) return roundMoney(Number(row.sale_price) * 0.9);
  return roundMoney(list * 0.9);
}

function unitPricePayable(row, linked893) {
  return linked893 ? unitPricePay893(row) : unitPricePublic(row);
}

/** Any valid row in customers gets 10% pre-tax discount when linked to the sale. */
function customerDiscountApplies(customerRow) {
  if (!customerRow || typeof customerRow !== 'object') return false;
  const id = Number(customerRow.id);
  return Number.isFinite(id) && id > 0;
}

function hasCardOnFile(customerRow) {
  const value = customerRow?.card_fake;
  return typeof value === 'string' && value.trim().length > 0;
}

function cardLast4(customerRow) {
  const raw = String(customerRow?.card_fake ?? '');
  const digits = raw.replace(/\D/g, '');
  if (digits.length < 4) return null;
  return digits.slice(-4);
}

/** @deprecated name kept for JSON field linked893 */
function is893Member(customerRow) {
  return customerDiscountApplies(customerRow);
}

function enrichCartRow(row, linked893) {
  const qty = Number(row.quantity);
  const regularPrice = roundMoney(Number(row.price));
  const onSale = isOnSale(row);
  const salePrice = onSale ? roundMoney(Number(row.sale_price)) : null;
  const unitPublic = unitPricePublic(row);
  const unitPay = unitPricePayable(row, linked893);
  const linePublic = roundMoney(unitPublic * qty);
  const linePay = roundMoney(unitPay * qty);
  return {
    id: Number(row.id),
    productId: Number(row.product_id),
    name: row.name,
    regularPrice,
    salePrice,
    onSale,
    quantity: qty,
    unitPricePublic: unitPublic,
    unitPricePayable: unitPay,
    lineSubtotalPublic: linePublic,
    lineSubtotalPayable: linePay,
  };
}

function summarizeCart(cartRows, linked893) {
  const items = cartRows.map((r) => enrichCartRow(r, linked893));
  const subtotalPreMember = roundMoney(items.reduce((s, it) => s + it.lineSubtotalPublic, 0));
  const subtotalPayable = roundMoney(items.reduce((s, it) => s + it.lineSubtotalPayable, 0));
  const memberDiscountPreTax = roundMoney(subtotalPreMember - subtotalPayable);
  return {
    items,
    subtotalPreMember,
    subtotalPayable,
    memberDiscountPreTax: linked893 ? memberDiscountPreTax : 0,
    linked893,
  };
}

const {
  applyBulkConsumptionForSale,
  canFulfillBulkConsumption,
  canFulfillQuantity,
  loadBulkInventoryMap,
  loadConsumptionRulesMap,
  loadInventoryMap,
  mapProductForCashier,
  recordInventoryMovement,
  tracksInventory,
} = require('./lib/inventory');

// ── Products ──────────────────────────────────────────────────────────────

app.get('/api/products', asyncHandler(async (req, res) => {
  const [products, inventoryMap] = await Promise.all([
    ordsGet('products/'),
    loadInventoryMap(ordsGet),
  ]);
  res.json(products.map((p) => mapProductForCashier(p, inventoryMap)));
}));

// ── Customers (for linking at checkout / cart preview) ────────────────────

app.get('/api/customers', asyncHandler(async (req, res) => {
  const rows = await ordsGet('customers/');
  const out = rows.map((c) => ({
    id: Number(c.id),
    name: c.name,
    email: c.email,
    phone: c.phone,
    memberCode: c.member_code ?? null,
    is893: customerDiscountApplies(c),
    hasCardOnFile: hasCardOnFile(c),
    cardLast4: cardLast4(c),
  }));
  res.json(out);
}));

// ── Cart ──────────────────────────────────────────────────────────────────

async function resolveLinked893FromRequest(req) {
  const raw = req.query.customerId ?? req.body?.customerId;
  if (raw === undefined || raw === null || String(raw).trim() === '') {
    return { linked893: false, error: null };
  }
  const row = await ordsTryGet(`customers/${raw}`);
  if (!row || Number(row.id) !== Number(raw)) {
    return { linked893: false, error: 'Invalid customerId' };
  }
  return { linked893: is893Member(row), error: null };
}

async function fetchCartSummary(linked893) {
  const cart = await ordsGet('cart_view/');
  const rows = Array.isArray(cart) ? cart : [];
  return summarizeCart(rows, linked893);
}

async function respondWithCart(req, res) {
  const { linked893, error } = await resolveLinked893FromRequest(req);
  if (error) {
    res.status(400).json({ error });
    return;
  }
  res.json(await fetchCartSummary(linked893));
}

async function getProductById(productId) {
  const filter = encodeURIComponent(JSON.stringify({ id: { $eq: Number(productId) } }));
  const products = await ordsGet(`products/?q=${filter}`);
  return products.length > 0 ? products[0] : null;
}

async function loadProductsById() {
  const products = await ordsGet('products/');
  return new Map(products.map((p) => [Number(p.id), p]));
}

async function validateCartLines(cartLines) {
  const productsById = await loadProductsById();
  const inventoryMap = await loadInventoryMap(ordsGet);
  const rulesByType = await loadConsumptionRulesMap(ordsGet);
  const bulkMap = await loadBulkInventoryMap(ordsGet);

  for (const line of cartLines) {
    const productId = Number(line.productId);
    const quantity = Number(line.quantity);
    const product = productsById.get(productId);
    if (!product) {
      return { error: `Product not found: ${productId}`, status: 404 };
    }
    const stockCheck = canFulfillQuantity(product, inventoryMap, quantity);
    if (!stockCheck.ok) {
      return { error: stockCheck.error, status: 409 };
    }
  }

  const bulkCheck = canFulfillBulkConsumption(cartLines, productsById, rulesByType, bulkMap);
  if (!bulkCheck.ok) {
    return { error: bulkCheck.error, status: 409 };
  }

  return { ok: true, productsById, rulesByType };
}

function cartLinesAfterQuantityChange(cartItems, productId, newQty) {
  const lines = [];
  let found = false;
  for (const row of cartItems) {
    const pid = Number(row.product_id);
    if (pid === Number(productId)) {
      found = true;
      if (newQty > 0) {
        lines.push({ productId: pid, quantity: newQty });
      }
    } else {
      lines.push({ productId: pid, quantity: Number(row.quantity) });
    }
  }
  if (!found && newQty > 0) {
    lines.push({ productId: Number(productId), quantity: newQty });
  }
  return lines;
}

async function upsertCartLine(productId, quantityDelta = 1) {
  const product = await getProductById(productId);
  if (!product) {
    return { error: 'Product not found', status: 404 };
  }

  const filter = encodeURIComponent(JSON.stringify({ product_id: { $eq: productId } }));
  const existing = await ordsGet(`cart_items/?q=${filter}`);
  const currentCartQty = existing.length > 0 ? Number(existing[0].quantity) : 0;
  const newQty = currentCartQty + quantityDelta;
  const cartItems = await ordsGet('cart_items/');
  const cartLines = cartLinesAfterQuantityChange(cartItems, productId, newQty);
  const validation = await validateCartLines(cartLines);
  if (validation.error) {
    return { error: validation.error, status: validation.status || 409 };
  }

  if (existing.length > 0) {
    const item = existing[0];
    await ordsPut(`cart_items/${item.id}`, {
      product_id: item.product_id,
      quantity: newQty,
    });
  } else {
    await ordsPost('cart_items/', { product_id: productId, quantity: newQty });
  }
  return { ok: true };
}

app.get('/api/cart', asyncHandler(async (req, res) => {
  await respondWithCart(req, res);
}));

app.post('/api/cart', asyncHandler(async (req, res) => {
  const productId = Number(req.body?.productId);
  if (!Number.isFinite(productId)) {
    return res.status(400).json({ error: 'productId is required' });
  }

  const result = await upsertCartLine(productId);
  if (result.error) {
    return res.status(result.status || 400).json({ error: result.error });
  }
  await respondWithCart(req, res);
}));

app.post('/api/cart/barcode', asyncHandler(async (req, res) => {
  const { barcode } = req.body;
  if (!barcode) {
    return res.status(400).json({ error: 'barcode is required' });
  }

  const filter = encodeURIComponent(JSON.stringify({ barcode: { $eq: String(barcode) } }));
  const products = await ordsGet(`products/?q=${filter}`);
  if (!products.length) {
    return res.status(404).json({ error: 'Product not found' });
  }

  const result = await upsertCartLine(Number(products[0].id));
  if (result.error) {
    return res.status(result.status || 400).json({ error: result.error });
  }
  await respondWithCart(req, res);
}));

/** Replace server cart with exact line quantities (used when replaying offline checkouts). */
app.post('/api/cart/replace', asyncHandler(async (req, res) => {
  const items = Array.isArray(req.body?.items) ? req.body.items : [];

  const existing = await ordsGet('cart_items/');
  for (const row of existing) {
    await ordsDelete(`cart_items/${row.id}`);
  }

  const requestedByProduct = new Map();

  for (const line of items) {
    const productId = Number(line.productId);
    const quantity = Number(line.quantity);
    if (!Number.isFinite(productId) || quantity < 1) continue;
    requestedByProduct.set(productId, (requestedByProduct.get(productId) || 0) + quantity);
  }

  const cartLines = [...requestedByProduct.entries()].map(([productId, quantity]) => ({
    productId,
    quantity,
  }));
  const validation = await validateCartLines(cartLines);
  if (validation.error) {
    return res.status(validation.status || 409).json({ error: validation.error });
  }

  for (const [productId, quantity] of requestedByProduct.entries()) {
    await ordsPost('cart_items/', { product_id: productId, quantity });
  }

  await respondWithCart(req, res);
}));

app.put('/api/cart/:id', asyncHandler(async (req, res) => {
  const cartItemId = req.params.id;
  const quantity = Number(req.body?.quantity);
  if (!Number.isFinite(quantity)) {
    return res.status(400).json({ error: 'quantity must be a number' });
  }

  if (quantity <= 0) {
    await ordsDelete(`cart_items/${cartItemId}`);
  } else {
    const existing = await ordsTryGet(`cart_items/${cartItemId}`);
    if (!existing || Number(existing.id) !== Number(cartItemId)) {
      return res.status(404).json({ error: 'Cart item not found' });
    }
    const cartItems = await ordsGet('cart_items/');
    const cartLines = cartLinesAfterQuantityChange(cartItems, existing.product_id, quantity);
    const validation = await validateCartLines(cartLines);
    if (validation.error) {
      return res.status(validation.status || 409).json({ error: validation.error });
    }
    await ordsPut(`cart_items/${cartItemId}`, {
      product_id: existing.product_id,
      quantity,
    });
  }

  await respondWithCart(req, res);
}));

app.delete('/api/cart/:id', asyncHandler(async (req, res) => {
  await ordsDelete(`cart_items/${req.params.id}`);
  await respondWithCart(req, res);
}));

app.post('/api/checkout', asyncHandler(async (req, res) => {
  const paymentMethod = normalizePaymentMethod(req.body?.paymentMethod);
  const customerIdRaw = req.body?.customerId;
  const checkoutTotalResult = normalizeCheckoutTotal(req.body?.checkoutTotal);
  if (checkoutTotalResult?.error) {
    return res.status(400).json({ error: checkoutTotalResult.error });
  }
  const clientCheckoutTotal = checkoutTotalResult?.checkoutTotal ?? null;
  const cartRows = await ordsGet('cart_view/');
  const rows = Array.isArray(cartRows) ? cartRows : [];

  if (!rows.length) {
    return res.status(400).json({ error: 'Cart is empty' });
  }

  let customerRow = null;
  let customerId = null;
  if (customerIdRaw !== undefined && customerIdRaw !== null && String(customerIdRaw).trim() !== '') {
    customerId = Number(customerIdRaw);
    if (Number.isNaN(customerId)) {
      return res.status(400).json({ error: 'Invalid customerId' });
    }
    customerRow = await ordsTryGet(`customers/${customerId}`);
    if (!customerRow || Number(customerRow.id) !== customerId) {
      return res.status(400).json({ error: 'Invalid customerId' });
    }
  }

  const linked893 = is893Member(customerRow);
  const summary = summarizeCart(rows, linked893);
  const validation = await validateCartLines(summary.items);
  if (validation.error) {
    return res.status(validation.status || 409).json({ error: validation.error });
  }
  const { productsById, rulesByType } = validation;

  const settlement = resolveCheckoutSettlement({
    subtotalPayable: summary.subtotalPayable,
    paymentMethod,
    rawPayments: req.body?.payments ?? null,
    clientCheckoutTotal,
    salesFeeRate: POS_RATES.salesFeeRate,
    taxRate: POS_RATES.taxRate,
  });
  if (settlement.error) {
    return res.status(400).json({ error: settlement.error });
  }

  const {
    registerTotal,
    cashDue,
    recordedTotal,
    payments: persistedPayments,
  } = settlement;

  const cashierSession = getActiveCashierSession(req);
  const cashAllowed = sessionAllowsCashPayments(cashierSession);
  const cashPayments = persistedPayments.filter((p) => p.method === 'cash');
  const singleCash = paymentMethod === 'cash';
  if (!cashAllowed && (cashPayments.length > 0 || singleCash)) {
    return res.status(403).json({ error: 'Cash payments are not enabled for this shift' });
  }
  const recordedPaymentMethod = serializePaymentMethod(paymentMethod, persistedPayments);

  let orderNumber;
  for (let attempt = 0; attempt < 5; attempt++) {
    orderNumber = await allocateOrderNumber({ ordsGet });
    try {
      await postSaleRow({
        order_number: orderNumber,
        total: recordedTotal,
        register_total: registerTotal,
        cash_due: cashDue,
        payment_method: recordedPaymentMethod,
        customer_id: customerId,
        subtotal_pre_member: summary.subtotalPreMember,
        member_discount_pre_tax: summary.memberDiscountPreTax,
        linked_893: linked893 ? 1 : 0,
        till_id: cashierSession?.tillId ?? cashierSession?.shiftId ?? null,
        created_at: ordsTimestamp(),
      });
      break;
    } catch (err) {
      if (isDuplicateOrderNumberError(err) && attempt < 4) continue;
      throw err;
    }
  }

  for (const item of summary.items) {
    const quantity = Number(item.quantity);
    const unitPrice = item.unitPricePayable;
    await ordsPost('sale_items/', {
      order_number: orderNumber,
      product_id: Number(item.productId),
      quantity,
      unit_price: unitPrice,
      line_total: roundMoney(unitPrice * quantity),
    });
  }

  for (const item of summary.items) {
    const product = productsById.get(Number(item.productId));
    if (product && tracksInventory(product)) {
      await recordInventoryMovement(
        { ordsGet, ordsPost, ordsPut, ordsTimestamp },
        {
          productId: item.productId,
          delta: -Number(item.quantity),
          reason: 'sale',
          orderNumber,
        },
      );
    }
  }

  await applyBulkConsumptionForSale(
    { ordsGet, ordsPost, ordsPut, ordsTimestamp },
    {
      cartLines: summary.items,
      productsById,
      rulesByType,
      orderNumber,
    },
  );

  for (const [index, payment] of persistedPayments.entries()) {
    await ordsPost('sale_payments/', {
      order_number: orderNumber,
      sequence_number: index + 1,
      payment_method: payment.method,
      amount: payment.amount,
      tendered_amount: payment.tenderedAmount,
      change_given: payment.changeGiven,
      created_at: ordsTimestamp(),
    });
  }

  const cartItems = await ordsGet('cart_items/');
  for (const item of cartItems) {
    await ordsDelete(`cart_items/${item.id}`);
  }

  return res.json({
    ok: true,
    orderNumber,
    paymentMethod: recordedPaymentMethod,
    total: recordedTotal,
    registerTotal,
    cashDue,
    subtotalPreMember: summary.subtotalPreMember,
    memberDiscountPreTax: summary.memberDiscountPreTax,
    linked893,
    customerId,
    payments: persistedPayments,
    itemCount: summary.items.reduce((sum, item) => sum + Number(item.quantity), 0),
  });
}));

const { registerAdminRoutes } = require('./lib/admin-routes');
const { registerSupervisorRoutes } = require('./lib/supervisor-routes');

registerSupervisorRoutes(app, { loginApprovalStore, shiftCloseStore });
registerAdminRoutes(app, { ordsGet, ordsPost, ordsPut, ordsDelete, ordsTimestamp });

app.get('/api/sales/recent', asyncHandler(async (req, res) => {
  const sales = await ordsGet('sales/?limit=20&offset=0&order=created_at:desc');
  const mapped = sales.map((s) => ({
    id: Number(s.id),
    orderNumber: s.order_number,
    total: Number(s.total),
    registerTotal: s.register_total != null ? Number(s.register_total) : Number(s.total),
    cashDue: s.cash_due != null ? Number(s.cash_due) : null,
    paymentMethod: s.payment_method,
    linked893: Number(s.linked_893) === 1,
    memberDiscountPreTax: s.member_discount_pre_tax != null ? Number(s.member_discount_pre_tax) : 0,
    subtotalPreMember: s.subtotal_pre_member != null ? Number(s.subtotal_pre_member) : Number(s.total),
  }));
  res.json(mapped);
}));

const { startServer } = require('./lib/start-server');

const { server, scheme } = startServer(app, PORT);
server.on('listening', () => {
  console.log(`✅ Cart app running on ${scheme}://localhost:${PORT}`);
  console.log(`🗄  ORDS base: ${ORDS_BASE}`);
  if (loginApprovalStore?.probeTillColumns) {
    loginApprovalStore
      .probeTillColumns()
      .then((result) => {
        if (!result.ok) {
          console.warn(`⚠️  ${result.message}`);
        }
      })
      .catch((err) => {
        console.warn(`⚠️  login approval till column check failed: ${err.message}`);
      });
  }
});
