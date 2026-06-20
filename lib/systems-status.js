const fs = require('fs');
const path = require('path');
const tls = require('tls');
const http = require('http');

const MANIFEST_PATH = path.join(__dirname, '..', 'data', 'systems-oci-resources.json');

/** Smoke checks for Express routes (localhost self-probe). */
const NODE_ROUTE_CHECKS = [
  { method: 'GET', path: '/api/build-info', expect: [200], label: 'Build info' },
  { method: 'GET', path: '/api/products', expect: [200], label: 'Products catalog' },
  { method: 'GET', path: '/api/cashier/session', expect: [200], label: 'Cashier session' },
  { method: 'GET', path: '/api/admin/session', expect: [200], label: 'Admin session' },
  { method: 'GET', path: '/api/cart', expect: [401], label: 'Cart (auth required)' },
  { method: 'GET', path: '/api/admin/meta', expect: [401], label: 'Admin meta (auth required)' },
  { method: 'GET', path: '/api/customers', expect: [401], label: 'Customers (auth required)' },
  { method: 'GET', path: '/api/sales/recent', expect: [401], label: 'Sales recent (auth required)' },
];

const WARNING_DAYS = 30;

const { getBuildInfo } = require('./build-info');
const { getStoreClients } = require('./store-clients');
const { getHostInfo } = require('./host-info');

function certExpiryStatus(expiresAt) {
  const ms = new Date(expiresAt).getTime() - Date.now();
  if (!Number.isFinite(ms)) return 'unknown';
  if (ms < 0) return 'expired';
  if (ms <= WARNING_DAYS * 24 * 60 * 60 * 1000) return 'warning';
  return 'ok';
}

function daysUntil(expiresAt) {
  const ms = new Date(expiresAt).getTime() - Date.now();
  if (!Number.isFinite(ms)) return null;
  return Math.floor(ms / 86400000);
}

function probeTlsCert(host, { port = 443, servername } = {}) {
  const sni = servername || host;
  return new Promise((resolve) => {
    const socket = tls.connect(
      { host, port, servername: sni, timeout: 8000 },
      () => {
        const cert = socket.getPeerCertificate();
        socket.end();
        if (!cert?.valid_to) {
          resolve({ ok: false, hostname: sni, error: 'no certificate returned' });
          return;
        }
        const expiresAt = new Date(cert.valid_to).toISOString();
        resolve({
          ok: true,
          hostname: sni,
          name: cert.subject?.CN || sni,
          issuer: cert.issuer?.O || cert.issuer?.CN || '—',
          expiresAt,
          status: certExpiryStatus(cert.valid_to),
          daysRemaining: daysUntil(cert.valid_to),
        });
      },
    );
    socket.on('error', (err) => {
      resolve({ ok: false, hostname: sni, error: err.message });
    });
    socket.on('timeout', () => {
      socket.destroy();
      resolve({ ok: false, hostname: sni, error: 'connection timed out' });
    });
  });
}

function probeRoute(port, check) {
  return new Promise((resolve) => {
    const req = http.request(
      {
        host: '127.0.0.1',
        port,
        path: check.path,
        method: check.method,
        headers: { Accept: 'application/json' },
        timeout: 5000,
      },
      (res) => {
        res.resume();
        const ok = check.expect.includes(res.statusCode);
        resolve({
          route: `${check.method} ${check.path}`,
          label: check.label,
          statusCode: res.statusCode,
          expected: check.expect,
          ok,
          status: ok ? 'ok' : 'fail',
        });
      },
    );
    req.on('error', (err) => {
      resolve({
        route: `${check.method} ${check.path}`,
        label: check.label,
        ok: false,
        status: 'fail',
        error: err.message,
      });
    });
    req.on('timeout', () => {
      req.destroy();
      resolve({
        route: `${check.method} ${check.path}`,
        label: check.label,
        ok: false,
        status: 'fail',
        error: 'request timed out',
      });
    });
    req.end();
  });
}

function envResource(type, name, state, id) {
  if (!id && !name) return null;
  return {
    type: type || '—',
    name: name || '—',
    state: state || '—',
    id: id || null,
  };
}

function filterOciResourcesForDisplay(resources) {
  const seenLatestNames = new Set();
  return resources.filter((row) => {
    if (row.type !== 'ContainerImage') return true;
    const name = String(row.name || '');
    if (!/:latest(?:$|@)/.test(name)) return false;
    if (seenLatestNames.has(name)) return false;
    seenLatestNames.add(name);
    return true;
  });
}

