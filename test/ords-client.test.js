'use strict';

const { test, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const { createOrdsClient, ordsTimestamp } = require('../lib/ords-client');

const originalFetch = global.fetch;

afterEach(() => {
  global.fetch = originalFetch;
});

test('ordsTimestamp strips milliseconds from ISO string', () => {
  const date = new Date('2026-06-05T12:34:56.789Z');
  assert.equal(ordsTimestamp(date), '2026-06-05T12:34:56Z');
});

test('createOrdsClient requires base URL', () => {
  assert.throws(() => createOrdsClient(''), /ORDS base URL is required/);
});

test('createOrdsClient normalizes trailing slash', async () => {
  const calls = [];
  global.fetch = async (url, init) => {
    calls.push({ url, init });
    return {
      ok: true,
      async json() {
        return { items: [{ id: 1 }] };
      },
    };
  };

  const client = createOrdsClient('https://example.com/ords/cloud_store/');
  const rows = await client.ordsGet('products/');
  assert.equal(rows.length, 1);
  assert.equal(calls[0].url, 'https://example.com/ords/cloud_store/products/');
});

test('ordsTryGet returns null on non-OK response', async () => {
  global.fetch = async () => ({ ok: false, status: 404 });
  const client = createOrdsClient('https://example.com/ords');
  assert.equal(await client.ordsTryGet('missing/'), null);
});

test('ordsPost includes response detail in error', async () => {
  global.fetch = async () => ({
    ok: false,
    status: 400,
    async json() {
      return { message: 'bad payload' };
    },
  });
  const client = createOrdsClient('https://example.com/ords');
  await assert.rejects(
    () => client.ordsPost('cart/', { productId: 1 }),
    /bad payload/,
  );
});
