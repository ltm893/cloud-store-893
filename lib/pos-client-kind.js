'use strict';

/** Canonical POS `client_kind` values (query param / JSON body). */
const POS_CLIENT_KIND = {
  TABLET: 'tablet',
  IOS: 'ios',
  WEB: 'web',
};

const NATIVE_POS_CLIENT_KINDS = new Set([
  POS_CLIENT_KIND.TABLET,
  POS_CLIENT_KIND.IOS,
]);

const REGISTER_ID_PREFIX = 'tablet-';

function normalizePosClientKind(kind) {
  if (kind == null) return null;
  const trimmed = String(kind).trim().toLowerCase();
  return trimmed || null;
}

/** Native register apps (Android tablet, iOS iPad) — not web POS. */
function isNativePosClient(kind) {
  const normalized = normalizePosClientKind(kind);
  return normalized != null && NATIVE_POS_CLIENT_KINDS.has(normalized);
}

/**
 * OIDC resume redirect query after till resume.
 * Native clients watch `cashier_resume`; web uses `resumed`.
 */
function cashierResumeRedirectQuery(clientKind) {
  return isNativePosClient(clientKind) ? 'cashier_resume=1' : 'resumed=1';
}

function normalizeRegisterId(registerId) {
  if (registerId == null) return null;
  const trimmed = String(registerId).trim();
  return trimmed || null;
}

/**
 * Stable per-device register id: `tablet-{deviceId}` on Android and iOS.
 * @see docs/pos-client-identifiers.md
 */
function isValidRegisterId(registerId) {
  const id = normalizeRegisterId(registerId);
  if (!id) return false;
  return id.startsWith(REGISTER_ID_PREFIX) && id.length > REGISTER_ID_PREFIX.length;
}

function invalidRegisterIdError() {
  const err = new Error(
    `register_id must start with "${REGISTER_ID_PREFIX}" (e.g. tablet-{deviceId})`,
  );
  err.status = 400;
  err.code = 'INVALID_REGISTER_ID';
  return err;
}

/**
 * When a native client sends register_id, enforce the shared prefix contract.
 * Web POS may omit register_id.
 */
function assertValidNativeRegisterContext({ registerId, clientKind } = {}) {
  const kind = normalizePosClientKind(clientKind);
  const id = normalizeRegisterId(registerId);
  if (!isNativePosClient(kind)) return;
  if (!id) return;
  if (!isValidRegisterId(id)) {
    throw invalidRegisterIdError();
  }
}

module.exports = {
  POS_CLIENT_KIND,
  NATIVE_POS_CLIENT_KINDS,
  REGISTER_ID_PREFIX,
  normalizePosClientKind,
  isNativePosClient,
  cashierResumeRedirectQuery,
  normalizeRegisterId,
  isValidRegisterId,
  assertValidNativeRegisterContext,
  invalidRegisterIdError,
};
