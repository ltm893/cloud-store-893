'use strict';

const crypto = require('crypto');
const { GetCommand, PutCommand, DeleteCommand, QueryCommand } = require('@aws-sdk/lib-dynamodb');
const { getDocClient, getTableName } = require('./client');
const { sessionPk, sessionSk } = require('./keys');

/**
 * Dynamo-backed session map compatible with createSessionStore API (async methods).
 * @param {{ storeKey: string, sessionMs: number }} options
 */
function createDynamoSessionBackend({ storeKey, sessionMs }) {
  const table = () => {
    const name = getTableName();
    if (!name) throw new Error('DYNAMODB_TABLE is required for SESSION_BACKEND=dynamo');
    return name;
  };

  function ttlEpochSeconds(createdMs = Date.now()) {
    return Math.floor((createdMs + sessionMs) / 1000);
  }

  async function createSession(meta = {}) {
    const id = crypto.randomBytes(24).toString('hex');
    const created = Date.now();
    const entry = { created, auth: 'pin', ...meta };
    await getDocClient().send(
      new PutCommand({
        TableName: table(),
        Item: {
          pk: sessionPk(storeKey),
          sk: sessionSk(id),
          entry,
          expiresAt: ttlEpochSeconds(created),
        },
      }),
    );
    return id;
  }

  async function getSession(sessionId) {
    if (!sessionId) return null;
    const res = await getDocClient().send(
      new GetCommand({
        TableName: table(),
        Key: { pk: sessionPk(storeKey), sk: sessionSk(sessionId) },
      }),
    );
    const item = res.Item;
    if (!item?.entry) return null;
    if (Date.now() - Number(item.entry.created) > sessionMs) {
      await deleteSession(sessionId);
      return null;
    }
    return item.entry;
  }

  async function isValidSession(id) {
    return (await getSession(id)) != null;
  }

  async function deleteSession(sessionId) {
    if (!sessionId) return;
    await getDocClient().send(
      new DeleteCommand({
        TableName: table(),
        Key: { pk: sessionPk(storeKey), sk: sessionSk(sessionId) },
      }),
    );
  }

  async function updateSession(sessionId, entry) {
    if (!sessionId || !entry) return;
    const created = Number(entry.created) || Date.now();
    await getDocClient().send(
      new PutCommand({
        TableName: table(),
        Item: {
          pk: sessionPk(storeKey),
          sk: sessionSk(sessionId),
          entry,
          expiresAt: ttlEpochSeconds(created),
        },
      }),
    );
  }

  async function listSessions() {
    const res = await getDocClient().send(
      new QueryCommand({
        TableName: table(),
        KeyConditionExpression: 'pk = :pk',
        ExpressionAttributeValues: { ':pk': sessionPk(storeKey) },
      }),
    );
    return res.Items || [];
  }

  return {
    createSession,
    getSession,
    isValidSession,
    deleteSession,
    updateSession,
    listSessions,
    touchSessions() {},
    /** memory Map shim — empty; dynamo is source of truth */
    sessions: new Map(),
  };
}

module.exports = { createDynamoSessionBackend };
