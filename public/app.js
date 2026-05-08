const productsEl = document.getElementById('products');
const cartEl = document.getElementById('cart');
const totalEl = document.getElementById('total');
const statusEl = document.getElementById('status');
const salesHistoryEl = document.getElementById('salesHistory');
const checkoutBtn = document.getElementById('checkoutBtn');
const paymentMethodEl = document.getElementById('paymentMethod');

function setStatus(message) {
  statusEl.textContent = message;
}

function money(value) {
  return `$${Number(value).toFixed(2)}`;
}

async function loadProducts() {
  const res = await fetch('/api/products');
  const products = await res.json();

  productsEl.innerHTML = products.map((product) => `
    <article class="product-card">
      <div class="product-name">${product.name}</div>
      <div class="product-price">${money(product.price)}</div>
      <button onclick="addToCart(${product.id})">Add</button>
    </article>
  `).join('');
}

async function loadCart() {
  const res = await fetch('/api/cart');
  const cart = await res.json();
  const total = cart.reduce((sum, item) => sum + Number(item.price) * Number(item.quantity), 0);

  cartEl.innerHTML = cart.length
    ? cart.map((item) => `
      <div class="cart-item">
        <div>
          <strong>${item.name}</strong><br>
          Qty ${item.quantity} x ${money(item.price)}
        </div>
        <button class="remove" onclick="removeFromCart(${item.id})">Remove</button>
      </div>
    `).join('')
    : '<p>No items yet.</p>';

  totalEl.textContent = `Total: ${money(total)}`;
}

async function loadSalesHistory() {
  const res = await fetch('/api/sales/recent');
  const sales = await res.json();

  salesHistoryEl.innerHTML = sales.length
    ? sales.map((sale) => `
      <div class="cart-item">
        <div><strong>${sale.order_number}</strong></div>
        <div>${money(sale.total)} · ${sale.payment_method}</div>
      </div>
    `).join('')
    : '<p>No sales recorded yet.</p>';
}

async function addToCart(productId) {
  await fetch('/api/cart', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ productId }),
  });
  await loadCart();
}

async function removeFromCart(id) {
  await fetch(`/api/cart/${id}`, { method: 'DELETE' });
  await loadCart();
}

async function checkout() {
  checkoutBtn.disabled = true;
  setStatus('Processing sale...');

  const res = await fetch('/api/checkout', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ paymentMethod: paymentMethodEl.value }),
  });

  const payload = await res.json();
  if (!res.ok) {
    setStatus(payload.error || 'Checkout failed');
    checkoutBtn.disabled = false;
    return;
  }

  setStatus(`Sale completed: ${payload.orderNumber}`);
  checkoutBtn.disabled = false;
  await loadCart();
  await loadSalesHistory();
}

checkoutBtn.addEventListener('click', checkout);

async function init() {
  try {
    setStatus('Loading POS...');
    await Promise.all([loadProducts(), loadCart(), loadSalesHistory()]);
    setStatus('Ready');
  } catch (error) {
    setStatus('Failed to load POS');
    console.error(error);
  }
}

init();
