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
app.use(express.static('public'));

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

async function ordsPost(path, body) {
  const res = await fetch(`${ORDS_BASE}/${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`ORDS POST ${path} → ${res.status}`);
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

// ── Pricing (pre-tax): public shelf/sale totals vs 893 member (10% off pre-tax) ─

function roundMoney(n) {
  return Math.round(Number(n) * 100) / 100;
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

/** 893: sale lines pay sale_price × 0.9; non-sale lines pay regular price × 0.9 */
function unitPricePay893(row) {
  const list = Number(row.price);
  if (isOnSale(row)) return roundMoney(Number(row.sale_price) * 0.9);
  return roundMoney(list * 0.9);
}

function unitPricePayable(row, linked893) {
  return linked893 ? unitPricePay893(row) : unitPricePublic(row);
}

function is893Member(customerRow) {
  if (!customerRow || typeof customerRow !== 'object') return false;
  return String(customerRow.member_code ?? '').trim() === '893';
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
      is893: is893Member(c),
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
    const paymentMethod = req.body?.paymentMethod || 'card';
    const customerIdRaw = req.body?.customerId;
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
    const orderNumber = `POS-${Date.now()}`;

    await ordsPost('sales/', {
      order_number: orderNumber,
      total: summary.subtotalPayable,
      payment_method: paymentMethod,
      customer_id: customerId,
      subtotal_pre_member: summary.subtotalPreMember,
      member_discount_pre_tax: summary.memberDiscountPreTax,
      linked_893: linked893 ? 1 : 0,
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

    const cartItems = await ordsGet('cart_items/');
    for (const item of cartItems) {
      await ordsDelete(`cart_items/${item.id}`);
    }

    return res.json({
      ok: true,
      orderNumber,
      paymentMethod,
      total: summary.subtotalPayable,
      subtotalPreMember: summary.subtotalPreMember,
      memberDiscountPreTax: summary.memberDiscountPreTax,
      linked893,
      customerId,
      itemCount: summary.items.reduce((sum, item) => sum + Number(item.quantity), 0),
    });
  } catch (err) {
    console.error(err.message);
    return res.status(500).json({ error: err.message });
  }
});

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
