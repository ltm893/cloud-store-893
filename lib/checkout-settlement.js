const {
  roundMoney,
  computeRegisterTotalFromLines,
  computeCollectedTotal,
  remainingCashAmountDue,
} = require('./pos-pricing');

function normalizePaymentMethod(method) {
  const normalized = String(method || 'card').trim().toLowerCase();
  return normalized || 'card';
}

function parseCheckoutPayments(rawPayments) {
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

  return { payments };
}

/**
 * Resolve register total, nickel cash due, and collected total for checkout.
 */
function resolveCheckoutSettlement({
  cartItems,
  paymentMethod,
  rawPayments,
  clientCheckoutTotal,
  salesFeeRate,
  taxRate,
}) {
  if (!Array.isArray(cartItems) || cartItems.length === 0) {
    return { error: 'cartItems must be a non-empty array' };
  }
  const registerTotal = computeRegisterTotalFromLines(cartItems, salesFeeRate, taxRate);
  const collectedTotal = computeCollectedTotal(registerTotal);

  if (clientCheckoutTotal != null) {
    const normalizedClientTotal = roundMoney(clientCheckoutTotal);
    if (!Number.isFinite(normalizedClientTotal) || normalizedClientTotal <= 0) {
      return { error: 'checkoutTotal must be greater than zero' };
    }
    const matchesRegister = Math.abs(normalizedClientTotal - registerTotal) <= 0.02;
    const matchesCollected = Math.abs(normalizedClientTotal - collectedTotal) <= 0.009;
    if (!matchesRegister && !matchesCollected) {
      return {
        error: `checkoutTotal must match register total ${registerTotal.toFixed(2)} or collected ${collectedTotal.toFixed(2)}`,
      };
    }
  }

  if (rawPayments != null) {
    const parsed = parseCheckoutPayments(rawPayments);
    if (parsed.error) return parsed;

    const payments = parsed.payments;
    const cardTotal = roundMoney(
      payments.filter((p) => p.method === 'card').reduce((sum, p) => sum + p.amount, 0),
    );
    const cashTotal = roundMoney(
      payments.filter((p) => p.method === 'cash').reduce((sum, p) => sum + p.amount, 0),
    );
    const hasCash = cashTotal > 0.005;
    const hasCard = cardTotal > 0.005;

    let expectedRecorded;
    let cashDue = null;

    if (hasCash && !hasCard) {
      expectedRecorded = collectedTotal;
      cashDue = collectedTotal;
    } else if (hasCard && !hasCash) {
      expectedRecorded = collectedTotal;
    } else if (hasCash && hasCard) {
      cashDue = remainingCashAmountDue(registerTotal, cardTotal);
      expectedRecorded = roundMoney(cardTotal + cashDue);
    } else {
      return { error: 'payments must include at least one tender' };
    }

    const totalPaid = roundMoney(payments.reduce((sum, p) => sum + p.amount, 0));
    if (Math.abs(totalPaid - expectedRecorded) > 0.009) {
      return {
        error: `Split payments must equal total ${expectedRecorded.toFixed(2)}`,
      };
    }

    return {
      registerTotal,
      cashDue,
      recordedTotal: expectedRecorded,
      payments,
    };
  }

  const method = normalizePaymentMethod(paymentMethod);
  if (method === 'cash') {
    return {
      registerTotal,
      cashDue: collectedTotal,
      recordedTotal: collectedTotal,
      payments: [
        {
          method: 'cash',
          amount: collectedTotal,
          tenderedAmount: collectedTotal,
          changeGiven: null,
        },
      ],
    };
  }

  if (method === 'card') {
    return {
      registerTotal,
      cashDue: null,
      recordedTotal: collectedTotal,
      payments: [
        {
          method: 'card',
          amount: collectedTotal,
          tenderedAmount: collectedTotal,
          changeGiven: null,
        },
      ],
    };
  }

  return { error: `Unsupported payment method: ${method}` };
}

module.exports = {
  normalizePaymentMethod,
  parseCheckoutPayments,
  resolveCheckoutSettlement,
};
