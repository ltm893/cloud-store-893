'use strict';

/**
 * Admin landscape / portrait client detection (web + unit tests).
 * Browser bundle: public/admin/admin-orientation.js — keep behavior in sync.
 */
function isPortraitOkClient({ hasPortraitOkClass, clientKind }) {
  if (hasPortraitOkClass) return true;
  return clientKind === 'ios';
}

function parseClientKind(search) {
  return new URLSearchParams(search || '').get('client_kind');
}

function shouldUseLandscapeLock({ hasPortraitOkClass, clientKind }) {
  return !isPortraitOkClient({ hasPortraitOkClass, clientKind });
}

/** Desktop browsers with mouse — skip tablet portrait overlay. */
function isDesktopFinePointer(finePointer) {
  if (finePointer === true) return true;
  if (finePointer === false) return false;
  if (typeof window === 'undefined' || !window.matchMedia) return false;
  return window.matchMedia('(hover: hover) and (pointer: fine)').matches;
}

function shouldShowPortraitBlocker({ hasPortraitOkClass, clientKind, finePointer } = {}) {
  if (isPortraitOkClient({ hasPortraitOkClass, clientKind })) return false;
  if (isDesktopFinePointer(finePointer)) return false;
  return true;
}

module.exports = {
  isPortraitOkClient,
  parseClientKind,
  shouldUseLandscapeLock,
  isDesktopFinePointer,
  shouldShowPortraitBlocker,
};
