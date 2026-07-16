'use strict';

const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient } = require('@aws-sdk/lib-dynamodb');

let cached = null;

function getTableName(env = process.env) {
  return env.DYNAMODB_TABLE || '';
}

function getDocClient(env = process.env) {
  if (cached) return cached;
  const region = env.AWS_REGION || env.AWS_DEFAULT_REGION || 'us-east-1';
  const endpoint = env.DYNAMODB_ENDPOINT || undefined; // DynamoDB Local
  const client = new DynamoDBClient({
    region,
    ...(endpoint ? { endpoint, credentials: { accessKeyId: 'local', secretAccessKey: 'local' } } : {}),
  });
  cached = DynamoDBDocumentClient.from(client, {
    marshallOptions: { removeUndefinedValues: true },
  });
  return cached;
}

function resetDocClientForTests() {
  cached = null;
}

module.exports = { getDocClient, getTableName, resetDocClientForTests };
