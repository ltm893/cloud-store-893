'use strict';

const fs = require('fs');
const path = require('path');
const { Pool } = require('pg');

/**
 * Apply schema + optional seed. Uses DATABASE_URL from env.
 * Safe to re-run (schema drops/recreates).
 */
async function main() {
  const databaseUrl = process.env.DATABASE_URL;
  if (!databaseUrl) {
    console.error('DATABASE_URL is required');
    process.exit(1);
  }

  const seed = process.env.MIGRATE_SEED !== 'false';
  const dir = __dirname;
  const files = ['001_schema.sql'];
  if (seed) files.push('002_seed.sql');

  const pool = new Pool({ connectionString: databaseUrl, ssl: sslOption() });
  const client = await pool.connect();
  try {
    for (const name of files) {
      const sqlPath = path.join(dir, name);
      const sql = fs.readFileSync(sqlPath, 'utf8');
      console.log(`Applying ${name}…`);
      await client.query(sql);
      console.log(`OK ${name}`);
    }
    console.log('Migration complete');
  } finally {
    client.release();
    await pool.end();
  }
}

function sslOption() {
  // Aurora requires TLS; local Compose does not.
  if (process.env.PGSSLMODE === 'disable' || process.env.DATABASE_SSL === 'false') {
    return false;
  }
  if (process.env.DATABASE_SSL === 'true' || /rds\.amazonaws\.com|amazonaws\.com/.test(process.env.DATABASE_URL || '')) {
    return { rejectUnauthorized: false };
  }
  return undefined;
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
