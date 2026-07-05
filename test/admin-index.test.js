'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

const indexHtml = fs.readFileSync(
  path.join(__dirname, '..', 'public', 'admin', 'index.html'),
  'utf8',
);

test('logged-in admin index exposes Platform as a top-level tab', () => {
  assert.match(indexHtml, /class="admin-tab-btn"[^>]*data-tab="systems"/);
  assert.match(indexHtml, />Platform<\/button>/);
  assert.match(indexHtml, /id="systemsPanel"/);
  assert.match(indexHtml, /admin-systems\.js/);
});

test('logged-in admin index wires Platform tab script before admin.js', () => {
  const systemsIdx = indexHtml.indexOf('admin-systems.js');
  const adminIdx = indexHtml.indexOf('admin.js');
  assert.ok(systemsIdx >= 0 && adminIdx > systemsIdx);
});

test('admin index includes in-page prompt for WebView supervisor actions', () => {
  assert.match(indexHtml, /id="adminPromptDialog"/);
  assert.match(indexHtml, /admin-prompt\.js/);
  const promptIdx = indexHtml.indexOf('admin-prompt.js');
  const openTillsIdx = indexHtml.indexOf('admin-open-tills.js');
  assert.ok(promptIdx >= 0 && openTillsIdx > promptIdx);
});
