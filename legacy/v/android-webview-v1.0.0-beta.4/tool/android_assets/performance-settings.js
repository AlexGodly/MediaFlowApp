/* MediaFlow Android-only client performance controls; cloud state untouched. */
(function() {
  'use strict';
  const key = 'mediaflow-android-performance-v1';
  const modes = ['original', 'balanced', 'smooth'];
  function selected() {
    try {
      const v = localStorage.getItem(key);
      return modes.includes(v) ? v : 'balanced';
    } catch (_) { return 'balanced'; }
  }
  function apply(mode) {
    const safe = modes.includes(mode) ? mode : 'balanced';
    document.documentElement.setAttribute('data-android-perf', safe);
    try { localStorage.setItem(key, safe); } catch (_) {}
    document.querySelectorAll('[data-mf-android-mode]').forEach(button => {
      const active = button.getAttribute('data-mf-android-mode') === safe;
      button.setAttribute('aria-pressed', String(active));
      button.classList.toggle('selected', active);
    });
  }
  apply(selected());

  function mount() {
    const root = document.getElementById('view-root');
    if (!root || typeof S === 'undefined' || S.view !== 'settings') return;
    const panel = root.querySelector('.fade-in') || root;
    if (document.getElementById('mf-android-performance')) return;
    const section = document.createElement('section');
    section.className = 'card mf-android-controls';
    section.id = 'mf-android-performance';
    section.innerHTML = '<div class="mf-android-title">Android performance</div>' +
      '<p>Choose how much visual processing your phone uses. This only changes appearance on this Android app; Logging, Supabase and your website settings are unchanged.</p>' +
      '<div class="mf-android-modes">' +
      '<button type="button" data-mf-android-mode="original">Original</button>' +
      '<button type="button" data-mf-android-mode="balanced">Balanced</button>' +
      '<button type="button" data-mf-android-mode="smooth">Smooth</button>' +
      '</div><small>Balanced preserves most effects. Smooth reduces blurs, decorative animation and transitions. Restart is not required.</small>';
    section.addEventListener('click', event => {
      const button = event.target.closest('[data-mf-android-mode]');
      if (button) apply(button.getAttribute('data-mf-android-mode'));
    });
    panel.prepend(section);
    apply(selected());
  }

  function init() {
    document.addEventListener('click', event => {
      const a = event.target.closest('a[download]');
      if (a) window.__mfAndroidDownload = {
        url: a.href, name: a.getAttribute('download') || '',
        time: Date.now()
      };
    }, true);
    const root = document.getElementById('view-root');
    if (root) {
      new MutationObserver(() => mount()).observe(root, {childList:true});
      mount();
    }
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();