const productsEl = document.getElementById('products');
const cartEl = document.getElementById('cart');
const totalEl = document.getElementById('total');
const statusEl = document.getElementById('status');
const salesHistoryEl = document.getElementById('salesHistory');
const checkoutBtn = document.getElementById('checkoutBtn');
const paymentMethodEl = document.getElementById('paymentMethod');
const customerSelectEl = document.getElementById('customerSelect');
const menuBtn = document.getElementById('menuBtn');
const appMenuEl = document.getElementById('appMenu');
const toggleStatusBtn = document.getElementById('toggleStatusBtn');

let selectedCustomerId = null;
let statusVisible = false;

function setStatus(message) {
  statusEl.textContent = message;
}

function money(value) {
  return `$${Number(value).toFixed(2)}`;
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function customerQs() {
  return selectedCustomerId != null ? `?customerId=${encodeURIComponent(selectedCustomerId)}` : '';
}

async function loadCustomers() {
  const res = await fetch('/api/customers');
  const customers = await res.json();
  customerSelectEl.innerHTML =
    '<option value="">Walk-in (no customer)</option>' +
    customers
      .map(
        (c) =>
          `<option value="${c.id}">${escapeHtml(c.name)}${c.is893 ? ' (893)' : ''}</option>`,
      )
      .join('');
  customerSelectEl.value = selectedCustomerId != null ? String(selectedCustomerId) : '';
}

async function loadProducts() {
  const res = await fetch('/api/products');
  const products = await res.json();

  productsEl.innerHTML = products
    .map((product) => {
      const reg = money(product.regularPrice);
      const saleLine =
        product.onSale && product.salePrice != null
          ? `<div class="product-prices"><span class="price-reg">Reg ${reg}</span><span class="price-sale">Sale ${money(product.salePrice)}</span></div>`
          : `<div class="product-prices"><span class="price-reg">${reg}</span></div>`;
      return `
    <article class="product-card">
      <div class="product-name">${escapeHtml(product.name)}</div>
      ${saleLine}
      <button onclick="addToCart(${product.id})">Add</button>
    </article>
  `;
    })
    .join('');
}

async function loadCart() {
  const res = await fetch(`/api/cart${customerQs()}`);
  const payload = await res.json();
  if (!res.ok) {
    setStatus(payload.error || 'Cart load failed');
    return;
  }

  const items = payload.items || [];
  const subPublic = Number(payload.subtotalPreMember || 0);
  const subPay = Number(payload.subtotalPayable || 0);
  const disc = Number(payload.memberDiscountPreTax || 0);
  const linked = !!payload.linked893;

  cartEl.innerHTML = items.length
    ? items
        .map((item) => {
          const reg = money(item.regularPrice);
          const salePart =
            item.onSale && item.salePrice != null
              ? ` · Sale ${money(item.salePrice)}`
              : '';
          const line893 =
            linked && Math.abs(item.lineSubtotalPayable - item.lineSubtotalPublic) > 0.005
              ? `<div class="cart-detail">Pre-tax: ${money(item.lineSubtotalPublic)} → ${money(item.lineSubtotalPayable)} (893)</div>`
              : `<div class="cart-detail">Pre-tax line: ${money(item.lineSubtotalPayable)}</div>`;
          return `
      <div class="cart-item">
        <div>
          <strong>${escapeHtml(item.name)}</strong><br>
          <span class="cart-detail">Qty ${item.quantity} · Reg ${reg}${salePart}</span>
          ${line893}
        </div>
        <button class="remove" onclick="removeFromCart(${item.id})">Remove</button>
      </div>
    `;
        })
        .join('')
    : '<p>No items yet.</p>';

  let totalHtml = `<div><strong>Pre-tax payable:</strong> ${money(subPay)}</div>`;
  if (linked && disc > 0.005) {
    totalHtml += `<div class="cart-summary-893">893 member — shelf subtotal ${money(subPublic)}, pre-tax discount ${money(disc)}</div>`;
  } else {
    totalHtml += `<div class="cart-muted">Shelf subtotal ${money(subPublic)}</div>`;
  }
  totalEl.innerHTML = totalHtml;
}

async function loadSalesHistory() {
  const res = await fetch('/api/sales/recent');
  const sales = await res.json();

  salesHistoryEl.innerHTML = sales.length
    ? sales
        .map((sale) => {
          const tag = sale.linked893
            ? ' <span class="tag-893">893</span>'
            : '';
          const disc =
            sale.memberDiscountPreTax > 0.005
              ? ` · discount ${money(sale.memberDiscountPreTax)}`
              : '';
          return `
      <div class="cart-item">
        <div><strong>${escapeHtml(sale.orderNumber)}</strong>${tag}</div>
        <div>${money(sale.total)} · ${escapeHtml(sale.paymentMethod)}${disc}</div>
      </div>
    `;
        })
        .join('')
    : '<p>No sales recorded yet.</p>';
}

async function addToCart(productId) {
  await fetch(`/api/cart${customerQs()}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ productId }),
  });
  await loadCart();
}

async function removeFromCart(id) {
  await fetch(`/api/cart/${id}${customerQs()}`, { method: 'DELETE' });
  await loadCart();
}

async function checkout() {
  checkoutBtn.disabled = true;
  setStatus('Processing sale...');

  const body = {
    paymentMethod: paymentMethodEl.value,
  };
  if (selectedCustomerId != null) {
    body.customerId = selectedCustomerId;
  }

  const res = await fetch('/api/checkout', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });

  const payload = await res.json();
  if (!res.ok) {
    setStatus(payload.error || 'Checkout failed');
    checkoutBtn.disabled = false;
    return;
  }

  const parts = [`Sale completed: ${payload.orderNumber}`];
  if (payload.linked893) parts.push('893 member');
  if (payload.memberDiscountPreTax > 0.005) {
    parts.push(`pre-tax discount ${money(payload.memberDiscountPreTax)}`);
  }
  setStatus(parts.join(' — '));
  checkoutBtn.disabled = false;
  await loadCart();
  await loadSalesHistory();
}

checkoutBtn.addEventListener('click', checkout);

menuBtn.addEventListener('click', () => {
  appMenuEl.hidden = !appMenuEl.hidden;
});

toggleStatusBtn.addEventListener('click', () => {
  statusVisible = !statusVisible;
  statusEl.classList.toggle('status-hidden', !statusVisible);
  toggleStatusBtn.textContent = statusVisible ? 'Hide status' : 'Show status';
  appMenuEl.hidden = true;
});

statusEl.classList.add('status-hidden');

customerSelectEl.addEventListener('change', () => {
  const v = customerSelectEl.value;
  selectedCustomerId = v === '' ? null : Number(v);
  loadCart().catch(console.error);
});

async function init() {
  try {
    setStatus('Loading POS...');
    await loadCustomers();
    await Promise.all([loadProducts(), loadCart(), loadSalesHistory()]);
    setStatus('Ready');
  } catch (error) {
    setStatus('Failed to load POS');
    console.error(error);
  }
}

init();
