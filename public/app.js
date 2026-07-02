const fetchOpts = { credentials: 'include' };

const pinGateEl = document.getElementById('pinGate');
const pinSignInBlockEl = document.getElementById('pinSignInBlock');
const signInIdpHintEl = document.getElementById('signInIdpHint');
const pinDisplayEl = document.getElementById('pinDisplay');
const pinNumpadEl = document.getElementById('pinNumpad');
const pinSubmitBtn = document.getElementById('pinSubmitBtn');
const pinErrorEl = document.getElementById('pinError');
const approvalGateEl = document.getElementById('approvalGate');
const approvalCashierEl = document.getElementById('approvalCashier');
const approvalTimerEl = document.getElementById('approvalTimer');
const approvalPollStatusEl = document.getElementById('approvalPollStatus');
const approvalCancelBtn = document.getElementById('approvalCancelBtn');
const approvalErrorEl = document.getElementById('approvalError');
const tillGateEl = document.getElementById('tillGate');
const tillTargetEl = document.getElementById('tillTarget');
const tillDenomListEl = document.getElementById('tillDenomList');
const tillSummaryEl = document.getElementById('tillSummary');
const tillSubmitBtn = document.getElementById('tillSubmitBtn');
const tillCreditOnlyBtn = document.getElementById('tillCreditOnlyBtn');
const tillCancelBtn = document.getElementById('tillCancelBtn');
const tillErrorEl = document.getElementById('tillError');

const APPROVAL_POLL_MS = 2500;
const PIN_MAX = 8;

let approvalPollTimer = null;
let tillConfig = null;
let pinDigits = '';
let lastSessionData = null;

function money(value) {
  return PosMath.formatMoney(value);
}

function updatePinDisplay() {
  pinDisplayEl.textContent = pinDigits ? '•'.repeat(pinDigits.length) : '••••';
}

function renderPinNumpad() {
  const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9'];
  pinNumpadEl.innerHTML = '';
  const addKey = (label, handler) => {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'numpad-key';
    btn.textContent = label;
    btn.addEventListener('click', handler);
    pinNumpadEl.appendChild(btn);
  };

  keys.forEach((digit) => {
    addKey(digit, () => {
      if (pinDigits.length < PIN_MAX) {
        pinDigits += digit;
        updatePinDisplay();
      }
    });
  });
  addKey('C', () => {
    pinDigits = '';
    updatePinDisplay();
  });
  addKey('0', () => {
    if (pinDigits.length < PIN_MAX) {
      pinDigits += '0';
      updatePinDisplay();
    }
  });
  addKey('⌫', () => {
    pinDigits = pinDigits.slice(0, -1);
    updatePinDisplay();
  });
}

function stopApprovalPoll() {
  if (approvalPollTimer) {
    clearInterval(approvalPollTimer);
    approvalPollTimer = null;
  }
}

function hideApprovalGate() {
  approvalGateEl.hidden = true;
  approvalErrorEl.hidden = true;
  approvalErrorEl.textContent = '';
}

function hidePinGate() {
  pinGateEl.hidden = true;
  pinErrorEl.hidden = true;
  pinErrorEl.textContent = '';
  pinDigits = '';
  updatePinDisplay();
}

function hideTillGate() {
  tillGateEl.hidden = true;
  tillErrorEl.hidden = true;
  tillErrorEl.textContent = '';
  tillConfig = null;
}

function hideAllAuthOverlays() {
  hidePinGate();
  hideApprovalGate();
  hideTillGate();
  stopApprovalPoll();
  PosRegister.stop();
}

function formatApprovalTimer(secondsRemaining, expiresAt) {
  if (Number.isFinite(secondsRemaining) && secondsRemaining >= 0) {
    const mins = Math.floor(secondsRemaining / 60);
    const secs = secondsRemaining % 60;
    return `Request expires in ${mins}:${String(secs).padStart(2, '0')}`;
  }
  if (expiresAt) {
    return `Expires ${new Date(expiresAt).toLocaleTimeString()}`;
  }
  return '';
}

function showApprovalGate(approval) {
  hidePinGate();
  hideTillGate();
  PosRegister.stop();
  approvalGateEl.hidden = false;
  approvalErrorEl.hidden = true;
  approvalErrorEl.textContent = '';
  approvalPollStatusEl.textContent = 'Checking approval status…';

  if (approval?.cashierEmail) {
    approvalCashierEl.textContent = `Cashier: ${approval.cashierEmail}`;
    approvalCashierEl.hidden = false;
  } else {
    approvalCashierEl.hidden = true;
    approvalCashierEl.textContent = '';
  }

  approvalTimerEl.textContent = formatApprovalTimer(
    approval?.secondsRemaining,
    approval?.expiresAt,
  );
}

