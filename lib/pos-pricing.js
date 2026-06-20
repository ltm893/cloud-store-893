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

/** @typedef {{ lineSubtotalPayable: number, taxExempt?: boolean }} PricedCartLine */

function taxableSubtotalPayable(lines) {
  return roundMoney(
    lines
      .filter((it) => !it.taxExempt)
      .reduce((sum, it) => sum + Number(it.lineSubtotalPayable), 0),
  );
}

function computeTaxAmountFromLines(lines, salesFeeRate, taxRate) {
  const taxablePreTax = taxableSubtotalPayable(lines);
  const salesFee = taxablePreTax * salesFeeRate;
  const taxBase = taxablePreTax + salesFee;
  return roundMoney(taxBase * taxRate);
}

function computeRegisterTotalFromLines(lines, salesFeeRate, taxRate) {
  const preTax = roundMoney(
    lines.reduce((sum, it) => sum + Number(it.lineSubtotalPayable), 0),
  );
  const taxablePreTax = taxableSubtotalPayable(lines);
  const nonTaxablePreTax = roundMoney(preTax - taxablePreTax);
  const salesFee = taxablePreTax * salesFeeRate;
  const taxBase = taxablePreTax + salesFee;
  const taxAmt = taxBase * taxRate;
  return roundMoney(nonTaxablePreTax + taxBase + taxAmt);
}

/** All-taxable shorthand (tests and legacy callers). */
function computeRegisterTotal(subtotalPayable, salesFeeRate, taxRate) {
  return computeRegisterTotalFromLines(
    [{ lineSubtotalPayable: subtotalPayable, taxExempt: false }],
    salesFeeRate,
    taxRate,
  );
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
  taxableSubtotalPayable,
  computeTaxAmountFromLines,
  computeRegisterTotalFromLines,
  computeRegisterTotal,
  computeCashAmountDue,
  computeCollectedTotal,
  remainingCashAmountDue,
};
