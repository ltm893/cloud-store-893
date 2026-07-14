'use strict';

const { createOrdsClient } = require('../ords-client');
const { createPgOrdsClient } = require('./ords-shim');

/**
 * Select data client from DATA_BACKEND=ords|postgres (default ords).
 * @returns {{ backend: string, client: object }}
 */
function createDataClient(env = process.env) {
  const backend = String(env.DATA_BACKEND || 'ords').toLowerCase();

  if (backend === 'postgres' || backend === 'pg' || backend === 'aurora') {
    const client = createPgOrdsClient({
      connectionString: env.DATABASE_URL,
    });
    return { backend: 'postgres', client };
  }

  if (backend === 'ords' || backend === 'oracle') {
    const base = env.ORDS_BASE_URL;
    if (!base) {
      throw new Error('ORDS_BASE_URL is not set. Create a .env file — see .env.example');
    }
    return { backend: 'ords', client: createOrdsClient(base) };
  }

  throw new Error(`Unknown DATA_BACKEND=${backend} (expected ords|postgres)`);
}

module.exports = { createDataClient };
