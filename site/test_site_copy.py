#!/usr/bin/env python3
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parent
REPO_ROOT = ROOT.parent


def normalized(source: str) -> str:
    return " ".join(source.split())


class SiteCopyTests(unittest.TestCase):
    def test_landing_privacy_copy_matches_the_documented_network_boundary(self) -> None:
        landing = (ROOT / "public/index.html").read_text()

        self.assertNotIn("Nothing leaves your Mac", landing)
        self.assertIn("Your audio stays on your Mac", landing)
        self.assertIn("No analytics", landing)
        self.assertIn("no audio is recorded or transmitted", landing)
        self.assertIn("Automatic update checks make a standard web request", landing)
        self.assertIn("exposes your IP address and standard headers", landing)

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
                    "Writ does not create an account or collect analytics, crash reports, or app telemetry.",
                    policy,
                )
                self.assertIn(
                    "server can see your IP address, the standard headers",
                    policy,
                )
                self.assertIn("the fact that Writ checked for an update", policy)
                self.assertIn(
                    "Writ does not send analytics or telemetry about how you use the app.",
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
                    "Writ does not retain personal data or collect analytics, crash reports, or app telemetry.",
                    eula,
                )
                self.assertIn("Update checks expose ordinary request metadata", eula)

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
