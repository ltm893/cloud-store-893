'use strict';

const { GetCommand, PutCommand } = require('@aws-sdk/lib-dynamodb');
const { getDocClient, getTableName } = require('./client');
const { productPk, productBarcodePk, productSk } = require('./keys');

const DEFAULT_TTL_SEC = 60;

function table() {
  const name = getTableName();
  if (!name) throw new Error('DYNAMODB_TABLE is required for hybrid product cache');
  return name;
}

function ttlEpoch(sec = DEFAULT_TTL_SEC) {
  return Math.floor(Date.now() / 1000) + sec;
}

async function putProduct(product) {
  const id = Number(product.id);
  const expiresAt = ttlEpoch();
  const item = {
    pk: productPk(id),
    sk: productSk(),
    product,
    expiresAt,
  };
  await getDocClient().send(new PutCommand({ TableName: table(), Item: item }));
  if (product.barcode) {
    await getDocClient().send(
      new PutCommand({
        TableName: table(),
        Item: {
          pk: productBarcodePk(String(product.barcode)),
          sk: productSk(),
          productId: id,
          expiresAt,
        },
      }),
    );
  }
}

async function putProducts(products) {
  for (const p of products) {
    await putProduct(p);
  }
}

async function getProductById(productId) {
  const res = await getDocClient().send(
    new GetCommand({
      TableName: table(),
      Key: { pk: productPk(productId), sk: productSk() },
    }),
  );
  return res.Item?.product || null;
}

async function getProductIdByBarcode(barcode) {
  const res = await getDocClient().send(
    new GetCommand({
      TableName: table(),
      Key: { pk: productBarcodePk(String(barcode)), sk: productSk() },
    }),
  );
  return res.Item?.productId != null ? Number(res.Item.productId) : null;
}

/**
 * List cached products via Query on PRODUCT# prefix is not possible (different PKs).
 * Cache is per-id; callers should fall back to Postgres for full catalog list.
 * This helper returns [] — list always loads from Postgres then warms cache.
 */
async function listCachedProductIds() {
  return [];
}

module.exports = {
  putProduct,
  putProducts,
  getProductById,
  getProductIdByBarcode,
  listCachedProductIds,
  DEFAULT_TTL_SEC,
};
