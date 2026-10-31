#!/usr/bin/env python3
"""Pin and package the exact MediaFlow website release frontend for the apps.

The same packaged folder is used by the Android APK, the Windows desktop app and
the iOS app. No Supabase schema/keys/state are modified. CDN JavaScript becomes a
local app asset, and only the website scripts that index.html / sw.js actually
load are copied (the release archive also carries ~150 retired bundles).
"""
import argparse
import hashlib
import json
import re
import shutil
import urllib.request
import zipfile
from pathlib import Path, PurePosixPath

VERSION = "554"
ARCHIVE_SHA256 = "71176f1cb058e2b7d3d14ca4cb9383ba24a2d450fb602b79e58dea00a5acc214"
ARCHIVE_URL = f"https://github.com/AlexGodly/MediaFlow/releases/download/{VERSION}/MediaFlow_v{VERSION}_Stable.zip"
BUNDLE = f"assets/js/mediaflow-v{VERSION}.bundle.js"
CDN = {
    "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2": "assets/vendor/supabase-js-v2.js",
    "https://cdn.jsdelivr.net/npm/react@18.3.1/umd/react.production.min.js": "assets/vendor/react-18.3.1.js",
    "https://cdn.jsdelivr.net/npm/react-dom@18.3.1/umd/react-dom.production.min.js": "assets/vendor/react-dom-18.3.1.js",
}
EXACT = {"index.html", "manifest.json", "version.json", "sw.js", "favicon.ico", "icon.svg"}
MAX_FILE_BYTES = 80_000_000


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as stream:
        for block in iter(lambda: stream.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()



def patch_android_backup_bundle(path):
    """Patch the four website backup functions in the app COPY only, failing closed
    if the verified release changes its expected source structure."""
    javascript = path.read_text("utf-8")
    hooks = {
        "async function openBackupFolder(){": r"""
  if (window.__mfAndroidBackup) {
    try {
      const folder = await window.__mfAndroidBackup.choose();
      if (folder.selected) { await saveBackupNow(true); render(); }
    } catch (error) {
      if (error?.code !== 'cancelled') alert('Cannot access Android backup folder: ' + (error?.message || error));
    }
    return;
  }
""",
        "async function restoreBackupFolder(){": r"""
  if (window.__mfAndroidBackup) {
    try { await window.__mfAndroidBackup.status(); }
    catch (error) { console.warn('Android backup folder check', error); }
    return;
  }
""",
        "async function saveBackupNow(manual=false){": r"""
  if (window.__mfAndroidBackup) {
    if (!S.settings?.backup?.enabled && !manual) return;
    try {
      const folder = await window.__mfAndroidBackup.status();
      if (!folder.selected) { if (manual) await openBackupFolder(); return; }
      const filename = S.settings.backup.mode === 'single'
        ? (S.settings.backup.fileName || 'mediaflow-backup.json')
        : backupFilename();
      // Use the website's FINAL wrapped full-backup pipeline, not a stripped-down export.
      await window.__mfAndroidBackup.save(filename, JSON.stringify(backupSnapshot(), null, 2));
      S.settings.backup.lastBackup = Date.now();
      if (!manual) await persistSettings();
      if (manual) showToast('Backup saved to Android folder ✓');
    } catch (error) {
      console.warn('Android folder backup failed', error);
      if (manual) alert('Backup could not be written: ' + (error?.message || error));
    }
    return;
  }
""",
        "function restartBackupTimer(){": r"""
  if (window.__mfAndroidBackup && !window.__mfAndroidBackupWakeBound) {
    window.__mfAndroidBackupWakeBound = true;
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState !== 'visible' || !S.settings?.backup?.enabled) return;
      const interval = Math.max(1, Number(S.settings.backup.interval) || 60) * 60000;
      const previous = Number(S.settings.backup.lastBackup) || 0;
      if (Date.now() - previous >= interval && !window.__mfAndroidBackup.isWriting()) {
        saveBackupNow(false);
      }
    });
  }
"""
    }
    for marker, addition in hooks.items():
        if javascript.count(marker) != 1:
            raise ValueError(f"Refusing to patch unexpected v{VERSION} backup structure: {marker}")
        javascript = javascript.replace(marker, marker + addition, 1)
    path.write_text(javascript, "utf-8")
    return len(hooks)



def patch_android_mobile_render(path):
    """Avoid unnecessary mobile navigation DOM, desktop layout on phones,
    and cap only Ultra light Library page rendering without changing settings."""
    js = path.read_text("utf-8")
    edits = {
        "const mobileBar=document.querySelector('.mobile-tabbar'); if(mobileBar) mobileBar.innerHTML=renderMobileTabs();":
            """const mobileBar=document.querySelector('.mobile-tabbar');
  if(mobileBar){
    const nextMobileHtml=renderMobileTabs();
    if(mobileBar.__mfAndroidLastHtml!==nextMobileHtml){
      mobileBar.innerHTML=nextMobileHtml;
      mobileBar.__mfAndroidLastHtml=nextMobileHtml;
    }
  }""",
        "renderShell(); bindSidebarResizer(); autoFitSidebarToProfile(); return;":
            """renderShell();
    if(window.innerWidth>1080){bindSidebarResizer();autoFitSidebarToProfile();}
    return;""",
        "  bindSidebarResizer();\n\n  // update sidebar active states":
            """  if(window.innerWidth>1080)bindSidebarResizer();

  // update sidebar active states""",
        "  autoFitSidebarToProfile();\n\n  renderView();":
            """  if(window.innerWidth>1080)autoFitSidebarToProfile();

  renderView();""",
        "const PAGE = v175PageSize('library');":
            """const PAGE = window.__mfAndroidPerf
      ? window.__mfAndroidPerf.pageSize('library',v175PageSize('library'))
      : v175PageSize('library');"""
    }
    for before, after in edits.items():
        if js.count(before) != 1:
            raise ValueError(f"Unexpected v{VERSION} mobile render source contract: {before[:100]}")
        js = js.replace(before, after, 1)
    path.write_text(js, "utf-8")
    return len(edits)



def patch_android_offline_session_restore(path):
    """Allow a previously saved Supabase user to open the account-scoped local
    workspace when the phone is offline. Cloud writes remain queued until auth
    can refresh online; this does not authorize offline cloud requests."""
    javascript = path.read_text("utf-8")
    marker = "async function v475RestoreSavedSession(){"
    helper = r"""
function mfAndroidReadStoredSessionUser(){
  try{
    const project = new URL(SUPABASE_URL).hostname.split('.')[0];
    const keys = ['sb-' + project + '-auth-token'];
    for(const key of keys){
      const raw = localStorage.getItem(key);
      if(!raw) continue;
      const stored = JSON.parse(raw);
      const session = stored && (stored.currentSession || stored.session || stored);
      const user = session && session.user || stored && stored.user;
      if(user && user.id) return user;
    }
  }catch(_){}
  return null;
}
function mfAndroidIsNetworkFailure(error){
  const message = String(error && (error.message || error) || '');
  return navigator.onLine === false ||
    /failed to fetch|network|offline|load failed|err_internet_disconnected|connection reset|connection refused|timed out|timeout|fetch failed/i.test(message);
}
"""
    start_app_marker = "async function startAuthenticatedApp(){"
    if javascript.count(start_app_marker) != 1:
        raise ValueError(f"Unexpected v{VERSION} authenticated app entry point")
    ready_gate = r"""
window.__mfAndroidCompanionReady = new Promise(function(resolve){
  window.__mfAndroidCompanionResolve = resolve;
  setTimeout(function(){ resolve(false); }, 5000);
});
"""
    javascript = javascript.replace(start_app_marker, ready_gate + start_app_marker, 1)
    app_start = javascript.index(start_app_marker)
    app_end = javascript.index(marker, app_start)
    app_block = javascript[app_start:app_end]
    app_block = app_block.replace(start_app_marker, start_app_marker + "\n  if(window.__mfAndroidCompanionReady) await window.__mfAndroidCompanionReady;", 1)
    javascript = javascript[:app_start] + app_block + javascript[app_end:]
    if javascript.count(marker) != 1:
        raise ValueError(f"Unexpected v{VERSION} saved-session restore function")
    handler_marker = "function v475HandleAuthEvent(event,session){"
    if javascript.count(handler_marker) != 1:
        raise ValueError(f"Unexpected v{VERSION} auth event handler")
    handler_start = javascript.index(handler_marker)
    handler_end = javascript.index(marker, handler_start)
    handler_block = javascript[handler_start:handler_end]
    signed_out_marker = "if(event==='SIGNED_OUT'){"
    if handler_block.count(signed_out_marker) != 1:
        raise ValueError(f"Unexpected v{VERSION} sign-out handler")
    handler_block = handler_block.replace(
        handler_marker,
        handler_marker + r"""
if(event==='SIGNED_OUT'&&!V475_AUTH.logoutRequested&&
   (navigator.onLine===false||window.__mfAndroidOfflineMode)){
  const cachedUser=mfAndroidReadStoredSessionUser();
  if(cachedUser&&cachedUser.id&&(!AUTH_USER?.id||AUTH_USER.id===cachedUser.id)){
    AUTH_USER=cachedUser;
    window.__mfAndroidOfflineMode=true;
    return;
  }
}
if(event==='SIGNED_OUT'&&window.__mfAndroidOfflineMode&&AUTH_USER?.id&&!V475_AUTH.logoutRequested)return;
""",
        1
    )
    javascript = javascript[:handler_start] + handler_block + javascript[handler_end:]
    javascript = javascript.replace(marker, helper + marker, 1)
    start = javascript.index(marker)
    end = javascript.index("async function init(){", start)
    block = javascript[start:end]
    loop_marker = "if(V475_AUTH.logoutRequested||V475_AUTH.explicitLogout)return false;"
    fallback = r"""
if(!confirmed && navigator.onLine === false){
  const cachedUser = mfAndroidReadStoredSessionUser();
  if(cachedUser && cachedUser.id){
    confirmed = cachedUser;
    AUTH_USER = cachedUser;
    window.__mfAndroidOfflineMode = true;
    break;
  }
}
"""
    if block.count(loop_marker) != 1:
        raise ValueError(f"Unexpected v{VERSION} auth restore loop")
    block = block.replace(loop_marker, loop_marker + fallback, 1)
    catch_marker = "}catch(err){lastError=err;}"
    catch_fallback = r""" }catch(err){
          lastError=err;
          if(mfAndroidIsNetworkFailure(err)){
            const cachedUser=mfAndroidReadStoredSessionUser();
            if(cachedUser && cachedUser.id){
              confirmed=cachedUser;
              AUTH_USER=cachedUser;
              window.__mfAndroidOfflineMode=true;
              break;
            }
          }
        }"""
    if block.count(catch_marker) != 1:
        raise ValueError(f"Unexpected v{VERSION} auth network error handler")
    block = block.replace(catch_marker, catch_fallback, 1)
    final_marker = "if(!confirmed&&AUTH_USER?.id)confirmed=AUTH_USER;"
    if block.count(final_marker) != 1:
        raise ValueError(f"Unexpected v{VERSION} saved-session final fallback")
    block = block.replace(final_marker, final_marker + r"""
      if(!confirmed && lastError && mfAndroidIsNetworkFailure(lastError)){
        const cachedUser=mfAndroidReadStoredSessionUser();
        if(cachedUser && cachedUser.id){
          confirmed=cachedUser;
          AUTH_USER=cachedUser;
          window.__mfAndroidOfflineMode=true;
        }
      }""", 1)
    javascript = javascript[:start] + block + javascript[end:]
    path.write_text(javascript, "utf-8")
    return 6



COMPANION_BEGIN = "/* ---- MediaFlowApp companion layer (injected at package time) ---- */"


def inject_companion_into_bundle(path, companion_path):
    """Run the companion layer INSIDE the website bundle's private scope.

    The website bundle is one `(function(){ 'use strict'; ... })();`. Its state
    (S, App, render, rawSet, ...) is invisible to separate <script> files, which
    is why Beta 10's companion-mode.js stopped at its first line on every launch.
    Appending the companion just before the closing `})();` gives it the same
    scope as the website's own later patches. Fails closed on any other shape."""
    javascript = path.read_text("utf-8")
    head = javascript.lstrip()
    if not re.match(r"(?:/\*.*?\*/\s*)*\(function\(\)\{\s*'use strict';", head, re.S):
        raise ValueError("Website bundle no longer starts with the expected private scope")
    body = javascript.rstrip()
    closing = "})();"
    if not body.endswith(closing):
        raise ValueError("Website bundle no longer ends with the expected private scope")
    if COMPANION_BEGIN in javascript:
        raise ValueError("Companion layer already injected")
    companion = companion_path.read_text("utf-8")
    body = body[: -len(closing)] + "\n" + COMPANION_BEGIN + "\n" + companion.rstrip() + "\n" + closing + "\n"
    path.write_text(body, "utf-8")
    return len(companion)


def validate_android_companion_contract(path):
    """Fail closed unless the pinned website bundle exposes the original features the
    app layer wraps (logging, batch logging, recommendations, XP, cloud sync)."""
    javascript = path.read_text("utf-8")
    required = {
        "recommendation renderer": "function mf395DashboardRecommendationHtml(",
        "single-title logging form": "function renderLogForm(",
        "batch logging form": "function renderBatchLog(",
        "title reroll history": "function v180EnsureRecommendationHistory(",
        "title reroll action": "function v180RerollRecommendedTitle(",
        "unified XP projection": "function mf537ProjectXP(",
        "unified XP card": "function mf537XPCardMarkup(",
        "batch draft initializer": "function ensureBatchDraft(",
        "consumed-reroll units": "function mf553RerollUnitRows(",
        "reroll XP projection": "function mf553EnrichProjection(",
        "XP award after successful logging": "const mf553SubmitBase=App.submitLog;",
        "public XP contract": "window.MediaFlowV553=Object.freeze(",
        "authenticated cloud save": "async function rawSet(key,value){",
        "authenticated cloud read": "async function v115FetchCloudState(){",
        "local recovery cache": "function v115ReadRecoveryCache(){",
        "local state bootstrap": "async function v115StartWithData(data){",
    }
    missing = [name for name, marker in required.items() if marker not in javascript]
    if missing:
        raise ValueError(f"MediaFlow v{VERSION} app contract missing: " + ", ".join(missing))
    return list(required.keys())


def package(archive, output, skip_vendor=False, verify=True):
    archive, output = Path(archive), Path(output)
    if verify and sha256(archive) != ARCHIVE_SHA256:
        raise ValueError(f"MediaFlow v{VERSION} release archive SHA-256 mismatch")
    output.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as z:
        files = [n for n in z.namelist() if not n.endswith("/")]
        index_candidates = []
        for name in files:
            path = PurePosixPath(name)
            if path.name != "index.html" or any(v in path.parts for v in ("legacy", "node_modules")):
                continue
            root = str(path.parent)
            base = "" if root == "." else root + "/"
            if base + BUNDLE in files:
                index_candidates.append(base)
        if not index_candidates:
            raise ValueError(f"No MediaFlow v{VERSION} index + matching compiled bundle found")
        base = min(index_candidates, key=lambda p: (len(PurePosixPath(p).parts), len(p)))
        # Only scripts the page or its service worker load. Retired bundles stay out.
        referenced = set()
        for entry in ("index.html", "sw.js"):
            if base + entry in files:
                text = z.read(base + entry).decode("utf-8", "replace")
                referenced.update(m.lstrip("./") if m.startswith("./") else m
                                  for m in re.findall(r'(?:\./)?assets/js/[A-Za-z0-9_.-]+\.js', text))
        if BUNDLE not in referenced:
            raise ValueError(f"index.html/sw.js do not reference {BUNDLE}")
        copied = []
        skipped_scripts = 0
        for member in z.infolist():
            path = PurePosixPath(member.filename)
            if member.is_dir() or not member.filename.startswith(base):
                continue
            rel = str(path)[len(base):]
            clean = PurePosixPath(rel)
            if not rel or clean.is_absolute() or ".." in clean.parts:
                continue
            if not (rel in EXACT or rel.startswith("assets/")):
                continue
            if rel.startswith("assets/js/") and rel not in referenced:
                skipped_scripts += 1
                continue
            if member.file_size > MAX_FILE_BYTES:
                raise ValueError(f"Oversized asset: {rel}")
            dest = output.joinpath(*clean.parts)
            dest.parent.mkdir(parents=True, exist_ok=True)
            with z.open(member) as source, dest.open("wb") as target:
                shutil.copyfileobj(source, target)
            copied.append(rel)

    validated_contracts = validate_android_companion_contract(output / BUNDLE)
    patch_count = patch_android_backup_bundle(output / BUNDLE)
    mobile_patch_count = patch_android_mobile_render(output / BUNDLE)
    offline_auth_patch_count = patch_android_offline_session_restore(output / BUNDLE)
    companion_bytes = inject_companion_into_bundle(
        output / BUNDLE, Path(__file__).resolve().parent / "android_assets" / "companion-mode.js")

    index = output / "index.html"
    html = index.read_text("utf-8")
    if f'<meta name="mediaflow-version" content="{VERSION}">' not in html:
        raise ValueError(f"Bundled index.html is not v{VERSION}")
    for source, target in CDN.items():
        if source not in html:
            raise ValueError(f"Expected upstream runtime library absent: {source}")
        html = html.replace(source, target)
    # Only the app builds gain these resources; the website itself is unchanged.
    android_assets = Path(__file__).resolve().parent / "android_assets"
    target = output / "assets/android"
    target.mkdir(parents=True, exist_ok=True)
    shutil.copy2(android_assets / "performance-settings.js", target / "performance-settings.js")
    shutil.copy2(android_assets / "mobile-performance.css", target / "mobile-performance.css")
    shutil.copy2(android_assets / "backup-bridge.js", target / "backup-bridge.js")
    shutil.copy2(android_assets / "performance-boot.js", target / "performance-boot.js")
    shutil.copy2(android_assets / "cloud-state-cas.js", target / "cloud-state-cas.js")
    shutil.copy2(android_assets / "companion-mode.css", target / "companion-mode.css")
    if "</head>" not in html or "</body>" not in html:
        raise ValueError("Cannot safely mount Android-specific UI resources")
    runtime_script = f'<script src="{BUNDLE}"></script>'
    if html.count(runtime_script) != 1:
        raise ValueError(f"Missing exact MediaFlow v{VERSION} application script")
    html = html.replace(runtime_script,
                        '<script src="assets/android/backup-bridge.js"></script>\n<script src="assets/android/cloud-state-cas.js"></script>\n' + runtime_script, 1)
    html = html.replace("</head>",
                        '<script src="assets/android/performance-boot.js"></script>\n</head>', 1)
    html = html.replace("</head>",
                        '<link rel="stylesheet" href="assets/android/mobile-performance.css">\n<link rel="stylesheet" href="assets/android/companion-mode.css">\n</head>', 1)
    html = html.replace("</body>",
                        '<script src="assets/android/performance-settings.js"></script>\n</body>', 1)
    index.write_text(html, "utf-8")
    for local in re.findall(r'(?:src|href)="(assets/[^"]+)"', html):
        if not (output / local.split("?")[0]).exists() and local not in CDN.values():
            raise ValueError(f"Referenced local asset missing: {local}")
    if not skip_vendor:
        for source, target in CDN.items():
            dest = output / target
            dest.parent.mkdir(parents=True, exist_ok=True)
            with urllib.request.urlopen(urllib.request.Request(source, headers={"User-Agent": "MediaFlowApp-Android/1.0"}), timeout=90) as response:
                data = response.read(18_000_000)
            if len(data) < 10_000 or not (b"function" in data or b"supabase" in data.lower()):
                raise ValueError(f"Unexpected CDN JavaScript for {source}")
            dest.write_bytes(data)

    missing = [p for p in CDN.values() if not (output / p).is_file()]
    if missing:
        raise ValueError(f"Missing bundled runtime dependencies: {missing}")
    sw = output / "sw.js"
    if sw.is_file():
        precached = re.findall(r'"\./(assets/[^"]+)"', sw.read_text("utf-8"))
        absent = [p for p in precached if not (output / p).is_file()]
        if absent:
            raise ValueError(f"Service worker precaches missing files: {absent[:5]}")
    manifest = {
        "basedOnMediaFlow": VERSION,
        "sourceRelease": ARCHIVE_URL,
        "sourceSha256": ARCHIVE_SHA256 if verify else sha256(archive),
        "assets": len(copied),
        "bundleSha256": sha256(output / BUNDLE),
        "skippedRetiredScripts": skipped_scripts,
        "companionInjectedBytes": companion_bytes,
        "vendoredDependencies": {name: sha256(output / path) for name, path in CDN.items()},
        "androidEnhancements": ["performance-settings", "chunked-downloads", "spa-back", "service-worker", "native-saf-folder-picker", "chunked-automatic-folder-backups", "foreground-timer-resume", "mobile-safe-insets", "mobile-render-dom-reuse", "desktop-layout-skip-on-phone", "low-end-paint-budget", "mobile-contrast-fix", "full-website-navigation", "quick-log-button", "dashboard-batch-logging", "trimmed-retired-bundles", "indexeddb-offline-snapshot-queue", "offline-session-restore", "offline-draft-autosave", "cloud-backed-draft-sync", "revision-checked-cloud-sync", "three-way-conflict-resolution", "reconnect-merge-sync", "single-and-batch-logging", "reroll-title-xp-preview", "reroll-title-xp-award", f"pinned-mediaflow-v{VERSION}-contract"],
        "validatedCompanionContracts": validated_contracts,
        "patchedBackupFunctions": patch_count,
        "patchedMobileRenderSites": mobile_patch_count,
        "patchedOfflineSessionRestoreSites": offline_auth_patch_count,
    }
    (output / "mediaflow-android-build.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest, indent=2))
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive", default=f".downloads/MediaFlow_v{VERSION}_Stable.zip")
    parser.add_argument("--output", default="app/src/main/assets/www")
    parser.add_argument("--skip-vendor", action="store_true")
    parser.add_argument("--skip-hash", action="store_true")
    args = parser.parse_args()
    package(args.archive, args.output, skip_vendor=args.skip_vendor, verify=not args.skip_hash)
