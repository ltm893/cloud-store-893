'use strict';

const {
  GetCommand,
  PutCommand,
  DeleteCommand,
  QueryCommand,
  BatchWriteCommand,
} = require('@aws-sdk/lib-dynamodb');
const { getDocClient, getTableName } = require('./client');
const { cartPk, cartItemSk, cartMetaSk } = require('./keys');

function table() {
  const name = getTableName();
  if (!name) throw new Error('DYNAMODB_TABLE is required for hybrid cart');
  return name;
}

/** Single shared cart id for credit-only web POS; tablets may pass registerId. */
function resolveCartId(req) {
  const registerId = String(req?.body?.registerId || req?.query?.registerId || '').trim();
  if (registerId) return registerId;
  const session = req?._cashierSession;
  if (session?.id) return `session:${session.id}`;
  const sid = req?._cashierSessionId;
  if (sid) return `session:${sid}`;
  return 'default';
}

async function listCartItems(cartId) {
  const res = await getDocClient().send(
    new QueryCommand({
      TableName: table(),
      KeyConditionExpression: 'pk = :pk AND begins_with(sk, :sk)',
      ExpressionAttributeValues: {
        ':pk': cartPk(cartId),
        ':sk': 'ITEM#',
      },
    }),
  );
  return (res.Items || []).map((it) => ({
    id: `${cartId}:${it.product_id}`,
    product_id: Number(it.product_id),
    quantity: Number(it.quantity),
  }));
}

async function getCartMeta(cartId) {
  const res = await getDocClient().send(
    new GetCommand({
      TableName: table(),
      Key: { pk: cartPk(cartId), sk: cartMetaSk() },
    }),
  );
  return res.Item || null;
}

async function putCartItem(cartId, productId, quantity) {
  await getDocClient().send(
    new PutCommand({
      TableName: table(),
      Item: {
        pk: cartPk(cartId),
        sk: cartItemSk(productId),
        product_id: Number(productId),
        quantity: Number(quantity),
      },
    }),
  );
}

async function deleteCartItem(cartId, productId) {
  await getDocClient().send(
    new DeleteCommand({
      TableName: table(),
      Key: { pk: cartPk(cartId), sk: cartItemSk(productId) },
    }),
  );
}

async function clearCart(cartId) {
  const res = await getDocClient().send(
    new QueryCommand({
      TableName: table(),
      KeyConditionExpression: 'pk = :pk',
      ExpressionAttributeValues: { ':pk': cartPk(cartId) },
    }),
  );
  const items = res.Items || [];
  if (!items.length) return;
  // BatchWrite max 25
  for (let i = 0; i < items.length; i += 25) {
    const chunk = items.slice(i, i + 25);
    await getDocClient().send(
      new BatchWriteCommand({
        RequestItems: {
          [table()]: chunk.map((it) => ({
            DeleteRequest: { Key: { pk: it.pk, sk: it.sk } },
          })),
        },
      }),
    );
  }
}

/**
 * Build cart_view-shaped rows by joining Dynamo cart lines with product map.
 * @param {Array} cartItems
 * @param {Map<number, object>} productsById
 */
function cartViewRows(cartItems, productsById) {
  const rows = [];
  for (const item of cartItems) {
    const p = productsById.get(Number(item.product_id));
    if (!p) continue;
    rows.push({
      id: item.id,
      product_id: Number(item.product_id),
      name: p.name,
      price: p.price,
      sale_price: p.sale_price,
      tax_exempt: p.tax_exempt,
      quantity: Number(item.quantity),
    });
  }
  return rows;
}

module.exports = {
  resolveCartId,
  listCartItems,
  getCartMeta,
  putCartItem,
  deleteCartItem,
  clearCart,
  cartViewRows,
};