function showApprovalError(message) {
  approvalErrorEl.hidden = false;
  approvalErrorEl.textContent = message;
}

function configureIdpLink(data) {
  const idpLink = document.getElementById('idpLoginLink');
  if (idpLink && data.idpEnabled) {
    idpLink.hidden = false;
    if (data.idpLoginUrl) idpLink.href = data.idpLoginUrl;
  } else if (idpLink) {
    idpLink.hidden = true;
  }
}

function showPinGate(message, { pinAllowed = true } = {}) {
  hideApprovalGate();
  hideTillGate();
  stopApprovalPoll();
  PosRegister.stop();
  pinGateEl.hidden = false;

  const pinOk = pinAllowed !== false;
  pinSignInBlockEl.hidden = !pinOk;
  signInIdpHintEl.hidden = pinOk;

  if (message) {
    pinErrorEl.hidden = false;
    pinErrorEl.textContent = message;
  } else {
    pinErrorEl.hidden = true;
    pinErrorEl.textContent = '';
  }
}

function sumTillCounts(denominations, counts) {
  let total = 0;
  for (const denom of denominations || []) {
    const count = Number(counts[denom.id] || 0);
    if (!Number.isFinite(count) || count <= 0) continue;
    total += denom.value * count;
  }
  return PosMath.roundMoney(total);
}

function readTillCounts() {
  const counts = {};
  tillDenomListEl.querySelectorAll('[data-denom-id]').forEach((input) => {
    const id = input.dataset.denomId;
    const count = Math.max(0, Math.floor(Number(input.value) || 0));
    if (count > 0) counts[id] = count;
  });
  return counts;
}

function updateTillSummary() {
  if (!tillConfig) return;
  const counts = readTillCounts();
  const total = sumTillCounts(tillConfig.denominations, counts);
  const expected = tillConfig.expectedOpeningFloat;
  let summary = `Counted total: ${money(total)}`;
  let hasVariance = false;

  if (expected != null) {
    const variance = PosMath.roundMoney(total - expected);
    if (Math.abs(variance) > 0.005) {
      const sign = variance >= 0 ? '+' : '';
      summary += ` · Variance ${sign}${money(variance)}`;
      hasVariance = true;
    }
  }

  tillSummaryEl.textContent = summary;
  tillSummaryEl.classList.toggle('variance-warn', hasVariance);

  const hasCounts = Object.keys(counts).length > 0;
  const targetReached = expected == null || Math.abs(total - expected) < 0.005;
  tillSubmitBtn.disabled = !hasCounts && !targetReached;
  tillSubmitBtn.textContent = tillConfig.supervisorApprovalRequired
    ? 'Submit for approval'
    : 'Open register';
}

function showTillGate(data) {
  hidePinGate();
  hideApprovalGate();
  stopApprovalPoll();
  PosRegister.stop();
  tillConfig = {
    denominations: Array.isArray(data.denominations) ? data.denominations : [],
    expectedOpeningFloat: data.expectedOpeningFloat ?? null,
    awaitingTillToken: data.awaitingTillToken || null,
    supervisorApprovalRequired: Boolean(data.supervisorApprovalRequired),
  };

  if (tillConfig.expectedOpeningFloat != null) {
    tillTargetEl.textContent = `Target opening float: ${money(tillConfig.expectedOpeningFloat)}`;
    tillTargetEl.hidden = false;
  } else {
    tillTargetEl.hidden = true;
    tillTargetEl.textContent = '';
  }

  tillDenomListEl.innerHTML = tillConfig.denominations
    .map(
      (denom) => `
    <div class="till-denom-row">
      <label for="till-count-${escapeHtml(denom.id)}">${escapeHtml(denom.label)}</label>
      <input
        id="till-count-${escapeHtml(denom.id)}"
        type="number"
        min="0"
        step="1"
        inputmode="numeric"
        value="0"
        data-denom-id="${escapeHtml(denom.id)}"
        data-denom-value="${denom.value}"
      />
      <span class="till-denom-line" data-line-for="${escapeHtml(denom.id)}">${money(0)}</span>
    </div>
  `,
    )
    .join('');

  tillDenomListEl.querySelectorAll('[data-denom-id]').forEach((input) => {
    input.addEventListener('input', () => {
      const count = Math.max(0, Math.floor(Number(input.value) || 0));
      const value = Number(input.dataset.denomValue) || 0;
      const line = tillDenomListEl.querySelector(`[data-line-for="${input.dataset.denomId}"]`);
      if (line) line.textContent = money(value * count);
      updateTillSummary();
    });
  });

  tillErrorEl.hidden = true;
  tillErrorEl.textContent = '';
  tillGateEl.hidden = false;
  updateTillSummary();
}

