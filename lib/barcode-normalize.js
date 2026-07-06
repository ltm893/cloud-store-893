'use strict';

/**
 * EAN-13 check digit for the first 12 data digits.
 * @param {string} data12
 * @returns {string|null}
 */
function ean13CheckDigit(data12) {
  const digits = String(data12 || '').replace(/\D/g, '');
  if (digits.length !== 12) return null;
  let sum = 0;
  for (let i = 0; i < 12; i += 1) {
    const n = Number(digits[i]);
    if (!Number.isFinite(n)) return null;
    sum += i % 2 === 0 ? n : n * 3;
  }
  return String((10 - (sum % 10)) % 10);
}

/**
 * Alternate barcode strings to try when a scanner and catalog disagree on
 * check digits or UPC-A vs EAN-13 padding.
 * @param {string} raw
 * @returns {string[]}
 */
function barcodeLookupCandidates(raw) {
  const value = String(raw || '').trim();
  if (!value) return [];
  if (!/^\d+$/.test(value)) return [value];

  const candidates = [];
  const add = (code) => {
    if (code && !candidates.includes(code)) candidates.push(code);
  };

  add(value);

  if (value.length === 13) {
    add(value.slice(0, 12));
    if (value.startsWith('0')) {
      add(value.slice(1));
    }
  }

  if (value.length === 12) {
    const check = ean13CheckDigit(value);
    if (check) add(value + check);
    add(`0${value}`);
  }

  if (value.length === 11) {
    const padded = value.padStart(12, '0');
    const check = ean13CheckDigit(padded);
    if (check) add(padded + check);
    add(padded);
  }

  return candidates;
}

module.exports = {
  ean13CheckDigit,
  barcodeLookupCandidates,
};
