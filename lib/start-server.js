const fs = require('fs');
const https = require('https');

function shouldTrustProxy() {
  const raw = String(process.env.TRUST_PROXY || '').toLowerCase();
  if (raw === 'true' || raw === '1' || raw === 'yes') return true;
  if (raw === 'false' || raw === '0' || raw === 'no') return false;
  return (
    String(process.env.CASHIER_SESSION_SECURE || '').toLowerCase() === 'true' ||
    Boolean(process.env.TLS_KEY_PATH && process.env.TLS_CERT_PATH)
  );
}

function readTlsFile(label, filePath) {
  try {
    return fs.readFileSync(filePath);
  } catch (err) {
    console.error(`❌ ${label} not readable (${filePath}): ${err.message}`);
    process.exit(1);
  }
}

function loadTlsOptions() {
  const keyPath = process.env.TLS_KEY_PATH;
  const certPath = process.env.TLS_CERT_PATH;
  if (!keyPath && !certPath) return null;
  if (!keyPath || !certPath) {
    console.error('❌ TLS_KEY_PATH and TLS_CERT_PATH must both be set (or neither).');
    process.exit(1);
  }
  const opts = {
    key: readTlsFile('TLS_KEY_PATH', keyPath),
    cert: readTlsFile('TLS_CERT_PATH', certPath),
  };
  const caPath = process.env.TLS_CA_PATH;
  if (caPath) opts.ca = readTlsFile('TLS_CA_PATH', caPath);
  return opts;
}

/** @param {import('express').Express} app */
function startServer(app, port) {
  if (shouldTrustProxy()) {
    app.set('trust proxy', 1);
  }

  const tls = loadTlsOptions();
  const scheme = tls ? 'https' : 'http';
  const server = tls
    ? https.createServer(tls, app).listen(port)
    : app.listen(port);
  return { server, scheme };
}

module.exports = { startServer, shouldTrustProxy, loadTlsOptions };
