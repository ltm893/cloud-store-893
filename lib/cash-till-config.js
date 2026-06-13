const CASH_MODE = {
  CASH_AND_CREDIT: 'cash_and_credit',
  CREDIT_ONLY: 'credit_only',
};

const DEFAULT_DENOMINATIONS = [
  { id: '100', label: '$100', value: 100 },
  { id: '50', label: '$50', value: 50 },
  { id: '20', label: '$20', value: 20 },
  { id: '10', label: '$10', value: 10 },
  { id: '5', label: '$5', value: 5 },
  { id: '1', label: '$1', value: 1 },
  { id: '0.50', label: 'Half Dollars', value: 0.5 },
  { id: '0.25', label: 'Quarters', value: 0.25 },
  { id: '0.10', label: 'Dimes', value: 0.1 },
  { id: '0.05', label: 'Nickels', value: 0.05 },
  { id: '0.01', label: 'Pennies', value: 0.01 },
];

function roundMoney(n) {
  return Math.round(Number(n) * 100) / 100;
}

function isCashTillConfigured() {
  const raw = String(process.env.OPENING_CASH_FLOAT ?? '').trim();
  if (!raw) return false;
  const value = Number(raw);
  return Number.isFinite(value) && value >= 0;
}

function getExpectedOpeningFloat() {
  if (!isCashTillConfigured()) return null;
  return roundMoney(process.env.OPENING_CASH_FLOAT);
}

function getDenominations() {
  const raw = String(process.env.CASH_TILL_DENOMINATIONS || '').trim();
  if (!raw) return DEFAULT_DENOMINATIONS;
  try {
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed) || parsed.length === 0) return DEFAULT_DENOMINATIONS;
    return parsed
      .map((row) => ({
        id: String(row.id ?? row.value ?? '').trim(),
        label: String(row.label || row.id || '').trim(),
        value: Number(row.value),
      }))
      .filter((row) => row.id && Number.isFinite(row.value) && row.value > 0);
  } catch {
    return DEFAULT_DENOMINATIONS;
  }
}

function sumDenominations(denominations, counts) {
  const denomById = new Map(denominations.map((row) => [row.id, row.value]));
  let total = 0;
  for (const [id, countRaw] of Object.entries(counts || {})) {
    const value = denomById.get(String(id));
    if (value == null) continue;
    const count = Number(countRaw);
    if (!Number.isFinite(count) || count < 0) continue;
    total += value * count;
  }
  return roundMoney(total);
}

function normalizeDenominationCounts(raw, denominations) {
  const allowed = new Set(denominations.map((row) => row.id));
  const counts = {};
  for (const [id, countRaw] of Object.entries(raw || {})) {
    const key = String(id).trim();
    if (!allowed.has(key)) continue;
    const count = Math.floor(Number(countRaw));
    if (!Number.isFinite(count) || count < 0) continue;
    if (count === 0) continue;
    counts[key] = count;
  }
  return counts;
}

function isCashEnabledForMode(cashMode) {
  return cashMode === CASH_MODE.CASH_AND_CREDIT;
}

function openingVariance(countedFloat, expectedFloat) {
  if (countedFloat == null || expectedFloat == null) return null;
  return roundMoney(countedFloat - expectedFloat);
}

function parseTillSubmit(body, denominations) {
  const cashMode = String(body?.cashMode || '').trim().toLowerCase();
  if (cashMode === CASH_MODE.CREDIT_ONLY) {
    return { cashMode: CASH_MODE.CREDIT_ONLY };
  }
  if (cashMode !== CASH_MODE.CASH_AND_CREDIT) {
    const err = new Error('cashMode must be cash_and_credit or credit_only');
    err.status = 400;
    throw err;
  }

  const counts = normalizeDenominationCounts(body?.denominations, denominations);
  const countedFromBody = body?.countedTotal == null ? null : roundMoney(body.countedTotal);
  const countedTotal = countedFromBody ?? sumDenominations(denominations, counts);
  if (!Number.isFinite(countedTotal) || countedTotal < 0) {
    const err = new Error('countedTotal must be zero or greater');
    err.status = 400;
    throw err;
  }

  const summed = sumDenominations(denominations, counts);
  if (Object.keys(counts).length > 0 && Math.abs(summed - countedTotal) > 0.009) {
    const err = new Error('countedTotal does not match denomination counts');
    err.status = 400;
    throw err;
  }

  const expected = getExpectedOpeningFloat();
  return {
    cashMode: CASH_MODE.CASH_AND_CREDIT,
    denominations: counts,
    countedTotal,
    expectedOpeningFloat: expected,
    openingVariance: openingVariance(countedTotal, expected),
  };
}

function tillConfigPayload() {
  return {
    cashTillEnabled: isCashTillConfigured(),
    expectedOpeningFloat: getExpectedOpeningFloat(),
    denominations: getDenominations(),
  };
}

function sessionAllowsCashPayments(session) {
  if (!isCashTillConfigured()) return true;
  return Boolean(session?.cashEnabled);
}

function tillFieldsForApproval(till) {
  if (!till) return {};
  if (till.cashMode === CASH_MODE.CREDIT_ONLY) {
    return {
      till_type: CASH_MODE.CREDIT_ONLY,
      expected_opening_float: null,
      opening_counted_float: null,
      opening_variance: null,
      opening_denominations: null,
    };
  }
  return {
    till_type: CASH_MODE.CASH_AND_CREDIT,
    expected_opening_float: till.expectedOpeningFloat,
    opening_counted_float: till.countedTotal,
    opening_variance: till.openingVariance,
    opening_denominations: JSON.stringify(till.denominations || {}),
  };
}

function tillFieldsFromApproval(approval) {
  if (!approval) {
    return {
      cashEnabled: !isCashTillConfigured(),
      cashTillEnabled: isCashTillConfigured(),
      expectedOpeningFloat: getExpectedOpeningFloat(),
      openingCountedFloat: null,
      cashMode: isCashTillConfigured() ? CASH_MODE.CREDIT_ONLY : null,
    };
  }
  const cashMode = approval.cashMode || approval.tillType || CASH_MODE.CREDIT_ONLY;
  return {
    cashEnabled: isCashEnabledForMode(cashMode),
    cashTillEnabled: isCashTillConfigured(),
    expectedOpeningFloat: approval.expectedOpeningFloat ?? getExpectedOpeningFloat(),
    openingCountedFloat: approval.openingCountedFloat ?? null,
    cashMode,
  };
}

module.exports = {
  CASH_MODE,
  DEFAULT_DENOMINATIONS,
  roundMoney,
  isCashTillConfigured,
  getExpectedOpeningFloat,
  getDenominations,
  sumDenominations,
  normalizeDenominationCounts,
  isCashEnabledForMode,
  openingVariance,
  parseTillSubmit,
  tillConfigPayload,
  sessionAllowsCashPayments,
  tillFieldsForApproval,
  tillFieldsFromApproval,
};
