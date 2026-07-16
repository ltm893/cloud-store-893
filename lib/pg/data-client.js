'use strict';

const { createOrdsClient } = require('../ords-client');
const { createPgOrdsClient } = require('./ords-shim');

/**
 * Select data client from DATA_BACKEND=ords|postgres|hybrid (default ords).
 * hybrid uses Postgres for ledger/inventory (same client) + Dynamo for cart/sessions/cache.
 * @returns {{ backend: string, client: object, hybrid: boolean }}
 */
function createDataClient(env = process.env) {
  const backend = String(env.DATA_BACKEND || 'ords').toLowerCase();

  if (backend === 'hybrid') {
    const connectionString = env.DATABASE_URL;
    if (!connectionString) {
      throw new Error('DATABASE_URL is required for DATA_BACKEND=hybrid');
    }
    if (!env.DYNAMODB_TABLE) {
      throw new Error('DYNAMODB_TABLE is required for DATA_BACKEND=hybrid');
    }
    const client = createPgOrdsClient({ connectionString });
    return { backend: 'hybrid', client, hybrid: true };
  }

  if (backend === 'postgres' || backend === 'pg' || backend === 'aurora') {
    const client = createPgOrdsClient({
      connectionString: env.DATABASE_URL,
    });
    return { backend: 'postgres', client, hybrid: false };
  }

  if (backend === 'ords' || backend === 'oracle') {
    const base = env.ORDS_BASE_URL;
    if (!base) {
      throw new Error('ORDS_BASE_URL is not set. Create a .env file — see .env.example');
    }
    return { backend: 'ords', client: createOrdsClient(base), hybrid: false };
  }

  throw new Error(`Unknown DATA_BACKEND=${backend} (expected ords|postgres|hybrid)`);
}

module.exports = { createDataClient };
