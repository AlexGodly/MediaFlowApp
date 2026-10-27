import tempfile
import unittest
import zipfile
from pathlib import Path

from tool.package_mediaflow import package, CDN, patch_android_backup_bundle, patch_android_mobile_render, patch_android_offline_session_restore

class PackageMediaFlowTest(unittest.TestCase):
    def test_layout_and_vendor_rewrite(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "fixture.zip"
            with zipfile.ZipFile(source, "w") as z:
                z.writestr("archive/index.html", '<meta name="mediaflow-version" content="507">' +
                    "".join('<script src="' + u + '"></script>' for u in CDN) +
                    '<script src="assets/js/mediaflow-v507.bundle.js"></script>' +
                    '</head><body></body>')
                z.writestr("archive/assets/js/mediaflow-v507.bundle.js", "\n".join((
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
                )))
                z.writestr("archive/assets/css/demo.css", "body{}")
                z.writestr("archive/legacy/old/index.html", "old")
            output = root / "assets"
            for target in CDN.values():
                file = output / target
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text("function vendor(){}")
            result = package(source, output, skip_vendor=True, verify=False)
            self.assertEqual(result["basedOnMediaFlow"], "507")
            html = (output / "index.html").read_text()
            self.assertNotIn("cdn.jsdelivr.net", html)
            self.assertIn("assets/android/performance-settings.js", html)
            self.assertIn("assets/android/mobile-performance.css", html)
            self.assertTrue((output / "assets/android/performance-settings.js").is_file())
            self.assertTrue((output / "assets/android/mobile-performance.css").is_file())
            self.assertIn("chunked-downloads", result["androidEnhancements"])
            self.assertIn("native-saf-folder-picker", result["androidEnhancements"])
            self.assertEqual(result["patchedBackupFunctions"], 4)
            self.assertIn("assets/android/backup-bridge.js", html)
            self.assertIn("assets/android/performance-boot.js", html)
            self.assertIn("assets/android/companion-mode.js", html)
            self.assertIn("assets/android/companion-mode.css", html)
            self.assertTrue((output / "assets/android/companion-mode.js").is_file())
            self.assertTrue((output / "assets/android/companion-mode.css").is_file())
            self.assertEqual(result["patchedOfflineSessionRestoreSites"], 6)
            self.assertIn("mfAndroidReadStoredSessionUser", (output / "assets/js/mediaflow-v507.bundle.js").read_text())
            self.assertIn("indexedDB.open", (output / "assets/android/companion-mode.js").read_text())
            self.assertIn("mf395DashboardRecommendationHtml", (output / "assets/android/companion-mode.js").read_text())
            self.assertTrue((output / "assets/android/performance-boot.js").exists())
            self.assertEqual(result["patchedMobileRenderSites"], 5)
            self.assertIn("__mfAndroidLastHtml", (output / "assets/js/mediaflow-v507.bundle.js").read_text())
            self.assertIn("window.__mfAndroidBackup.choose()",
                          (output / "assets/js/mediaflow-v507.bundle.js").read_text())
            self.assertTrue((output / "assets/android/backup-bridge.js").is_file())
            self.assertTrue((output / "assets/css/demo.css").exists())
            self.assertFalse((output / "legacy").exists())

if __name__ == "__main__":
    unittest.main()
