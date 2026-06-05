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

let tablesMeta = [];
let activeTable = 'products';
let activeMeta = null;
let editingRow = null;

function setStatus(message, isError = false) {
  statusEl.textContent = message || '';
  statusEl.classList.toggle('error', isError);
}

function escapeHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

function formatCell(value) {
  if (value === null || value === undefined) return '';
  if (typeof value === 'object') return escapeHtml(JSON.stringify(value));
  return escapeHtml(value);
}

menuBtn.addEventListener('click', () => {
  document.body.classList.toggle('nav-open');
});

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
      if (window.AdminApprovals?.isActive?.()) {
        window.AdminApprovals.hide();
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

function attrEscape(s) {
  return String(s ?? '')
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;');
}

function openEdit(row) {
  editingRow = row;
  editFieldsEl.innerHTML = activeMeta.columns
    .filter((c) => c !== 'id')
    .map((col) => {
      const val = row[col] ?? '';
      return `<label>${escapeHtml(col)}<input name="${escapeHtml(col)}" type="text" value="${attrEscape(val)}"></label>`;
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
  activeMeta = tablesMeta.find((t) => t.name === name);
  if (!activeMeta) return;

  tableTitleEl.textContent = activeMeta.label;
  tableHintEl.textContent = activeMeta.readOnly
    ? 'Read-only view (ORDS cart_view).'
    : 'Create, edit, and delete rows. Changes apply to the live database.';

  renderCreateForm(activeMeta);
  setStatus('Loading…');

  try {
    const res = await apiFetch(`${API}/${name}`);
    const rows = await res.json();
    if (!res.ok) throw new Error(rows.error || res.statusText);

    const cols = activeMeta.columns;
    dataHeadEl.innerHTML = `<tr>${cols.map((c) => `<th>${escapeHtml(c)}</th>`).join('')}<th>Actions</th></tr>`;

    dataBodyEl.innerHTML = rows
      .map((row) => {
        const cells = cols.map((c) => `<td>${formatCell(row[c])}</td>`).join('');
        const actions = activeMeta.readOnly
          ? ''
          : `<td class="row-actions">
              <button type="button" data-edit="${row.id}">Edit</button>
              <button type="button" class="danger" data-del="${row.id}">Delete</button>
            </td>`;
        return `<tr>${cells}${activeMeta.readOnly ? '' : actions}</tr>`;
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
    if (window.matchMedia('(min-width: 900px)').matches) {
      document.body.classList.add('nav-open');
    }
    if (window.AdminApprovals) {
      window.AdminApprovals.configure({
        apiFetch,
        setStatus,
        adminSession: session,
      });
    }
    await loadMeta();
    if (session.supervisorApprovalEnabled && session.isSupervisor) {
      window.AdminApprovals.show();
    } else {
      await loadTable(activeTable);
    }
  } catch (err) {
    if (err.message !== 'Session expired') setStatus(err.message, true);
  }
})();
