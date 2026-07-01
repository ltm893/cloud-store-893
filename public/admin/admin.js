const API = '/api/admin';

async function apiFetch(url, options = {}) {
  const res = await fetch(url, { credentials: 'same-origin', ...options });
  if (res.status === 401) {
    window.location.href = '/admin/login.html';
    throw new Error('Session expired');
  }
  return res;
}

const statusEl = document.getElementById('status');
const logoutBtn = document.getElementById('logoutBtn');
const tableNavEl = document.getElementById('tableNav');
const tableTitleEl = document.getElementById('tableTitle');
const tableHintEl = document.getElementById('tableHint');
const createFormEl = document.getElementById('createForm');
const dataHeadEl = document.getElementById('dataHead');
const dataBodyEl = document.getElementById('dataBody');
const editDialog = document.getElementById('editDialog');
const editForm = document.getElementById('editForm');
const editFieldsEl = document.getElementById('editFields');
const editCancelBtn = document.getElementById('editCancel');
const menuBtn = document.getElementById('menuBtn');
const approvalsPanelEl = document.getElementById('approvalsPanel');
const shiftClosesPanelEl = document.getElementById('shiftClosesPanel');
const openTillsPanelEl = document.getElementById('openTillsPanel');
const reportsPanelEl = document.getElementById('reportsPanel');
const systemsPanelEl = document.getElementById('systemsPanel');
const tablePanelEl = document.getElementById('tablePanel');
const approvalsTabBtn = document.getElementById('approvalsTabBtn');

const ADMIN_TAB_IDS = ['approvals', 'reports', 'systems', 'tables'];

let tablesMeta = [];
let activeTable = 'products';
let activeMeta = null;
let editingRow = null;
let activeAdminTab = 'tables';

function setStatus(message, isError = false) {
  statusEl.textContent = message || '';
  statusEl.classList.toggle('error', isError);
}

function columnHeaderLabel(meta, col) {
  return meta.columnLabels?.[col] || col;
}

function formatCell(value, col, tableName) {
  if (value === null || value === undefined || value === '') {
    if (tableName === 'till_open_approvals' && col === 'till_type') return '—';
    return '';
  }
  if (tableName === 'till_open_approvals') {
    if (col === 'till_type') {
      if (value === 'credit_only') return 'Card only';
      if (value === 'cash_and_card') return 'Cash + card';
    }
    if (
      col === 'opening_counted_float' ||
      col === 'expected_opening_float' ||
      col === 'opening_variance'
    ) {
      const n = Number(value);
      if (Number.isFinite(n)) return `$${n.toFixed(2)}`;
    }
  }
  if (tableName === 'till_close_approvals') {
    if (col === 'status' && value === 'force_closed') return 'Force closed';
    if (col === 'till_type') {
      if (value === 'credit_only') return 'Card only';
      if (value === 'cash_and_card') return 'Cash + card';
    }
    if (
      col === 'expected_close_float' ||
      col === 'counted_close_float' ||
      col === 'close_variance' ||
      col === 'cash_sales_total' ||
      col === 'change_given_total' ||
      col === 'opening_counted_float'
    ) {
      const n = Number(value);
      if (Number.isFinite(n)) return `$${n.toFixed(2)}`;
    }
  }
  if (tableName === 'tills') {
    if (col === 'till_type') {
      if (value === 'credit_only') return 'Credit cards only';
      if (value === 'cash_and_card') return 'Cash + card';
    }
    if (
      col === 'sales_total' ||
      col === 'cash_total' ||
      col === 'credit_total' ||
      col === 'expected_opening_float' ||
      col === 'opening_counted_float' ||
      col === 'opening_variance'
    ) {
      const n = Number(value);
      if (Number.isFinite(n)) return `$${n.toFixed(2)}`;
    }
  }
  if (typeof value === 'object') return escapeHtml(JSON.stringify(value));
  return escapeHtml(value);
}

menuBtn.addEventListener('click', () => {
  if (activeAdminTab !== 'tables') return;
  document.body.classList.toggle('nav-open');
});

