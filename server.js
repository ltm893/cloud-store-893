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

// ── ORDS helpers ──────────────────────────────────────────────────────────

async function ordsGet(path) {
  const res = await fetch(`${ORDS_BASE}/${path}`);
  if (!res.ok) throw new Error(`ORDS GET ${path} → ${res.status}`);
  const data = await res.json();
  return Array.isArray(data.items) ? data.items : data;
}

async function ordsTryGet(path) {
  const res = await fetch(`${ORDS_BASE}/${path}`);
  if (!res.ok) return null;
  const data = await res.json();
  if (Array.isArray(data.items)) return data.items;
  return data;
}

/** ORDS accepts ISO-8601 with Z; rejects milliseconds (e.g. .000Z). */
function ordsTimestamp(date = new Date()) {
  return date.toISOString().replace(/\.\d{3}Z$/, 'Z');
}

async function ordsPost(path, body) {
  const res = await fetch(`${ORDS_BASE}/${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    let detail = '';
    try {
      const errBody = await res.json();
      detail = errBody.message || errBody.error || JSON.stringify(errBody);
    } catch {
      detail = await res.text().catch(() => '');
    }
    throw new Error(`ORDS POST ${path} → ${res.status}${detail ? `: ${detail}` : ''}`);
  }
  return res.json();
}

async function ordsPut(path, body) {
  const res = await fetch(`${ORDS_BASE}/${path}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`ORDS PUT ${path} → ${res.status}`);
  return res.json();
}

async function ordsDelete(path) {
  const res = await fetch(`${ORDS_BASE}/${path}`, { method: 'DELETE' });
  if (!res.ok) throw new Error(`ORDS DELETE ${path} → ${res.status}`);
}

const { createLoginApprovalStore } = require('./lib/login-approval');
const loginApprovalStore = createLoginApprovalStore({
  ordsGet,
  ordsPost,
  ordsPut,
  ordsTimestamp,
});

const { registerCashierAuth, requireCashierForPosApi } = require('./lib/cashier-auth');
const { registerAdminAuth, requireAdminSession, protectAdminPages } = require('./lib/admin-auth');
registerCashierAuth(app, { loginApprovalStore });
registerAdminAuth(app);
app.use('/admin', protectAdminPages);
app.use('/api/admin', requireAdminSession);
app.use(requireCashierForPosApi);

app.use(express.static('public'));

// ── Pricing (pre-tax): public shelf/sale totals vs linked customer (10% off pre-tax) ─

function roundMoney(n) {
  return Math.round(Number(n) * 100) / 100;
}

function normalizePaymentMethod(method) {
  const normalized = String(method || 'card').trim().toLowerCase();
  return normalized || 'card';
}

function normalizeCheckoutTotal(rawTotal) {
  if (rawTotal == null) return null;
  const checkoutTotal = roundMoney(rawTotal);
  if (!Number.isFinite(checkoutTotal) || checkoutTotal <= 0) {
    return { error: 'checkoutTotal must be greater than zero' };
  }
  return { checkoutTotal };
}

