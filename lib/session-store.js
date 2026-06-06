'use strict';

const crypto = require('crypto');
const { parseCookies } = require('./session-cookies');
const { restoreSessions, persistSessions } = require('./dev-session-store');

const DEFAULT_SESSION_MS = 8 * 60 * 60 * 1000;

/**
 * @param {{
 *   cookieName: string,
 *   storeKey: string,
 *   sessionMs?: number,
 *   secure?: boolean | (() => boolean),
 *   useAppendHeader?: boolean,
 * }} options
 */
function createSessionStore({
  cookieName,
  storeKey,
  sessionMs = DEFAULT_SESSION_MS,
  secure = false,
  useAppendHeader = false,
} = {}) {
  if (!cookieName || !storeKey) {
    throw new Error('createSessionStore requires cookieName and storeKey');
  }

  const sessions = new Map();

  function touchSessions() {
    persistSessions(storeKey, sessions);
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

  function isValidSession(id) {
    if (!id) return false;
    const entry = sessions.get(id);
    if (!entry) return false;
    if (Date.now() - entry.created > sessionMs) {
      sessions.delete(id);
      touchSessions();
      return false;
    }
    return true;
  }

  restoreSessions(storeKey, sessions, isValidSession);

  function createSession(meta = {}) {
    const id = crypto.randomBytes(24).toString('hex');
    sessions.set(id, { created: Date.now(), auth: 'pin', ...meta });
    touchSessions();
    return id;
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

  function deleteSession(sessionId) {
    if (!sessionId) return;
    sessions.delete(sessionId);
    touchSessions();
  }

  function getSession(sessionId) {
    if (!sessionId || !isValidSession(sessionId)) return null;
    return sessions.get(sessionId) || null;
  }

  function getSessionFromRequest(req) {
    return getSession(getSessionId(req));
  }

  return {
    sessions,
    cookieName,
    storeKey,
    sessionMs,
    getSessionId,
    isValidSession,
    createSession,
    setSessionCookie,
    clearSessionCookie,
    deleteSession,
    getSession,
    getSessionFromRequest,
    touchSessions,
    applySetCookie,
    cookieExtraFlags,
  };
}

module.exports = { createSessionStore, DEFAULT_SESSION_MS };