function setPanelHidden(el, hidden) {
  if (el) el.hidden = hidden;
}

function resolveInitialAdminTab(session) {
  const requested = new URLSearchParams(window.location.search).get('tab');
  let tab = requested && ADMIN_TAB_IDS.includes(requested) ? requested : null;
  if (tab === 'approvals' && !session.isSupervisor && !session.supervisorApprovalEnabled) tab = null;
  if (!tab) {
    tab = session.isSupervisor ? 'approvals' : 'tables';
  }
  return tab;
}

function setAdminTabButtonActive(tab) {
  document.querySelectorAll('.admin-tab-btn').forEach((btn) => {
    btn.classList.toggle('active', btn.dataset.tab === tab);
  });
}

function switchAdminTab(tab) {
  if (!tab || tab === activeAdminTab) return;
  activeAdminTab = tab;
  document.body.classList.remove('tab-approvals', 'tab-reports', 'tab-systems', 'tab-tables');
  document.body.classList.add(`tab-${tab}`);
  setAdminTabButtonActive(tab);

  if (tab !== 'tables') {
    document.body.classList.remove('nav-open');
  }

  setPanelHidden(approvalsPanelEl, true);
  setPanelHidden(shiftClosesPanelEl, true);
  setPanelHidden(openTillsPanelEl, true);
  setPanelHidden(reportsPanelEl, true);
  setPanelHidden(systemsPanelEl, true);
  setPanelHidden(tablePanelEl, true);

  window.AdminApprovals?.deactivate?.();
  window.AdminShiftCloses?.deactivate?.();
  window.AdminOpenTills?.deactivate?.();
  window.AdminReports?.deactivate?.();
  window.AdminSystems?.deactivate?.();

  if (tab === 'approvals') {
    window.AdminApprovals?.activate?.();
    window.AdminShiftCloses?.activate?.();
    window.AdminOpenTills?.activate?.();
  } else if (tab === 'reports') {
    window.AdminReports?.activate?.();
  } else if (tab === 'systems') {
    setPanelHidden(systemsPanelEl, false);
    window.AdminSystems?.activate?.();
  } else if (tab === 'tables') {
    setPanelHidden(tablePanelEl, false);
    renderNav();
    loadTable(activeTable);
  }
}

document.querySelectorAll('.admin-tab-btn').forEach((btn) => {
  btn.addEventListener('click', () => switchAdminTab(btn.dataset.tab));
});

window.AdminTabs = { switchAdminTab, getActiveTab: () => activeAdminTab };

logoutBtn.addEventListener('click', async () => {
  await fetch(`${API}/logout`, { method: 'POST', credentials: 'same-origin' });
  window.location.href = '/admin/login.html?reauth=1';
});

editCancelBtn.addEventListener('click', () => editDialog.close());

editForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  if (!editingRow || !activeMeta) return;
  const id = editingRow.id;
  const body = {};
  for (const col of activeMeta.columns) {
    if (col === 'id') continue;
    const input = editFieldsEl.querySelector(`[name="${col}"]`);
    if (input) body[col] = input.value;
  }
  try {
    const res = await apiFetch(`${API}/${activeTable}/${id}`, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    const payload = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(payload.error || res.statusText);
    editDialog.close();
    setStatus('Row updated');
    await loadTable(activeTable);
  } catch (err) {
    setStatus(err.message, true);
  }
});

async function loadMeta() {
  const res = await apiFetch(`${API}/meta`);
  if (!res.ok) throw new Error('Failed to load admin metadata');
  tablesMeta = await res.json();
  tableNavEl.innerHTML = tablesMeta
    .map(
      (t) =>
        `<button type="button" data-table="${escapeHtml(t.name)}" class="${t.name === activeTable ? 'active' : ''}">${escapeHtml(t.label)}</button>`,
    )
    .join('');
  tableNavEl.querySelectorAll('button').forEach((btn) => {
    btn.addEventListener('click', () => {
      if (activeAdminTab !== 'tables') {
        switchAdminTab('tables');
      }
      activeTable = btn.dataset.table;
      document.body.classList.remove('nav-open');
      renderNav();
      loadTable(activeTable);
    });
  });
}

