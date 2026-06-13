/**
 * Admin on-demand sales and inventory reports.
 */
(function initAdminReports() {
  const reportsNavEl = document.getElementById('reportsNav');
  const reportsNavBtn = document.getElementById('reportsNavBtn');
  const reportsPanelEl = document.getElementById('reportsPanel');
  const tablePanelEl = document.getElementById('tablePanel');
  const periodSelectEl = document.getElementById('reportsPeriod');
  const anchorInputEl = document.getElementById('reportsAnchor');
  const loadBtnEl = document.getElementById('reportsLoadBtn');
  const salesSummaryEl = document.getElementById('reportsSalesSummary');
  const inventorySummaryEl = document.getElementById('reportsInventorySummary');
  const salesByDayEl = document.getElementById('reportsSalesByDay');
  const topProductsEl = document.getElementById('reportsTopProducts');
  const lowStockEl = document.getElementById('reportsLowStock');
  const movementsEl = document.getElementById('reportsMovements');
  const rangeLabelEl = document.getElementById('reportsRangeLabel');

  let apiFetch = null;
  let setStatus = null;
  let active = false;

  function money(value) {
    const n = Number(value);
    if (!Number.isFinite(n)) return '—';
    return `$${n.toFixed(2)}`;
  }

  function int(value) {
    const n = Number(value);
    if (!Number.isFinite(n)) return '—';
    return String(Math.round(n));
  }

  function todayAnchor() {
    const now = new Date();
    const y = now.getUTCFullYear();
    const m = String(now.getUTCMonth() + 1).padStart(2, '0');
    const d = String(now.getUTCDate()).padStart(2, '0');
    return `${y}-${m}-${d}`;
  }

  function renderSummaryGrid(el, rows) {
    el.innerHTML = rows
      .map(
        ([label, value]) =>
          `<div class="report-stat"><dt>${label}</dt><dd>${value}</dd></div>`,
      )
      .join('');
  }

  function renderTable(el, columns, rows) {
    if (!rows.length) {
      el.innerHTML = '<p class="hint">No rows for this period.</p>';
      return;
    }
    const head = columns.map(([key, label]) => `<th>${label}</th>`).join('');
    const body = rows
      .map((row) => {
        const cells = columns
          .map(([key]) => `<td>${row[key] ?? ''}</td>`)
          .join('');
        return `<tr>${cells}</tr>`;
      })
      .join('');
    el.innerHTML = `<table><thead><tr>${head}</tr></thead><tbody>${body}</tbody></table>`;
  }

  async function loadReports() {
    const period = periodSelectEl?.value || 'daily';
    const anchor = anchorInputEl?.value || todayAnchor();
    if (!apiFetch || !setStatus) return;

    setStatus('Loading reports…');
    try {
      const qs = new URLSearchParams({ period, anchor });
      const [salesRes, inventoryRes] = await Promise.all([
        apiFetch(`/api/admin/reports/sales?${qs}`),
        apiFetch(`/api/admin/reports/inventory?${qs}`),
      ]);
      const sales = await salesRes.json();
      const inventory = await inventoryRes.json();
      if (!salesRes.ok) throw new Error(sales.error || salesRes.statusText);
      if (!inventoryRes.ok) throw new Error(inventory.error || inventoryRes.statusText);

      if (rangeLabelEl) {
        rangeLabelEl.textContent = `${sales.range.label} (${sales.range.start.slice(0, 10)} → ${sales.range.end.slice(0, 10)} UTC)`;
      }

      renderSummaryGrid(salesSummaryEl, [
        ['Transactions', int(sales.summary.transaction_count)],
        ['Sales total', money(sales.summary.sales_total)],
        ['Cash', money(sales.summary.cash_total)],
        ['Card', money(sales.summary.credit_total)],
        ['Items sold', int(sales.summary.items_sold)],
        ['Member discounts', money(sales.summary.member_discount_total)],
      ]);

      renderSummaryGrid(inventorySummaryEl, [
        ['Tracked SKUs', int(inventory.snapshot.tracked_skus)],
        ['Units on hand', int(inventory.snapshot.total_units_on_hand)],
        ['Low stock', int(inventory.snapshot.low_stock_count)],
        ['Received', int(inventory.activity.received)],
        ['Sold', int(inventory.activity.sold)],
        ['Adjusted', int(inventory.activity.adjusted)],
        ['Net change', int(inventory.activity.net_product_units)],
      ]);

      if (sales.by_day?.length) {
        renderTable(
          salesByDayEl,
          [
            ['date', 'Date'],
            ['transaction_count', 'Transactions'],
            ['sales_total', 'Sales'],
          ],
          sales.by_day.map((row) => ({
            date: row.date,
            transaction_count: int(row.transaction_count),
            sales_total: money(row.sales_total),
          })),
        );
      } else if (salesByDayEl) {
        salesByDayEl.innerHTML = '<p class="hint">Daily breakdown appears for weekly and monthly reports.</p>';
      }

      renderTable(
        topProductsEl,
        [
          ['name', 'Product'],
          ['quantity', 'Qty'],
          ['revenue', 'Revenue'],
        ],
        (sales.top_products || []).map((row) => ({
          name: row.name,
          quantity: int(row.quantity),
          revenue: money(row.revenue),
        })),
      );

      renderTable(
        lowStockEl,
        [
          ['name', 'Product'],
          ['quantity_on_hand', 'On hand'],
          ['reorder_point', 'Reorder at'],
        ],
        (inventory.low_stock || []).map((row) => ({
          name: row.name,
          quantity_on_hand: int(row.quantity_on_hand),
          reorder_point: int(row.reorder_point),
        })),
      );

      renderTable(
        movementsEl,
        [
          ['created_at', 'When'],
          ['reason', 'Reason'],
          ['delta', 'Delta'],
          ['product_id', 'Product'],
          ['bulk_sku_key', 'Bulk SKU'],
          ['order_number', 'Order'],
        ],
        (inventory.recent_movements || []).map((row) => ({
          created_at: String(row.created_at || '').replace('T', ' ').replace('Z', ' UTC'),
          reason: row.reason || '',
          delta: int(row.delta),
          product_id: row.product_id ?? '—',
          bulk_sku_key: row.bulk_sku_key ?? '—',
          order_number: row.order_number ?? '—',
        })),
      );

      setStatus('Reports loaded');
    } catch (err) {
      setStatus(err.message || 'Failed to load reports', true);
    }
  }

  function show() {
    active = true;
    if (reportsNavEl) reportsNavEl.hidden = false;
    if (anchorInputEl && !anchorInputEl.value) anchorInputEl.value = todayAnchor();
  }

  function openPanel() {
    active = true;
    if (reportsPanelEl) reportsPanelEl.hidden = false;
    if (tablePanelEl) tablePanelEl.hidden = true;
    document.querySelectorAll('#tableNav button').forEach((btn) => btn.classList.remove('active'));
    document.getElementById('approvalsNavBtn')?.classList.remove('active');
    document.getElementById('shiftClosesNavBtn')?.classList.remove('active');
    reportsNavBtn?.classList.add('active');
    loadReports();
  }

  function closePanel() {
    active = false;
    if (reportsPanelEl) reportsPanelEl.hidden = true;
    reportsNavBtn?.classList.remove('active');
  }

  function configure({ apiFetch: fetchFn, setStatus: statusFn }) {
    apiFetch = fetchFn;
    setStatus = statusFn;
    show();
  }

  reportsNavBtn?.addEventListener('click', openPanel);
  loadBtnEl?.addEventListener('click', loadReports);

  window.AdminReports = {
    configure,
    show,
    openPanel,
    closePanel,
    isActive: () => active,
    loadReports,
  };
})();
