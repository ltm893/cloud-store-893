const { restoreEntries, persistEntries } = require('./dev-session-store');

const FLOW_TTL_MS = 10 * 60 * 1000;
const STORE_KEY = 'oidcFlow';
const flows = new Map();

function isValidFlow(state, flow) {
  return Boolean(
    state &&
    flow?.state === state &&
    flow?.createdAt &&
    Date.now() - flow.createdAt <= FLOW_TTL_MS,
  );
}

function touchFlows() {
  persistEntries(STORE_KEY, flows);
}

function pruneExpired() {
  const now = Date.now();
  let changed = false;
  for (const [state, flow] of flows.entries()) {
    if (!flow?.createdAt || now - flow.createdAt > FLOW_TTL_MS) {
      flows.delete(state);
      changed = true;
    }
  }
  if (changed) touchFlows();
}

restoreEntries(STORE_KEY, flows, isValidFlow);
pruneExpired();

/**
 * Remember OIDC state/nonce for WebView flows where the flow cookie is lost
 * across the external IdP redirect.
 */
function createOidcFlow({ state, nonce, clientKind = null, registerId = null }) {
  pruneExpired();
  const key = String(state || '').trim();
  if (!key) throw new Error('OIDC flow state is required');
  const flow = {
    state: key,
    nonce,
    clientKind: clientKind ? String(clientKind).trim() : null,
    registerId: registerId ? String(registerId).trim() : null,
    createdAt: Date.now(),
  };
  flows.set(key, flow);
  touchFlows();
  return flow;
}

function getOidcFlow(state) {
  pruneExpired();
  const key = String(state || '').trim();
  if (!key) return null;
  const flow = flows.get(key);
  if (!flow || !isValidFlow(key, flow)) {
    flows.delete(key);
    touchFlows();
    return null;
  }
  return flow;
}

function deleteOidcFlow(state) {
  const key = String(state || '').trim();
  if (!key) return;
  if (flows.delete(key)) touchFlows();
}

function clearOidcFlowStore() {
  flows.clear();
  touchFlows();
}

module.exports = {
  createOidcFlow,
  getOidcFlow,
  deleteOidcFlow,
  clearOidcFlowStore,
};
