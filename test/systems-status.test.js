'use strict';

const fs = require('fs');
const path = require('path');
const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  WARNING_DAYS,
  certExpiryStatus,
  daysUntil,
  isProbeableHostname,
  resolveTlsHostname,
  loadOciResources,
  filterOciResourcesForDisplay,
} = require('../lib/systems-status');

test('certExpiryStatus returns ok, warning, expired', () => {
  const futureFar = new Date(Date.now() + (WARNING_DAYS + 5) * 86400000).toISOString();
  const futureSoon = new Date(Date.now() + 10 * 86400000).toISOString();
  const past = new Date(Date.now() - 86400000).toISOString();

  assert.equal(certExpiryStatus(futureFar), 'ok');
  assert.equal(certExpiryStatus(futureSoon), 'warning');
  assert.equal(certExpiryStatus(past), 'expired');
});

test('daysUntil counts calendar days remaining', () => {
  const inThreeDays = new Date(Date.now() + 3.2 * 86400000).toISOString();
  assert.equal(daysUntil(inThreeDays), 3);
});

test('resolveTlsHostname prefers env then request Host', () => {
  const prev = {
    SYSTEMS_TLS_HOSTNAME: process.env.SYSTEMS_TLS_HOSTNAME,
    LB_PUBLIC_HOSTNAME: process.env.LB_PUBLIC_HOSTNAME,
    APP_PUBLIC_URL: process.env.APP_PUBLIC_URL,
  };
  delete process.env.SYSTEMS_TLS_HOSTNAME;
  delete process.env.LB_PUBLIC_HOSTNAME;
  delete process.env.APP_PUBLIC_URL;
  try {
    assert.equal(resolveTlsHostname('oci.cloudstore893.com'), 'oci.cloudstore893.com');
    assert.equal(resolveTlsHostname('localhost:3000'), null);
    assert.equal(isProbeableHostname('127.0.0.1'), false);
    assert.equal(isProbeableHostname('129.153.187.63'), false);
    assert.equal(isProbeableHostname('oci.cloudstore893.com'), true);
  } finally {
    for (const [key, value] of Object.entries(prev)) {
      if (value == null) delete process.env[key];
      else process.env[key] = value;
    }
  }
});

test('filterOciResourcesForDisplay keeps only latest ContainerImage tags', () => {
  const filtered = filterOciResourcesForDisplay([
    { type: 'ContainerImage', name: 'cloud-store:latest', id: 'a' },
    { type: 'ContainerImage', name: 'cloud-store:latest', id: 'b' },
    {
      type: 'ContainerImage',
      name: 'cloud-store:unknown@sha256:abc',
      id: 'c',
    },
    { type: 'loadbalancer', name: 'lb-cloud-store', id: 'd' },
  ]);
  assert.equal(filtered.length, 2);
  assert.ok(filtered.some((r) => r.type === 'loadbalancer'));
  assert.ok(filtered.some((r) => r.type === 'ContainerImage' && r.name === 'cloud-store:latest'));
  assert.ok(!filtered.some((r) => r.id === 'c'));
  assert.ok(!filtered.some((r) => r.id === 'b'));
});

test('loadOciResources falls back to env snapshot when manifest empty', () => {
  const manifestPath = path.join(__dirname, '..', 'data', 'systems-oci-resources.json');
  const prev = {
    SYSTEMS_COMPARTMENT_OCID: process.env.SYSTEMS_COMPARTMENT_OCID,
    SYSTEMS_COMPARTMENT_NAME: process.env.SYSTEMS_COMPARTMENT_NAME,
    manifest: null,
  };
  if (fs.existsSync(manifestPath)) {
    prev.manifest = fs.readFileSync(manifestPath, 'utf8');
    fs.writeFileSync(
      manifestPath,
      JSON.stringify({ resources: [], source: 'test-empty' }, null, 2) + '\n',
    );
  }
  process.env.SYSTEMS_COMPARTMENT_OCID = 'ocid1.compartment.oc1..test';
  process.env.SYSTEMS_COMPARTMENT_NAME = 'cloud-store';
  try {
    const data = loadOciResources();
    assert.equal(data.source, 'env');
    assert.ok(data.resources.some((r) => r.type === 'compartment'));
  } finally {
    if (prev.manifest != null) fs.writeFileSync(manifestPath, prev.manifest);
    if (prev.SYSTEMS_COMPARTMENT_OCID == null) delete process.env.SYSTEMS_COMPARTMENT_OCID;
    else process.env.SYSTEMS_COMPARTMENT_OCID = prev.SYSTEMS_COMPARTMENT_OCID;
    if (prev.SYSTEMS_COMPARTMENT_NAME == null) delete process.env.SYSTEMS_COMPARTMENT_NAME;
    else process.env.SYSTEMS_COMPARTMENT_NAME = prev.SYSTEMS_COMPARTMENT_NAME;
  }
});
