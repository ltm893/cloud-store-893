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

module.exports = {
  isPortraitOkClient,
  parseClientKind,
  shouldUseLandscapeLock,
};
