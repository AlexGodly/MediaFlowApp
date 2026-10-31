import tempfile
import unittest
import zipfile
from pathlib import Path

from tool.package_mediaflow import (
    BUNDLE, CDN, COMPANION_BEGIN, VERSION, inject_companion_into_bundle, package,
)

MARKERS = (
    "async function openBackupFolder(){",
    "async function restoreBackupFolder(){",
    "async function saveBackupNow(manual=false){",
    "function restartBackupTimer(){",
    "const mobileBar=document.querySelector('.mobile-tabbar'); if(mobileBar) mobileBar.innerHTML=renderMobileTabs();",
    "renderShell(); bindSidebarResizer(); autoFitSidebarToProfile(); return;",
    "  bindSidebarResizer();\n\n  // update sidebar active states",
    "  autoFitSidebarToProfile();\n\n  renderView();",
    "const PAGE = v175PageSize('library');",
    "async function startAuthenticatedApp(){",
    "const booted=await v115SafeBootstrap();",
    "}",
    "function v475HandleAuthEvent(event,session){",
    "if(event==='SIGNED_OUT'){",
    "}",
    "async function v475RestoreSavedSession(){",
    "if(V475_AUTH.logoutRequested||V475_AUTH.explicitLogout)return false;",
    "}catch(err){lastError=err;}",
    "if(!confirmed&&AUTH_USER?.id)confirmed=AUTH_USER;",
    "async function init(){",
    "function mf395DashboardRecommendationHtml(task, cat){",
    "function renderLogForm(task, cat){",
    "function renderBatchLog(){",
    "function ensureBatchDraft(){",
    "function v180EnsureRecommendationHistory(task){",
    "function v180RerollRecommendedTitle(){",
    "function mf537ProjectXP(){",
    "function mf537XPCardMarkup(){",
    "function mf553RerollUnitRows(){",
    "function mf553EnrichProjection(base){",
    "const mf553SubmitBase=App.submitLog;",
    "window.MediaFlowV553=Object.freeze({version:MF553_VERSION});",
    "async function rawSet(key,value){",
    "async function v115FetchCloudState(){",
    "function v115ReadRecoveryCache(){",
    "async function v115StartWithData(data){",
)


def fixture_bundle():
    # The real website bundle is ONE private scope; the companion must run inside it.
    return "/* MediaFlow */\n(function(){\n'use strict';\n" + "\n".join(MARKERS) + "\n})();\n"


