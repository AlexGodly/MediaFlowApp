import tempfile
import unittest
import zipfile
from pathlib import Path

from tool.package_mediaflow import package, CDN

class PackageMediaFlowTest(unittest.TestCase):
    def test_layout_and_vendor_rewrite(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "fixture.zip"
            with zipfile.ZipFile(source, "w") as z:
                z.writestr("archive/index.html", '<meta name="mediaflow-version" content="507">' +
                    "".join('<script src="' + u + '"></script>' for u in CDN) +
                    '<script src="assets/js/mediaflow-v507.bundle.js"></script>')
                z.writestr("archive/assets/js/mediaflow-v507.bundle.js", "console.log('ready')")
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
            self.assertTrue((output / "assets/css/demo.css").exists())
            self.assertFalse((output / "legacy").exists())

if __name__ == "__main__":
    unittest.main()
