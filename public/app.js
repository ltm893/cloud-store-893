const fetchOpts = { credentials: 'include' };

const productsEl = document.getElementById('products');
const pinGateEl = document.getElementById('pinGate');
const pinInputEl = document.getElementById('pinInput');
const pinSubmitBtn = document.getElementById('pinSubmitBtn');
const pinErrorEl = document.getElementById('pinError');
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

function showPinGate(message) {
  pinGateEl.hidden = false;
  if (message) {
    pinErrorEl.hidden = false;
    pinErrorEl.textContent = message;
  }
}

function hidePinGate() {
  pinGateEl.hidden = true;
  pinErrorEl.hidden = true;
  pinErrorEl.textContent = '';
}

async function ensureCashierSession() {
  const res = await fetch('/api/cashier/session', fetchOpts);
  const data = await res.json();
  if (data.ok) {
    hidePinGate();
    return true;
  }
  if (data.idpEnabled && data.idpLoginUrl && !data.pinAllowed) {
    window.location.href = data.idpLoginUrl;
    return false;
  }
  showPinGate(data.idpEnabled ? 'Enter PIN or use IdP sign-in below' : '');
  return false;
}

async function unlockCashier(pin) {
  const res = await fetch('/api/cashier/unlock', {
    ...fetchOpts,
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ pin }),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    showPinGate(data.error || 'Invalid PIN');
    return false;
  }
  hidePinGate();
  return true;
}

pinSubmitBtn.addEventListener('click', async () => {
  const pin = pinInputEl.value.trim();
  if (!pin) {
    showPinGate('Enter PIN');
    return;
  }
  pinSubmitBtn.disabled = true;
  const ok = await unlockCashier(pin);
  pinSubmitBtn.disabled = false;
  if (ok) {
    pinInputEl.value = '';
    await initPos();
  }
});

pinInputEl.addEventListener('keydown', (e) => {
  if (e.key === 'Enter') pinSubmitBtn.click();
});

async function loadCustomers() {
  const res = await fetch('/api/customers', fetchOpts);
  const customers = await res.json();
  customerSelectEl.innerHTML =
    '<option value="">Walk-in (no customer)</option>' +
    customers
      .map(
        (c) =>
          `<option value="${c.id}">${escapeHtml(c.name)}</option>`,
      )
      .join('');
  customerSelectEl.value = selectedCustomerId != null ? String(selectedCustomerId) : '';
}

async function loadProducts() {
  const res = await fetch('/api/products', fetchOpts);
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
  const res = await fetch(`/api/cart${customerQs()}`, fetchOpts);
  const payload = await res.json();
  if (res.status === 401) {
    showPinGate('Cashier sign-in required');
    return;
  }
  if (!res.ok) {
    setStatus(payload.error || 'Cart load failed');
    return;
  }

  const items = payload.items || [];
  const subPublic = Number(payload.subtotalPreMember || 0);
  const subPay = Number(payload.subtotalPayable || 0);
  const disc = Number(payload.memberDiscountPreTax || 0);
  const linked = !!payload.linked893; // true when any customer is linked at checkout

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
              ? `<div class="cart-detail">Pre-tax: ${money(item.lineSubtotalPublic)} → ${money(item.lineSubtotalPayable)}</div>`
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
    totalHtml += `<div class="cart-summary-893">Customer discount — shelf subtotal ${money(subPublic)}, pre-tax discount ${money(disc)}</div>`;
  } else {
    totalHtml += `<div class="cart-muted">Shelf subtotal ${money(subPublic)}</div>`;
  }
  totalEl.innerHTML = totalHtml;
}

async function loadSalesHistory() {
  const res = await fetch('/api/sales/recent', fetchOpts);
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
    ...fetchOpts,
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ productId }),
  });
  await loadCart();
}

async function removeFromCart(id) {
  await fetch(`/api/cart/${id}${customerQs()}`, { ...fetchOpts, method: 'DELETE' });
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
    ...fetchOpts,
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
  if (payload.linked893) parts.push('customer discount');
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

async function initPos() {
  try {
    setStatus('Loading POS...');
    await loadCustomers();
    await Promise.all([loadProducts(), loadCart(), loadSalesHistory()]);
    setStatus('Ready');
  } catch (error) {
    if (error && error.message && String(error).includes('401')) {
      showPinGate('Cashier sign-in required');
      return;
    }
    setStatus('Failed to load POS');
    console.error(error);
  }
}

async function init() {
  const res = await fetch('/api/cashier/session', fetchOpts);
  const data = await res.json();
  const idpLink = document.getElementById('idpLoginLink');
  if (idpLink && data.idpEnabled) {
    idpLink.hidden = false;
    if (data.idpLoginUrl) idpLink.href = data.idpLoginUrl;
  }
  if (data.ok) {
    hidePinGate();
    await initPos();
    return;
  }
  if (data.idpEnabled && data.idpLoginUrl && !data.pinAllowed) {
    window.location.href = data.idpLoginUrl;
    return;
  }
  showPinGate(data.idpEnabled ? 'Enter PIN or use IdP sign-in below' : '');
}

init();
