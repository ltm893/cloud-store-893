/** BUILD_ID display helpers — shared by /api/build-info and /api/systems. */

const { version: packageVersion } = require('../package.json');

const TIMESTAMP_RE = /^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})$/;

function stripDeployPrefix(buildId) {
  return String(buildId || '').replace(/^deploy-/, '');
}

function isTimestampBuildId(buildId) {
  return TIMESTAMP_RE.test(stripDeployPrefix(buildId));
}

function normalizeBuildId(buildId) {
  const raw = String(buildId || 'unknown');
  if (raw === 'unknown' || raw === 'dev') return raw;
  const stripped = stripDeployPrefix(raw);
  return isTimestampBuildId(stripped) ? stripped : raw;
}

function normalizeGitSha(sha) {
  const raw = String(sha || '').trim();
  if (!raw || raw === 'unknown') return null;
  return raw.slice(0, 7);
}

function getAppVersion(env = process.env) {
  const override = String(env.APP_VERSION || '').trim();
  return override || packageVersion;
}

function buildInfoLabel(buildId) {
  const raw = String(buildId || 'unknown');
  if (raw === 'unknown' || raw === 'dev') return raw;

  const stamp = TIMESTAMP_RE.exec(stripDeployPrefix(raw));
  if (stamp) {
    const [, y, mo, d, h, mi, s] = stamp;
    return `${y}-${mo}-${d} ${h}:${mi}:${s} UTC`;
  }

  return raw.replace(/-/g, ' ');
}

function formatBuildInfo(buildId, explicitLabel) {
  const normalized = normalizeBuildId(buildId);
  const label = String(explicitLabel ?? '').trim() || buildInfoLabel(normalized);
  return {
    buildId: normalized,
    label,
  };
}

function formatBuildDisplay({ buildId, label, appVersion, gitSha } = {}) {
  if (!buildId) return '—';
  const left = label || buildId;
  const versionPrefix =
    appVersion && appVersion !== 'unknown' ? `v${appVersion} · ` : '';
  const shaSuffix = gitSha ? ` (${gitSha})` : '';
  return `${versionPrefix}${left} : ${buildId}${shaSuffix}`;
}

function getBuildInfo(env = process.env) {
  const base = formatBuildInfo(env.BUILD_ID || 'unknown', env.BUILD_LABEL);
  const appVersion = getAppVersion(env);
  const gitSha = normalizeGitSha(env.GIT_SHA);
  const info = { ...base, appVersion, gitSha };
  info.display = formatBuildDisplay(info);
  return info;
}

module.exports = {
  buildInfoLabel,
  formatBuildInfo,
  formatBuildDisplay,
  getAppVersion,
  getBuildInfo,
  isTimestampBuildId,
  normalizeBuildId,
  normalizeGitSha,
};
