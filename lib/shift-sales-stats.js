function roundMoney(n) {
  return Math.round(Number(n) * 100) / 100;
}

/**
 * @param {{ ordsGet: Function }} helpers
 */
function createTillSalesStats(helpers) {
  const { ordsGet } = helpers;

  async function listSalesForTill(tillId) {
    const id = Number(tillId);
    if (!Number.isFinite(id) || id <= 0) return [];
    const sales = await ordsGet(
      `sales/?q=${encodeURIComponent(JSON.stringify({ till_id: { $eq: id } }))}`,
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
    return { sales, payments };
  }

  function summarizeTillSales({ sales, payments }) {
    const salesList = Array.isArray(sales) ? sales : [];
    const paymentsList = Array.isArray(payments) ? payments : [];
    let salesTotal = 0;
    for (const sale of salesList) {
      salesTotal += Number(sale?.total) || 0;
    }
    let cashTotal = 0;
    let creditTotal = 0;
    for (const payment of paymentsList) {
      const amount = Number(payment?.amount) || 0;
      const method = String(payment.payment_method || '').toLowerCase();
      if (method === 'cash') cashTotal += amount;
      else if (method === 'card') creditTotal += amount;
    }
    return {
      transaction_count: salesList.length,
      sales_total: roundMoney(salesTotal),
      cash_total: roundMoney(cashTotal),
      credit_total: roundMoney(creditTotal),
    };
  }

  async function statsForTill(tillId) {
    const data = await listSalePaymentsForTill(tillId);
    return summarizeTillSales(data);
  }

  async function attachStatsToTills(tills) {
    const list = Array.isArray(tills) ? tills : [];
    return Promise.all(
      list.map(async (till) => {
        const stats = await statsForTill(till?.id);
        return { ...till, ...stats };
      }),
    );
  }

  return {
    listSalesForTill,
    listSalePaymentsForTill,
    summarizeTillSales,
    statsForTill,
    attachStatsToTills,
    attachStatsToShifts: attachStatsToTills,
    statsForShift: statsForTill,
    summarizeTillSales,
    summarizeShiftSales: summarizeTillSales,
  };
}

module.exports = {
  createTillSalesStats,
  createShiftSalesStats: createTillSalesStats,
};
