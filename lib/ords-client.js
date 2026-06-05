'use strict';

/** ORDS accepts ISO-8601 with Z; rejects milliseconds (e.g. .000Z). */
function ordsTimestamp(date = new Date()) {
  return date.toISOString().replace(/\.\d{3}Z$/, 'Z');
}

async function parseOrdsBody(res) {
  const data = await res.json();
  return Array.isArray(data.items) ? data.items : data;
}

async function readOrdsErrorDetail(res) {
  try {
    const errBody = await res.json();
    return errBody.message || errBody.error || JSON.stringify(errBody);
  } catch {
    return res.text().catch(() => '');
  }
}

/**
 * @param {string} baseUrl ORDS module base (no trailing slash required)
 * @returns {{ ordsGet, ordsTryGet, ordsPost, ordsPut, ordsDelete, ordsTimestamp }}
 */
function createOrdsClient(baseUrl) {
  if (!baseUrl || typeof baseUrl !== 'string') {
    throw new Error('ORDS base URL is required');
  }
  const base = baseUrl.replace(/\/$/, '');

  async function ordsGet(path) {
    const res = await fetch(`${base}/${path}`);
    if (!res.ok) throw new Error(`ORDS GET ${path} → ${res.status}`);
    return parseOrdsBody(res);
  }

  async function ordsTryGet(path) {
    const res = await fetch(`${base}/${path}`);
    if (!res.ok) return null;
    return parseOrdsBody(res);
  }

  async function ordsPost(path, body) {
    const res = await fetch(`${base}/${path}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      const detail = await readOrdsErrorDetail(res);
      throw new Error(`ORDS POST ${path} → ${res.status}${detail ? `: ${detail}` : ''}`);
    }
    return res.json();
  }

  async function ordsPut(path, body) {
    const res = await fetch(`${base}/${path}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    if (!res.ok) throw new Error(`ORDS PUT ${path} → ${res.status}`);
    return res.json();
  }

  async function ordsDelete(path) {
    const res = await fetch(`${base}/${path}`, { method: 'DELETE' });
    if (!res.ok) throw new Error(`ORDS DELETE ${path} → ${res.status}`);
  }

  return {
    ordsGet,
    ordsTryGet,
    ordsPost,
    ordsPut,
    ordsDelete,
    ordsTimestamp,
  };
}

module.exports = { createOrdsClient, ordsTimestamp };
