/** Browser POS pricing + checkout math (mirrors lib/pos-pricing.js and Android domain). */
const PosMath = (() => {
  function roundMoney(n) {
    return Math.round(Number(n) * 100) / 100;
  }

  function roundToNickel(amount) {
    return roundMoney(Math.floor(Number(amount) * 20) / 20);
  }

  function formatMoney(amount) {
    return `$${roundMoney(amount).toFixed(2)}`;
  }

  function taxableSubtotalPayable(lines) {
    return roundMoney(
      lines
        .filter((it) => !it.taxExempt)
        .reduce((sum, it) => sum + Number(it.lineSubtotalPayable), 0),
    );
  }

  function computeTaxAmount(cart, customerLinked, customerDiscount, salesFeeRate, taxRate) {
    const items = customerLinked ? normalizeCartItems(cart, customerDiscount) : cart;
    const taxablePreTax = taxableSubtotalPayable(items);
    const salesFee = taxablePreTax * salesFeeRate;
    const taxBase = taxablePreTax + salesFee;
    return roundMoney(taxBase * taxRate);
  }

  function computeSaleSavings(cart) {
    const raw = cart
      .filter((it) => it.onSale && it.salePrice != null)
      .reduce((sum, item) => {
        return sum + roundMoney(item.regularPrice) * item.quantity - item.lineSubtotalPublic;
      }, 0);
    return roundMoney(Math.max(0, raw));
  }

  function normalizeCartItems(items, customerDiscount) {
    if (customerDiscount) return items;
    return items.map((item) => {
      if (Math.abs(item.lineSubtotalPayable - item.lineSubtotalPublic) <= 0.005) {
        return item;
      }
      const qty = Number(item.quantity) || 1;
      return {
        ...item,
        unitPricePayable: item.unitPricePublic,
        lineSubtotalPayable: roundMoney(item.unitPricePublic * qty),
      };
    });
  }

  function computeCartTotals(cart, customerDiscount) {
    const shelf = cart.reduce((s, it) => s + Number(it.lineSubtotalPublic), 0);
    const preTax = customerDiscount
      ? cart.reduce((s, it) => s + Number(it.lineSubtotalPayable), 0)
      : shelf;
    const discount = customerDiscount ? roundMoney(shelf - preTax) : 0;
    return {
      itemCount: cart.reduce((s, it) => s + Number(it.quantity), 0),
      shelfSubtotal: roundMoney(shelf),
      itemPreTax: roundMoney(preTax),
      memberDiscount: discount,
      saleSavings: computeSaleSavings(cart),
      linked893: customerDiscount,
      showDiscount: customerDiscount && discount > 0.005,
    };
  }

  function computeSaleGrandTotal(cart, customerLinked, customerDiscount, salesFeeRate, taxRate) {
    const items = customerLinked ? normalizeCartItems(cart, customerDiscount) : cart;
    const totals = computeCartTotals(items, customerLinked && customerDiscount);
    const taxablePreTax = taxableSubtotalPayable(items);
    const nonTaxablePreTax = roundMoney(totals.itemPreTax - taxablePreTax);
    const salesFee = taxablePreTax * salesFeeRate;
    const taxBase = taxablePreTax + salesFee;
    const taxAmt = taxBase * taxRate;
    return roundMoney(nonTaxablePreTax + taxBase + taxAmt);
  }

  function collectedTotal(registerTotal) {
    return roundToNickel(registerTotal);
  }

  function remainingCashAmountDue(registerTotal, nonCashPaid) {
    const collected = collectedTotal(registerTotal);
    return roundToNickel(roundMoney(Math.max(0, collected - nonCashPaid)));
  }

  function cashQuickDenominations(amountDue, cashEnabled = true) {
    if (!cashEnabled || amountDue <= 0.005) return [];
    const bills = [5, 10, 20, 50, 100];
    const start = bills.findIndex((b) => b >= amountDue - 0.001);
    if (start >= 0) return bills.slice(start, start + 3);
    const base = Math.ceil(amountDue / 10) * 10;
    return [base, base + 10, base + 20];
  }

  function paymentMethodLabel(method) {
    if (method === 'card') return 'Card';
    if (method === 'cash') return 'Cash';
    if (method === 'split') return 'Split';
    return method;
  }

  function normalizeCashEntryInput(raw) {
    const trimmed = String(raw || '').trim();
    if (!trimmed) return '0';
    if (trimmed === '.') return '0.';
    if (trimmed.includes('.')) {
      const parts = trimmed.split('.', 2);
      const whole = parts[0].replace(/^0+/, '') || '0';
      const frac = parts[1] || '';
      return frac === '' ? `${whole}.` : `${whole}.${frac}`;
    }
    return trimmed.replace(/^0+/, '') || '0';
  }

  function appendCashDigit(current, digit) {
    const base = normalizeCashEntryInput(current || '0');
    if (digit === '.') {
      if (base.includes('.')) return base;
      return base === '0' ? '0.' : `${base}.`;
    }
    if (base.includes('.')) {
      const frac = base.split('.')[1] || '';
      if (frac.length >= 2) return base;
      return normalizeCashEntryInput(`${base}${digit}`);
    }
    if (base === '0') return digit === '0' ? '0' : String(digit);
    if (base.length >= 7) return base;
    return normalizeCashEntryInput(base + digit);
  }

  function appendCashDigitLimited(current, digit, maxAmount) {
    const next = appendCashDigit(current, digit);
    if (maxAmount == null || maxAmount <= 0.005) return next;
    const parsed = parseCashTendered(next);
    if (parsed != null && parsed > maxAmount + 0.005) {
      return normalizeCashEntryInput(current || '0');
    }
    return next;
  }

  function backspaceCashEntry(current) {
    const base = String(current || '').trim() || '0';
    if (base.length <= 1) return '0';
    return normalizeCashEntryInput(base.slice(0, -1));
  }

  function parseCashTendered(raw) {
    const trimmed = String(raw || '').trim();
    if (!trimmed || trimmed === '.' || trimmed === '0') return null;
    const n = Number(trimmed);
    return Number.isFinite(n) ? n : null;
  }

  function displayCashEntry(raw) {
    const trimmed = String(raw || '').trim();
    if (!trimmed || trimmed === '.') return '—';
    return `$${normalizeCashEntryInput(trimmed)}`;
  }

  function checkoutChangeTotal(payments) {
    return roundMoney(
      payments.reduce((sum, p) => sum + Number(p.changeGiven || 0), 0),
    );
  }

  function exactBalanceDue(registerTotal, payments) {
    const paid = roundMoney(payments.reduce((sum, p) => sum + Number(p.amount), 0));
    return roundMoney(Math.max(0, collectedTotal(registerTotal) - paid));
  }

  function cashBalanceDue(registerTotal, payments) {
    const cardPaid = roundMoney(
      payments.filter((p) => p.method === 'card').reduce((s, p) => s + Number(p.amount), 0),
    );
    const cashPaid = roundMoney(
      payments.filter((p) => p.method === 'cash').reduce((s, p) => s + Number(p.amount), 0),
    );
    const cashDue = remainingCashAmountDue(registerTotal, cardPaid);
    return roundMoney(Math.max(0, cashDue - cashPaid));
  }

  function balanceDueForMethod(registerTotal, payments) {
    return roundToNickel(exactBalanceDue(registerTotal, payments));
  }

  function isCheckoutComplete(registerTotal, payments) {
    const paid = roundMoney(payments.reduce((sum, p) => sum + Number(p.amount), 0));
    return paid + 0.005 >= collectedTotal(registerTotal);
  }

  function buildCheckoutPaymentLine(method, enteredAmount, balanceDue) {
    if (enteredAmount <= 0 || balanceDue <= 0.005) return null;
    if (method === 'card' && enteredAmount > balanceDue + 0.005) return null;
    const appliedAmount = roundMoney(
      method === 'cash' ? Math.min(enteredAmount, balanceDue) : enteredAmount,
    );
    if (appliedAmount <= 0) return null;
    const changeGiven =
      method === 'cash' ? roundMoney(Math.max(0, enteredAmount - balanceDue)) : 0;
    return {
      method,
      amount: appliedAmount,
      tenderedAmount: enteredAmount,
      changeGiven: changeGiven > 0.005 ? changeGiven : null,
    };
  }

  function checkoutFinalizeMethod(payments) {
    return payments.length === 1 ? payments[0].method : 'split';
  }

  return {
    roundMoney,
    roundToNickel,
    formatMoney,
    computeTaxAmount,
    computeCartTotals,
    computeSaleGrandTotal,
    collectedTotal,
    remainingCashAmountDue,
    cashQuickDenominations,
    paymentMethodLabel,
    normalizeCashEntryInput,
    appendCashDigit,
    appendCashDigitLimited,
    backspaceCashEntry,
    parseCashTendered,
    displayCashEntry,
    checkoutChangeTotal,
    exactBalanceDue,
    cashBalanceDue,
    balanceDueForMethod,
    isCheckoutComplete,
    buildCheckoutPaymentLine,
    checkoutFinalizeMethod,
  };
})();
