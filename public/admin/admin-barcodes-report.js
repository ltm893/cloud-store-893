/**
 * Product barcode catalog — search, select, and print from Admin Reports.
 */
(function initAdminBarcodesReport() {
  const searchInputEl = document.getElementById('barcodesSearchInput');
  const refreshBtnEl = document.getElementById('barcodesRefreshBtn');
  const printAllBtnEl = document.getElementById('barcodesPrintAllBtn');
  const printSelectedBtnEl = document.getElementById('barcodesPrintSelectedBtn');
  const summaryEl = document.getElementById('barcodesSummary');
  const tableWrapEl = document.getElementById('barcodesTableWrap');

  let apiFetch = null;
  let setStatus = null;
  let allProducts = [];
  const selectedIds = new Set();
  let jsBarcodePromise = null;
  let printFrameEl = null;

  function ensureJsBarcode() {
    if (window.JsBarcode) return Promise.resolve(window.JsBarcode);
    if (jsBarcodePromise) return jsBarcodePromise;
    jsBarcodePromise = new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = 'https://cdn.jsdelivr.net/npm/jsbarcode@3.11.6/dist/JsBarcode.all.min.js';
      script.async = true;
      script.onload = () => {
        if (window.JsBarcode) resolve(window.JsBarcode);
        else reject(new Error('Barcode library failed to initialize'));
      };
      script.onerror = () => reject(new Error('Failed to load barcode library'));
      document.head.appendChild(script);
    });
    return jsBarcodePromise;
  }

  function barcodeFormat(value) {
    const digits = String(value || '').replace(/\D/g, '');
    if (digits.length === 12 || digits.length === 13) return 'EAN13';
    return 'CODE128';
  }

  function renderBarcodeMarkup(value) {
    const barcode = String(value || '').trim();
    if (!barcode) {
      return '<p class="barcode-print-missing">No barcode on file</p>';
    }
    const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
    svg.setAttribute('class', 'barcode-print-svg');
    const format = barcodeFormat(barcode);
    const options = {
      displayValue: false,
      margin: 6,
      height: 48,
      width: format === 'EAN13' ? 1.4 : 1.2,
    };
    try {
      window.JsBarcode(svg, barcode, { ...options, format });
    } catch {
      try {
        window.JsBarcode(svg, barcode, { ...options, format: 'CODE128' });
      } catch {
        return `<p class="barcode-print-missing">Could not render barcode for ${escapeHtml(barcode)}</p>`;
      }
    }
    return `${svg.outerHTML}<p class="barcode-print-code">${escapeHtml(barcode)}</p>`;
  }

  function ensurePrintFrame() {
    if (printFrameEl && document.body.contains(printFrameEl)) return printFrameEl;
    printFrameEl = document.createElement('iframe');
    printFrameEl.setAttribute('title', 'Barcode print preview');
    printFrameEl.setAttribute('aria-hidden', 'true');
    printFrameEl.style.cssText = 'position:fixed;right:0;bottom:0;width:0;height:0;border:0;visibility:hidden;';
    document.body.appendChild(printFrameEl);
    return printFrameEl;
  }

  function normalizeSearch(value) {
    return String(value || '').trim().toLowerCase();
  }

  function productMatchesSearch(product, query) {
    if (!query) return true;
    const haystack = [
      product.name,
      product.barcode,
      product.product_type,
      product.manufacturer,
      String(product.id),
    ]
      .join(' ')
      .toLowerCase();
    return haystack.includes(query);
  }

  function filteredProducts() {
    const query = normalizeSearch(searchInputEl?.value);
    return allProducts.filter((product) => productMatchesSearch(product, query));
  }

  function updateSummary(visible) {
    if (!summaryEl) return;
    const selectedVisible = visible.filter((row) => selectedIds.has(row.id)).length;
    const generated = allProducts._generatedAt
      ? ` · Updated ${String(allProducts._generatedAt).replace('T', ' ').replace('Z', ' UTC')}`
      : '';
    summaryEl.textContent = `${visible.length} shown · ${allProducts.length} total · ${selectedVisible} selected${generated}`;
  }

  function updatePrintSelectedButton() {
    if (!printSelectedBtnEl) return;
    const hasSelection = allProducts.some((row) => selectedIds.has(row.id));
    printSelectedBtnEl.disabled = !hasSelection;
  }

  function renderTable() {
    if (!tableWrapEl) return;
    const visible = filteredProducts();
    updateSummary(visible);

    if (!allProducts.length) {
      tableWrapEl.innerHTML = '<p class="hint">No products in catalog.</p>';
      return;
    }
    if (!visible.length) {
      tableWrapEl.innerHTML = '<p class="hint">No products match your search.</p>';
      return;
    }

    const allVisibleSelected = visible.every((row) => selectedIds.has(row.id));
    const head = `<thead><tr>
      <th class="barcodes-col-select"><input type="checkbox" id="barcodesSelectAllVisible" aria-label="Select all visible"${allVisibleSelected ? ' checked' : ''}></th>
      <th>Product ID</th>
      <th>Name</th>
      <th>Type</th>
      <th>Manufacturer</th>
      <th>Barcode</th>
    </tr></thead>`;

    const body = visible
      .map((row) => {
        const checked = selectedIds.has(row.id) ? ' checked' : '';
        return `<tr data-product-id="${row.id}">
          <td class="barcodes-col-select"><input type="checkbox" class="barcodes-row-select" data-product-id="${row.id}" aria-label="Select ${escapeHtml(row.name)}"${checked}></td>
          <td>${escapeHtml(row.id)}</td>
          <td>${escapeHtml(row.name)}</td>
          <td>${escapeHtml(row.product_type || '—')}</td>
          <td>${escapeHtml(row.manufacturer || '—')}</td>
          <td class="barcodes-code-cell"><code>${escapeHtml(row.barcode || '—')}</code></td>
        </tr>`;
      })
      .join('');

    tableWrapEl.innerHTML = `<table class="barcodes-table">${head}<tbody>${body}</tbody></table>`;

    const selectAllEl = document.getElementById('barcodesSelectAllVisible');
    selectAllEl?.addEventListener('change', () => {
      if (selectAllEl.checked) {
        visible.forEach((row) => selectedIds.add(row.id));
      } else {
        visible.forEach((row) => selectedIds.delete(row.id));
      }
      renderTable();
      updatePrintSelectedButton();
    });

    tableWrapEl.querySelectorAll('.barcodes-row-select').forEach((input) => {
      input.addEventListener('change', () => {
        const id = Number(input.dataset.productId);
        if (input.checked) selectedIds.add(id);
        else selectedIds.delete(id);
        updateSummary(filteredProducts());
        updatePrintSelectedButton();
        const selectAll = document.getElementById('barcodesSelectAllVisible');
        if (selectAll) {
          const currentVisible = filteredProducts();
          selectAll.checked = currentVisible.length > 0
            && currentVisible.every((row) => selectedIds.has(row.id));
        }
      });
    });
  }

  async function printProducts(products, title) {
    if (!products.length) {
      setStatus?.('Nothing to print', true);
      return;
    }

    setStatus?.('Preparing barcodes…');
    try {
      await ensureJsBarcode();
    } catch (err) {
      setStatus?.(err.message || 'Failed to load barcode library', true);
      return;
    }

    const cards = products
      .map((row) => {
        const barcodeMarkup = renderBarcodeMarkup(row.barcode);
        return `<article class="barcode-print-card">
          <h2>${escapeHtml(row.name || `Product #${row.id}`)}</h2>
          <p class="barcode-print-meta">ID ${escapeHtml(row.id)}${row.product_type ? ` · ${escapeHtml(row.product_type)}` : ''}</p>
          ${barcodeMarkup}
          ${row.manufacturer ? `<p class="barcode-print-mfr">${escapeHtml(row.manufacturer)}</p>` : ''}
        </article>`;
      })
      .join('');

    const html = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>${escapeHtml(title)}</title>
  <style>
    * { box-sizing: border-box; }
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 16px; color: #111; }
    h1 { font-size: 1.1rem; margin: 0 0 12px; }
    .barcode-print-grid { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 12px; }
    .barcode-print-card { border: 1px solid #ccc; border-radius: 8px; padding: 12px; break-inside: avoid; page-break-inside: avoid; }
    .barcode-print-card h2 { font-size: 0.95rem; margin: 0 0 4px; line-height: 1.25; }
    .barcode-print-meta, .barcode-print-mfr { margin: 0 0 6px; font-size: 0.75rem; color: #555; }
    .barcode-print-svg { display: block; width: 100%; height: 56px; }
    .barcode-print-code { margin: 4px 0 0; font-family: ui-monospace, monospace; font-size: 0.85rem; letter-spacing: 0.04em; text-align: center; }
    .barcode-print-missing { margin: 8px 0 0; font-size: 0.8rem; color: #a00; font-style: italic; }
    @media print {
      body { margin: 8mm; }
      h1 { margin-bottom: 8mm; }
      .barcode-print-grid { grid-template-columns: repeat(2, 1fr); gap: 8mm; }
    }
  </style>
</head>
<body>
  <h1>${escapeHtml(title)}</h1>
  <div class="barcode-print-grid">${cards}</div>
</body>
</html>`;

    const frame = ensurePrintFrame();
    const frameDoc = frame.contentDocument || frame.contentWindow?.document;
    if (!frameDoc) {
      setStatus?.('Could not open print preview', true);
      return;
    }

    frameDoc.open();
    frameDoc.write(html);
    frameDoc.close();

    const triggerPrint = () => {
      try {
        frame.contentWindow?.focus();
        frame.contentWindow?.print();
        setStatus?.(`Print preview ready for ${products.length} item(s)`);
      } catch (err) {
        setStatus?.(err.message || 'Print failed', true);
      }
    };

    if (frame.contentWindow?.document?.readyState === 'complete') {
      window.setTimeout(triggerPrint, 50);
    } else {
      frame.onload = () => window.setTimeout(triggerPrint, 50);
    }
  }

  function printAllCatalog() {
    void printProducts(allProducts, `Product barcodes — all (${allProducts.length})`);
  }

  function printSelected() {
    const products = allProducts.filter((row) => selectedIds.has(row.id));
    void printProducts(products, `Product barcodes — selected (${products.length})`);
  }

  async function loadBarcodes() {
    if (!apiFetch || !setStatus) return;
    setStatus('Loading barcodes…');
    try {
      const res = await apiFetch('/api/admin/reports/barcodes');
      const report = await res.json();
      if (!res.ok) throw new Error(report.error || res.statusText);
      allProducts = Array.isArray(report.products) ? report.products : [];
      allProducts._generatedAt = report.generatedAt;
      selectedIds.clear();
      renderTable();
      updatePrintSelectedButton();
      setStatus(`Loaded ${allProducts.length} barcode(s)`);
    } catch (err) {
      if (tableWrapEl) {
        tableWrapEl.innerHTML = '<p class="hint">Could not load barcodes.</p>';
      }
      setStatus(err.message || 'Failed to load barcodes', true);
    }
  }

  function activate() {
    if (!allProducts.length) loadBarcodes();
    else renderTable();
  }

  function deactivate() {
    // Keep cached products while Reports tab is open in the same session.
  }

  function configure({ apiFetch: fetchFn, setStatus: statusFn }) {
    apiFetch = fetchFn;
    setStatus = statusFn;
  }

  searchInputEl?.addEventListener('input', () => {
    renderTable();
    updatePrintSelectedButton();
  });
  refreshBtnEl?.addEventListener('click', loadBarcodes);
  printAllBtnEl?.addEventListener('click', printAllCatalog);
  printSelectedBtnEl?.addEventListener('click', printSelected);

  window.AdminBarcodesReport = {
    configure,
    activate,
    deactivate,
    loadBarcodes,
    printAllCatalog,
    printSelected,
  };
})();
