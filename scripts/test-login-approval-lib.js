#!/usr/bin/env node
/**
 * Smoke-test lib/login-approval.js against live ORDS.
 *
 * Usage:
 *   node scripts/test-login-approval-lib.js
 *   ORDS_BASE_URL=... node scripts/test-login-approval-lib.js
 *
 * Creates a pending request, approves it, verifies terminal state, then exits.
 * Does not require the HTTP server to be running.
 */

require('dotenv').config({ quiet: true });

const { createLoginApprovalStore } = require('../lib/login-approval');

const ORDS_BASE = process.env.ORDS_BASE_URL;

if (!ORDS_BASE) {
  console.error('❌ ORDS_BASE_URL is not set (.env or env)');
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
    throw new Error(`ORDS POST ${path} → ${res.status}${detail ? `: ${detail}` : ''}`);
  }
  return res.json();
}

async function ordsPut(path, body) {
  const res = await fetch(`${ORDS_BASE}/${path}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    const detail = await res.text().catch(() => '');
    throw new Error(`ORDS PUT ${path} → ${res.status}${detail ? `: ${detail}` : ''}`);
  }
  return res.json();
}

function ordsTimestamp(date = new Date()) {
  return date.toISOString().replace(/\.\d{3}Z$/, 'Z');
}

async function main() {
  const store = createLoginApprovalStore({ ordsGet, ordsPost, ordsPut, ordsTimestamp });

  const cashierClaims = {
    sub: `test-cashier-${Date.now()}`,
    email: 'cashier.test@example.com',
    name: 'Test Cashier',
  };
  const supervisorClaims = {
    sub: `test-supervisor-${Date.now()}`,
    email: 'supervisor.test@example.com',
  };

  console.log('== login-approval store smoke test ==');
  console.log(`ORDS_BASE_URL=${ORDS_BASE}`);

  const created = await store.createRequest({
    claims: cashierClaims,
    registerId: 'test-register-1',
    clientKind: 'test',
  });
  console.log('OK   createRequest →', created.requestToken, created.status);

  const pending = await store.listPending();
  if (!pending.some((row) => row.requestToken === created.requestToken)) {
    throw new Error('listPending did not include created request');
  }
  console.log('OK   listPending includes new request (count=%d)', pending.length);

  const approved = await store.approve(created.requestToken, supervisorClaims);
  if (approved.status !== 'approved') {
    throw new Error(`approve expected approved, got ${approved.status}`);
  }
  console.log('OK   approve →', approved.status, 'by', approved.resolvedByEmail);

  const loaded = await store.findByToken(created.requestToken);
  if (loaded.status !== 'approved') {
    throw new Error(`findByToken expected approved, got ${loaded.status}`);
  }
  console.log('OK   findByToken →', loaded.status);

  console.log('== done ==');
}

main().catch((err) => {
  console.error('FAIL', err.message);
  process.exit(1);
});
