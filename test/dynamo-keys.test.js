'use strict';

const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const keys = require('../lib/dynamo/keys');

describe('dynamo keys', () => {
  it('builds session keys', () => {
    assert.equal(keys.sessionPk('cashier'), 'SESSION#cashier');
    assert.equal(keys.sessionSk('abc'), 'id#abc');
  });

  it('builds cart keys', () => {
    assert.equal(keys.cartPk('reg-1'), 'CART#reg-1');
    assert.equal(keys.cartItemSk(42), 'ITEM#42');
    assert.equal(keys.cartMetaSk(), 'META');
  });

  it('builds product and event keys', () => {
    assert.equal(keys.productPk(7), 'PRODUCT#7');
    assert.equal(keys.productBarcodePk('872'), 'PRODUCT#BARCODE#872');
    assert.equal(keys.eventPk('2026-07-15'), 'EVENT#2026-07-15');
  });

  it('reserves offline keys for phase A', () => {
    assert.equal(keys.offlinePk('device-1'), 'OFFLINE#device-1');
    assert.equal(keys.offlineOrderSk('0000001'), 'ORDER#0000001');
  });
});