function setNavActive(tableName) {
  tableNavEl.querySelectorAll('button').forEach((btn) => {
    btn.classList.toggle('active', tableName != null && btn.dataset.table === tableName);
  });
}

function renderNav() {
  setNavActive(activeTable);
}

window.AdminTables = { setNavActive };

function renderCreateForm(meta) {
  if (meta.readOnly || !meta.create.length) {
    createFormEl.innerHTML = '';
    createFormEl.hidden = true;
    return;
  }
  createFormEl.hidden = false;
  createFormEl.innerHTML =
    meta.create
      .map(
        (col) =>
          `<label>${escapeHtml(col)}<input name="${escapeHtml(col)}" type="text" autocomplete="off"></label>`,
      )
      .join('') + '<button type="submit">Add row</button>';

  createFormEl.onsubmit = async (e) => {
    e.preventDefault();
    const body = {};
    for (const col of meta.create) {
      const input = createFormEl.querySelector(`[name="${col}"]`);
      body[col] = input ? input.value : '';
    }
    try {
      const res = await apiFetch(`${API}/${activeTable}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
      const payload = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(payload.error || res.statusText);
      setStatus('Row created');
      createFormEl.reset();
      await loadTable(activeTable);
    } catch (err) {
      setStatus(err.message, true);
    }
  };
}

function openEdit(row) {
  editingRow = row;
  const readOnlyCols = new Set(activeMeta.readOnlyColumns || []);
  editFieldsEl.innerHTML = activeMeta.columns
    .filter((c) => c !== 'id')
    .map((col) => {
      const val = row[col] ?? '';
      const disabled = readOnlyCols.has(col) ? ' disabled' : '';
      return `<label>${escapeHtml(col)}<input name="${escapeHtml(col)}" type="text" value="${attrEscape(val)}"${disabled}></label>`;
    })
    .join('');
  editDialog.showModal();
}

async function deleteRow(id) {
  if (!confirm(`Delete row ${id} from ${activeMeta.label}?`)) return;
  try {
    const res = await apiFetch(`${API}/${activeTable}/${id}`, { method: 'DELETE' });
    if (!res.ok) {
      const payload = await res.json().catch(() => ({}));
      throw new Error(payload.error || res.statusText);
    }
    setStatus('Row deleted');
    await loadTable(activeTable);
  } catch (err) {
    setStatus(err.message, true);
  }
}

async function loadTable(name) {
  if (activeAdminTab !== 'tables') return;
  tablePanelEl.hidden = false;

  activeMeta = tablesMeta.find((t) => t.name === name);
  if (!activeMeta) return;

  tableTitleEl.textContent = activeMeta.label;
  if (activeMeta.name === 'inventory_status_view') {
    tableHintEl.textContent =
      'Read-only stock levels for tracked products. Use Inventory movements for history; receive/adjust via API or Product inventory + movements.';
  } else if (activeMeta.name === 'product_inventory') {
    tableHintEl.textContent =
      'On-hand counts are read-only here — use POST /api/admin/inventory/receive, /adjust, or /set-count. Edit reorder points below.';
  } else if (activeMeta.name === 'bulk_inventory') {
    tableHintEl.textContent =
      'Kitchen bulk stock (oz). Quantity read-only — use POST /api/admin/inventory/bulk/receive, /adjust, or /set-count.';
  } else if (activeMeta.name === 'inventory_consumption_rules') {
    tableHintEl.textContent =
      'Oz (or unit) consumed per POS unit sold by product_type. Example: made coffee → 1.5 oz kitchen beans per drink.';
  } else if (activeMeta.name === 'till_open_approvals') {
    tableHintEl.textContent =
      'Read-only audit log. Use Till open approval (menu) to approve pending till opens.';
  } else if (activeMeta.name === 'till_close_approvals') {
    tableHintEl.textContent =
      'Read-only audit log. Use Till close approval (menu) to approve pending till closes.';
  } else if (activeMeta.name === 'tills') {
    tableHintEl.textContent =
      'Read-only till history. Active tills are highlighted in teal. Sales totals are computed from sales and payments.';
  } else if (activeMeta.readOnly) {
    tableHintEl.textContent = 'Read-only view.';
  } else {
    tableHintEl.textContent =
      'Create, edit, and delete rows. Changes apply to the live database.';
  }

  renderCreateForm(activeMeta);
  setStatus('Loading…');

  try {
    const res = await apiFetch(`${API}/${name}`);
    const rows = await res.json();
    if (!res.ok) throw new Error(rows.error || res.statusText);

    const cols = activeMeta.columns;
    dataHeadEl.innerHTML = `<tr>${cols
      .map((c) => `<th>${escapeHtml(columnHeaderLabel(activeMeta, c))}</th>`)
      .join('')}<th>Actions</th></tr>`;

    dataBodyEl.innerHTML = rows
      .map((row) => {
        const lowStock = activeMeta.name === 'inventory_status_view' && Number(row.low_stock) === 1;
        const tillActive =
          activeMeta.name === 'tills' && String(row.status || '').toLowerCase() === 'active';
        const cells = cols
          .map((c) => {
            const cls = lowStock && c === 'quantity_on_hand' ? ' class="low-stock"' : '';
            return `<td${cls}>${formatCell(row[c], c, activeMeta.name)}</td>`;
          })
          .join('');
        const actions = activeMeta.readOnly
          ? ''
          : `<td class="row-actions">
              <button type="button" data-edit="${row.id}">Edit</button>
              <button type="button" class="danger" data-del="${row.id}">Delete</button>
            </td>`;
        const rowCls = tillActive ? ' class="till-row-active"' : '';
        return `<tr${rowCls}>${cells}${activeMeta.readOnly ? '' : actions}</tr>`;
      })
      .join('');

    dataBodyEl.querySelectorAll('[data-edit]').forEach((btn) => {
      btn.addEventListener('click', () => {
        const row = rows.find((r) => String(r.id) === btn.dataset.edit);
        if (row) openEdit(row);
      });
    });
    dataBodyEl.querySelectorAll('[data-del]').forEach((btn) => {
      btn.addEventListener('click', () => deleteRow(btn.dataset.del));
    });

    setStatus(`${rows.length} row(s)`);
  } catch (err) {
    dataHeadEl.innerHTML = '';
    dataBodyEl.innerHTML = '';
    setStatus(err.message, true);
  }
}

(async function init() {
  try {
    const sessionRes = await fetch(`${API}/session`, { credentials: 'same-origin' });
    const session = await sessionRes.json();
    if (!session.ok) {
      window.location.href = '/admin/login.html';
      return;
    }
    if (window.AdminApprovals) {
      window.AdminApprovals.configure({
        apiFetch,
        setStatus,
        adminSession: session,
      });
    }
    if (window.AdminShiftCloses) {
      window.AdminShiftCloses.configure({
        apiFetch,
        setStatus,
        adminSession: session,
      });
    }
    if (window.AdminOpenTills) {
      window.AdminOpenTills.configure({
        apiFetch,
        setStatus,
        adminSession: session,
      });
    }
    if (window.AdminReports) {
      window.AdminReports.configure({
        apiFetch,
        setStatus,
      });
    }
    if (window.AdminSystems) {
      window.AdminSystems.configure({
        apiFetch,
        setStatus,
      });
    }
    if (!session.supervisorApprovalEnabled && !session.isSupervisor && approvalsTabBtn) {
      approvalsTabBtn.hidden = true;
    }
    await loadMeta();
    const defaultTab = resolveInitialAdminTab(session);
    activeAdminTab = '';
    switchAdminTab(defaultTab);
    if (defaultTab === 'tables' && window.matchMedia('(min-width: 900px)').matches) {
      document.body.classList.add('nav-open');
    }
  } catch (err) {
    if (err.message !== 'Session expired') setStatus(err.message, true);
  }
})();
