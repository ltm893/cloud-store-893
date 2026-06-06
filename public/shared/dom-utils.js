/** Shared DOM helpers for web POS and admin (classic scripts, no bundler). */
function escapeHtml(s) {
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

/** Escape text for HTML attribute values (e.g. input value="…"). */
function attrEscape(s) {
  return String(s ?? '')
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;');
}
