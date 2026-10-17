import base64
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import verify_signing as verify


class CertificateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        root = Path(cls.temp.name)
        cls.password = "synthetic-test-export-password"
        cls.archives = {}
        for name, identity in [("expected", verify.IDENTITY), ("wrong", "Other Developer")]:
            key, cert = root / f"{name}.key", root / f"{name}.crt"
            subprocess.run([
                "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                "-keyout", str(key), "-out", str(cert), "-days", "1",
                "-subj", f"/OU={verify.TEAM}/CN={identity}",
            ], check=True, capture_output=True)
            result = subprocess.run([
                "openssl", "pkcs12", "-export", "-inkey", str(key), "-in", str(cert),
                "-passout", "env:TEST_EXPORT_PASSWORD",
            ], check=True, capture_output=True,
                env={**os.environ, "TEST_EXPORT_PASSWORD": cls.password})
            cls.archives[name] = base64.b64encode(result.stdout).decode()

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def test_real_pkcs12_expected_identity_and_private_key(self):
        verify.verify_certificate(self.archives["expected"], self.password)

    def test_real_pkcs12_wrong_password_refused(self):
        with self.assertRaises(ValueError):
            verify.verify_certificate(self.archives["expected"], "wrong-password")

    def test_real_pkcs12_wrong_identity_refused(self):
        with self.assertRaisesRegex(ValueError, "not Writ"):
            verify.verify_certificate(self.archives["wrong"], self.password)

    def test_no_secret_in_failure_output(self):
        secret = "synthetic-NOT-A-REAL-SECRET"
        environment = {**os.environ, **dict.fromkeys(verify.SECRET_NAMES, secret)}
        result = subprocess.run([sys.executable, str(Path(verify.__file__))],
                                capture_output=True, env=environment)
        self.assertEqual(result.returncode, 1)
        self.assertNotIn(secret.encode(), result.stdout + result.stderr)


class NotaryPromptTests(unittest.TestCase):
    def command(self, outcome="success"):
        # A real separate PTY consumer checks the password arrives only on
        # stdin. It emulates notarytool's observed macOS prompt and JSON shape.
        program = r'''
import json, os, sys, time
assert not any(key in os.environ for key in %r)
assert "synthetic-password" not in str(sys.argv)
if %r == "timeout":
    time.sleep(10)
sys.stdout.write("Password for verification@example.invalid: ")
sys.stdout.flush()
assert sys.stdin.readline().strip() == "synthetic-password"
if %r == "failure":
    print("synthetic-password")
    sys.exit(1)
print(json.dumps({"history": []}))
''' % (list(verify.SECRET_NAMES), outcome, outcome)
        return [sys.executable, "-c", program]

    def test_secure_prompt_and_successful_read(self):
        with patch.dict(os.environ, dict.fromkeys(verify.SECRET_NAMES, "not-in-child-env")):
            verify.notary_history("verification@example.invalid", verify.TEAM,
                                  "synthetic-password", command=self.command())

    def test_refused_authentication_is_not_retried(self):
        with self.assertRaisesRegex(ValueError, "authentication failed"):
            verify.notary_history("verification@example.invalid", verify.TEAM,
                                  "synthetic-password", command=self.command("failure"))

    def test_prompt_timeout_is_bounded(self):
        with self.assertRaisesRegex(ValueError, "timed out"):
            verify.notary_history("verification@example.invalid", verify.TEAM,
                                  "synthetic-password", timeout=0.2,
                                  command=self.command("timeout"))

    def test_other_team_refused_before_launch(self):
        with self.assertRaisesRegex(ValueError, "Unexpected"):
            verify.notary_history("verification@example.invalid", "OTHERTEAM",
                                  "synthetic-password", command=["must-not-run"])


if __name__ == "__main__":
    unittest.main()
