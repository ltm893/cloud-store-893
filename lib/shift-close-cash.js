function roundMoney(n) {
  return Math.round(Number(n) * 100) / 100;
}

function parseCloseDenominations(raw) {
  if (!raw) return null;
  if (typeof raw === 'object') return raw;
  try {
    return JSON.parse(String(raw));
  } catch {
    return null;
  }
}

/**
 * @param {{ ordsGet: Function }} helpers
 */
function createShiftCloseCash(helpers) {
  const { ordsGet } = helpers;

  async function listSalesForTill(tillId) {
    const sales = await ordsGet(
      `sales/?q=${encodeURIComponent(JSON.stringify({ till_id: { $eq: Number(tillId) } }))}`,
    );
    return Array.isArray(sales) ? sales : [];
  }

  async function listSalePaymentsForTill(tillId) {
    const sales = await listSalesForTill(tillId);
    const payments = [];
    for (const sale of sales) {
      const orderNumber = sale?.order_number;
      if (!orderNumber) continue;
      const payRows = await ordsGet(
        `sale_payments/?q=${encodeURIComponent(JSON.stringify({ order_number: { $eq: orderNumber } }))}`,
      );
      if (Array.isArray(payRows)) payments.push(...payRows);
    }
    return payments;
  }

  async function summarizeTillSales(tillId) {
    const payments = await listSalePaymentsForTill(tillId);
    let cashTotal = 0;
    let creditTotal = 0;
    for (const payment of payments) {
      const amount = Number(payment?.amount) || 0;
      const method = String(payment.payment_method || '').toLowerCase();
      if (method === 'cash') cashTotal += amount;
      else if (method === 'card') creditTotal += amount;
    }
    return {
      cashTotal: roundMoney(cashTotal),
      creditTotal: roundMoney(creditTotal),
    };
  }

  async function computeExpectedClose(till) {
    const tillId = Number(till?.id);
    if (!Number.isFinite(tillId) || tillId <= 0) {
      const err = new Error('Till is required to compute expected close');
      err.status = 400;
      throw err;
    }

    const opening = till.openingCountedFloat == null ? 0 : Number(till.openingCountedFloat);
    const payments = await listSalePaymentsForTill(tillId);
    let cashSalesTotal = 0;
    let changeGivenTotal = 0;
    for (const payment of payments) {
      if (String(payment.payment_method || '').toLowerCase() !== 'cash') continue;
      cashSalesTotal += Number(payment.amount) || 0;
      changeGivenTotal += Number(payment.change_given) || 0;
    }
    cashSalesTotal = roundMoney(cashSalesTotal);
    changeGivenTotal = roundMoney(changeGivenTotal);
    const expectedClose = roundMoney(opening + cashSalesTotal - changeGivenTotal);

    return {
      openingCountedFloat: roundMoney(opening),
      cashSalesTotal,
      changeGivenTotal,
      expectedClose,
    };
  }

  function closeVariance(countedClose, expectedClose) {
    if (countedClose == null || expectedClose == null) return null;
    return roundMoney(countedClose - expectedClose);
  }

  return {
    computeExpectedClose,
    closeVariance,
    parseCloseDenominations,
    summarizeTillSales,
    listSalesForTill,
    listSalePaymentsForTill,
  };
}

module.exports = {
  createShiftCloseCash,
};
