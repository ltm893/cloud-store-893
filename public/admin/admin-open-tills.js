/**
 * Supervisor force-close for open tills (orphan register / tablet in use).
 */
(function () {
  const panelEl = document.getElementById('openTillsPanel');
  const listEl = document.getElementById('openTillsList');
  const emptyEl = document.getElementById('openTillsEmpty');
  const forbiddenEl = document.getElementById('openTillsForbidden');

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

  function formatWhen(iso) {
    if (!iso) return '—';
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return '—';
    return d.toLocaleString();
  }

  function modeLabel(item) {
    return item?.cashMode === 'credit_only' ? 'Credit cards only' : 'Cash + card';
  }

  function statusLabel(item) {
    if (item?.pendingClose) return 'Closing (awaiting approval)';
    if (item?.status === 'in_progress') return 'Close in progress';
    return 'Open';
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
        const name = item.cashierEmail || item.cashierSub || 'Cashier';
        const register = item.registerId || '—';
        const expected =
          item.cashMode === 'credit_only' ? '—' : money(item.expectedCloseFloat);
        const pendingNote = item.pendingClose
          ? `<div class="approval-meta">Pending close · counted ${escapeHtml(money(item.pendingClose.countedCloseFloat))}</div>`
          : '';
        return `
      <article class="approval-card" data-till-id="${escapeHtml(String(item.id))}">
        <div class="approval-card-main">
          <div class="approval-card-head">
            <div class="approval-card-who">
              <strong>${escapeHtml(name)}</strong>
              <div class="approval-meta">Till #${escapeHtml(String(item.id))} · ${escapeHtml(register)} · ${escapeHtml(modeLabel(item))}</div>
              <div class="approval-meta">${escapeHtml(statusLabel(item))} · opened ${escapeHtml(formatWhen(item.openedAt))}</div>
              ${pendingNote}
            </div>
          </div>
          <dl class="approval-facts">
            <div class="approval-fact"><dt>Expected close</dt><dd>${escapeHtml(expected)}</dd></div>
            <div class="approval-fact"><dt>Cash sales</dt><dd>${escapeHtml(money(item.cashSalesTotal))}</dd></div>
            <div class="approval-fact"><dt>POS session</dt><dd>${escapeHtml(item.posSessionId ? String(item.posSessionId) : '—')}</dd></div>
          </dl>
        </div>
        <div class="approval-actions approval-actions--stacked">
          <button type="button" class="danger force-close-btn" data-force="${escapeHtml(String(item.id))}">Force close</button>
        </div>
      </article>`;
      })
      .join('');

    listEl.querySelectorAll('[data-force]').forEach((btn) => {
      btn.addEventListener('click', () => forceCloseTill(btn.dataset.force, btn));
    });
  }

  async function loadOpen({ quiet = false } = {}) {
    if (!session?.isSupervisor || loading) return;
    loading = true;
    if (!quiet) setStatus('Loading open tills…');
    try {
      const res = await apiFetch('/api/admin/open-tills');
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
        setStatus(count === 1 ? '1 open till' : `${count} open till(s)`);
      }
    } finally {
      loading = false;
    }
  }

  async function forceCloseTill(tillId, btn) {
    if (!tillId) return;
    const reason =
      window.prompt(
        'Force-close this till? Clears register lock without a cashier count.\n\nReason (optional):',
        '',
      ) ?? null;
    if (reason === null) return;

    btn.disabled = true;
    try {
      const res = await apiFetch(`/api/admin/open-tills/${encodeURIComponent(tillId)}/force-close`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ reason: reason.trim() || undefined }),
      });
      const payload = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(payload.error || res.statusText);
      const who = payload.cashierEmail || `till #${payload.tillId}`;
      setStatus(`Force-closed ${who} on ${payload.registerId || 'register'}`);
      await loadOpen({ quiet: true });
      window.AdminShiftCloses?.refresh?.();
    } catch (err) {
      setStatus(err.message, true);
      btn.disabled = false;
    }
  }

  function showView() {
    if (!session?.isSupervisor) {
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
    loadOpen();
    if (!pollTimer) pollTimer = window.setInterval(() => loadOpen({ quiet: true }), 8000);
  }

  function activate() {
    if (!session?.isSupervisor) return;
    active = true;
    panelEl.hidden = false;
    showView();
  }

  function deactivate() {
    active = false;
    panelEl.hidden = true;
    if (pollTimer) {
      window.clearInterval(pollTimer);
      pollTimer = null;
    }
  }

  function configure({ apiFetch: fetchFn, setStatus: statusFn, adminSession }) {
    apiFetch = fetchFn;
    setStatus = statusFn;
    session = adminSession;
  }

  window.AdminOpenTills = {
    configure,
    activate,
    deactivate,
    refresh: () => loadOpen({ quiet: true }),
  };
})();
