'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  buildInfoLabel,
  formatBuildInfo,
  formatBuildDisplay,
  getBuildInfo,
  normalizeBuildId,
} = require('../lib/build-info');

test('formatBuildInfo uses YYYYMMDDHHmmss buildId with UTC label', () => {
  assert.deepEqual(formatBuildInfo('20260613120530'), {
    buildId: '20260613120530',
    label: '2026-06-13 12:05:30 UTC',
  });
});

test('formatBuildInfo normalizes legacy deploy- timestamp prefix', () => {
  assert.deepEqual(formatBuildInfo('deploy-20260613120530'), {
    buildId: '20260613120530',
    label: '2026-06-13 12:05:30 UTC',
  });
});

test('formatBuildInfo humanizes semantic build ids', () => {
  assert.deepEqual(formatBuildInfo('update-systems-page-2'), {
    buildId: 'update-systems-page-2',
    label: 'update systems page 2',
  });
});

test('formatBuildInfo uses explicit BUILD_LABEL when provided', () => {
  assert.deepEqual(formatBuildInfo('20260613120530', 'systems tab fixes'), {
    buildId: '20260613120530',
    label: 'systems tab fixes',
  });
});

test('getBuildInfo reads BUILD_ID, BUILD_LABEL, GIT_SHA, and package version', () => {
  const info = getBuildInfo({
    BUILD_ID: '20260613120530',
    BUILD_LABEL: 'close till flow',
    GIT_SHA: 'abc1234567890',
  });
  assert.equal(info.buildId, '20260613120530');
  assert.equal(info.label, 'close till flow');
  assert.equal(info.gitSha, 'abc1234');
  assert.match(info.appVersion, /^\d+\.\d+\.\d+$/);
  assert.equal(
    info.display,
    `v${info.appVersion} · close till flow : 20260613120530 (abc1234)`,
  );
});

test('formatBuildDisplay shows version, label, buildId, and git sha', () => {
  assert.equal(
    formatBuildDisplay({
      appVersion: '1.0.0',
      buildId: '20260613120530',
      label: 'systems tab fixes',
      gitSha: 'a1b2c3d',
    }),
    'v1.0.0 · systems tab fixes : 20260613120530 (a1b2c3d)',
  );
  assert.equal(formatBuildDisplay({ buildId: 'unknown', label: 'unknown' }), 'unknown : unknown');
});

test('normalizeBuildId leaves semantic ids unchanged', () => {
  assert.equal(normalizeBuildId('update-systems-page-2'), 'update-systems-page-2');
  assert.equal(buildInfoLabel('dev'), 'dev');
});
