import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from test_live_exit import LiveExitTest


ROOT = Path(__file__).resolve().parents[1]


class FeatureMapTest(unittest.TestCase):
    def test_removed_accessibility_identifier_fails_the_check(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            manifest = Path(directory) / "features.json"
            manifest.write_text(json.dumps({
                "app": [{
                    "id": "stale",
                    "source": "Sources/Writ/WritApp.swift",
                    "marker": "writ.removed-control",
                }],
                "site": [],
            }))
            result = subprocess.run(
                ["python3", "tools/check_feature_map.py"],
                cwd=ROOT,
                env={**os.environ, "WRIT_FEATURE_MAP": str(manifest)},
                text=True,
                capture_output=True,
            )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("stale", result.stdout)

    def run_check(self, pages) -> subprocess.CompletedProcess:
        with tempfile.TemporaryDirectory() as directory:
            walk = Path(directory) / "browser-pages.json"
            walk.write_text(json.dumps({"pages": pages}))
            return subprocess.run(
                ["python3", "tools/check_feature_map.py"],
                cwd=ROOT,
                env={**os.environ, "WRIT_BROWSER_PAGES": str(walk)},
                text=True,
                capture_output=True,
            )

    def test_every_mapped_site_page_is_walked_in_the_browser(self) -> None:
        committed = json.loads((ROOT / "browser-pages.json").read_text())["pages"]
        self.assertEqual(self.run_check(committed).returncode, 0)
        result = self.run_check([page for page in committed if page["path"] != "/privacy/"])
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not walk /privacy/", result.stdout)

    def test_walk_text_must_be_on_the_committed_page(self) -> None:
        committed = json.loads((ROOT / "browser-pages.json").read_text())["pages"]
        stale = [{**page, "assertions": [{"selector": "h1", "text": "Retired heading"}]} if page["path"] == "/eula/" else page
                 for page in committed]
        result = self.run_check(stale)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("'Retired heading'", result.stdout)


if __name__ == "__main__":
    unittest.main()
