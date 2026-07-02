/**
 * In-page prompt for admin WebViews (Android/iOS WKWebView do not support window.prompt).
 */
const AdminPrompt = (() => {
  const dialog = document.getElementById('adminPromptDialog');
  const form = document.getElementById('adminPromptForm');
  const titleEl = document.getElementById('adminPromptTitle');
  const messageEl = document.getElementById('adminPromptMessage');
  const labelTextEl = document.getElementById('adminPromptLabelText');
  const inputEl = document.getElementById('adminPromptInput');
  const cancelBtn = document.getElementById('adminPromptCancel');
  const confirmBtn = document.getElementById('adminPromptConfirm');

  let pendingResolve = null;

  function cleanup() {
    pendingResolve = null;
    form.removeEventListener('submit', onSubmit);
    cancelBtn.removeEventListener('click', onCancel);
    dialog.removeEventListener('cancel', onCancel);
    dialog.close();
  }

  function onCancel(event) {
    if (event) event.preventDefault();
    const resolve = pendingResolve;
    cleanup();
    resolve?.(null);
  }

  function onSubmit(event) {
    event.preventDefault();
    const value = inputEl.value.trim();
    if (confirmBtn.dataset.required === '1' && !value) {
      inputEl.focus();
      return;
    }
    const resolve = pendingResolve;
    cleanup();
    resolve?.(value);
  }

  /**
   * @param {object} opts
   * @param {string} opts.title
   * @param {string} [opts.message]
   * @param {string} [opts.label]
   * @param {string} [opts.defaultValue]
   * @param {boolean} [opts.required]
   * @param {string} [opts.confirmText]
   * @param {string} [opts.cancelText]
   * @returns {Promise<string|null>} trimmed value, or null if cancelled
   */
  function ask(opts = {}) {
    if (!dialog || !form || !inputEl) {
      return Promise.resolve(null);
    }

    return new Promise((resolve) => {
      if (pendingResolve) {
        onCancel();
      }
      pendingResolve = resolve;

      titleEl.textContent = opts.title || 'Confirm';
      const message = opts.message || '';
      messageEl.textContent = message;
      messageEl.hidden = !message;
      labelTextEl.textContent = opts.label || 'Reason (optional)';
      inputEl.value = opts.defaultValue || '';
      inputEl.placeholder = opts.placeholder || '';
      confirmBtn.textContent = opts.confirmText || 'Confirm';
      cancelBtn.textContent = opts.cancelText || 'Cancel';
      confirmBtn.dataset.required = opts.required ? '1' : '0';

      form.addEventListener('submit', onSubmit);
      cancelBtn.addEventListener('click', onCancel);
      dialog.addEventListener('cancel', onCancel);

      if (typeof dialog.showModal === 'function') {
        dialog.showModal();
      } else {
        dialog.setAttribute('open', '');
      }
      inputEl.focus();
    });
  }

  return { ask };
})();
