/**
 * Supervisor shift-close panel (EOD till balance).
 */
(function () {
  const shiftClosesPanelEl = document.getElementById('shiftClosesPanel');
  const listEl = document.getElementById('shiftClosesList');
  const emptyEl = document.getElementById('shiftClosesEmpty');
  const forbiddenEl = document.getElementById('shiftClosesForbidden');

  let apiFetch = null;
  let setStatus = null;
  let session = null;
  let pollTimer = null;
  let active = false;
  let loading = false;

  function money(value) {
    const n = Number(value);
    if (!Number.isFinite(n)) return '—';
    return `$${n.toFixed(2)}`;
  }

  function formatTimer(secondsRemaining, expiresAt) {
    if (Number.isFinite(secondsRemaining) && secondsRemaining >= 0) {
      const mins = Math.floor(secondsRemaining / 60);
      const secs = secondsRemaining % 60;
      return `Expires in ${mins}:${String(secs).padStart(2, '0')}`;
    }
    if (expiresAt) return `Expires ${new Date(expiresAt).toLocaleTimeString()}`;
    return '';
  }

  function modeLabel(item) {
    return item?.cashMode === 'credit_only' ? 'Credit cards only' : 'Cash + card';
  }

  function renderItems(items) {
    if (!items.length) {
      listEl.innerHTML = '';
      emptyEl.hidden = false;
      return;
    }
    emptyEl.hidden = true;
    listEl.innerHTML = items
      .map((item) => {
        const name = item.cashierName || item.cashierEmail || item.cashierSub || 'Cashier';
        const timer = formatTimer(item.secondsRemaining, item.expiresAt);
        const counted =
          item.cashMode === 'credit_only' ? '—' : money(item.countedCloseFloat);
        const expected =
          item.cashMode === 'credit_only' ? '—' : money(item.expectedCloseFloat);
        const variance =
          item.cashMode === 'credit_only' ? '—' : money(item.closeVariance);
        return `
      <article class="approval-card" data-token="${escapeHtml(item.closeToken)}">
        <div class="approval-card-main">
          <div class="approval-card-head">
            <div class="approval-card-who">
              <strong>${escapeHtml(name)}</strong>
              <div class="approval-meta">Close till · ${escapeHtml(modeLabel(item))}</div>
            </div>
          </div>
          <dl class="approval-facts">
            <div class="approval-fact"><dt>Expected</dt><dd>${escapeHtml(expected)}</dd></div>
            <div class="approval-fact"><dt>Counted</dt><dd>${escapeHtml(counted)}</dd></div>
            <div class="approval-fact"><dt>Variance</dt><dd>${escapeHtml(variance)}</dd></div>
            <div class="approval-fact"><dt>Expires</dt><dd>${escapeHtml(timer || '—')}</dd></div>
          </dl>
        </div>
        <div class="approval-actions approval-actions--stacked">
          <button type="button" class="approve-btn" data-approve="${escapeHtml(item.closeToken)}">Approve close</button>
          <button type="button" class="deny-btn" data-deny="${escapeHtml(item.closeToken)}">Deny</button>
        </div>
      </article>`;
      })
      .join('');

    listEl.querySelectorAll('[data-approve]').forEach((btn) => {
      btn.addEventListener('click', () => approveClose(btn.dataset.approve, btn));
    });
    listEl.querySelectorAll('[data-deny]').forEach((btn) => {
      btn.addEventListener('click', () => denyClose(btn.dataset.deny, btn));
    });
  }

  async function loadPending({ quiet = false } = {}) {
    if (!session?.isSupervisor || loading) return;
    loading = true;
    if (!quiet) setStatus('Loading pending shift closes…');
    try {
      const res = await apiFetch('/api/admin/shift-closes?status=pending');
      const payload = await res.json().catch(() => ({}));
      if (res.status === 403) {
        session = { ...session, isSupervisor: false };
        showView();
        return;
      }
      if (!res.ok) throw new Error(payload.error || res.statusText);
      renderItems(Array.isArray(payload.items) ? payload.items : []);
      if (!quiet) {
        const count = Array.isArray(payload.items) ? payload.items.length : 0;
        setStatus(count === 1 ? '1 pending shift close' : `${count} pending shift close(s)`);
      }
    } finally {
      loading = false;
    }
  }

  async function approveClose(closeToken, btn) {
    if (!closeToken) return;
    btn.disabled = true;
    try {
      const res = await apiFetch(
        `/api/admin/shift-closes/${encodeURIComponent(closeToken)}/approve`,
        { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' },
      );
      const payload = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(payload.error || res.statusText);
      setStatus(`Approved close for ${payload.cashierEmail || payload.cashierName || 'cashier'}`);
      await loadPending({ quiet: true });
    } catch (err) {
      setStatus(err.message, true);
      btn.disabled = false;
    }
  }

  async function denyClose(closeToken, btn) {
    if (!closeToken) return;
    const reason = await AdminPrompt.ask({
      title: 'Deny till close',
      message: 'The cashier will need to submit a new close request.',
      label: 'Reason for denial (optional)',
      confirmText: 'Deny',
    });
    if (reason === null) return;

    btn.disabled = true;
    try {
      const res = await apiFetch(
        `/api/admin/shift-closes/${encodeURIComponent(closeToken)}/deny`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ reason: reason || undefined }),
        },
      );
      const payload = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(payload.error || res.statusText);
      setStatus('Shift close denied');
      await loadPending({ quiet: true });
    } catch (err) {
      setStatus(err.message, true);
      btn.disabled = false;
    }
  }

  function activate() {
    if (!session?.supervisorApprovalEnabled) return;
    active = true;
    shiftClosesPanelEl.hidden = false;
    if (!session.isSupervisor) {
      forbiddenEl.hidden = false;
      listEl.innerHTML = '';
      emptyEl.hidden = true;
      if (pollTimer) {
        window.clearInterval(pollTimer);
        pollTimer = null;
      }
      return;
    }
    forbiddenEl.hidden = true;
    loadPending();
    if (!pollTimer) pollTimer = window.setInterval(() => loadPending({ quiet: true }), 4000);
  }

  function deactivate() {
    active = false;
    shiftClosesPanelEl.hidden = true;
    if (pollTimer) {
      window.clearInterval(pollTimer);
      pollTimer = null;
    }
  }

  function show() {
    window.AdminTabs?.switchAdminTab?.('approvals');
  }

  function hide() {
    deactivate();
  }

  function isActive() {
    return active;
  }

  function configure({ apiFetch: fetchFn, setStatus: statusFn, adminSession }) {
    apiFetch = fetchFn;
    setStatus = statusFn;
    session = adminSession;
  }

  window.AdminShiftCloses = { configure, activate, deactivate, show, hide, isActive, refresh: () => loadPending({ quiet: true }) };
})();
