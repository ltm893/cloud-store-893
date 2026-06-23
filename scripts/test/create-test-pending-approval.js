#!/usr/bin/env node
/**
 * Create a pending login approval row and print requestToken to stdout.
 * Used by scripts/test-supervisor-routes.sh
 */

require('dotenv').config({ quiet: true });

const { createOrdsClient } = require('../lib/ords-client');
const { createLoginApprovalStore } = require('../lib/login-approval');

const ORDS_BASE = process.env.ORDS_BASE_URL;
if (!ORDS_BASE) {
  console.error('ORDS_BASE_URL is not set');
  process.exit(1);
}

const { ordsGet, ordsPost, ordsPut, ordsTimestamp } = createOrdsClient(ORDS_BASE);

async function main() {
  const store = createLoginApprovalStore({ ordsGet, ordsPost, ordsPut, ordsTimestamp });
  const created = await store.createRequest({
    claims: {
      sub: `route-test-cashier-${Date.now()}`,
      email: 'route.test.cashier@example.com',
      name: 'Route Test Cashier',
    },
    registerId: 'route-test-register',
    clientKind: 'test',
  });
  process.stdout.write(created.requestToken);
}

main().catch((err) => {
  console.error(err.message);
  process.exit(1);
});