function showTillError(message) {
  tillErrorEl.hidden = false;
  tillErrorEl.textContent = message;
}

async function submitOpeningTill(cashMode) {
  tillSubmitBtn.disabled = true;
  tillCreditOnlyBtn.disabled = true;
  tillCancelBtn.disabled = true;
  tillErrorEl.hidden = true;

  const body = { cashMode };
  if (cashMode === 'cash_and_credit') {
    const counts = readTillCounts();
    body.denominations = counts;
    body.countedTotal = sumTillCounts(tillConfig.denominations, counts);
  }
  if (tillConfig?.awaitingTillToken) {
    body.awaitingTillToken = tillConfig.awaitingTillToken;
  }

  try {
    const res = await fetch('/api/cashier/approval/till', {
      ...fetchOpts,
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    const data = await res.json().catch(() => ({}));

    if (res.status === 401) {
      hideTillGate();
      showPinGate(data.error || 'Sign-in expired — sign in with Oracle again', {
        pinAllowed: false,
      });
      return;
    }

    if (!res.ok) {
      showTillError(data.error || 'Could not submit till count');
      return;
    }

    if (data.pending) {
      hideTillGate();
      showApprovalGate({
        requestToken: data.requestToken,
        expiresAt: data.expiresAt,
        cashierEmail: data.cashierEmail,
        secondsRemaining: data.secondsRemaining,
      });
      startApprovalPoll();
      return;
    }

    hideTillGate();
    await initPos(lastSessionData);
  } catch (error) {
    console.error(error);
    showTillError('Network error while submitting till count');
  } finally {
    tillSubmitBtn.disabled = false;
    tillCreditOnlyBtn.disabled = false;
    tillCancelBtn.disabled = false;
    updateTillSummary();
  }
}

async function cancelTillWait() {
  tillCancelBtn.disabled = true;
  try {
    await fetch('/api/cashier/approval/till/cancel', {
      ...fetchOpts,
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
    });
    hideTillGate();
    const res = await fetch('/api/cashier/session', fetchOpts);
    const data = await res.json();
    applySessionGate(data);
  } catch (error) {
    console.error(error);
    showTillError('Could not cancel till count');
  } finally {
    tillCancelBtn.disabled = false;
  }
}

tillSubmitBtn.addEventListener('click', () => {
  if (tillSubmitBtn.disabled) return;
  submitOpeningTill('cash_and_credit');
});

tillCreditOnlyBtn.addEventListener('click', () => {
  if (!window.confirm('Open the register with credit card payments only (no cash today)?')) {
    return;
  }
  submitOpeningTill('credit_only');
});

tillCancelBtn.addEventListener('click', cancelTillWait);

function applySessionGate(data) {
  configureIdpLink(data);

  if (data.ok) {
    if (data.tillOpenForSales === false) {
      hideAllAuthOverlays();
      lastSessionData = data;
      showPinGate(
        data.saleBlockedMessage
          || 'This till was closed by a supervisor. Sign out and start a new shift to continue selling.',
        { pinAllowed: data.pinAllowed !== false },
      );
      return 'blocked';
    }
    hideAllAuthOverlays();
    lastSessionData = data;
    return 'ok';
  }

  if (data.pending) {
    showApprovalGate(data.approval);
    startApprovalPoll();
    return 'pending';
  }

  if (data.awaitingTill) {
    showTillGate(data);
    return 'awaitingTill';
  }

  if (data.supervisorApprovalRequired && data.idpEnabled && data.idpLoginUrl && !data.pinAllowed) {
    showPinGate('', { pinAllowed: false });
    return 'signIn';
  }

  if (data.idpEnabled && data.idpLoginUrl && !data.pinAllowed) {
    window.location.href = data.idpLoginUrl;
    return 'redirect';
  }

  showPinGate(data.idpEnabled ? 'Enter PIN or use IdP sign-in below' : '', {
    pinAllowed: data.pinAllowed,
  });
  return 'signIn';
}

async function pollApprovalStatus() {
  try {
    const res = await fetch('/api/cashier/approval/status', fetchOpts);
    const data = await res.json().catch(() => ({}));

    if (res.ok && data.status === 'approved' && data.ok) {
      stopApprovalPoll();
      hideAllAuthOverlays();
      const sessionRes = await fetch('/api/cashier/session', fetchOpts);
      lastSessionData = await sessionRes.json();
      await initPos(lastSessionData);
      return;
    }

    if (res.ok && data.status === 'pending') {
      approvalPollStatusEl.textContent = 'Still waiting for supervisor approval…';
      approvalTimerEl.textContent = formatApprovalTimer(
        data.secondsRemaining,
        data.expiresAt,
      );
      return;
    }

    stopApprovalPoll();

    if (data.status === 'denied') {
      hideApprovalGate();
      showPinGate(data.reason || 'Supervisor denied login', { pinAllowed: false });
      return;
    }

    if (data.status === 'cancelled' || data.status === 'expired') {
      hideApprovalGate();
      const msg =
        data.status === 'expired'
          ? 'Login request expired. Sign in again.'
          : 'Login request cancelled.';
      showPinGate(msg, { pinAllowed: false });
      return;
    }

    if (res.status === 401) {
      hideApprovalGate();
      showPinGate('No pending login request. Sign in again.', { pinAllowed: false });
      return;
    }

    showApprovalError(data.error || 'Unable to check approval status');
  } catch (error) {
    console.error(error);
    showApprovalError('Network error while waiting for approval');
  }
}

function startApprovalPoll() {
  stopApprovalPoll();
  pollApprovalStatus();
  approvalPollTimer = setInterval(pollApprovalStatus, APPROVAL_POLL_MS);
}

async function cancelApprovalWait() {
  approvalCancelBtn.disabled = true;
  try {
    const res = await fetch('/api/cashier/approval/cancel', {
      ...fetchOpts,
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
    });
    const data = await res.json().catch(() => ({}));
    stopApprovalPoll();
    hideApprovalGate();
    if (!res.ok) {
      showPinGate(data.error || 'Could not cancel request', { pinAllowed: false });
      return;
    }
    showPinGate('Login request cancelled.', { pinAllowed: false });
  } catch (error) {
    console.error(error);
    showApprovalError('Could not cancel request');
  } finally {
    approvalCancelBtn.disabled = false;
  }
}

approvalCancelBtn.addEventListener('click', cancelApprovalWait);

async function ensureCashierSession() {
  const res = await fetch('/api/cashier/session', fetchOpts);
  const data = await res.json();
  const gate = applySessionGate(data);
  if (gate === 'ok') {
    await initPos(data);
  }
  return gate === 'ok';
}

async function unlockCashier(pin) {
  const res = await fetch('/api/cashier/unlock', {
    ...fetchOpts,
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ pin }),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    showPinGate(data.error || 'Invalid PIN', { pinAllowed: true });
    return false;
  }
  if (data.awaitingTill) {
    hidePinGate();
    showTillGate(data);
    return false;
  }
  hidePinGate();
  return true;
}

pinSubmitBtn.addEventListener('click', async () => {
  if (!pinDigits) {
    showPinGate('Enter PIN', { pinAllowed: true });
    return;
  }
  pinSubmitBtn.disabled = true;
  const ok = await unlockCashier(pinDigits);
  pinSubmitBtn.disabled = false;
  if (ok) {
    pinDigits = '';
    updatePinDisplay();
    const res = await fetch('/api/cashier/session', fetchOpts);
    lastSessionData = await res.json();
    await initPos(lastSessionData);
  }
});

async function initPos(sessionData) {
  try {
    await PosRegister.start(sessionData || lastSessionData || {});
  } catch (error) {
    if (error && String(error).includes('401')) {
      await ensureCashierSession();
      return;
    }
    console.error(error);
  }
}

async function init() {
  renderPinNumpad();
  updatePinDisplay();

  const params = new URLSearchParams(window.location.search);
  if (params.get('approval') === 'pending' || params.get('awaiting_till') != null) {
    window.history.replaceState({}, '', window.location.pathname);
  }

  const res = await fetch('/api/cashier/session', fetchOpts);
  const data = await res.json();
  const gate = applySessionGate(data);

  if (gate === 'ok') {
    await initPos(data);
  }
}

init();
