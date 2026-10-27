#!/usr/bin/env python3
"""Pin and package the exact MediaFlow v507 release frontend into Android assets.

No Supabase schema/keys/state are modified. Any downloaded CDN JavaScript becomes
a local app asset (so weak mobile connections do not block the UI shell startup).
"""
import argparse
import hashlib
import json
import re
import shutil
import urllib.request
import zipfile
from pathlib import Path, PurePosixPath

VERSION = "507"
ARCHIVE_SHA256 = "12ea38109649b4467ba069e00ab2b1d9a1daab3c4f9af4f9d0013de693c8414a"
ARCHIVE_URL = "https://github.com/AlexGodly/MediaFlow/releases/download/507/MediaFlow_v507_Stable.zip"
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
    """Patch the four v507 functions in the Android COPY only, failing closed
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
      // Use v507's FINAL wrapped full-backup pipeline, not a stripped-down export.
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
            raise ValueError(f"Refusing to patch unexpected v507 backup structure: {marker}")
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
            raise ValueError(f"Unexpected v507 mobile render source contract: {before[:100]}")
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
        raise ValueError("Unexpected v507 authenticated app entry point")
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
        raise ValueError("Unexpected v507 saved-session restore function")
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
        raise ValueError("Unexpected v507 auth restore loop")
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
        raise ValueError("Unexpected v507 auth network error handler")
    block = block.replace(catch_marker, catch_fallback, 1)
    final_marker = "if(!confirmed&&AUTH_USER?.id)confirmed=AUTH_USER;"
    if block.count(final_marker) != 1:
        raise ValueError("Unexpected v507 saved-session final fallback")
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
    return 5


def package(archive, output, skip_vendor=False, verify=True):
    archive, output = Path(archive), Path(output)
    if verify and sha256(archive) != ARCHIVE_SHA256:
        raise ValueError("MediaFlow v507 release archive SHA-256 mismatch")
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
            if base + "assets/js/mediaflow-v507.bundle.js" in files:
                index_candidates.append(base)
        if not index_candidates:
            raise ValueError("No MediaFlow v507 index + matching compiled bundle found")
        base = min(index_candidates, key=lambda p: (len(PurePosixPath(p).parts), len(p)))
        copied = []
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
            if member.file_size > MAX_FILE_BYTES:
                raise ValueError(f"Oversized asset: {rel}")
            dest = output.joinpath(*clean.parts)
            dest.parent.mkdir(parents=True, exist_ok=True)
            with z.open(member) as source, dest.open("wb") as target:
                shutil.copyfileobj(source, target)
            copied.append(rel)

    patch_count = patch_android_backup_bundle(output / "assets/js/mediaflow-v507.bundle.js")
    mobile_patch_count = patch_android_mobile_render(output / "assets/js/mediaflow-v507.bundle.js")
    offline_auth_patch_count = patch_android_offline_session_restore(output / "assets/js/mediaflow-v507.bundle.js")

    index = output / "index.html"
    html = index.read_text("utf-8")
    if not re.search(r'<meta name="mediaflow-version" content="507">', html):
        raise ValueError("Bundled index.html is not v507")
    for source, target in CDN.items():
        if source not in html:
            raise ValueError(f"Expected upstream runtime library absent: {source}")
        html = html.replace(source, target)
    # Only the Android build gains these resources; v507 website is unchanged.
    android_assets = Path(__file__).resolve().parent / "android_assets"
    target = output / "assets/android"
    target.mkdir(parents=True, exist_ok=True)
    shutil.copy2(android_assets / "performance-settings.js", target / "performance-settings.js")
    shutil.copy2(android_assets / "mobile-performance.css", target / "mobile-performance.css")
    shutil.copy2(android_assets / "backup-bridge.js", target / "backup-bridge.js")
    shutil.copy2(android_assets / "performance-boot.js", target / "performance-boot.js")
    shutil.copy2(android_assets / "companion-mode.js", target / "companion-mode.js")
    shutil.copy2(android_assets / "companion-mode.css", target / "companion-mode.css")
    if "</head>" not in html or "</body>" not in html:
        raise ValueError("Cannot safely mount Android-specific UI resources")
    runtime_script = '<script src="assets/js/mediaflow-v507.bundle.js"></script>'
    if html.count(runtime_script) != 1:
        raise ValueError("Missing exact MediaFlow v507 application script")
    html = html.replace(runtime_script,
                        '<script src="assets/android/backup-bridge.js"></script>\n' + runtime_script + '\n<script src="assets/android/companion-mode.js"></script>', 1)
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
    manifest = {
        "basedOnMediaFlow": VERSION,
        "sourceRelease": ARCHIVE_URL,
        "sourceSha256": ARCHIVE_SHA256 if verify else sha256(archive),
        "assets": len(copied),
        "bundleSha256": sha256(output / "assets/js/mediaflow-v507.bundle.js"),
        "vendoredDependencies": {name: sha256(output / path) for name, path in CDN.items()},
        "androidEnhancements": ["performance-settings", "chunked-downloads", "spa-back", "service-worker", "native-saf-folder-picker", "chunked-automatic-folder-backups", "foreground-timer-resume", "mobile-safe-insets", "mobile-render-dom-reuse", "desktop-layout-skip-on-phone", "low-end-paint-budget", "mobile-contrast-fix", "focused-recommendation-logging-workspace", "indexeddb-offline-snapshot-queue", "offline-session-restore", "offline-draft-autosave", "reconnect-merge-sync", "single-and-batch-logging"],
        "patchedBackupFunctions": patch_count,
        "patchedMobileRenderSites": mobile_patch_count,
        "patchedOfflineSessionRestoreSites": offline_auth_patch_count,
    }
    (output / "mediaflow-android-build.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest, indent=2))
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--archive", default=".downloads/MediaFlow_v507_Stable.zip")
    parser.add_argument("--output", default="app/src/main/assets/www")
    parser.add_argument("--skip-vendor", action="store_true")
    parser.add_argument("--skip-hash", action="store_true")
    args = parser.parse_args()
    package(args.archive, args.output, skip_vendor=args.skip_vendor, verify=not args.skip_hash)