function loadOciResources() {
  try {
    if (fs.existsSync(MANIFEST_PATH)) {
      const data = JSON.parse(fs.readFileSync(MANIFEST_PATH, 'utf8'));
      if (data && Array.isArray(data.resources) && data.resources.length > 0) {
        return {
          ...data,
          source: data.source || 'manifest',
          resources: filterOciResourcesForDisplay(data.resources),
        };
      }
    }
  } catch {
    /* fall through to env snapshot */
  }

  const resources = [];
  const add = (row) => {
    if (row) resources.push(row);
  };

  add(envResource('compartment', process.env.SYSTEMS_COMPARTMENT_NAME, 'ACTIVE', process.env.SYSTEMS_COMPARTMENT_OCID));
  add(envResource('loadbalancer', process.env.SYSTEMS_LB_NAME, 'ACTIVE', process.env.SYSTEMS_LB_OCID));
  add(envResource('certificate', process.env.SYSTEMS_LB_CERT_NAME, 'ACTIVE', process.env.SYSTEMS_LB_CERT_OCID));
  add(envResource('containerinstance', process.env.SYSTEMS_CONTAINER_NAME, 'ACTIVE', process.env.SYSTEMS_CONTAINER_OCID));
  add(envResource('autonomousdatabase', process.env.SYSTEMS_ADB_NAME, 'AVAILABLE', process.env.SYSTEMS_ADB_OCID));
  add(envResource('vcn', process.env.SYSTEMS_VCN_NAME, 'AVAILABLE', process.env.SYSTEMS_VCN_OCID));

  return {
    generatedAt: null,
    compartment: process.env.SYSTEMS_COMPARTMENT_NAME || 'cloud-store',
    region: process.env.SYSTEMS_OCI_REGION || null,
    resources,
    source: resources.length ? 'env' : 'none',
  };
}

function isProbeableHostname(host) {
  if (!host || typeof host !== 'string') return false;
  const value = host.trim().toLowerCase();
  if (!value || value === 'localhost' || value === '127.0.0.1' || value === '0.0.0.0') return false;
  if (value.endsWith('.local')) return false;
  if (/^\d{1,3}(\.\d{1,3}){3}$/.test(value)) return false;
  return true;
}

function normalizeRequestHost(requestHost) {
  if (!requestHost || typeof requestHost !== 'string') return null;
  const host = requestHost.trim().split(':')[0];
  return isProbeableHostname(host) ? host : null;
}

function resolveTlsHostname(requestHost) {
  const explicit = process.env.SYSTEMS_TLS_HOSTNAME || process.env.LB_PUBLIC_HOSTNAME;
  if (explicit?.trim()) return explicit.trim();
  const fromRequest = normalizeRequestHost(requestHost);
  if (fromRequest) return fromRequest;
  const appUrl = process.env.APP_PUBLIC_URL || '';
  try {
    const host = new URL(appUrl).hostname;
    return isProbeableHostname(host) ? host : null;
  } catch {
    return null;
  }
}

function loadLbMetadata() {
  return {
    lbOcid: process.env.SYSTEMS_LB_OCID || null,
    lbName: process.env.SYSTEMS_LB_NAME || null,
    lbPublicIp: process.env.SYSTEMS_LB_PUBLIC_IP || null,
    certOcid: process.env.SYSTEMS_LB_CERT_OCID || null,
    certName: process.env.SYSTEMS_LB_CERT_NAME || null,
  };
}

async function probeLbCertificate(requestHost) {
  const meta = loadLbMetadata();
  const hostname = resolveTlsHostname(requestHost);
  if (!hostname) {
    return {
      ok: false,
      skipped: true,
      reason:
        'TLS hostname not configured — browse via the public URL, set SYSTEMS_TLS_HOSTNAME, or apply Terraform systems env.',
      hostname: null,
      ...meta,
    };
  }

  const connectHost = meta.lbPublicIp || hostname;
  const probe = await probeTlsCert(connectHost, { servername: hostname });
  return {
    ...probe,
    ...meta,
    hostname,
    probeHost: connectHost,
    sni: hostname,
  };
}

async function buildSystemsStatus({ port, requestHost } = {}) {
  const listenPort = Number(port || process.env.PORT || 3000);
  const repoUrl = process.env.SYSTEMS_REPO_URL || 'https://github.com/ltm893/cloud-store-893';

  const [lbCertificate, routes] = await Promise.all([
    probeLbCertificate(requestHost),
    Promise.all(NODE_ROUTE_CHECKS.map((check) => probeRoute(listenPort, check))),
  ]);

  return {
    generatedAt: new Date().toISOString(),
    repo: {
      url: repoUrl,
      label: repoUrl.replace(/^https?:\/\//, ''),
    },
    build: getBuildInfo(),
    host: getHostInfo(),
    clients: getStoreClients(),
    oci: loadOciResources(),
    lbCertificate,
    routes,
  };
}

module.exports = {
  NODE_ROUTE_CHECKS,
  WARNING_DAYS,
  certExpiryStatus,
  daysUntil,
  isProbeableHostname,
  resolveTlsHostname,
  loadLbMetadata,
  probeTlsCert,
  probeRoute,
  loadOciResources,
  filterOciResourcesForDisplay,
  buildSystemsStatus,
};
