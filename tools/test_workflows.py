#!/usr/bin/env python3
"""Hosted macOS runs only when Bradley authorizes the run (BIV-1320).

Owner: the ci, native, release and verify-signing workflows. Retire when the
org lint in agent-runtime covers per-event gates, or when writ has no hosted
macOS job left.
"""
import re
import unittest
from pathlib import Path

WORKFLOWS = Path(__file__).resolve().parents[1] / ".github/workflows"


def jobs(name):
    text = (WORKFLOWS / name).read_text()
    body = text.split("\njobs:\n", 1)[1]
    return {m.group(1): m.group(2) for m in re.finditer(r"^  ([a-z][\w-]*):\n(.*?)(?=^  [a-z][\w-]*:|\Z)", body, re.M | re.S)}


def condition(job):
    match = re.search(r"^    if: (?:>-\n((?:      .*\n)+)|(.*)\n)", job, re.M)
    assert match, "job has no if:"
    return " ".join(part.strip() for part in (match.group(1) or match.group(2)).split("\n")).strip()


class HostedMacos(unittest.TestCase):
    def test_every_hosted_macos_job_reads_an_input_or_a_pull_request_label(self):
        for name in ("ci.yml", "release.yml", "verify-signing.yml"):
            for job_name, job in jobs(name).items():
                if not re.search(r"runs-on: .*macos-", job):
                    continue
                with self.subTest(workflow=name, job=job_name):
                    gate = condition(job)
                    self.assertRegex(gate, r"inputs\.hosted_macos|contains\(github\.event\.pull_request\.labels\.\*\.name, 'hosted-native-ci'\)")
                    # A main push is not an authorization.
                    self.assertNotIn("github.event_name == 'push'", gate)

    def test_the_native_lane_runs_only_this_repositorys_commits_on_named_events(self):
        job = jobs("native.yml")["swift-test"]
        self.assertEqual(condition(job),
            "github.event_name == 'push' || github.event_name == 'workflow_dispatch' "
            "|| (github.event_name == 'pull_request' && github.event.pull_request.head.repo.full_name == github.repository)")
        self.assertIn("runs-on: ${{ fromJSON(inputs.hosted_native && '[\"macos-15\"]' || '[\"self-hosted\",\"macOS\",\"mac-xcode\"]') }}", job)
        self.assertNotIn("ref:", job)

    def test_the_aggregate_is_the_required_check_and_deploys_wait_for_it(self):
        ci = jobs("ci.yml")
        self.assertIn("ci", ci)
        self.assertIn("needs: [check, swift-test]", ci["ci"])
        self.assertIn("needs: [ci, changes]", ci["deploy-site"])
        self.assertNotIn("push", condition(ci["swift-test"]))


if __name__ == "__main__":
    unittest.main()
