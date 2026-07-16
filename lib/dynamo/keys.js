'use strict';

/** Key helpers for the hybrid DynamoDB table (phase B + reserved phase A). */

function sessionPk(storeKey) {
  return `SESSION#${storeKey}`;
}

function sessionSk(sessionId) {
  return `id#${sessionId}`;
}

function cartPk(cartId) {
  return `CART#${cartId}`;
}

function cartItemSk(productId) {
  return `ITEM#${productId}`;
}

function cartMetaSk() {
  return 'META';
}

function productPk(productId) {
  return `PRODUCT#${productId}`;
}

function productBarcodePk(barcode) {
  return `PRODUCT#BARCODE#${barcode}`;
}

function productSk() {
  return 'META';
}

function eventPk(dayIso) {
  return `EVENT#${dayIso}`;
}

function eventSk(isoTs, id) {
  return `ts#${isoTs}#${id}`;
}

/** Reserved for phase A offline drain — do not use in phase B writes. */
function offlinePk(deviceId) {
  return `OFFLINE#${deviceId}`;
}

function offlineOrderSk(orderNumber) {
  return `ORDER#${orderNumber}`;
}

module.exports = {
  sessionPk,
  sessionSk,
  cartPk,
  cartItemSk,
  cartMetaSk,
  productPk,
  productBarcodePk,
  productSk,
  eventPk,
  eventSk,
  offlinePk,
  offlineOrderSk,
};
