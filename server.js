const express = require('express');
const app = express();
const PORT = process.env.PORT || 3000;

// ORDS_BASE_URL comes from .env file
// Example: https://abc123.adb.us-ashburn-1.oraclecloudapps.com/ords/admin
const ORDS_BASE = process.env.ORDS_BASE_URL;

if (!ORDS_BASE) {
  console.error('❌ ORDS_BASE_URL is not set. Create a .env file — see .env.example');
  process.exit(1);
}

app.use(express.json());
app.use(express.static('public'));


// ── ORDS helpers ──────────────────────────────────────────────────────────
// ORDS wraps list responses as { items: [...], hasMore: bool, count: N, ... }
// These helpers handle that unwrapping so route handlers stay clean.

async function ordsGet(path) {
  const res = await fetch(`${ORDS_BASE}/${path}`);
  if (!res.ok) throw new Error(`ORDS GET ${path} → ${res.status}`);
  const data = await res.json();
  return Array.isArray(data.items) ? data.items : data;
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


// ── Products ──────────────────────────────────────────────────────────────

// GET /api/products
// Returns all rows from the PRODUCTS table via ORDS
app.get('/api/products', async (req, res) => {
  try {
    const products = await ordsGet('products/');
    res.json(products);
  } catch (err) {
    console.error(err.message);
    res.status(500).json({ error: err.message });
  }
});


// ── Cart ──────────────────────────────────────────────────────────────────

// GET /api/cart
// Reads from CART_VIEW which joins CART_ITEMS + PRODUCTS
app.get('/api/cart', async (req, res) => {
  try {
    const cart = await ordsGet('cart_view/');
    res.json(cart);
  } catch (err) {
    console.error(err.message);
    res.status(500).json({ error: err.message });
  }
});


// POST /api/cart  { productId: N }
// Upsert: if the product is already in the cart, increment quantity.
// If not, insert a new cart_items row.
app.post('/api/cart', async (req, res) => {
  try {
    const { productId } = req.body;

    // ORDS filter syntax: ?q={"column":{"$eq":value}}
    const filter = encodeURIComponent(JSON.stringify({ product_id: { $eq: productId } }));
    const existing = await ordsGet(`cart_items/?q=${filter}`);

    if (existing.length > 0) {
      // Product already in cart — increment quantity
      const item = existing[0];
      await ordsPut(`cart_items/${item.id}`, {
        product_id: item.product_id,
        quantity: item.quantity + 1,
      });
    } else {
      // New cart item
      await ordsPost('cart_items/', { product_id: productId, quantity: 1 });
    }

    const cart = await ordsGet('cart_view/');
    res.json(cart);
  } catch (err) {
    console.error(err.message);
    res.status(500).json({ error: err.message });
  }
});


// DELETE /api/cart/:id
// :id is the CART_ITEMS row id (not the product id)
app.delete('/api/cart/:id', async (req, res) => {
  try {
    await ordsDelete(`cart_items/${req.params.id}`);
    const cart = await ordsGet('cart_view/');
    res.json(cart);
  } catch (err) {
    console.error(err.message);
    res.status(500).json({ error: err.message });
  }
});


// ── Start ─────────────────────────────────────────────────────────────────
app.listen(PORT, () => {
  console.log(`✅ Cart app running on http://localhost:${PORT}`);
  console.log(`🗄  ORDS base: ${ORDS_BASE}`);
});
