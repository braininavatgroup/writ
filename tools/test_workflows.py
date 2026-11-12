#!/usr/bin/env python3
"""writ's macOS jobs: the native lane on hosted macOS, never the Mini (BIV-1608);
release and signing only when Bradley authorizes the run (BIV-1320).

Owner: the ci, native, release and verify-signing workflows. Retire when the
org lint in infra covers per-event gates and self-hosted targets, or when writ
has no macOS job left.
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
        self.assertRegex(job, r"(?m)^    runs-on: macos-\d+$")
        self.assertNotIn("ref:", job)

    def test_no_workflow_targets_a_self_hosted_runner(self):
        # writ is public: the Mini's runners can reach the login Keychain, so
        # no writ job may run there (BIV-1608, Bradley 2026-11-12).
        for path in sorted(WORKFLOWS.glob("*.y*ml")):
            with self.subTest(workflow=path.name):
                self.assertNotRegex(path.read_text(), r"self-hosted|mac-xcode|mac-keychain|mac-tools")

    def test_a_dispatch_without_the_authorization_fails_loudly(self):
        for name in ("release.yml", "verify-signing.yml"):
            job = jobs(name)["refuse-without-authorization"]
            # Any pinned Ubuntu image, so a Renovate runner bump passes. Still
            # refuses a moving label, a hosted macOS image or an expression.
            self.assertRegex(job, r"(?m)^    runs-on: ubuntu-\d+\.\d+$")
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

    def test_ci_calls_this_commits_native_lane(self):
        # A local path, so a pull request that edits native.yml tests its own copy.
        job = jobs("ci.yml")["swift-test"]
        self.assertIn("uses: ./.github/workflows/native.yml", job)
        self.assertNotIn("with:", job)
        self.assertNotIn("runs-on", job)


if __name__ == "__main__":
    unittest.main()
