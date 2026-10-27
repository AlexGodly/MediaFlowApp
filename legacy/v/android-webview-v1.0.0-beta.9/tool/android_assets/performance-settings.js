/* MediaFlow Android-only performance center. Source/cloud state unchanged. */
(function () {
  'use strict';
  const perf = window.__mfAndroidPerf;
  if (!perf) return;
  const modes = [
    ['original', 'Original'],
    ['balanced', 'Balanced'],
    ['smooth', 'Smooth'],
    ['ultra', 'Ultra light']
  ];
  let longTasks = 0;
  let longTaskMs = 0;
  const startTime = performance.now();
  if ('PerformanceObserver' in window) {
    try {
      const observer = new PerformanceObserver(list => {
        for (const entry of list.getEntries()) {
          longTasks++;
          longTaskMs += Math.max(0, Number(entry.duration) || 0);
        }
      });
      observer.observe({entryTypes: ['longtask']});
    } catch (_) {}
  }
  function metrics() {
    const sec = Math.max(1, Math.floor((performance.now() - startTime) / 1000));
    return 'This session: ' + longTasks + ' slow main-thread tasks (' +
      Math.round(longTaskMs) + ' ms total) in ' + sec + 's. ' +
      'Hardware hint: ' + (navigator.hardwareConcurrency || '?') + ' CPU threads.';
  }
  function apply(mode) {
    perf.setMode(mode);
    document.querySelectorAll('[data-mf-android-mode]').forEach(button => {
      const active = button.getAttribute('data-mf-android-mode') === perf.mode;
      button.setAttribute('aria-pressed', String(active));
      button.classList.toggle('selected', active);
    });
    const current = document.getElementById('mf-android-mode-info');
    if (current) {
      current.textContent = perf.mode === 'ultra'
        ? 'Ultra light: reduces effects, skips painting offscreen Library rows and temporarily limits Library pages to 48 titles (without changing saved settings).'
        : perf.mode === 'smooth'
          ? 'Smooth: reduces animation, blurred layers and expensive shadows. Library page size remains unchanged.'
          : perf.mode === 'balanced'
            ? 'Balanced: keeps most appearance effects, while limiting some mobile blur.'
            : 'Original: full MediaFlow visual effects and original Library page sizes.';
    }
  }
  // Optimize cover image decode outside the critical frame. Only page rows are
  // targeted; title detail previews, badges, accounts and hero art are untouched.
  let scheduled = false;
  function processImages(deadline) {
    scheduled = false;
    if (perf.mode === 'original' || perf.mode === 'balanced') return;
    const root = document.getElementById('view-root');
    if (!root) return;
    const images = root.querySelectorAll('.item-row img, .hist-row img, .v86-log-result img');
    let count = 0;
    for (const img of images) {
      if (!img.dataset.mfAndroidDecoded) {
        img.dataset.mfAndroidDecoded = '1';
        img.decoding = 'async';
        if (!img.hasAttribute('loading')) img.loading = 'lazy';
      }
      if (++count >= 500 || (deadline && deadline.timeRemaining() < 2)) break;
    }
  }
  function scheduleImages() {
    if (scheduled) return;
    scheduled = true;
    if (window.requestIdleCallback) requestIdleCallback(processImages, {timeout:650});
    else setTimeout(() => processImages(), 90);
  }
  function mount() {
    const root = document.getElementById('view-root');
    if (!root) return;
    scheduleImages();
    if (typeof S === 'undefined' || S.view !== 'settings') return;
    if (document.getElementById('mf-android-performance')) return;
    const panel = root.querySelector('.fade-in') || root;
    const section = document.createElement('section');
    section.className = 'card mf-android-controls';
    section.id = 'mf-android-performance';
    const title = document.createElement('div');
    title.className = 'mf-android-title';
    title.textContent = 'Android performance';
    const note = document.createElement('p');
    note.textContent = 'Optimize this phone without changing your MediaFlow cloud settings, progress, themes on desktop, or Supabase account.';
    const buttons = document.createElement('div');
    buttons.className = 'mf-android-modes';
    for (const [id, label] of modes) {
      const button = document.createElement('button');
      button.type = 'button';
      button.textContent = label;
      button.dataset.mfAndroidMode = id;
      button.onclick = () => apply(id);
      buttons.appendChild(button);
    }
    const explanation = document.createElement('small');
    explanation.id = 'mf-android-mode-info';
    const diagnostics = document.createElement('p');
    diagnostics.className = 'mf-android-metrics';
    diagnostics.textContent = metrics();
    section.append(title, note, buttons, explanation, diagnostics);
    panel.prepend(section);
    apply(perf.mode);
  }
  function initialize() {
    const root = document.getElementById('view-root');
    if (root) {
      const watcher = new MutationObserver(() => mount());
      watcher.observe(root, {childList:true});
      mount();
    }
    document.addEventListener('click', event => {
      const anchor = event.target.closest('a[download]');
      if (anchor) window.__mfAndroidDownload = {
        url: anchor.href, name: anchor.getAttribute('download') || '',
        time: Date.now()
      };
    }, true);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded',initialize);
  else initialize();
})();
