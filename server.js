const express = require('express');
const app = express();
const PORT = 3000;

app.use(express.json());
app.use(express.static('public'));

// In-memory product list (database comes later in OCI)
const products = [
  { id: 1, name: 'Burgundy Wine', price: 45.99 },
  { id: 2, name: 'Napa Cabernet', price: 38.50 },
  { id: 3, name: 'Champagne', price: 62.00 },
];

// In-memory cart
let cart = [];

// Get all products
app.get('/api/products', (req, res) => {
  res.json(products);
});

// Get cart
app.get('/api/cart', (req, res) => {
  res.json(cart);
});

// Add to cart
app.post('/api/cart', (req, res) => {
  const { productId } = req.body;
  const product = products.find(p => p.id === productId);
  if (!product) return res.status(404).json({ error: 'Product not found' });

  const existing = cart.find(item => item.id === productId);
  if (existing) {
    existing.quantity += 1;
  } else {
    cart.push({ ...product, quantity: 1 });
  }
  res.json(cart);
});

// Remove from cart
app.delete('/api/cart/:id', (req, res) => {
  cart = cart.filter(item => item.id !== parseInt(req.params.id));
  res.json(cart);
});

app.listen(PORT, () => {
  console.log(`Cart app running on http://localhost:${PORT}`);
});