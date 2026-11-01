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

    def test_a_dispatch_without_the_authorization_fails_loudly(self):
        for name in ("release.yml", "verify-signing.yml"):
            job = jobs(name)["refuse-without-authorization"]
            self.assertIn("runs-on: ubuntu-24.04", job)
            self.assertIn("!inputs.hosted_macos", condition(job))
            self.assertIn("exit 1", job)

    def test_the_aggregate_is_the_required_check_and_deploys_wait_for_it(self):
        ci = jobs("ci.yml")
        self.assertIn("ci", ci)
        self.assertIn("needs: [check, swift-test]", ci["ci"])
        self.assertIn("needs: [ci, changes]", ci["deploy-site"])
        # The lane is owed on every same-repository PR and main push; a skipped
        # lane (a fork PR, or the group refusing the file) fails the aggregate.
        self.assertIn('test "$SWIFT" = success ||', ci["ci"])
        self.assertNotIn("skipped) ;;", ci["ci"])

    def test_ci_calls_the_native_lane_at_main_and_routes_hosted_only_by_label(self):
        job = jobs("ci.yml")["swift-test"]
        self.assertIn("uses: braininavatgroup/writ/.github/workflows/native.yml@main", job)
        self.assertIn("hosted_native: ${{ github.event_name == 'pull_request' && github.event.pull_request.head.repo.full_name == github.repository && contains(github.event.pull_request.labels.*.name, 'hosted-native-ci') }}", job)
        self.assertNotIn("runs-on", job)


if __name__ == "__main__":
    unittest.main()
