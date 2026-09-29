#!/usr/bin/env python3
from pathlib import Path
import re
import sys
import hashlib
import json
import os
import shutil
import subprocess
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from verify_release_feed import no_public_release, published_build, validate


ROOT = Path(__file__).resolve().parent
REPO_ROOT = ROOT.parent


def normalized(source: str) -> str:
    return " ".join(source.split())


class SiteCopyTests(unittest.TestCase):
    def test_public_download_targets_the_versioned_release(self) -> None:
        landing = (ROOT / "public/index.html").read_text()
        version = (ROOT / "PUBLISHED_VERSION").read_text().strip()
        app_version = (REPO_ROOT / "VERSION").read_text().strip()
        self.assertRegex(version, r"^\d+\.\d+(?:\.\d+)?$")
        self.assertLessEqual(tuple(map(int, version.split("."))), tuple(map(int, app_version.split("."))))
        url = f"https://github.com/braininavatgroup/writ/releases/download/v{version}/Writ-{version}.dmg"
        self.assertIn(f'href="{url}"', landing)
        self.assertIn(f"Writ {version} for macOS", landing)
        self.assertIn(f"Download Writ {version}.", landing)
        self.assertIn("brew install --cask braininavatgroup/tap/writ", landing)
        for stale in ("Private release", "not publicly released", "Public distribution is not open", 'content="noindex"'):
            self.assertNotIn(stale, landing)

    def test_update_feed_is_a_durable_release_redirect(self) -> None:
        redirect = (ROOT / "public/_redirects").read_text()
        self.assertIn(
            "/appcast.json https://github.com/braininavatgroup/writ/releases/latest/download/appcast.json 302",
            redirect,
        )
        self.assertFalse((ROOT / "public/appcast.json").exists())

    def test_release_feed_checks_versioned_url_and_artifact_digest(self) -> None:
        artifact_bytes = bytearray(1024)
        artifact_bytes[512:516] = b"koly"
        artifact_bytes = bytes(artifact_bytes)
        feed = {
            "version": "1.0",
            "build": 1790540276,
            "url": "https://github.com/braininavatgroup/writ/releases/download/v1.0/Writ-1.0.dmg",
            "sha256": hashlib.sha256(artifact_bytes).hexdigest(),
            "notes": "Initial release",
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            feed_path, artifact_path = root / "appcast.json", root / "Writ.dmg"
            feed_path.write_text(json.dumps(feed))
            artifact_path.write_bytes(artifact_bytes)
            self.assertEqual(validate(feed_path, artifact_path)["version"], "1.0")
            with self.assertRaisesRegex(ValueError, "latest release"):
                validate(feed_path, latest_release_tag="v1.1")
            changed_artifact = bytearray(1024)
            changed_artifact[512:516] = b"koly"
            changed_artifact[0] = 1
            artifact_path.write_bytes(changed_artifact)
            with self.assertRaisesRegex(ValueError, "SHA-256"):
                validate(feed_path, artifact_path)
            feed["url"] = "https://example.invalid/Writ.dmg"
            feed_path.write_text(json.dumps(feed))
            with self.assertRaisesRegex(ValueError, "immutable release DMG"):
                validate(feed_path)

    def test_first_release_bootstrap_requires_verified_github_404(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            feed_path = Path(directory) / "empty.json"
            repo_path = Path(directory) / "repo.json"
            latest_path = Path(directory) / "latest.json"
            feed_path.write_text("")
            repo_path.write_text(json.dumps({"full_name": "braininavatgroup/writ"}))
            latest_path.write_text(json.dumps({"message": "Not Found"}))
            self.assertTrue(no_public_release(repo_path, "200", latest_path, "404"))
            repo_path.write_text(json.dumps({"full_name": "other/private-repo"}))
            self.assertFalse(no_public_release(repo_path, "404", latest_path, "404"))
            repo_path.write_text(json.dumps({"full_name": "braininavatgroup/writ"}))
            latest_path.write_text(json.dumps({"message": "rate limit exceeded"}))
            self.assertFalse(no_public_release(repo_path, "200", latest_path, "404"))
            with self.assertRaisesRegex(ValueError, "cannot establish"):
                published_build(feed_path, "404")
            with self.assertRaisesRegex(ValueError, "cannot establish"):
                published_build(feed_path, "000")

    def test_release_script_allows_only_verified_first_release_bootstrap(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tools = root / "tools"
            tools.mkdir()
            shutil.copy(REPO_ROOT / "tools/verify_release_feed.py", tools)
            shutil.copy(REPO_ROOT / "release.sh", root)
            (root / "VERSION").write_text("1.0\n")
            log = root / "calls.log"
            build = root / "build.sh"
            build.write_text(
                "#!/usr/bin/env bash\n"
                "echo build-reached >> \"$RELEASE_GATE_LOG\"\n"
                "exit 23\n"
            )
            build.chmod(0o755)
            bin_dir = root / "bin"
            bin_dir.mkdir()
            fake_git = bin_dir / "git"
            fake_git.write_text(
                "#!/usr/bin/env bash\n"
                "if [[ $1 == log ]]; then echo 1000; fi\n"
            )
            fake_git.chmod(0o755)
            fake_curl = bin_dir / "curl"
            fake_curl.write_text(
                "#!/usr/bin/env bash\n"
                "out= url=\n"
                "while (($#)); do\n"
                "  if [[ $1 == -o ]]; then out=$2; shift 2; continue; fi\n"
                "  url=$1; shift\n"
                "done\n"
                "case $url in\n"
                "  *appcast.json) body= status=404;;\n"
                "  */repos/braininavatgroup/writ) body='{\"full_name\":\"braininavatgroup/writ\"}' status=200;;\n"
                "  */releases/latest) body='{\"message\":\"Not Found\"}' status=404;;\n"
                "  *) exit 9;;\n"
                "esac\n"
                "printf '%s' \"$body\" > \"$out\"\n"
                "printf '%s' \"$status\"\n"
            )
            fake_curl.chmod(0o755)
            env = os.environ | {
                "PATH": f"{bin_dir}:{os.environ['PATH']}",
                "RELEASE_GATE_LOG": str(log),
                "DEVELOPER_ID": "test identity",
            }
            result = subprocess.run(
                ["bash", str(root / "release.sh")],
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 23, result.stderr)
            self.assertIn("build-reached", log.read_text())

    def test_failed_latest_live_check_demotes_release_and_restores_previous_latest(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tools = root / "tools"
            bin_dir = root / "bin"
            tools.mkdir()
            bin_dir.mkdir()
            shutil.copy(REPO_ROOT / "tools/promote_release.sh", tools / "promote_release.sh")
            live = tools / "live"
            live.write_text(
                "#!/usr/bin/env bash\n"
                "echo \"live ${LIVE_EXPECTED_VERSION:-none}\" >> \"$PROMOTION_LOG\"\n"
                "if [[ ${FAIL_LIVE_ONCE:-0} == 1 && ! -e $PROMOTION_STATE ]]; then "
                "touch \"$PROMOTION_STATE\"; exit 1; fi\n"
            )
            live.chmod(0o755)
            gh = bin_dir / "gh"
            gh.write_text("#!/usr/bin/env bash\necho \"gh $*\" >> \"$PROMOTION_LOG\"\n")
            gh.chmod(0o755)
            log = root / "calls.log"
            env = os.environ | {
                "PATH": f"{bin_dir}:{os.environ['PATH']}",
                "PROMOTION_LOG": str(log),
                "PROMOTION_STATE": str(root / "live-failed-once"),
                "FAIL_LIVE_ONCE": "1",
            }
            result = subprocess.run(
                ["bash", str(tools / "promote_release.sh"), "v2.0", "v1.9"],
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )
            self.assertEqual(result.returncode, 1)
            calls = log.read_text().splitlines()
            self.assertEqual(
                calls,
                [
                    "gh release edit v2.0 --draft=false --prerelease=false --latest=true",
                    "live 2.0",
                    "gh release edit v2.0 --prerelease=true --latest=false",
                    "gh release edit v1.9 --latest=true",
                    "live 1.9",
                ],
            )

    def test_release_is_staged_before_the_site_promotes_it(self) -> None:
        release = (REPO_ROOT / ".github/workflows/release.yml").read_text()
        promotion = (REPO_ROOT / ".github/workflows/promote-release.yml").read_text()

        self.assertIn('gh release edit "$GITHUB_REF_NAME" --draft=false --prerelease', release)
        self.assertNotIn("tools/promote_release.sh", release)
        self.assertIn('cat site/PUBLISHED_VERSION', promotion)
        self.assertIn('tools/promote_release.sh "$RELEASE_TAG"', promotion)
        self.assertIn('LIVE_ATTEMPTS: "6"', promotion)

    def test_app_bundle_contains_license_with_required_notice(self) -> None:
        license_text = (REPO_ROOT / "LICENSE").read_text()
        self.assertIn(
            "Required Notice: Copyright Bradley Berkman (https://bradleyberkman.com)",
            license_text,
        )
        build = (REPO_ROOT / "build.sh").read_text()
        self.assertIn('cp LICENSE "dist/$APP/Contents/Resources/LICENSE"', build)
        self.assertIn("WritErrorReportURL", build)
        self.assertIn("https://biv-errors.bradley-d45.workers.dev/app/writ", build)

    def test_landing_privacy_copy_matches_the_documented_network_boundary(self) -> None:
        landing = (ROOT / "public/index.html").read_text()

        self.assertNotIn("Nothing leaves your Mac", landing)
        self.assertIn("Your audio stays on your Mac", landing)
        self.assertIn("No analytics", landing)
        self.assertIn("no audio is recorded or transmitted", landing)
        self.assertIn("Optional crash and failed-device-switch reports are off by default", landing)
        self.assertIn("only the error kind, Writ version, and macOS version", landing)
        self.assertIn("Network requests expose your IP address and standard headers", landing)

    def test_privacy_policies_do_not_overstate_the_network_boundary(self) -> None:
        policies = {
            "public policy": (ROOT / "public/privacy/index.html").read_text(),
            "canonical policy": (REPO_ROOT / "docs/PRIVACY.md").read_text(),
        }

        for name, source in policies.items():
            with self.subTest(policy=name):
                policy = normalized(source)
                self.assertNotIn("Writ collects nothing about you.", policy)
                self.assertNotIn("nothing about your use of it leaves your Mac", policy)
                self.assertNotIn("Since no personal data is collected or transmitted", policy)
                self.assertNotIn("Nothing about your devices, settings or usage is transmitted", policy)
                self.assertIn(
                    "Writ does not create an account or collect analytics.",
                    policy,
                )
                self.assertIn("Optional crash and failed-device-switch reporting is off by default.", policy)
                self.assertIn("Each report contains exactly the error kind, Writ version and macOS version.", policy)
                self.assertIn("no persistent identifier, device name or identifier", policy)
                self.assertIn("user content or stack trace", policy)
                self.assertIn(
                    "server can see your IP address, the standard headers",
                    policy,
                )
                self.assertIn("the fact that Writ checked for an update", policy)
                self.assertIn(
                    "Writ does not send analytics or usage telemetry.",
                    policy,
                )
                self.assertIn("Because Writ does not retain personal data", policy)

    def test_eulas_scope_privacy_claim_to_retention_and_telemetry(self) -> None:
        eulas = {
            "public EULA": (ROOT / "public/eula/index.html").read_text(),
            "canonical EULA": (REPO_ROOT / "docs/EULA.md").read_text(),
        }

        for name, source in eulas.items():
            with self.subTest(eula=name):
                eula = normalized(source)
                self.assertNotIn("Writ collects no personal data", eula)
                self.assertIn(
                    "Writ does not retain personal data or collect analytics.",
                    eula,
                )
                self.assertIn("Optional crash and failed-device-switch reporting is off by default", eula)
                self.assertIn("only the error kind, Writ version and macOS version", eula)

    def test_terms_match_the_free_polyform_noncommercial_license(self) -> None:
        terms = {
            "public EULA": (ROOT / "public/eula/index.html").read_text(),
            "canonical EULA": (REPO_ROOT / "docs/EULA.md").read_text(),
            "public policy": (ROOT / "public/privacy/index.html").read_text(),
            "canonical policy": (REPO_ROOT / "docs/PRIVACY.md").read_text(),
            "landing": (ROOT / "public/index.html").read_text(),
        }
        commercial = ["refund", "purchase", "payment provider", "licence key", "If you buy", "you actually paid", "Draft EULA"]

        for name, source in terms.items():
            with self.subTest(terms=name):
                text = normalized(source)
                for phrase in commercial:
                    self.assertNotIn(phrase, text)
                self.assertIsNone(re.search(r"\[(?:N|[A-Z]{2,}[^\]]*)\]", text), "bracketed placeholder")

        for name in ("public EULA", "canonical EULA"):
            with self.subTest(eula=name):
                eula = normalized(terms[name])
                self.assertIn("PolyForm Noncommercial License 1.0.0", eula)
                self.assertIn("Writ is free", eula)
                self.assertIn("Commercial use needs a separate licence", eula)
                self.assertIn("support@braininavat.systems", eula)


if __name__ == "__main__":
    unittest.main()
