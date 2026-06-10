(function () {
  if (window.__cloudstoreIosPortrait) return;
  window.__cloudstoreIosPortrait = true;
  document.documentElement.classList.add('admin-portrait-ok');

  if (!document.getElementById('cloudstore-ios-portrait-style')) {
    var style = document.createElement('style');
    style.id = 'cloudstore-ios-portrait-style';
    style.textContent = [
      '@media (orientation: portrait) {',
      '  .portrait-blocker { display: none !important; }',
      '  body.admin-landscape > :not(.portrait-blocker) { visibility: visible !important; }',
      '}',
      'html.admin-portrait-ok .portrait-blocker { display: none !important; }',
      'html.admin-portrait-ok body.admin-landscape > :not(.portrait-blocker) {',
      '  visibility: visible !important;',
      '}',
    ].join('\n');
    (document.head || document.documentElement).appendChild(style);
  }

  if (screen.orientation && typeof screen.orientation.lock === 'function') {
    screen.orientation.lock = function () { return Promise.resolve(); };
  }
})();
