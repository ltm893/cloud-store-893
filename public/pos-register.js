/** Web register UI — layout and flows aligned with Android PosScreen. */
const PosRegister = (() => {
  const fetchOpts = { credentials: 'include' };

  const els = {};
  const state = {
    cart: { items: [], linked893: false },
    customers: [],
    products: [],
    selectedCustomerId: null,
    cashEnabled: true,
    sessionUser: null,
    sessionMeta: {},
    salesFeeRate: 0,
    taxRate: 0.06,
    buildInfo: null,
    barcodeInput: '',
    addItemError: null,
    checkout: {
      open: false,
      amountInput: '0',
      payments: [],
      saleItemsLocked: false,
    },
    quantityEditId: null,
    customerFindOpen: false,
    customerSearch: '',
    receipt: null,
    statusVisible: false,
  };

  function $(id) {
    return document.getElementById(id);
  }

  function cacheElements() {
    [
      'appShell',
      'barcodeInput',
      'scanBtn',
      'addBarcodeBtn',
      'addItemError',
      'linkedCustomerRow',
      'linkedCustomerName',
      'unlinkCustomerBtn',
      'cart',
      'paymentsReceived',
      'saleTotals',
      'salePanel',
      'receiptPanel',
      'receiptBody',
      'newSaleBtn',
      'payBtn',
      'statusPanel',
      'statusPanelBody',
      'barcodeNumpadPanel',
      'qtyEditHeader',
      'saleNumpad',
      'customerFindPanel',
      'customerSearchInput',
      'customerResults',
      'customerFindBackBtn',
      'checkoutPanel',
      'checkoutBackBtn',
      'checkoutAmounts',
      'quickBills',
      'checkoutNumpad',
      'payCashBtn',
      'payCardBtn',
      'payCardOnFileBtn',
      'headerUser',
      'headerBuild',
      'statusToast',
      'processingOverlay',
      'processingMessage',
      'processingProgress',
      'cardOnFileDialog',
      'cardOnFileText',
      'cardOnFileConfirmBtn',
      'cardOnFileCancelBtn',
      'drawer',
      'drawerBackdrop',
      'menuBtn',
      'toggleStatusBtn',
      'findCustomerBtn',
      'signOutBtn',
    ].forEach((id) => {
      els[id] = $(id);
    });
  }

  function customerQs() {
    return state.selectedCustomerId != null
      ? `?customerId=${encodeURIComponent(state.selectedCustomerId)}`
      : '';
  }

  function setToast(message) {
    if (els.statusToast) els.statusToast.textContent = message || '';
  }

  function selectedCustomer() {
    if (state.selectedCustomerId == null) return null;
    return state.customers.find((c) => c.id === state.selectedCustomerId) || null;
  }

  function customerDiscountActive() {
    const c = selectedCustomer();
    return Boolean(c?.is893);
  }

  function customerLinked() {
    return state.selectedCustomerId != null;
  }

  function registerTotal() {
    return PosMath.computeSaleGrandTotal(
      state.cart.items || [],
      customerLinked(),
      customerDiscountActive(),
      state.salesFeeRate,
      state.taxRate,
    );
  }

  function renderNumpad(container, handlers, { showDecimal = false, showClear = true } = {}) {
    container.innerHTML = '';
    const addKey = (label, className, handler, disabled = false) => {
      const btn = document.createElement('button');
      btn.type = 'button';
      btn.className = `numpad-key${className ? ` ${className}` : ''}`;
      btn.textContent = label;
      if (disabled) btn.disabled = true;
      else btn.addEventListener('click', handler);
      container.appendChild(btn);
    };

    '123456789'.split('').forEach((digit) => {
      addKey(digit, '', () => handlers.onDigit(digit));
    });

    if (showClear) {
      addKey('C', 'numpad-key--action', handlers.onClear);
    }
    if (showDecimal) {
      addKey('.', 'numpad-key--action', () => handlers.onDigit('.'));
    }
    addKey('0', '', () => handlers.onDigit('0'));
    addKey('⌫', 'numpad-key--action', handlers.onBackspace);
  }

  function renderSaleNumpad() {
    const inCheckout = state.checkout.open;
    const inQty = state.quantityEditId != null && !inCheckout;

    if (inCheckout) {
      renderCheckoutNumpad();
      return;
    }

    renderNumpad(
      els.saleNumpad,
      {
        onDigit: (d) => {
          if (inQty) {
            applyQtyDigit(d);
          } else {
            state.barcodeInput += d;
            els.barcodeInput.value = state.barcodeInput;
            updateBarcodeButtons();
          }
        },
        onClear: () => {
          if (inQty) {
            state.qtyDraft = '0';
            renderQtyHeader();
          } else {
            state.barcodeInput = '';
            els.barcodeInput.value = '';
            updateBarcodeButtons();
          }
        },
        onBackspace: () => {
          if (inQty) {
            state.qtyDraft = PosMath.backspaceCashEntry(state.qtyDraft || '0');
            renderQtyHeader();
          } else {
            state.barcodeInput = state.barcodeInput.slice(0, -1);
            els.barcodeInput.value = state.barcodeInput;
            updateBarcodeButtons();
          }
        },
      },
      { showDecimal: false, showClear: true },
    );
  }

  function renderCheckoutNumpad() {
    const register = registerTotal();
    const balance = PosMath.balanceDueForMethod(register, state.checkout.payments);
    const maxCard = !state.cashEnabled ? balance : null;

    renderNumpad(
      els.checkoutNumpad,
      {
        onDigit: (d) => {
          state.checkout.amountInput = PosMath.appendCashDigitLimited(
            state.checkout.amountInput,
            d,
            maxCard,
          );
          renderCheckoutPanel();
        },
        onClear: () => {
          state.checkout.amountInput = '0';
          renderCheckoutPanel();
        },
        onBackspace: () => {
          state.checkout.amountInput = PosMath.backspaceCashEntry(state.checkout.amountInput);
          renderCheckoutPanel();
        },
      },
      { showDecimal: true, showClear: false },
    );
  }

  function updateBarcodeButtons() {
    const locked = state.checkout.saleItemsLocked;
    const hasInput = state.barcodeInput.trim().length > 0;
    els.addBarcodeBtn.disabled = locked || !hasInput;
    els.scanBtn.disabled = locked || hasInput;
    els.barcodeInput.readOnly = locked;
  }

  function renderCart() {
    const items = state.cart.items || [];
    const locked = state.checkout.saleItemsLocked;

    if (!items.length) {
      els.cart.innerHTML = '<p class="cart-line-meta">No items yet. Scan or enter a product ID.</p>';
    } else {
      els.cart.innerHTML = items
        .map((item) => {
          const salePart =
            item.onSale && item.salePrice != null
              ? `<span class="price-strike">${PosMath.formatMoney(item.regularPrice)}</span> → ${PosMath.formatMoney(item.salePrice)}`
              : PosMath.formatMoney(item.regularPrice);
          const linked =
            state.cart.linked893 &&
            Math.abs(item.lineSubtotalPayable - item.lineSubtotalPublic) > 0.005
              ? `<div class="cart-line-meta">Pre-tax: ${PosMath.formatMoney(item.lineSubtotalPublic)} → ${PosMath.formatMoney(item.lineSubtotalPayable)}</div>`
              : '';
          return `
        <div class="cart-line">
          <div class="cart-line-main">
            <div class="cart-line-name">${escapeHtml(item.name)}</div>
            <div class="cart-line-meta">ID ${item.productId} · ${salePart}</div>
            ${linked}
          </div>
          <div class="cart-line-actions">
            <div class="cart-line-price">${PosMath.formatMoney(item.lineSubtotalPayable)}</div>
            <button type="button" class="qty-btn" data-qty-id="${item.id}" ${locked ? 'disabled' : ''}>Qty ${item.quantity}</button>
            <button type="button" class="remove-btn" data-remove-id="${item.id}" ${locked ? 'disabled' : ''}>Remove</button>
          </div>
        </div>`;
        })
        .join('');
    }

    els.cart.querySelectorAll('[data-qty-id]').forEach((btn) => {
      btn.addEventListener('click', () => {
        startQuantityEdit(Number(btn.dataset.qtyId));
      });
    });
    els.cart.querySelectorAll('[data-remove-id]').forEach((btn) => {
      btn.addEventListener('click', () => removeCartItem(Number(btn.dataset.removeId)));
    });

    renderTotals();
    renderPaymentsReceived();
    renderLinkedCustomer();
    updateBarcodeButtons();
    els.payBtn.disabled = locked || items.length === 0;
  }

  function renderTotals() {
    const items = state.cart.items || [];
    const discount = customerDiscountActive();
    const totals = PosMath.computeCartTotals(items, discount);
    const tax = PosMath.computeTaxAmount(
      items,
      customerLinked(),
      discount,
      state.salesFeeRate,
      state.taxRate,
    );
    const grand = registerTotal();

    const stats = [
      { label: 'Items', value: String(totals.itemCount) },
    ];
    if (customerLinked()) {
      stats.push(
        { label: 'Subtotal', value: PosMath.formatMoney(totals.shelfSubtotal) },
        {
          label: 'Discount',
          value: totals.showDiscount ? `−${PosMath.formatMoney(totals.memberDiscount)}` : PosMath.formatMoney(0),
          cls: totals.showDiscount ? 'stat-value--discount' : '',
        },
        { label: 'PreTax', value: PosMath.formatMoney(totals.itemPreTax) },
      );
    } else {
      stats.push({ label: 'Subtotal', value: PosMath.formatMoney(totals.itemPreTax) });
    }
    stats.push(
      {
        label: 'Savings',
        value: totals.saleSavings > 0.005 ? `−${PosMath.formatMoney(totals.saleSavings)}` : PosMath.formatMoney(0),
        cls: 'stat-value--discount',
      },
      { label: 'Tax', value: PosMath.formatMoney(tax) },
      { label: 'Total', value: PosMath.formatMoney(grand), cls: 'stat-value--total' },
    );

    els.saleTotals.innerHTML = stats
      .map(
        (s) => `
      <div class="stat-block">
        <div class="stat-label">${s.label}</div>
        <div class="stat-value ${s.cls || ''}">${s.value}</div>
      </div>`,
      )
      .join('');
  }

  function renderLinkedCustomer() {
    const customer = selectedCustomer();
    if (!customer) {
      els.linkedCustomerRow.hidden = true;
      return;
    }
    els.linkedCustomerRow.hidden = false;
    els.linkedCustomerName.textContent = customer.name || `Customer #${customer.id}`;
  }

  function renderPaymentsReceived() {
    const payments = state.checkout.payments;
    if (!state.checkout.open || !payments.length) {
      els.paymentsReceived.hidden = true;
      els.paymentsReceived.innerHTML = '';
      return;
    }
    els.paymentsReceived.hidden = false;
    els.paymentsReceived.innerHTML = `
      <div class="section-title">Payments received</div>
      ${payments
        .map((p, i) => {
          const change =
            p.changeGiven > 0.005 ? `<div class="cart-line-meta">Change ${PosMath.formatMoney(p.changeGiven)}</div>` : '';
          const remove =
            p.method !== 'card'
              ? `<button type="button" class="text-btn" data-remove-payment="${i}">Remove</button>`
              : '';
          return `
        <div class="payment-line">
          <div>
            <strong>${i + 1}. ${PosMath.paymentMethodLabel(p.method)} · ${PosMath.formatMoney(p.amount)}</strong>
            ${change}
          </div>
          ${remove}
        </div>`;
        })
        .join('')}`;
    els.paymentsReceived.querySelectorAll('[data-remove-payment]').forEach((btn) => {
      btn.addEventListener('click', () => {
        const idx = Number(btn.dataset.removePayment);
        state.checkout.payments = state.checkout.payments.filter((_, i) => i !== idx);
        renderCart();
        renderCheckoutPanel();
      });
    });
  }

  function renderRightPanel() {
    const checkout = state.checkout.open;
    const find = state.customerFindOpen;

    els.checkoutPanel.hidden = !checkout;
    els.customerFindPanel.hidden = !find;
    els.barcodeNumpadPanel.hidden = checkout || find;
    els.payBtn.hidden = checkout || state.receipt != null;

    if (checkout) renderCheckoutPanel();
    else if (find) renderCustomerFind();
    else renderSaleNumpad();
  }

  function renderCheckoutPanel() {
    const register = registerTotal();
    const collected = PosMath.collectedTotal(register);
    const balance = PosMath.balanceDueForMethod(register, state.checkout.payments);
    const cardPaid = PosMath.roundMoney(
      state.checkout.payments.filter((p) => p.method === 'card').reduce((s, p) => s + p.amount, 0),
    );
    const cashDue = state.cashEnabled ? PosMath.remainingCashAmountDue(register, cardPaid) : balance;
    const changeTotal = PosMath.checkoutChangeTotal(state.checkout.payments);
    const entered = PosMath.parseCashTendered(state.checkout.amountInput);
    const creditOnly = !state.cashEnabled;

    const rows = [
      ['Sale total', PosMath.formatMoney(register)],
    ];
    if (collected + 0.005 < register) {
      rows.push(['Payable (nickels)', PosMath.formatMoney(collected)]);
    }
    rows.push(['Balance due', PosMath.formatMoney(balance)]);
    if (state.cashEnabled && cashDue + 0.005 < balance) {
      rows.push(['Cash due (no pennies)', PosMath.formatMoney(cashDue)]);
    }
    if (changeTotal > 0.005) {
      rows.push(['Change from payments', PosMath.formatMoney(changeTotal)]);
    }
    rows.push(['Amount entered', PosMath.displayCashEntry(state.checkout.amountInput)]);

    if (entered != null && entered > balance + 0.005 && state.cashEnabled) {
      rows.push(['Give change', PosMath.formatMoney(entered - balance)]);
    } else if (balance > 0.005 && entered != null) {
      const still = PosMath.roundMoney(balance - Math.min(entered, balance));
      if (still > 0.005) rows.push(['Still need', PosMath.formatMoney(still)]);
    }

    els.checkoutAmounts.innerHTML = rows
      .map(
        ([label, value], i) => `
      <div class="amount-row${i === 2 ? ' amount-row--emph' : ''}">
        <span>${label}</span><span>${value}</span>
      </div>`,
      )
      .join('');

    const quickTarget = state.cashEnabled && !creditOnly ? cashDue : balance;
    const bills = ['Fill', ...PosMath.cashQuickDenominations(quickTarget, state.cashEnabled && !creditOnly).map((b) => `$${b}`)];
    els.quickBills.innerHTML = bills
      .map((label, i) => {
        if (i === 0) {
          return `<button type="button" class="quick-bill-btn" data-fill="1">Fill</button>`;
        }
        const amount = label.slice(1);
        return `<button type="button" class="quick-bill-btn" data-bill="${amount}">${label}</button>`;
      })
      .join('');

    els.quickBills.querySelectorAll('[data-fill]').forEach((btn) => {
      btn.addEventListener('click', () => {
        state.checkout.amountInput = PosMath.normalizeCashEntryInput(
          String(PosMath.roundMoney(quickTarget)),
        );
        renderCheckoutPanel();
      });
    });
    els.quickBills.querySelectorAll('[data-bill]').forEach((btn) => {
      btn.addEventListener('click', () => {
        state.checkout.amountInput = PosMath.normalizeCashEntryInput(btn.dataset.bill);
        renderCheckoutPanel();
      });
    });

    const canCash = state.cashEnabled && balance > 0.005;
    const canCard =
      balance > 0.005 && entered != null && entered > 0 && entered <= balance + 0.005;
    els.payCashBtn.hidden = !state.cashEnabled;
    els.payCashBtn.disabled = !canCash;
    els.payCardBtn.disabled = !canCard;

    const linked = selectedCustomer();
    const showCof = linked?.hasCardOnFile && balance > 0.005;
    els.payCardOnFileBtn.hidden = !showCof;

    els.checkoutBackBtn.disabled = state.checkout.payments.some((p) => p.method === 'card');
    renderCheckoutNumpad();
  }

  function renderCustomerFind() {
    const q = state.customerSearch.trim().toLowerCase();
    const matches = !q
      ? state.customers.slice(0, 20)
      : state.customers.filter((c) => {
          const blob = [c.id, c.name, c.email, c.phone, c.memberCode]
            .filter(Boolean)
            .join(' ')
            .toLowerCase();
          return blob.includes(q);
        }).slice(0, 30);

    els.customerResults.innerHTML = matches.length
      ? matches
          .map(
            (c) => `
        <button type="button" class="customer-result-btn" data-customer-id="${c.id}">
          <strong>${escapeHtml(c.name || `Customer #${c.id}`)}</strong>
          <span class="customer-result-meta">${escapeHtml([c.email, c.phone].filter(Boolean).join(' · '))}</span>
        </button>`,
          )
          .join('')
      : '<p class="cart-line-meta">No customers found.</p>';

    els.customerResults.querySelectorAll('[data-customer-id]').forEach((btn) => {
      btn.addEventListener('click', async () => {
        state.selectedCustomerId = Number(btn.dataset.customerId);
        state.customerFindOpen = false;
        closeDrawer();
        await refreshCart();
        renderAll();
      });
    });
  }

  function renderReceipt() {
    const r = state.receipt;
    if (!r) {
      els.salePanel.hidden = false;
      els.receiptPanel.hidden = true;
      return;
    }
    els.salePanel.hidden = true;
    els.receiptPanel.hidden = false;
    const change = PosMath.checkoutChangeTotal(r.payments || []);
    els.receiptBody.innerHTML = `
      <div class="receipt-line"><strong>Order</strong><span>${escapeHtml(r.orderNumber)}</span></div>
      <div class="receipt-line"><span>Total</span><span>${PosMath.formatMoney(r.total)}</span></div>
      <div class="receipt-line"><span>Payment</span><span>${escapeHtml(r.paymentMethod)}</span></div>
      ${change > 0.005 ? `<div class="receipt-line"><span>Change</span><span>${PosMath.formatMoney(change)}</span></div>` : ''}
      ${r.linked893 ? '<p><span class="tag-893">893</span> Customer discount applied</p>' : ''}
    `;
  }

  function renderStatusPanel() {
    const lines = [
      ['API', window.location.origin],
      ['User', state.sessionUser || '—'],
      ['Till', state.sessionMeta.tillId != null ? String(state.sessionMeta.tillId) : '—'],
      ['Cash', state.cashEnabled ? 'enabled' : 'credit only'],
      ['Tax rate', `${(state.taxRate * 100).toFixed(2)}%`],
    ];
    if (state.buildInfo?.display) {
      lines.push(['Build', state.buildInfo.display]);
    }
    els.statusPanelBody.innerHTML = lines
      .map(([k, v]) => `<dt>${escapeHtml(k)}</dt><dd>${escapeHtml(v)}</dd>`)
      .join('');
    els.statusPanel.hidden = !state.statusVisible;
    els.toggleStatusBtn.textContent = state.statusVisible ? 'Hide status' : 'Show status';
  }

  function renderHeader() {
    els.headerUser.textContent = state.sessionUser ? `user: ${state.sessionUser}` : '';
    els.headerBuild.textContent = state.buildInfo?.display || '';
  }

  function renderAll() {
    renderCart();
    renderRightPanel();
    renderReceipt();
    renderStatusPanel();
    renderHeader();
  }

  async function refreshCart() {
    const res = await fetch(`/api/cart${customerQs()}`, fetchOpts);
    if (res.status === 401) throw new Error('401');
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || 'Cart load failed');
    state.cart = data;
    state.addItemError = null;
    if (els.addItemError) els.addItemError.hidden = true;
  }

  async function loadProducts() {
    const res = await fetch('/api/products', fetchOpts);
    if (res.status === 401) throw new Error('401');
    state.products = await res.json();
  }

  async function loadCustomers() {
    const res = await fetch('/api/customers', fetchOpts);
    if (res.status === 401) throw new Error('401');
    state.customers = await res.json();
  }

  async function loadBuildInfo() {
    const res = await fetch('/api/build-info', fetchOpts);
    if (!res.ok) return;
    state.buildInfo = await res.json();
    if (state.buildInfo.posRates) {
      state.salesFeeRate = Number(state.buildInfo.posRates.salesFeeRate) || 0;
      state.taxRate = Number(state.buildInfo.posRates.taxRate) || 0.06;
    }
  }

  async function addByBarcode() {
    const cleaned = state.barcodeInput.trim();
    if (!cleaned) return;
    state.addItemError = null;

    const asId = /^\d+$/.test(cleaned) ? Number(cleaned) : null;
    const treatAsId = asId != null && cleaned.length <= 6;

    if (treatAsId) {
      const product = state.products.find((p) => p.id === asId);
      const hasCustomer = state.customers.some((c) => c.id === asId);
      if (!product && hasCustomer) {
        state.selectedCustomerId = asId;
        state.barcodeInput = '';
        els.barcodeInput.value = '';
        await refreshCart();
        renderAll();
        return;
      }
      if (!product) {
        state.addItemError = `Product not found: ID ${cleaned}`;
        els.addItemError.hidden = false;
        els.addItemError.textContent = state.addItemError;
        return;
      }
      if (product.inStock === false) {
        const stockMsg = product.quantityOnHand != null ? ` (qty ${product.quantityOnHand})` : '';
        state.addItemError = `${product.name} is out of stock${stockMsg}`;
        els.addItemError.hidden = false;
        els.addItemError.textContent = state.addItemError;
        return;
      }

      const res = await fetch(`/api/cart${customerQs()}`, {
        ...fetchOpts,
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ productId: asId }),
      });
      const data = await res.json().catch(() => ({}));
      if (res.status === 401) throw new Error('401');
      if (!res.ok) {
        state.addItemError = data.error || 'Add failed';
        els.addItemError.hidden = false;
        els.addItemError.textContent = state.addItemError;
        return;
      }
      state.cart = data;
      state.barcodeInput = '';
      els.barcodeInput.value = '';
      renderAll();
      return;
    }

    const byBarcode = state.products.find((p) => String(p.barcode || '') === cleaned);
    if (byBarcode && byBarcode.inStock === false) {
      const stockMsg = byBarcode.quantityOnHand != null ? ` (qty ${byBarcode.quantityOnHand})` : '';
      state.addItemError = `${byBarcode.name} is out of stock${stockMsg}`;
      els.addItemError.hidden = false;
      els.addItemError.textContent = state.addItemError;
      return;
    }

    const res = await fetch(`/api/cart/barcode${customerQs()}`, {
      ...fetchOpts,
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ barcode: cleaned }),
    });
    const data = await res.json().catch(() => ({}));
    if (res.status === 401) throw new Error('401');
    if (!res.ok) {
      state.addItemError = data.error || 'Product not found';
      els.addItemError.hidden = false;
      els.addItemError.textContent = state.addItemError;
      return;
    }
    state.cart = data;
    state.barcodeInput = '';
    els.barcodeInput.value = '';
    renderAll();
  }

  async function removeCartItem(id) {
    await fetch(`/api/cart/${id}${customerQs()}`, { ...fetchOpts, method: 'DELETE' });
    await refreshCart();
    renderAll();
  }

  function startQuantityEdit(cartItemId) {
    const item = (state.cart.items || []).find((i) => i.id === cartItemId);
    if (!item) return;
    state.quantityEditId = cartItemId;
    state.qtyDraft = String(item.quantity);
    state.customerFindOpen = false;
    renderQtyHeader();
    renderRightPanel();
  }

  function renderQtyHeader() {
    const item = (state.cart.items || []).find((i) => i.id === state.quantityEditId);
    if (!item) {
      els.qtyEditHeader.hidden = true;
      return;
    }
    els.qtyEditHeader.hidden = false;
    els.qtyEditHeader.innerHTML = `
      <div><strong>${escapeHtml(item.name)}</strong></div>
      <div>Quantity: ${escapeHtml(state.qtyDraft || '0')}</div>
      <button type="button" class="btn btn-teal" id="applyQtyBtn" style="margin-top:6px">Set quantity</button>
      <button type="button" class="text-btn" id="cancelQtyBtn">Cancel</button>`;
    $('applyQtyBtn').addEventListener('click', applyQuantityEdit);
    $('cancelQtyBtn').addEventListener('click', cancelQuantityEdit);
  }

  function applyQtyDigit(d) {
    if (state.qtyDraft === '0' && d !== '.') {
      state.qtyDraft = d;
    } else {
      state.qtyDraft = (state.qtyDraft || '0') + d;
    }
    renderQtyHeader();
  }

  async function applyQuantityEdit() {
    const qty = Math.floor(Number(state.qtyDraft));
    if (!Number.isFinite(qty) || qty < 0) return;
    const id = state.quantityEditId;
    state.quantityEditId = null;
    els.qtyEditHeader.hidden = true;
    if (qty === 0) {
      await removeCartItem(id);
      return;
    }
    await fetch(`/api/cart/${id}${customerQs()}`, {
      ...fetchOpts,
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ quantity: qty }),
    });
    await refreshCart();
    renderAll();
  }

  function cancelQuantityEdit() {
    state.quantityEditId = null;
    els.qtyEditHeader.hidden = true;
    renderRightPanel();
  }

  function openCheckout() {
    if (!(state.cart.items || []).length) return;
    state.checkout.open = true;
    state.checkout.amountInput = '0';
    state.checkout.payments = [];
    state.customerFindOpen = false;
    state.quantityEditId = null;
    renderAll();
  }

  function closeCheckout() {
    if (state.checkout.payments.some((p) => p.method === 'card')) return;
    state.checkout.open = false;
    state.checkout.amountInput = '0';
    state.checkout.payments = [];
    state.checkout.saleItemsLocked = false;
    renderAll();
  }

  function applyPayment(method) {
    const register = registerTotal();
    const balance = PosMath.balanceDueForMethod(register, state.checkout.payments);
    const entered = PosMath.parseCashTendered(state.checkout.amountInput);
    if (entered == null || entered <= 0) {
      setToast(`Enter a valid amount for ${PosMath.paymentMethodLabel(method)}`);
      return;
    }
    const payment = PosMath.buildCheckoutPaymentLine(method, entered, balance);
    if (!payment) {
      setToast(`Enter a valid amount for ${PosMath.paymentMethodLabel(method)}`);
      return;
    }

    if (method === 'card') {
      processCardPayment(payment);
      return;
    }

    const payments = [...state.checkout.payments, payment];
    if (PosMath.isCheckoutComplete(register, payments)) {
      finalizeCheckout(payments, register);
    } else {
      state.checkout.payments = payments;
      state.checkout.amountInput = '0';
      renderAll();
    }
  }

  async function processCardPayment(payment) {
    state.checkout.saleItemsLocked = true;
    els.processingOverlay.hidden = false;
    els.processingMessage.textContent = `Sending ${PosMath.formatMoney(payment.amount)} to Credit Terminal`;
    els.processingProgress.style.width = '0%';

    for (let i = 1; i <= 20; i += 1) {
      await new Promise((r) => setTimeout(r, 100));
      els.processingProgress.style.width = `${(i / 20) * 100}%`;
    }

    const register = registerTotal();
    const payments = [...state.checkout.payments, payment];
    els.processingOverlay.hidden = true;

    if (PosMath.isCheckoutComplete(register, payments)) {
      await finalizeCheckout(payments, register);
    } else {
      state.checkout.payments = payments;
      state.checkout.amountInput = '0';
      renderAll();
    }
  }

  async function finalizeCheckout(payments, registerTotalValue) {
    state.checkout.saleItemsLocked = true;
    setToast('Completing sale…');

    const body = {
      payments: payments.map((p) => ({
        method: p.method,
        amount: p.amount,
        tenderedAmount: p.tenderedAmount,
        changeGiven: p.changeGiven,
      })),
      checkoutTotal: PosMath.collectedTotal(registerTotalValue),
    };
    if (state.selectedCustomerId != null) {
      body.customerId = state.selectedCustomerId;
    }

    const res = await fetch('/api/checkout', {
      ...fetchOpts,
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      state.checkout.saleItemsLocked = false;
      setToast(data.error || 'Checkout failed');
      renderAll();
      return;
    }

    state.receipt = {
      ...data,
      payments,
    };
    state.checkout = {
      open: false,
      amountInput: '0',
      payments: [],
      saleItemsLocked: false,
    };
    state.cart = { items: [], linked893: false };
    setToast(`Sale completed: ${data.orderNumber}`);
    renderAll();
  }

  function newSale() {
    state.receipt = null;
    renderAll();
  }

  function openDrawer() {
    els.drawer.hidden = false;
    els.drawerBackdrop.hidden = false;
  }

  function closeDrawer() {
    els.drawer.hidden = true;
    els.drawerBackdrop.hidden = true;
  }

  async function signOut() {
    closeDrawer();
    await fetch('/api/cashier/sign-off', { ...fetchOpts, method: 'POST' });
    window.location.reload();
  }

  function bindEvents() {
    els.menuBtn.addEventListener('click', openDrawer);
    els.drawerBackdrop.addEventListener('click', closeDrawer);
    els.toggleStatusBtn.addEventListener('click', () => {
      state.statusVisible = !state.statusVisible;
      renderStatusPanel();
      closeDrawer();
    });
    els.findCustomerBtn.addEventListener('click', () => {
      state.customerFindOpen = true;
      state.checkout.open = false;
      closeDrawer();
      renderAll();
      els.customerSearchInput.focus();
    });
    els.signOutBtn.addEventListener('click', signOut);

    els.barcodeInput.addEventListener('input', () => {
      state.barcodeInput = els.barcodeInput.value;
      updateBarcodeButtons();
    });
    els.barcodeInput.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') addByBarcode();
    });
    els.addBarcodeBtn.addEventListener('click', addByBarcode);
    els.scanBtn.addEventListener('click', () => {
      setToast('Camera scan is available on the tablet app');
    });

    els.unlinkCustomerBtn.addEventListener('click', async () => {
      state.selectedCustomerId = null;
      await refreshCart();
      renderAll();
    });

    els.payBtn.addEventListener('click', openCheckout);
    els.checkoutBackBtn.addEventListener('click', closeCheckout);
    els.customerFindBackBtn.addEventListener('click', () => {
      state.customerFindOpen = false;
      renderAll();
    });
    els.customerSearchInput.addEventListener('input', () => {
      state.customerSearch = els.customerSearchInput.value;
      renderCustomerFind();
    });

    els.payCashBtn.addEventListener('click', () => applyPayment('cash'));
    els.payCardBtn.addEventListener('click', () => applyPayment('card'));
    els.payCardOnFileBtn.addEventListener('click', () => {
      const linked = selectedCustomer();
      if (!linked?.hasCardOnFile) return;
      const last4 = linked.cardLast4 || '????';
      els.cardOnFileText.textContent = `Charge the card on file ending in ${last4}?`;
      els.cardOnFileDialog.hidden = false;
    });
    els.cardOnFileCancelBtn.addEventListener('click', () => {
      els.cardOnFileDialog.hidden = true;
    });
    els.cardOnFileConfirmBtn.addEventListener('click', () => {
      els.cardOnFileDialog.hidden = true;
      const register = registerTotal();
      const balance = PosMath.balanceDueForMethod(register, state.checkout.payments);
      state.checkout.amountInput = PosMath.normalizeCashEntryInput(String(PosMath.roundMoney(balance)));
      applyPayment('card');
    });

    els.newSaleBtn.addEventListener('click', newSale);
  }

  async function start(sessionData = {}) {
    cacheElements();
    bindEvents();

    state.sessionUser = sessionData.user || sessionData.name || sessionData.email || null;
    state.sessionMeta = sessionData;
    state.cashEnabled = sessionData.cashEnabled !== false;
    state.cashEnabled = sessionData.cashTillEnabled ? sessionData.cashEnabled !== false : state.cashEnabled;

    els.appShell.hidden = false;
    setToast('Loading register…');

    await Promise.all([loadBuildInfo(), loadCustomers(), loadProducts()]);
    await refreshCart();

    renderSaleNumpad();
    renderAll();
    setToast('Ready');
    els.barcodeInput.focus();
  }

  function stop() {
    if (els.appShell) els.appShell.hidden = true;
  }

  return { start, stop };
})();
