const fs = require('fs');
const path = require('path');

const STORE_PATH = path.join(process.cwd(), '.dev-auth-sessions.json');

function isEnabled() {
  return String(process.env.DEV_PERSIST_AUTH_SESSIONS || '').toLowerCase() === 'true';
}

function readAll() {
  try {
    return JSON.parse(fs.readFileSync(STORE_PATH, 'utf8'));
  } catch {
    return {};
  }
}

function writeAll(all) {
  fs.writeFileSync(STORE_PATH, JSON.stringify(all, null, 2));
}

/**
 * Restore in-memory sessions from .dev-auth-sessions.json (local dev only).
 * @param {string} storeKey e.g. "cashier" | "admin"
 * @param {Map} sessions
 * @param {(id: string) => boolean} isValidSession
 */
function restoreSessions(storeKey, sessions, isValidSession) {
  if (!isEnabled()) return;
  const entries = readAll()[storeKey];
  if (!Array.isArray(entries)) return;
  for (const [id, entry] of entries) {
    if (entry && isValidSession(id)) sessions.set(id, entry);
  }
}

function persistSessions(storeKey, sessions) {
  if (!isEnabled()) return;
  const all = readAll();
  all[storeKey] = Array.from(sessions.entries());
  writeAll(all);
}

/**
 * @param {string} storeKey
 * @param {Map} map
 * @param {(id: string, entry: unknown) => boolean} isValidEntry
 */
function restoreEntries(storeKey, map, isValidEntry) {
  if (!isEnabled()) return;
  const entries = readAll()[storeKey];
  if (!Array.isArray(entries)) return;
  for (const [id, entry] of entries) {
    if (entry && isValidEntry(id, entry)) map.set(id, entry);
  }
}

function persistEntries(storeKey, map) {
  if (!isEnabled()) return;
  const all = readAll();
  all[storeKey] = Array.from(map.entries());
  writeAll(all);
}

module.exports = {
  restoreSessions,
  persistSessions,
  restoreEntries,
  persistEntries,
  isEnabled,
};
