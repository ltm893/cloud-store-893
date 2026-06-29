'use strict';

const ORDER_NUMBER_LENGTH = 7;
const ORDER_NUMBER_MAX = 10 ** ORDER_NUMBER_LENGTH - 1;
/** ORDS defaults to 25 rows per page; checkout must scan all sales for the max order number. */
const SALES_PAGE_SIZE = 500;

function formatOrderNumber(value) {
  const n = Number(value);
  if (!Number.isFinite(n) || n < 0 || n > ORDER_NUMBER_MAX) {
    throw new Error(`order number out of range (0–${ORDER_NUMBER_MAX})`);
  }
  return String(Math.trunc(n)).padStart(ORDER_NUMBER_LENGTH, '0');
}

function parseOrderNumber(raw) {
  const value = String(raw ?? '').trim();
  if (!value) {
    const err = new Error('order_number is required');
    err.status = 400;
    throw err;
  }
  if (!/^\d{7}$/.test(value)) {
    const err = new Error('order_number must be exactly 7 digits');
    err.status = 400;
    throw err;
  }
  return value;
}

function orderNumberFromRow(row) {
  const digits = String(row?.order_number ?? '').replace(/\D/g, '');
  if (!digits) return null;
  const n = Number(digits);
  return Number.isFinite(n) && n >= 0 && n <= ORDER_NUMBER_MAX ? n : null;
}

async function maxOrderNumberFromSales(ordsGet) {
  let maxNum = 0;
  let offset = 0;
  while (true) {
    const rows = await ordsGet(`sales/?limit=${SALES_PAGE_SIZE}&offset=${offset}`);
    const batch = Array.isArray(rows) ? rows : [];
    for (const sale of batch) {
      const n = orderNumberFromRow(sale);
      if (n != null && n > maxNum) maxNum = n;
    }
    if (batch.length < SALES_PAGE_SIZE) break;
    offset += SALES_PAGE_SIZE;
  }
  return maxNum;
}

/**
 * Next sequential 7-digit order number (0000001 … 9999999).
 * @param {{ ordsGet: Function }} helpers
 */
async function allocateOrderNumber({ ordsGet }) {
  const maxNum = await maxOrderNumberFromSales(ordsGet);
  const next = maxNum + 1;
  if (next > ORDER_NUMBER_MAX) {
    throw new Error('Order number space exhausted');
  }
  return formatOrderNumber(next);
}

function isDuplicateOrderNumberError(err) {
  const msg = String(err?.message || err);
  return /unique|duplicate|ORA-00001|23505/i.test(msg);
}

module.exports = {
  ORDER_NUMBER_LENGTH,
  ORDER_NUMBER_MAX,
  formatOrderNumber,
  parseOrderNumber,
  orderNumberFromRow,
  allocateOrderNumber,
  isDuplicateOrderNumberError,
};
