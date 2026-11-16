#!/usr/bin/env python3
"""Match denylisted word sequences in Git trees without logging private text.

The policy is supplied as SHA-256 fingerprints, not names. Fingerprints are
matching aids, not anonymization or secrets. This is a denylist, not a general
personal-data detector; encoded/compressed assets require separate review.
"""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import unicodedata


def words(text):
    return re.findall(r"[^\W_]+", unicodedata.normalize("NFKC", text).casefold())


def fingerprint(term):
    tokens = words(term)
    if not tokens or len(tokens) > 32:
        raise ValueError("Denylist terms must have 1–32 words")
    return {"words": len(tokens), "sha256": hashlib.sha256(" ".join(tokens).encode()).hexdigest()}


def policy(value):
    entries = json.loads(value)
    if not isinstance(entries, list) or not entries:
        raise ValueError("A nonempty denylist is required")
    grouped = {}
    for entry in entries:
        if (not isinstance(entry, dict) or set(entry) != {"words", "sha256"}
                or type(entry["words"]) is not int or not 1 <= entry["words"] <= 32
                or not isinstance(entry["sha256"], str)
                or not re.fullmatch(r"[a-f0-9]{64}", entry["sha256"])):
            raise ValueError("Invalid denylist fingerprint")
        grouped.setdefault(entry["words"], set()).add(entry["sha256"])
    return grouped


def matches(text, denied):
    tokens = words(text)
    for length, digests in denied.items():
        for start in range(len(tokens) - length + 1):
            digest = hashlib.sha256(" ".join(tokens[start:start + length]).encode()).hexdigest()
            if digest in digests:
                return True
    return False


def scan(root, denied):
    """Inspect committed blobs, filenames and symlink targets, never filesystem targets."""
    tree = subprocess.check_output(["git", "-C", str(root), "ls-tree", "-rz", "--full-tree", "HEAD"], stderr=subprocess.DEVNULL)
    found = 0
    with subprocess.Popen(["git", "-C", str(root), "cat-file", "--batch"],
                          stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL) as reader:
        try:
            for record in tree.split(b"\0"):
                if not record:
                    continue
                metadata, name = record.split(b"\t", 1)
                mode, kind, oid = metadata.split()
                if kind != b"blob":
                    raise ValueError("Gitlinks must be scanned separately before publication")
                reader.stdin.write(oid + b"\n")
                reader.stdin.flush()
                header = reader.stdout.readline().split()
                if len(header) != 3 or header[:2] != [oid, b"blob"]:
                    raise ValueError("Unable to read a tracked blob")
                data = reader.stdout.read(int(header[2]))
                if len(data) != int(header[2]) or reader.stdout.read(1) != b"\n":
                    raise ValueError("Incomplete tracked blob")
                texts = [name.decode("utf-8", "replace"), data.decode("utf-8", "replace")]
                if data.startswith((b"\xff\xfe", b"\xfe\xff")):
                    texts.append(data.decode("utf-16", "replace"))
                if any(matches(text, denied) for text in texts):
                    found += 1
                    # A filename can itself contain personal data. Only the
                    # object ID is safe to include in public CI output.
                    print(f"Denied term in tracked object {oid.decode()}")
        finally:
            reader.stdin.close()
            reader.wait()
        if reader.returncode:
            raise ValueError("Git object reader failed")
    return found


def main():
    try:
        denied = policy(os.environ.get("PUBLIC_TREE_DENYLIST", ""))
        found = scan(Path(sys.argv[1] if len(sys.argv) > 1 else "."), denied)
        if found:
            print(f"Public-tree denylist failed: {found} tracked objects. Remove private data; do not log it.")
            return 1
        print("Public-tree denylist passed for the complete committed tree.")
        return 0
    except (ValueError, OSError, subprocess.SubprocessError):
        print("Public-tree denylist could not complete; check policy and Git input. Details omitted.")
        return 2


if __name__ == "__main__":
    sys.exit(main())
