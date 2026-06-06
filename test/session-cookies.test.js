'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { parseCookies } = require('../lib/session-cookies');

test('parseCookies returns empty object when header missing', () => {
  assert.deepEqual(parseCookies({ headers: {} }), {});
});

test('parseCookies parses and decodes cookie pairs', () => {
  const req = { headers: { cookie: 'cashier_session=abc123; theme=dark%20mode' } };
  assert.deepEqual(parseCookies(req), {
    cashier_session: 'abc123',
    theme: 'dark mode',
  });
});

test('parseCookies ignores malformed segments', () => {
  const req = { headers: { cookie: 'valid=1; badsegment; other=2' } };
  assert.deepEqual(parseCookies(req), { valid: '1', other: '2' });
});
