'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { getHostInfo } = require('../lib/host-info');

test('getHostInfo includes overview and OCI host fields', () => {
  const info = getHostInfo();
  assert.match(info.overview, /oci\.cloudstore893\.com/);
  assert.match(info.overview, /Node\.js/);
  assert.equal(info.host.title, 'Host OCI');
  assert.ok(info.host.fields.some((f) => f.label === 'Service' && f.value === 'OCI Container Instance'));
  assert.ok(info.host.fields.some((f) => f.label === 'Shape' && /A1/.test(f.value)));
  assert.ok(info.host.fields.some((f) => f.label === 'Size' && f.value === '1 OCPU, 6 GB RAM'));
});

test('getHostInfo adds region when SYSTEMS_OCI_REGION is set', () => {
  const prev = process.env.SYSTEMS_OCI_REGION;
  process.env.SYSTEMS_OCI_REGION = 'us-ashburn-1';
  try {
    const info = getHostInfo();
    assert.ok(info.host.fields.some((f) => f.label === 'Region' && f.value === 'us-ashburn-1'));
  } finally {
    if (prev == null) delete process.env.SYSTEMS_OCI_REGION;
    else process.env.SYSTEMS_OCI_REGION = prev;
  }
});
