/* Android-only first-paint performance profile. Execute before v507 application CSS/JS.
   Local preference, never stored in MediaFlow's cloud settings. */
(function () {
  'use strict';
  const KEY = 'mediaflow-android-performance-v1';
  const modes = new Set(['original', 'balanced', 'smooth', 'ultra']);
  const cores = Math.max(1, Number(navigator.hardwareConcurrency) || 4);
  const memory = Number(navigator.deviceMemory) || 0;
  const automatic = cores <= 4 || (memory > 0 && memory <= 3) ? 'ultra' : 'smooth';
  let chosen = automatic;
  try {
    const saved = localStorage.getItem(KEY);
    if (modes.has(saved)) chosen = saved;
  } catch (_) {}
  const root = document.documentElement;
  root.dataset.androidPerf = chosen;
  root.dataset.androidDevice = automatic === 'ultra' ? 'low-end' : 'standard';

  const profile = Object.freeze({
    key: KEY,
    automatic,
    get mode() { return root.dataset.androidPerf || chosen; },
    setMode(value) {
      if (!modes.has(value)) return;
      chosen = value;
      root.dataset.androidPerf = value;
      try { localStorage.setItem(KEY, value); } catch (_) {}
    },
    pageSize(surface, normal) {
      const value = Math.max(1, Math.floor(Number(normal) || 20));
      // Only low-end mode applies a transient Library rendering budget.
      // Neither underlying Library nor cloud Settings are changed.
      return surface === 'library' && this.mode === 'ultra'
        ? Math.min(48, value) : value;
    }
  });
  window.__mfAndroidPerf = profile;
})();
