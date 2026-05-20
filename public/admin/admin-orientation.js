/** Prefer landscape on tablets; show rotate hint in portrait when lock API is unavailable. */
(function lockAdminLandscape() {
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
