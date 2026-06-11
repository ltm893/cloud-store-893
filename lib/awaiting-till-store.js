const crypto = require('crypto');
const { restoreEntries, persistEntries } = require('./dev-session-store');

const AWAITING_TTL_MS = 30 * 60 * 1000;
const STORE_KEY = 'awaitingTill';
const drafts = new Map();

function isValidDraft(_token, draft) {
  return Boolean(draft?.createdAt && Date.now() - draft.createdAt <= AWAITING_TTL_MS);
}

function touchDrafts() {
  persistEntries(STORE_KEY, drafts);
}

function pruneExpired() {
  const now = Date.now();
  let changed = false;
  for (const [token, draft] of drafts.entries()) {
    if (!draft?.createdAt || now - draft.createdAt > AWAITING_TTL_MS) {
      drafts.delete(token);
      changed = true;
    }
  }
  if (changed) touchDrafts();
}

restoreEntries(STORE_KEY, drafts, isValidDraft);
pruneExpired();

function createAwaitingTill({ claims = null, pinAuth = false, registerId = null, clientKind = 'web' }) {
  pruneExpired();
  const token = crypto.randomBytes(24).toString('hex');
  drafts.set(token, {
    token,
    claims,
    pinAuth: Boolean(pinAuth),
    registerId: registerId ? String(registerId).trim() : null,
    clientKind: clientKind ? String(clientKind).trim() : null,
    createdAt: Date.now(),
  });
  touchDrafts();
  return token;
}

function getAwaitingTill(token) {
  pruneExpired();
  const key = String(token || '').trim();
  if (!key) return null;
  const draft = drafts.get(key);
  if (!draft) return null;
  if (Date.now() - draft.createdAt > AWAITING_TTL_MS) {
    drafts.delete(key);
    touchDrafts();
    return null;
  }
  return draft;
}

function deleteAwaitingTill(token) {
  const key = String(token || '').trim();
  if (!key) return;
  if (drafts.delete(key)) touchDrafts();
}

function clearAwaitingTillStore() {
  drafts.clear();
  touchDrafts();
}

module.exports = {
  createAwaitingTill,
  getAwaitingTill,
  deleteAwaitingTill,
  clearAwaitingTillStore,
};
