#!/usr/bin/env python3
"""Read-only signing preflight: no Keychain changes, signing or submissions."""

import base64
import json
import os
import pty
import select
import subprocess
import sys
import termios
import time


IDENTITY = "Developer ID Application: Bradley Berkman (L65VUZN7VJ)"
TEAM = "L65VUZN7VJ"
SECRET_NAMES = {
    "CERTIFICATE_P12", "CERTIFICATE_PASSWORD", "APPLE_ID",
    "APPLE_TEAM_ID", "APPLE_APP_SPECIFIC_PASSWORD",
}


def child_environment():
    return {key: value for key, value in os.environ.items() if key not in SECRET_NAMES}


def openssl(arguments, data, password=None):
    environment = child_environment()
    if password is not None:
        environment["CERTIFICATE_PASSWORD"] = password
    result = subprocess.run(
        ["openssl", *arguments], input=data, capture_output=True,
        env=environment, timeout=15,
    )
    if result.returncode:
        # OpenSSL diagnostics may contain input; emit only our fixed message.
        raise ValueError("Certificate validation failed (format, password or key).")
    return result.stdout


def verify_certificate(encoded, password):
    archive = base64.b64decode(encoded, validate=True)
    args = ["pkcs12", "-passin", "env:CERTIFICATE_PASSWORD"]
    certificate = openssl([*args, "-clcerts", "-nokeys"], archive, password)
    subject = openssl(["x509", "-noout", "-subject", "-nameopt", "RFC2253"], certificate)
    if f"CN={IDENTITY},".encode() not in subject:
        raise ValueError("Certificate is not Writ's Developer ID Application identity.")
    openssl(["x509", "-noout", "-checkend", "0"], certificate)
    private_key = openssl([*args, "-nocerts", "-nodes"], archive, password)
    openssl(["rsa", "-check", "-noout"], private_key)
    private_public = openssl(["pkey", "-pubout"], private_key)
    certificate_public = openssl(["x509", "-pubkey", "-noout"], certificate)
    if private_public != certificate_public:
        raise ValueError("Certificate does not match the private key.")


def notary_history(apple_id, team, password, *, timeout=120, command=None):
    if team != TEAM:
        raise ValueError("Unexpected Apple developer team.")
    if not apple_id or not password or any(c in password for c in "\r\n\x00"):
        raise ValueError("Missing or malformed notarization credentials.")
    command = command or [
        "xcrun", "notarytool", "history", "--apple-id", apple_id,
        "--team-id", team, "--output-format", "json",
    ]
    # notarytool supports a secure prompt when --password is omitted. A private
    # PTY keeps the password out of argv, files and the Actions log.
    master, slave = pty.openpty()
    settings = termios.tcgetattr(slave)
    settings[3] &= ~termios.ECHO
    termios.tcsetattr(slave, termios.TCSANOW, settings)
    process = None
    try:
        process = subprocess.Popen(
            command, stdin=slave, stdout=slave, stderr=slave,
            env=child_environment(), start_new_session=True,
        )
        os.close(slave)
        slave = None
        output = bytearray()
        sent = False
        deadline = time.monotonic() + timeout
        while True:
            if time.monotonic() >= deadline:
                raise ValueError("Apple read-only authentication timed out; no automatic retry.")
            if select.select([master], [], [], 0.1)[0]:
                try:
                    chunk = os.read(master, 65536)
                except OSError:
                    break
                if not chunk:
                    break
                output.extend(chunk)
                if len(output) > 8 * 1024 * 1024:
                    raise ValueError("Apple history response exceeded the bounded read.")
                prompt = f"Password for {apple_id}: ".encode()
                if not sent and prompt in output:
                    if termios.tcgetattr(master)[3] & termios.ECHO:
                        raise ValueError("Refusing a password prompt with echo enabled.")
                    os.write(master, password.encode() + b"\n")
                    sent = True
                    output.clear()
            elif process.poll() is not None:
                break
        if process.wait(timeout=5) != 0 or not sent:
            raise ValueError("Apple read-only authentication failed; no automatic retry.")
        # Do not expose submission names, IDs or tool diagnostics.
        payload = json.loads(bytes(output).strip())
        if not isinstance(payload, dict) or not isinstance(payload.get("history"), list):
            raise ValueError("Unexpected Apple history response.")
    finally:
        if process is not None and process.poll() is None:
            process.kill()
            process.wait()
        os.close(master)
        if slave is not None:
            os.close(slave)


def main():
    try:
        if any(not os.environ.get(name) for name in SECRET_NAMES):
            raise ValueError("All five release-signing values are required.")
        verify_certificate(os.environ["CERTIFICATE_P12"], os.environ["CERTIFICATE_PASSWORD"])
        print("PASS: expected Developer ID certificate, unexpired, matching valid private key.")
        notary_history(os.environ["APPLE_ID"], os.environ["APPLE_TEAM_ID"],
                       os.environ["APPLE_APP_SPECIFIC_PASSWORD"])
        print("PASS: Apple notarization history authenticated read; no submission or release.")
    except Exception:
        # Even parser/subprocess exceptions must not echo secret-bearing input.
        print("FAIL: signing credential verification; no values or service response logged.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