function normalizeCheckoutPayments(rawPayments, totalAmount) {
  if (rawPayments == null) return null;
  if (!Array.isArray(rawPayments) || rawPayments.length === 0) {
    return { error: 'payments must be a non-empty array' };
  }

  const payments = [];
  for (const rawPayment of rawPayments) {
    const method = normalizePaymentMethod(rawPayment?.method);
    const amount = roundMoney(rawPayment?.amount);
    const tenderedAmount =
      rawPayment?.tenderedAmount == null ? amount : roundMoney(rawPayment.tenderedAmount);
    const changeGiven =
      rawPayment?.changeGiven == null ? 0 : roundMoney(rawPayment.changeGiven);
    if (!['card', 'cash'].includes(method)) {
      return { error: `Unsupported payment method: ${method}` };
    }
    if (!Number.isFinite(amount) || amount <= 0) {
      return { error: 'Each split payment amount must be greater than zero' };
    }
    if (!Number.isFinite(tenderedAmount) || tenderedAmount <= 0 || tenderedAmount + 0.009 < amount) {
      return { error: 'tenderedAmount must be at least the applied payment amount' };
    }
    if (!Number.isFinite(changeGiven) || changeGiven < 0) {
      return { error: 'changeGiven cannot be negative' };
    }
    const expectedChange = roundMoney(tenderedAmount - amount);
    if (Math.abs(expectedChange - changeGiven) > 0.009) {
      return { error: 'changeGiven must equal tenderedAmount minus amount' };
    }
    if (method === 'card' && changeGiven > 0.009) {
      return { error: 'Card payments cannot include change' };
    }
    payments.push({
      method,
      amount,
      tenderedAmount,
      changeGiven: changeGiven > 0.009 ? changeGiven : null,
    });
  }

  const totalPaid = roundMoney(payments.reduce((sum, payment) => sum + payment.amount, 0));
  const normalizedTotal = totalAmount == null ? totalPaid : roundMoney(totalAmount);
  if (Math.abs(totalPaid - normalizedTotal) > 0.009) {
    return { error: `Split payments must equal total ${normalizedTotal.toFixed(2)}` };
  }
  return { payments };
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

function mapProductRow(p) {
  const regularPrice = roundMoney(Number(p.price));
  const onSale = isOnSale(p);
  const salePrice =
    p.sale_price == null || p.sale_price === '' ? null : roundMoney(Number(p.sale_price));
  return {
    id: Number(p.id),
    barcode: p.barcode,
    name: p.name,
    regularPrice,
    salePrice: onSale ? salePrice : null,
    onSale,
  };
}

// ── Products ──────────────────────────────────────────────────────────────

app.get('/api/products', async (req, res) => {
  try {
    const products = await ordsGet('products/');
    res.json(products.map(mapProductRow));
  } catch (err) {
    console.error(err.message);
    res.status(500).json({ error: err.message });
  }
});

// ── Customers (for linking at checkout / cart preview) ────────────────────

app.get('/api/customers', async (req, res) => {
  try {
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
  } catch (err) {
    console.error(err.message);
    res.status(500).json({ error: err.message });
  }
});

// ── Cart ──────────────────────────────────────────────────────────────────

app.get('/api/cart', async (req, res) => {
  try {
    const raw = req.query.customerId;
    let linked893 = false;
    if (raw !== undefined && raw !== null && String(raw).trim() !== '') {
      const row = await ordsTryGet(`customers/${raw}`);
      if (!row || Number(row.id) !== Number(raw)) {
        return res.status(400).json({ error: 'Invalid customerId' });
      }
      linked893 = is893Member(row);
    }

    const cart = await ordsGet('cart_view/');
    const rows = Array.isArray(cart) ? cart : [];
    res.json(summarizeCart(rows, linked893));
  } catch (err) {
    console.error(err.message);
    res.status(500).json({ error: err.message });
  }
});

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

app.post('/api/cart', async (req, res) => {
  try {
    const { productId } = req.body;

    const filter = encodeURIComponent(JSON.stringify({ product_id: { $eq: productId } }));
    const existing = await ordsGet(`cart_items/?q=${filter}`);

    if (existing.length > 0) {
      const item = existing[0];
      await ordsPut(`cart_items/${item.id}`, {
        product_id: item.product_id,
        quantity: item.quantity + 1,
      });
    } else {
      await ordsPost('cart_items/', { product_id: productId, quantity: 1 });
    }

    const { linked893, error } = await resolveLinked893FromRequest(req);
    if (error) return res.status(400).json({ error });
    const cart = await ordsGet('cart_view/');
    const rows = Array.isArray(cart) ? cart : [];
    res.json(summarizeCart(rows, linked893));
  } catch (err) {
    console.error(err.message);
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/cart/barcode', async (req, res) => {
  try {
    const { barcode } = req.body;
    if (!barcode) {
      return res.status(400).json({ error: 'barcode is required' });
    }

    const filter = encodeURIComponent(JSON.stringify({ barcode: { $eq: String(barcode) } }));
    const products = await ordsGet(`products/?q=${filter}`);
    if (!products.length) {
      return res.status(404).json({ error: 'Product not found for barcode' });
    }

    const productId = Number(products[0].id);
    const existingFilter = encodeURIComponent(JSON.stringify({ product_id: { $eq: productId } }));
    const existing = await ordsGet(`cart_items/?q=${existingFilter}`);

    if (existing.length > 0) {
      const item = existing[0];
      await ordsPut(`cart_items/${item.id}`, {
        product_id: item.product_id,
        quantity: item.quantity + 1,
      });
    } else {
      await ordsPost('cart_items/', { product_id: productId, quantity: 1 });
    }

    const { linked893, error } = await resolveLinked893FromRequest(req);
    if (error) return res.status(400).json({ error });
    const cart = await ordsGet('cart_view/');
    const rows = Array.isArray(cart) ? cart : [];
    return res.json(summarizeCart(rows, linked893));
  } catch (err) {
    console.error(err.message);
    return res.status(500).json({ error: err.message });
  }
});

/** Replace server cart with exact line quantities (used when replaying offline checkouts). */
app.post('/api/cart/replace', async (req, res) => {
  try {
    const items = Array.isArray(req.body?.items) ? req.body.items : [];
    const customerIdRaw = req.body?.customerId;

    const existing = await ordsGet('cart_items/');
    for (const row of existing) {
      await ordsDelete(`cart_items/${row.id}`);
    }

    for (const line of items) {
      const productId = Number(line.productId);
      const quantity = Number(line.quantity);
      if (!Number.isFinite(productId) || quantity < 1) continue;
      await ordsPost('cart_items/', { product_id: productId, quantity });
    }

    let linked893 = false;
    if (customerIdRaw !== undefined && customerIdRaw !== null && String(customerIdRaw).trim() !== '') {
      const customerId = Number(customerIdRaw);
      const row = await ordsTryGet(`customers/${customerId}`);
      if (!row || Number(row.id) !== customerId) {
        return res.status(400).json({ error: 'Invalid customerId' });
      }
      linked893 = is893Member(row);
    }

    const cart = await ordsGet('cart_view/');
    const rows = Array.isArray(cart) ? cart : [];
    res.json(summarizeCart(rows, linked893));
  } catch (err) {
    console.error(err.message);
    res.status(500).json({ error: err.message });
  }
});

app.delete('/api/cart/:id', async (req, res) => {
  try {
    await ordsDelete(`cart_items/${req.params.id}`);
    const raw = req.query.customerId;
    let linked893 = false;
    if (raw !== undefined && raw !== null && String(raw).trim() !== '') {
      const row = await ordsTryGet(`customers/${raw}`);
      if (!row || Number(row.id) !== Number(raw)) {
        return res.status(400).json({ error: 'Invalid customerId' });
      }
      linked893 = is893Member(row);
    }
    const cart = await ordsGet('cart_view/');
    const rows = Array.isArray(cart) ? cart : [];
    res.json(summarizeCart(rows, linked893));
  } catch (err) {
    console.error(err.message);
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/checkout', async (req, res) => {
  try {
    const paymentMethod = normalizePaymentMethod(req.body?.paymentMethod);
    const customerIdRaw = req.body?.customerId;
    const checkoutTotalResult = normalizeCheckoutTotal(req.body?.checkoutTotal);
    if (checkoutTotalResult?.error) {
      return res.status(400).json({ error: checkoutTotalResult.error });
    }
    const checkoutTotal = checkoutTotalResult?.checkoutTotal ?? null;
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
    const recordedTotal = checkoutTotal ?? summary.subtotalPayable;
    const paymentResult = normalizeCheckoutPayments(req.body?.payments, recordedTotal);
    if (paymentResult?.error) {
      return res.status(400).json({ error: paymentResult.error });
    }
    const payments = paymentResult?.payments || null;
    const persistedPayments = payments || [{
      method: paymentMethod,
      amount: recordedTotal,
      tenderedAmount: recordedTotal,
      changeGiven: null,
    }];
    const recordedPaymentMethod = serializePaymentMethod(paymentMethod, payments);
    const orderNumber = `POS-${Date.now()}`;

    await ordsPost('sales/', {
      order_number: orderNumber,
      total: recordedTotal,
      payment_method: recordedPaymentMethod,
      customer_id: customerId,
      subtotal_pre_member: summary.subtotalPreMember,
      member_discount_pre_tax: summary.memberDiscountPreTax,
      linked_893: linked893 ? 1 : 0,
      created_at: ordsTimestamp(),
    });

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
      subtotalPreMember: summary.subtotalPreMember,
      memberDiscountPreTax: summary.memberDiscountPreTax,
      linked893,
      customerId,
      payments: persistedPayments,
      itemCount: summary.items.reduce((sum, item) => sum + Number(item.quantity), 0),
    });
  } catch (err) {
    console.error(err.message);
    return res.status(500).json({ error: err.message });
  }
});

const { registerAdminRoutes } = require('./lib/admin-routes');
const { registerSupervisorRoutes } = require('./lib/supervisor-routes');

registerSupervisorRoutes(app, { loginApprovalStore });
registerAdminRoutes(app, { ordsGet, ordsPost, ordsPut, ordsDelete, ordsTimestamp });

app.get('/api/sales/recent', async (req, res) => {
  try {
    const sales = await ordsGet('sales/?limit=20&offset=0&order=created_at:desc');
    const mapped = sales.map((s) => ({
      id: Number(s.id),
      orderNumber: s.order_number,
      total: Number(s.total),
      paymentMethod: s.payment_method,
      linked893: Number(s.linked_893) === 1,
      memberDiscountPreTax: s.member_discount_pre_tax != null ? Number(s.member_discount_pre_tax) : 0,
      subtotalPreMember: s.subtotal_pre_member != null ? Number(s.subtotal_pre_member) : Number(s.total),
    }));
    res.json(mapped);
  } catch (err) {
    console.error(err.message);
    res.status(500).json({ error: err.message });
  }
});

app.listen(PORT, () => {
  console.log(`✅ Cart app running on http://localhost:${PORT}`);
  console.log(`🗄  ORDS base: ${ORDS_BASE}`);
});
