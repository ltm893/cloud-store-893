(function () {
  document.documentElement.classList.add('admin-portrait-ok');
  if (document.body) {
    document.body.classList.remove('admin-landscape');
  }
  var blocker = document.getElementById('portraitBlocker');
  if (blocker) {
    blocker.remove();
  }
})();
