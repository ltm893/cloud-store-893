#!/usr/bin/env node
/**
 * Create a pending login approval row and print requestToken to stdout.
 * Used by scripts/test-supervisor-routes.sh
 */

require('dotenv').config({ quiet: true });

const { createLoginApprovalStore } = require('../lib/login-approval');

const ORDS_BASE = process.env.ORDS_BASE_URL;
if (!ORDS_BASE) {
  console.error('ORDS_BASE_URL is not set');
  process.exit(1);
}

async function ordsGet(path) {
  const res = await fetch(`${ORDS_BASE}/${path}`);
  if (!res.ok) throw new Error(`ORDS GET ${path} → ${res.status}`);
  const data = await res.json();
  return Array.isArray(data.items) ? data.items : data;
}

async function ordsPost(path, body) {
  const res = await fetch(`${ORDS_BASE}/${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const detail = await res.text().catch(() => '');
    throw new Error(`ORDS POST ${path} → ${res.status}${detail ? `: ${detail.slice(0, 200)}` : ''}`);
  }
  return res.json();
}

async function ordsPut(path, body) {
  const res = await fetch(`${ORDS_BASE}/${path}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`ORDS PUT ${path} → ${res.status}`);
  return res.json();
}

function ordsTimestamp(date = new Date()) {
  return date.toISOString().replace(/\.\d{3}Z$/, 'Z');
}

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
