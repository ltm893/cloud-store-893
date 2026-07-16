'use strict';

const crypto = require('crypto');
const { parseCookies } = require('./session-cookies');
const { restoreSessions, persistSessions } = require('./dev-session-store');
const { createDynamoSessionBackend } = require('./dynamo/sessions');

const DEFAULT_SESSION_MS = 8 * 60 * 60 * 1000;

function resolveBackend(explicit) {
  if (explicit) return String(explicit).toLowerCase();
  const fromEnv = String(process.env.SESSION_BACKEND || '').toLowerCase();
  if (fromEnv === 'dynamo' || fromEnv === 'dynamodb') return 'dynamo';
  if (String(process.env.DATA_BACKEND || '').toLowerCase() === 'hybrid') return 'dynamo';
  return 'memory';
}

/**
 * @param {{
 *   cookieName: string,
 *   storeKey: string,
 *   sessionMs?: number,
 *   secure?: boolean | (() => boolean),
 *   useAppendHeader?: boolean,
 *   backend?: 'memory' | 'dynamo',
 * }} options
 */
function createSessionStore({
  cookieName,
  storeKey,
  sessionMs = DEFAULT_SESSION_MS,
  secure = false,
  useAppendHeader = false,
  backend: backendOpt,
} = {}) {
  if (!cookieName || !storeKey) {
    throw new Error('createSessionStore requires cookieName and storeKey');
  }

  const backendName = resolveBackend(backendOpt);
  const memorySessions = new Map();

  function touchSessions() {
    if (backendName === 'memory') persistSessions(storeKey, memorySessions);
  }

  function isSecureCookie() {
    return typeof secure === 'function' ? secure() : Boolean(secure);
  }

  function cookieExtraFlags() {
    return isSecureCookie() ? '; Secure' : '';
  }

  function applySetCookie(res, value) {
    if (useAppendHeader && typeof res.appendHeader === 'function') {
      res.appendHeader('Set-Cookie', value);
      return;
    }
    res.setHeader('Set-Cookie', value);
  }

  function getSessionId(req) {
    return parseCookies(req)[cookieName] || null;
  }

  let dyn = null;
  if (backendName === 'dynamo') {
    dyn = createDynamoSessionBackend({ storeKey, sessionMs });
  }

  function memoryIsValid(id) {
    if (!id) return false;
    const entry = memorySessions.get(id);
    if (!entry) return false;
    if (Date.now() - entry.created > sessionMs) {
      memorySessions.delete(id);
      touchSessions();
      return false;
    }
    return true;
  }

  if (backendName === 'memory') {
    restoreSessions(storeKey, memorySessions, memoryIsValid);
  }

  async function createSession(meta = {}) {
    if (dyn) return dyn.createSession(meta);
    const id = crypto.randomBytes(24).toString('hex');
    memorySessions.set(id, { created: Date.now(), auth: 'pin', ...meta });
    touchSessions();
    return id;
  }

  async function isValidSession(id) {
    if (dyn) return dyn.isValidSession(id);
    return memoryIsValid(id);
  }

  async function deleteSession(sessionId) {
    if (dyn) return dyn.deleteSession(sessionId);
    if (!sessionId) return;
    memorySessions.delete(sessionId);
    touchSessions();
  }

  async function updateSession(sessionId, entry) {
    if (dyn) return dyn.updateSession(sessionId, entry);
    if (!sessionId || !entry) return;
    memorySessions.set(sessionId, entry);
    touchSessions();
  }

  async function getSession(sessionId) {
    if (dyn) return dyn.getSession(sessionId);
    if (!sessionId || !memoryIsValid(sessionId)) return null;
    return memorySessions.get(sessionId) || null;
  }

  async function getSessionFromRequest(req) {
    return getSession(getSessionId(req));
  }

  function setSessionCookie(res, sessionId) {
    const maxAge = Math.floor(sessionMs / 1000);
    applySetCookie(
      res,
      `${cookieName}=${encodeURIComponent(sessionId)}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${maxAge}${cookieExtraFlags()}`,
    );
  }

  function clearSessionCookie(res) {
    applySetCookie(
      res,
      `${cookieName}=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0${cookieExtraFlags()}`,
    );
  }

  return {
    sessions: memorySessions,
    cookieName,
    storeKey,
    sessionMs,
    backend: backendName,
    getSessionId,
    isValidSession,
    createSession,
    setSessionCookie,
    clearSessionCookie,
    deleteSession,
    updateSession,
    getSession,
    getSessionFromRequest,
    touchSessions,
    applySetCookie,
    cookieExtraFlags,
  };
}

module.exports = { createSessionStore, DEFAULT_SESSION_MS, resolveBackend };
