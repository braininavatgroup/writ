import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


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


if __name__ == "__main__":
    unittest.main()