class PackageMediaFlowTest(unittest.TestCase):
    def test_offline_sync_contract_fails_closed(self):
        companion = Path("tool/android_assets/companion-mode.js").read_text(encoding="utf-8")
        cas = Path("tool/android_assets/cloud-state-cas.js").read_text(encoding="utf-8")
        package_source = Path("tool/package_mediaflow.py").read_text(encoding="utf-8")
        self.assertIn("DRAFT_FIELD", companion)
        self.assertIn("cloudSyncedAt", companion)
        self.assertIn("captureCloudDraft", companion)
        self.assertIn("baseProjection", companion)
        self.assertIn("MFAndroidCloudCAS.update", companion)
        self.assertNotIn(".upsert(", companion)
        self.assertIn(".eq('updated_at', expectedUpdatedAt)", cas)
        self.assertIn("window.__mfAndroidOfflineMode=true", package_source)
        self.assertIn("mfAndroidReadStoredSessionUser", package_source)
        self.assertIn("cloud-state-cas.js", package_source)

    def test_companion_exposes_handlers_and_full_website(self):
        companion = Path("tool/android_assets/companion-mode.js").read_text(encoding="utf-8")
        # Beta 10 regression: inline onclick handlers call window.MFAndroidCompanion.
        self.assertIn("window.MFAndroidCompanion = companion;", companion)
        # Full website: no page hiding, no replacement navigation or dashboard.
        self.assertNotIn("NAV_ITEMS.splice", companion)
        self.assertNotIn("MOBILE_PRIMARY_NAV.splice", companion)
        self.assertNotIn("renderMobileTabs =", companion)
        self.assertNotIn("v161VisibleNavItems =", companion)
        self.assertIn("originalRenderDashboard.apply", companion)
        self.assertIn("details.v238-log-library", companion)

    def test_injection_requires_private_scope(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            companion = root / "c.js"
            companion.write_text("(function(){ window.X = 1; })();")
            good = root / "good.js"
            good.write_text(fixture_bundle())
            inject_companion_into_bundle(good, companion)
            text = good.read_text()
            self.assertTrue(text.rstrip().endswith("})();"))
            self.assertLess(text.index(COMPANION_BEGIN), text.rindex("})();"))
            with self.assertRaises(ValueError):
                inject_companion_into_bundle(good, companion)  # never twice
            bad = root / "bad.js"
            bad.write_text("var S = {};\nfunction render(){}\n")
            with self.assertRaises(ValueError):
                inject_companion_into_bundle(bad, companion)

    def test_layout_vendor_rewrite_and_trim(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "fixture.zip"
            with zipfile.ZipFile(source, "w") as z:
                z.writestr("archive/index.html", f'<meta name="mediaflow-version" content="{VERSION}">' +
                    "".join('<script src="' + u + '"></script>' for u in CDN) +
                    f'<script src="{BUNDLE}"></script>' +
                    '<script src="assets/js/mediaflow-v261-react-ui.js"></script>' +
                    '</head><body></body>')
                z.writestr("archive/sw.js", f'const CORE=["./index.html","./{BUNDLE}","./assets/js/mediaflow-v261-react-ui.js","./assets/css/demo.css"];')
                z.writestr("archive/" + BUNDLE, fixture_bundle())
                z.writestr("archive/assets/js/mediaflow-v261-react-ui.js", "window.ui=1;")
                z.writestr("archive/assets/js/mediaflow-v400.bundle.js", "retired")
                z.writestr("archive/assets/js/mediaflow-v553.bundle.js", "retired")
                z.writestr("archive/assets/css/demo.css", "body{}")
                z.writestr("archive/legacy/old/index.html", "old")
            output = root / "assets"
            for target in CDN.values():
                file = output / target
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text("function vendor(){}")
            result = package(source, output, skip_vendor=True, verify=False)
            self.assertEqual(result["basedOnMediaFlow"], VERSION)
            self.assertIn("public XP contract", result["validatedCompanionContracts"])
            self.assertIn("batch draft initializer", result["validatedCompanionContracts"])
            self.assertEqual(result["patchedBackupFunctions"], 4)
            self.assertEqual(result["patchedMobileRenderSites"], 5)
            self.assertEqual(result["patchedOfflineSessionRestoreSites"], 6)
            self.assertEqual(result["skippedRetiredScripts"], 2)
            self.assertGreater(result["companionInjectedBytes"], 10000)
            self.assertIn("full-website-navigation", result["androidEnhancements"])
            self.assertIn("native-saf-folder-picker", result["androidEnhancements"])

            # Retired bundles are not shipped; referenced scripts are.
            self.assertFalse((output / "assets/js/mediaflow-v400.bundle.js").exists())
            self.assertFalse((output / "assets/js/mediaflow-v553.bundle.js").exists())
            self.assertTrue((output / "assets/js/mediaflow-v261-react-ui.js").is_file())
            self.assertTrue((output / "assets/css/demo.css").exists())
            self.assertFalse((output / "legacy").exists())

            html = (output / "index.html").read_text()
            self.assertNotIn("cdn.jsdelivr.net", html)
            for asset in ("performance-settings.js", "mobile-performance.css", "backup-bridge.js",
                          "performance-boot.js", "cloud-state-cas.js", "companion-mode.css"):
                self.assertIn("assets/android/" + asset, html)
                self.assertTrue((output / "assets/android" / asset).is_file())
            # The companion now lives inside the bundle, not as a separate script.
            self.assertNotIn("assets/android/companion-mode.js", html)
            self.assertLess(html.index("assets/android/cloud-state-cas.js"), html.index(BUNDLE))

            bundle = (output / BUNDLE).read_text()
            self.assertIn(COMPANION_BEGIN, bundle)
            self.assertTrue(bundle.rstrip().endswith("})();"))
            for needle in ("window.MFAndroidCompanion = companion", "syncDraftToCloud",
                           "mergeConcurrentStates", "showStateConflictDialog", "indexedDB.open",
                           "mfAndroidReadStoredSessionUser", "window.MediaFlowV553",
                           "__mfAndroidLastHtml", "window.__mfAndroidBackup.choose()"):
                self.assertIn(needle, bundle)
            self.assertNotIn(".upsert(", (output / "assets/android/cloud-state-cas.js").read_text())


if __name__ == "__main__":
    unittest.main()
