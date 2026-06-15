/**
 * Supervisor login-approval panel (Model B).
 * Loaded before admin.js; exposes window.AdminApprovals.
 */
(function () {
  const APPROVAL_POLL_MS = 4000;

  const approvalsPanelEl = document.getElementById('approvalsPanel');
  const approvalsListEl = document.getElementById('approvalsList');
  const approvalsEmptyEl = document.getElementById('approvalsEmpty');
  const approvalsForbiddenEl = document.getElementById('approvalsForbidden');
  const approvalsLastActionEl = document.getElementById('approvalsLastAction');

  let apiFetch = null;
  let setStatus = null;
  let session = null;
  let pollTimer = null;
  let active = false;
  let loading = false;

  function formatTimer(secondsRemaining, expiresAt) {
    if (Number.isFinite(secondsRemaining) && secondsRemaining >= 0) {
      const mins = Math.floor(secondsRemaining / 60);
      const secs = secondsRemaining % 60;
      return `Expires in ${mins}:${String(secs).padStart(2, '0')}`;
    }
    if (expiresAt) {
      return `Expires ${new Date(expiresAt).toLocaleTimeString()}`;
    }
    return '';
  }

  function formatWhen(iso) {
    if (!iso) return '';
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return '';
    return d.toLocaleString();
  }

  function money(value) {
    const n = Number(value);
    if (!Number.isFinite(n)) return '—';
    return `$${n.toFixed(2)}`;
  }

  const DENOM_LABELS = {
    100: '$100 bill',
    50: '$50 bill',
    20: '$20 bill',
    10: '$10 bill',
    5: '$5 bill',
    1: '$1 bill',
    0.25: 'Quarters',
    0.1: 'Dimes',
    0.05: 'Nickels',
    0.01: 'Pennies',
  };

  function denomLabel(id) {
    return DENOM_LABELS[id] || `$${id}`;
  }

  function isCreditOnly(item) {
    return item?.cashMode === 'credit_only';
  }

  function formatDenomBreakdown(openingDenominations) {
    if (!openingDenominations || typeof openingDenominations !== 'object') return '';
    const lines = Object.entries(openingDenominations)
      .filter(([, count]) => Number(count) > 0)
      .sort((a, b) => Number(b[0]) - Number(a[0]))
      .map(([id, count]) => `${denomLabel(id)}: ${count}`);
    if (!lines.length) return '';
    return `<ul class="approval-denom-list">${lines
      .map((line) => `<li>${escapeHtml(line)}</li>`)
      .join('')}</ul>`;
  }

  function shiftModeCell(item) {
    if (!item?.cashMode) {
      return `<span class="approval-mode-badge approval-mode-badge--unknown">Pending</span>`;
    }
    if (isCreditOnly(item)) {
      return `<span class="approval-mode-badge approval-mode-badge--credit">Credit cards only</span>`;
    }
    return `<span class="approval-mode-badge approval-mode-badge--cash">Cash + card</span>`;
  }

  function openingCell(item) {
    if (isCreditOnly(item)) return '—';
    if (Number.isFinite(item.openingCountedFloat)) {
      return money(item.openingCountedFloat);
    }
    return '—';
  }

  function renderApprovalSummary(item) {
    if (!item?.cashMode) {
      return `
        <div class="approval-till-summary approval-till-summary--unknown">
          <span class="approval-mode-badge">Mode pending</span>
          <p class="approval-summary-lead">Cashier has not finished the opening till step yet, or this request is missing till data. Deny and have them sign in again if it stays empty.</p>
        </div>`;
    }

    if (isCreditOnly(item)) {
      return `
        <div class="approval-till-summary approval-till-summary--credit">
          <span class="approval-mode-badge approval-mode-badge--credit">Credit cards only</span>
          <p class="approval-summary-lead">No cash drawer — card payments only for this shift.</p>
        </div>`;
    }

    const counted = item.openingCountedFloat;
    const expected = item.expectedOpeningFloat;
    const variance = item.openingVariance;
    const varianceClass =
      Number.isFinite(variance) && Math.abs(variance) > 0.009 ? ' approval-variance-warn' : '';
    const varianceLine =
      Number.isFinite(variance) && Number.isFinite(counted)
        ? `<p class="approval-meta${varianceClass}">Variance: ${variance >= 0 ? '+' : ''}${money(variance)}</p>`
        : '';

    return `
      <div class="approval-till-summary approval-till-summary--cash">
        <span class="approval-mode-badge approval-mode-badge--cash">Cash + card</span>
        <p class="approval-summary-lead">Approving opening cash drawer and card payments.</p>
        <p class="approval-summary-amount">Opening counted: <strong>${money(counted)}</strong></p>
        ${
          Number.isFinite(expected)
            ? `<p class="approval-meta">Target float: ${money(expected)}</p>`
            : ''
        }
        ${varianceLine}
        ${formatDenomBreakdown(item.openingDenominations)}
      </div>`;
  }

  function approveButtonLabel(item) {
    if (isCreditOnly(item)) return 'Approve credit cards only';
    if (item?.cashMode === 'cash_and_credit') return 'Approve cash + card';
    return 'Approve';
  }

  function cashModeLabel(cashMode) {
    if (cashMode === 'credit_only') return 'Credit cards only';
    if (cashMode === 'cash_and_credit') return 'Cash + card';
    return 'Register login';
  }

  function formatResolvedApprovalMessage(payload, action) {
    const mode = cashModeLabel(payload?.cashMode);
    const who =
      payload?.cashierEmail || payload?.cashierName || payload?.cashierSub || 'cashier';
    const verb = action === 'denied' ? 'Denied' : 'Approved';
    if (payload?.cashMode === 'credit_only') {
      return {
        title: `${verb}: ${mode}`,
        detail: `${who} may use card payments only (no cash drawer).`,
      };
    }
    if (payload?.cashMode === 'cash_and_credit') {
      const opening = Number.isFinite(payload.openingCountedFloat)
        ? `Opening float ${money(payload.openingCountedFloat)}`
        : null;
      const target = Number.isFinite(payload.expectedOpeningFloat)
        ? `target ${money(payload.expectedOpeningFloat)}`
        : null;
      const variance =
        Number.isFinite(payload.openingVariance) && Math.abs(payload.openingVariance) > 0.009
          ? `variance ${payload.openingVariance >= 0 ? '+' : ''}${money(payload.openingVariance)}`
          : null;
      const parts = [opening, target, variance].filter(Boolean);
      return {
        title: `${verb}: ${mode}`,
        detail:
          parts.length > 0
            ? `${who} — ${parts.join(' · ')}.`
            : `${who} may use cash and card payments.`,
      };
    }
    return {
      title: `${verb} login`,
      detail: who,
    };
  }

  function showLastApprovalAction(payload, action) {
    if (!approvalsLastActionEl) return;
    const { title, detail } = formatResolvedApprovalMessage(payload, action);
    approvalsLastActionEl.hidden = false;
    approvalsLastActionEl.classList.toggle('approvals-last-action--deny', action === 'denied');
    approvalsLastActionEl.innerHTML = `<strong>${escapeHtml(title)}</strong><span>${escapeHtml(detail)}</span>`;
  }

  function stopPoll() {
    if (pollTimer) {
      clearInterval(pollTimer);
      pollTimer = null;
    }
  }

  function startPoll() {
    stopPoll();
    if (!active || !session?.isSupervisor) return;
    pollTimer = setInterval(() => {
      loadPending({ quiet: true }).catch(() => {});
    }, APPROVAL_POLL_MS);
  }

  function activate() {
    if (!session?.supervisorApprovalEnabled) return;
    active = true;
    approvalsPanelEl.hidden = false;
    if (!session?.isSupervisor) {
      approvalsForbiddenEl.hidden = false;
      approvalsListEl.innerHTML = '';
      approvalsEmptyEl.hidden = true;
      stopPoll();
      return;
    }
    approvalsForbiddenEl.hidden = true;
    loadPending().catch((err) => setStatus(err.message, true));
    startPoll();
  }

  function deactivate() {
    active = false;
    approvalsPanelEl.hidden = true;
    stopPoll();
  }

  function showApprovalsView() {
    window.AdminTabs?.switchAdminTab?.('approvals');
  }

  function hideApprovalsView() {
    if (window.AdminTabs?.getActiveTab?.() === 'approvals') {
      window.AdminTabs?.switchAdminTab?.('tables');
    } else {
      deactivate();
    }
  }

  function renderItems(items) {
    if (!session?.isSupervisor) return;

    if (!items.length) {
      approvalsListEl.innerHTML = '';
      approvalsEmptyEl.hidden = false;
      return;
    }

    approvalsEmptyEl.hidden = true;
    approvalsListEl.innerHTML = items
      .map((item) => {
        const name = item.cashierName || item.cashierEmail || item.cashierSub || 'Cashier';
        const email = item.cashierEmail && item.cashierEmail !== name ? item.cashierEmail : '';
        const timer = formatTimer(item.secondsRemaining, item.expiresAt);
        const opening = openingCell(item);
        const details = renderApprovalSummary(item);

        return `
      <article class="approval-card" data-token="${escapeHtml(item.requestToken)}">
        <div class="approval-card-main">
          <div class="approval-card-head">
            <div class="approval-card-who">
              <strong>${escapeHtml(name)}</strong>
              ${email ? `<div class="approval-meta">${escapeHtml(email)}</div>` : ''}
            </div>
            <div class="approval-card-mode">${shiftModeCell(item)}</div>
          </div>
          <dl class="approval-facts">
            <div class="approval-fact">
              <dt>Opening</dt>
              <dd>${escapeHtml(opening)}</dd>
            </div>
            <div class="approval-fact">
              <dt>Client</dt>
              <dd>${escapeHtml(item.clientKind || '—')}</dd>
            </div>
            <div class="approval-fact">
              <dt>Expires</dt>
              <dd>${escapeHtml(timer || '—')}</dd>
            </div>
          </dl>
          ${details}
        </div>
        <div class="approval-actions approval-actions--stacked">
          <button type="button" class="approve-btn" data-approve="${escapeHtml(item.requestToken)}">${escapeHtml(approveButtonLabel(item))}</button>
          <button type="button" class="deny-btn" data-deny="${escapeHtml(item.requestToken)}">Deny</button>
        </div>
      </article>`;
      })
      .join('');

    approvalsListEl.querySelectorAll('[data-approve]').forEach((btn) => {
      btn.addEventListener('click', () => approveRequest(btn.dataset.approve, btn));
    });
    approvalsListEl.querySelectorAll('[data-deny]').forEach((btn) => {
      btn.addEventListener('click', () => denyRequest(btn.dataset.deny, btn));
    });
  }

  async function loadPending({ quiet = false } = {}) {
    if (!session?.isSupervisor || loading) return;
    loading = true;
    if (!quiet) setStatus('Loading pending approvals…');

    try {
      const res = await apiFetch('/api/admin/login-approvals?status=pending');
      const payload = await res.json().catch(() => ({}));
      if (res.status === 403) {
        session = { ...session, isSupervisor: false };
        showApprovalsView();
        return;
      }
      if (!res.ok) throw new Error(payload.error || res.statusText);

      const items = Array.isArray(payload.items) ? payload.items : [];
      renderItems(items);
      if (!quiet) {
        setStatus(
          items.length === 1
            ? '1 pending login request'
            : `${items.length} pending login request(s)`,
        );
      }
    } finally {
      loading = false;
    }
  }

  async function approveRequest(requestToken, btn) {
    if (!requestToken) return;
    btn.disabled = true;
    try {
      const res = await apiFetch(
        `/api/admin/login-approvals/${encodeURIComponent(requestToken)}/approve`,
        { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' },
      );
      const payload = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(payload.error || res.statusText);
      showLastApprovalAction(payload, 'approved');
      const { title } = formatResolvedApprovalMessage(payload, 'approved');
      setStatus(title);
      await loadPending({ quiet: true });
    } catch (err) {
      setStatus(err.message, true);
    } finally {
      btn.disabled = false;
    }
  }

  async function denyRequest(requestToken, btn) {
    if (!requestToken) return;
    const reason = window.prompt('Reason for denial (optional):', '') ?? '';
    if (reason === null) return;

    btn.disabled = true;
    try {
      const res = await apiFetch(
        `/api/admin/login-approvals/${encodeURIComponent(requestToken)}/deny`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ reason: reason.trim() || undefined }),
        },
      );
      const payload = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(payload.error || res.statusText);
      showLastApprovalAction(payload, 'denied');
      const { title } = formatResolvedApprovalMessage(payload, 'denied');
      setStatus(title);
      await loadPending({ quiet: true });
    } catch (err) {
      setStatus(err.message, true);
    } finally {
      btn.disabled = false;
    }
  }

  function configure({ apiFetch: fetchFn, setStatus: statusFn, adminSession }) {
    apiFetch = fetchFn;
    setStatus = statusFn;
    session = adminSession;
  }

  window.AdminApprovals = {
    configure,
    activate,
    deactivate,
    show: showApprovalsView,
    hide: hideApprovalsView,
    isActive: () => active,
    refresh: () => loadPending({ quiet: true }),
  };
})();
