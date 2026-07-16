'use strict';

const crypto = require('crypto');
const { PutCommand } = require('@aws-sdk/lib-dynamodb');
const { getDocClient, getTableName } = require('./client');
const { eventPk, eventSk } = require('./keys');

const EVENT_TTL_DAYS = 14;

/**
 * Best-effort event append. Never throws to callers.
 * @param {string} type
 * @param {object} payload
 */
async function appendEvent(type, payload = {}) {
  try {
    const table = getTableName();
    if (!table) return;
    const now = new Date();
    const day = now.toISOString().slice(0, 10);
    const iso = now.toISOString().replace(/\.\d{3}Z$/, 'Z');
    const id = crypto.randomBytes(8).toString('hex');
    await getDocClient().send(
      new PutCommand({
        TableName: table,
        Item: {
          pk: eventPk(day),
          sk: eventSk(iso, id),
          type: String(type),
          payload,
          createdAt: iso,
          expiresAt: Math.floor(Date.now() / 1000) + EVENT_TTL_DAYS * 24 * 3600,
        },
      }),
    );
  } catch (err) {
    console.warn(`dynamo event log failed: ${err.message}`);
  }
}

module.exports = { appendEvent, EVENT_TTL_DAYS };
