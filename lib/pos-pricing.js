function roundMoney(n) {
  return Math.round(Number(n) * 100) / 100;
}

/** Cash: round down to nearest $0.05 (no pennies). */
function roundToNickel(amount) {
  return roundMoney(Math.floor(Number(amount) * 20) / 20);
}

function readPosRate(envValue, fallback) {
  if (envValue == null || String(envValue).trim() === '') return fallback;
  const n = Number(envValue);
  return Number.isFinite(n) ? n : fallback;
}

function posRatesFromEnv(env = process.env) {
  return {
    salesFeeRate: readPosRate(env.POS_SALES_FEE_RATE, 0),
    taxRate: readPosRate(env.POS_TAX_RATE, 0.06),
  };
}

function computeRegisterTotal(subtotalPayable, salesFeeRate, taxRate) {
  const preTax = roundMoney(subtotalPayable);
  const salesFee = preTax * salesFeeRate;
  const taxable = preTax + salesFee;
  const taxAmt = taxable * taxRate;
  return roundMoney(taxable + taxAmt);
}

function computeCashAmountDue(registerTotal) {
  return roundToNickel(registerTotal);
}

/** Tax-inclusive total collected at checkout (nickel-rounded for all payment methods). */
function computeCollectedTotal(registerTotal) {
  return computeCashAmountDue(registerTotal);
}

function remainingCashAmountDue(registerTotal, nonCashPaid) {
  const collected = computeCollectedTotal(registerTotal);
  const remaining = roundMoney(Math.max(0, collected - nonCashPaid));
  return roundToNickel(remaining);
}

module.exports = {
  roundMoney,
  roundToNickel,
  readPosRate,
  posRatesFromEnv,
  computeRegisterTotal,
  computeCashAmountDue,
  computeCollectedTotal,
  remainingCashAmountDue,
};
