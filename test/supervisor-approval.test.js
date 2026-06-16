'use strict';

const { test, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const { isSupervisorApprovalEnabled } = require('../lib/login-approval');
const { sessionStatusPayload } = require('../lib/cashier-auth');
const { createAwaitingTill } = require('../lib/awaiting-till-store');

const APPROVAL_KEY = 'CASHIER_SUPERVISOR_APPROVAL';
const PIN_KEY = 'IDP_ALLOW_PIN';
const IDP_KEYS = ['IDP_POS_ISSUER', 'IDP_POS_CLIENT_ID', 'IDP_POS_CLIENT_SECRET'];

const saved = {};

function saveEnv(keys) {
  for (const key of keys) {
    saved[key] = process.env[key];
  }
}

function restoreEnv(keys) {
  for (const key of keys) {
    if (saved[key] === undefined) delete process.env[key];
    else process.env[key] = saved[key];
  }
}

afterEach(() => {
  restoreEnv([APPROVAL_KEY, PIN_KEY, ...IDP_KEYS]);
});

function mockReq(cookieHeader) {
  return { headers: cookieHeader ? { cookie: cookieHeader } : {} };
}

function mockRes() {
  const headers = {};
  return {
    headers,
    setHeader(name, value) {
      headers[name] = value;
    },
    appendHeader(name, value) {
      const prev = headers[name];
      if (prev === undefined) {
        headers[name] = value;
        return;
      }
      headers[name] = Array.isArray(prev) ? [...prev, value] : [prev, value];
    },
  };
}

function enablePosIdp() {
  saveEnv(IDP_KEYS);
  process.env.IDP_POS_ISSUER = 'https://idp.example.com';
  process.env.IDP_POS_CLIENT_ID = 'pos-client';
  process.env.IDP_POS_CLIENT_SECRET = 'pos-secret';
}

test('isSupervisorApprovalEnabled is false by default', () => {
  delete process.env[APPROVAL_KEY];
  assert.equal(isSupervisorApprovalEnabled(), false);
});

test('isSupervisorApprovalEnabled accepts true/1/yes', () => {
  for (const value of ['true', 'TRUE', '1', 'yes']) {
    process.env[APPROVAL_KEY] = value;
    assert.equal(isSupervisorApprovalEnabled(), true, `expected true for ${value}`);
  }
});

test('isSupervisorApprovalEnabled rejects other values', () => {
  for (const value of ['false', '0', '', 'no']) {
    process.env[APPROVAL_KEY] = value;
    assert.equal(isSupervisorApprovalEnabled(), false, `expected false for ${value}`);
  }
});

test('sessionStatusPayload allows PIN when Model B is off and IdP is off', async () => {
  delete process.env[APPROVAL_KEY];
  for (const key of IDP_KEYS) delete process.env[key];

  const payload = await sessionStatusPayload(mockReq(), mockRes(), null);
  assert.equal(payload.supervisorApprovalRequired, false);
  assert.equal(payload.pinAllowed, true);
  assert.equal(payload.ok, false);
});

test('sessionStatusPayload blocks PIN when Model B is on', async () => {
  process.env[APPROVAL_KEY] = 'true';
  delete process.env[PIN_KEY];

  const payload = await sessionStatusPayload(mockReq(), mockRes(), null);
  assert.equal(payload.supervisorApprovalRequired, true);
  assert.equal(payload.pinAllowed, false);
});

test('sessionStatusPayload blocks PIN when IdP is on and IDP_ALLOW_PIN is false', async () => {
  delete process.env[APPROVAL_KEY];
  enablePosIdp();
  process.env[PIN_KEY] = 'false';

  const payload = await sessionStatusPayload(mockReq(), mockRes(), null);
  assert.equal(payload.supervisorApprovalRequired, false);
  assert.equal(payload.idpEnabled, true);
  assert.equal(payload.pinAllowed, false);
});

test('sessionStatusPayload allows PIN when IdP is on and IDP_ALLOW_PIN is true', async () => {
  delete process.env[APPROVAL_KEY];
  enablePosIdp();
  process.env[PIN_KEY] = 'true';

  const payload = await sessionStatusPayload(mockReq(), mockRes(), null);
  assert.equal(payload.supervisorApprovalRequired, false);
  assert.equal(payload.idpEnabled, true);
  assert.equal(payload.pinAllowed, true);
});

test('sessionStatusPayload blocks PIN when Model B is on even if IDP_ALLOW_PIN is true', async () => {
  process.env[APPROVAL_KEY] = 'true';
  enablePosIdp();
  process.env[PIN_KEY] = 'true';

  const payload = await sessionStatusPayload(mockReq(), mockRes(), null);
  assert.equal(payload.supervisorApprovalRequired, true);
  assert.equal(payload.idpEnabled, true);
  assert.equal(payload.pinAllowed, false);
});

test('sessionStatusPayload echoes awaitingTillToken for native till submit fallback', async () => {
  const token = createAwaitingTill({
    claims: { sub: 'user-1', email: 'cashier@example.com' },
    registerId: 'tablet-abc',
    clientKind: 'tablet',
    posSessionId: 42,
  });
  const payload = await sessionStatusPayload(
    mockReq(`cashier_awaiting_till=${encodeURIComponent(token)}`),
    mockRes(),
    null,
  );
  assert.equal(payload.awaitingTill, true);
  assert.equal(payload.awaitingTillToken, token);
  assert.equal(payload.ok, false);
});
