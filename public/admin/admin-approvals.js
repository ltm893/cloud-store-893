/**
 * Supervisor login-approval panel (Model B).
 * Loaded before admin.js; exposes window.AdminApprovals.
 */
(function () {
  const APPROVAL_POLL_MS = 4000;

  const approvalsNavEl = document.getElementById('approvalsNav');
  const approvalsNavBtn = document.getElementById('approvalsNavBtn');
  const approvalsPanelEl = document.getElementById('approvalsPanel');
  const tablePanelEl = document.getElementById('tablePanel');
  const approvalsListEl = document.getElementById('approvalsList');
  const approvalsEmptyEl = document.getElementById('approvalsEmpty');
  const approvalsForbiddenEl = document.getElementById('approvalsForbidden');

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

  function renderNavActive(isApprovalsView) {
    if (approvalsNavBtn) {
      approvalsNavBtn.classList.toggle('active', isApprovalsView);
    }
  }

  function showApprovalsView() {
    active = true;
    approvalsPanelEl.hidden = false;
    tablePanelEl.hidden = true;
    renderNavActive(true);
    if (window.AdminTables?.setNavActive) {
      window.AdminTables.setNavActive(null);
    }
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

  function hideApprovalsView() {
    active = false;
    approvalsPanelEl.hidden = true;
    tablePanelEl.hidden = false;
    renderNavActive(false);
    stopPoll();
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
        const emailLine = item.cashierEmail
          ? `<p class="approval-meta">${escapeHtml(item.cashierEmail)}</p>`
          : '';
        const register = item.registerId
          ? `<p class="approval-meta">Register: ${escapeHtml(item.registerId)}</p>`
          : '';
        const client = item.clientKind
          ? `<p class="approval-meta">Client: ${escapeHtml(item.clientKind)}</p>`
          : '';
        const requested = item.requestedAt
          ? `<p class="approval-meta">Requested ${escapeHtml(formatWhen(item.requestedAt))}</p>`
          : '';
        const timer = formatTimer(item.secondsRemaining, item.expiresAt);
        const timerLine = timer
          ? `<p class="approval-meta">${escapeHtml(timer)}</p>`
          : '';

        return `
      <article class="approval-card" data-token="${escapeHtml(item.requestToken)}">
        <div class="approval-card-main">
          <strong>${escapeHtml(name)}</strong>
          ${emailLine}
          ${register}
          ${client}
          ${requested}
          ${timerLine}
        </div>
        <div class="approval-actions">
          <button type="button" class="approve-btn" data-approve="${escapeHtml(item.requestToken)}">Approve</button>
          <button type="button" class="deny-btn" data-deny="${escapeHtml(item.requestToken)}">Deny</button>
        </div>
      </article>
    `;
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
      setStatus(
        payload.cashierEmail
          ? `Approved login for ${payload.cashierEmail}`
          : 'Login approved',
      );
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
      setStatus(
        payload.cashierEmail
          ? `Denied login for ${payload.cashierEmail}`
          : 'Login denied',
      );
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

    if (!session?.supervisorApprovalEnabled) {
      approvalsNavEl.hidden = true;
      return;
    }

    approvalsNavEl.hidden = false;
    approvalsNavBtn.addEventListener('click', () => {
      document.body.classList.remove('nav-open');
      showApprovalsView();
    });
  }

  window.AdminApprovals = {
    configure,
    show: showApprovalsView,
    hide: hideApprovalsView,
    isActive: () => active,
    refresh: () => loadPending({ quiet: true }),
  };
})();
