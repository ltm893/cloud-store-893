'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  isPortraitOkClient,
  parseClientKind,
  shouldUseLandscapeLock,
  shouldShowPortraitBlocker,
} = require('../lib/admin-orientation');

test('isPortraitOkClient is true when admin-portrait-ok class is set', () => {
  assert.equal(
    isPortraitOkClient({ hasPortraitOkClass: true, clientKind: null }),
    true,
  );
});

test('isPortraitOkClient is true for client_kind=ios', () => {
  assert.equal(
    isPortraitOkClient({ hasPortraitOkClass: false, clientKind: 'ios' }),
    true,
  );
});

test('isPortraitOkClient is false for default tablet/browser client', () => {
  assert.equal(
    isPortraitOkClient({ hasPortraitOkClass: false, clientKind: null }),
    false,
  );
  assert.equal(
    isPortraitOkClient({ hasPortraitOkClass: false, clientKind: 'tablet' }),
    false,
  );
});

test('parseClientKind reads query string', () => {
  assert.equal(parseClientKind('?client_kind=ios'), 'ios');
  assert.equal(parseClientKind(''), null);
});

test('shouldUseLandscapeLock is inverse of portrait-ok clients', () => {
  assert.equal(
    shouldUseLandscapeLock({ hasPortraitOkClass: false, clientKind: null }),
    true,
  );
  assert.equal(
    shouldUseLandscapeLock({ hasPortraitOkClass: true, clientKind: null }),
    false,
  );
  assert.equal(
    shouldUseLandscapeLock({ hasPortraitOkClass: false, clientKind: 'ios' }),
    false,
  );
});

test('shouldShowPortraitBlocker is false for ios and desktop fine pointer', () => {
  assert.equal(
    shouldShowPortraitBlocker({ hasPortraitOkClass: false, clientKind: 'ios', finePointer: false }),
    false,
  );
  assert.equal(
    shouldShowPortraitBlocker({ hasPortraitOkClass: false, clientKind: null, finePointer: true }),
    false,
  );
  assert.equal(
    shouldShowPortraitBlocker({ hasPortraitOkClass: false, clientKind: null, finePointer: false }),
    true,
  );
});
