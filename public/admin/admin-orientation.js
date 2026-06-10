/** Prefer landscape on tablets; show rotate hint in portrait when lock API is unavailable. */
/** Logic mirrors lib/admin-orientation.js (see test/admin-orientation.test.js). */
(function lockAdminLandscape() {
  function isPortraitOkClient() {
    if (document.documentElement.classList.contains('admin-portrait-ok')) return true;
    return new URLSearchParams(window.location.search).get('client_kind') === 'ios';
  }

  function tryLock() {
    const o = screen.orientation;
    if (o && typeof o.lock === 'function') {
      o.lock('landscape').catch(() => {});
      return;
    }
    const legacy = screen.lockOrientation || screen.mozLockOrientation || screen.msLockOrientation;
    if (legacy) {
      try {
        legacy.call(screen, 'landscape');
      } catch (_) {
        /* ignore */
      }
    }
  }

  function init() {
    if (isPortraitOkClient()) {
      document.documentElement.classList.add('admin-portrait-ok');
      return;
    }
    document.documentElement.classList.add('admin-landscape');
    tryLock();
    window.addEventListener('orientationchange', tryLock);
    document.addEventListener('visibilitychange', () => {
      if (!document.hidden) tryLock();
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
