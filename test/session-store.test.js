'use strict';

const { test, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const { createSessionStore, DEFAULT_SESSION_MS } = require('../lib/session-store');

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

function mockReq(cookieHeader) {
  return { headers: cookieHeader ? { cookie: cookieHeader } : {} };
}

beforeEach(() => {
  delete process.env.DEV_PERSIST_AUTH_SESSIONS;
});

test('createSessionStore requires cookieName and storeKey', () => {
  assert.throws(
    () => createSessionStore({ cookieName: 'x' }),
    /cookieName and storeKey/,
  );
});

test('createSession and isValidSession round-trip', () => {
  const store = createSessionStore({ cookieName: 'test_session', storeKey: 'test' });
  const id = store.createSession({ auth: 'pin', email: 'a@b.com' });
  assert.match(id, /^[a-f0-9]{48}$/);
  assert.equal(store.isValidSession(id), true);
  assert.equal(store.getSession(id)?.email, 'a@b.com');
});

test('getSessionId reads cookie from request', () => {
  const store = createSessionStore({ cookieName: 'cashier_session', storeKey: 'cashier' });
  const id = store.createSession();
  const encoded = encodeURIComponent(id);
  assert.equal(store.getSessionId(mockReq(`cashier_session=${encoded}`)), id);
});

test('setSessionCookie uses setHeader by default', () => {
  const store = createSessionStore({ cookieName: 'cashier_session', storeKey: 'cashier' });
  const res = mockRes();
  store.setSessionCookie(res, 'sess-1');
  assert.match(res.headers['Set-Cookie'], /cashier_session=sess-1/);
  assert.match(res.headers['Set-Cookie'], /HttpOnly/);
  assert.match(res.headers['Set-Cookie'], /SameSite=Lax/);
});

test('useAppendHeader sets cookies via appendHeader', () => {
  const store = createSessionStore({
    cookieName: 'cashier_session',
    storeKey: 'cashier',
    useAppendHeader: true,
  });
  const res = mockRes();
  store.setSessionCookie(res, 'sess-1');
  store.applySetCookie(res, 'cashier_pending=token; Path=/; HttpOnly');
  assert.equal(Array.isArray(res.headers['Set-Cookie']), true);
  assert.equal(res.headers['Set-Cookie'].length, 2);
});

test('secure flag adds Secure to cookie', () => {
  const store = createSessionStore({
    cookieName: 'admin_session',
    storeKey: 'admin',
    secure: true,
  });
  const res = mockRes();
  store.setSessionCookie(res, 'admin-1');
  assert.match(res.headers['Set-Cookie'], /; Secure$/);
});

test('secure callback is evaluated per cookie', () => {
  let secure = false;
  const store = createSessionStore({
    cookieName: 'admin_session',
    storeKey: 'admin',
    secure: () => secure,
  });
  const res = mockRes();
  store.setSessionCookie(res, 'a');
  assert.doesNotMatch(res.headers['Set-Cookie'], /Secure/);
  secure = true;
  store.setSessionCookie(res, 'b');
  assert.match(res.headers['Set-Cookie'], /Secure/);
});

test('expired sessions are invalid', () => {
  const store = createSessionStore({
    cookieName: 'test_session',
    storeKey: 'test',
    sessionMs: 1,
  });
  const id = store.createSession();
  assert.equal(store.isValidSession(id), true);
  return new Promise((resolve) => {
    setTimeout(() => {
      assert.equal(store.isValidSession(id), false);
      assert.equal(store.getSession(id), null);
      resolve();
    }, 5);
  });
});

test('deleteSession removes entry', () => {
  const store = createSessionStore({ cookieName: 'test_session', storeKey: 'test' });
  const id = store.createSession();
  store.deleteSession(id);
  assert.equal(store.isValidSession(id), false);
});

test('getSessionFromRequest returns session metadata', () => {
  const store = createSessionStore({ cookieName: 'test_session', storeKey: 'test' });
  const id = store.createSession({ auth: 'oidc' });
  const req = mockReq(`test_session=${encodeURIComponent(id)}`);
  assert.equal(store.getSessionFromRequest(req)?.auth, 'oidc');
});

test('DEFAULT_SESSION_MS is eight hours', () => {
  assert.equal(DEFAULT_SESSION_MS, 8 * 60 * 60 * 1000);
});
