#!/usr/bin/env python3
"""Validate Writ's release feed and, when supplied, its downloaded DMG."""
import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Optional


def validate(
    feed_path: Path,
    artifact: Optional[Path] = None,
    expected_version: Optional[str] = None,
    latest_release_tag: Optional[str] = None,
) -> dict:
    feed = json.loads(feed_path.read_text())
    version = feed.get("version")
    if not isinstance(version, str) or not re.fullmatch(r"\d+\.\d+(?:\.\d+)?", version):
        raise ValueError("version must be a dotted numeric release version")
    if expected_version is not None and version != expected_version:
        raise ValueError(f"feed version {version} does not match expected {expected_version}")
    if latest_release_tag is not None and latest_release_tag != f"v{version}":
        raise ValueError(f"feed version {version} does not match latest release {latest_release_tag}")
    if not isinstance(feed.get("build"), int) or feed["build"] <= 0:
        raise ValueError("build must be a positive integer")
    expected_url = (
        f"https://github.com/braininavatgroup/writ/releases/download/v{version}/"
        f"Writ-{version}.dmg"
    )
    if feed.get("url") != expected_url:
        raise ValueError("url must point to this version's immutable release DMG")
    expected_hash = feed.get("sha256")
    if not isinstance(expected_hash, str) or not re.fullmatch(r"[0-9a-f]{64}", expected_hash):
        raise ValueError("sha256 must be a lowercase SHA-256 hex digest")
    if not isinstance(feed.get("notes"), str) or not feed["notes"].strip():
        raise ValueError("notes must be nonempty text")
    if artifact is not None:
        data = artifact.read_bytes()
        if len(data) < 512 or data[-512:-508] != b"koly":
            raise ValueError("downloaded artifact is not a UDIF disk image")
        actual_hash = hashlib.sha256(data).hexdigest()
        if actual_hash != expected_hash:
            raise ValueError("downloaded DMG SHA-256 does not match appcast")
    return feed


def no_public_release(
    repository_path: Path, repository_status: str, latest_path: Path, latest_status: str
) -> bool:
    """Prove the public repo exists and its latest-release endpoint is truly empty."""
    if repository_status != "200" or latest_status != "404":
        return False
    try:
        repository = json.loads(repository_path.read_text())
        latest = json.loads(latest_path.read_text())
    except (OSError, json.JSONDecodeError):
        return False
    return repository.get("full_name") == "braininavatgroup/writ" and latest.get("message") == "Not Found"


def published_build(feed_path: Path, feed_status: str) -> int:
    """Read the current build from a verified published feed."""
    if feed_status == "200":
        return validate(feed_path)["build"]
    raise ValueError(f"cannot establish published build (feed HTTP {feed_status})")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("feed", type=Path)
    parser.add_argument("--artifact", type=Path)
    parser.add_argument("--expected-version")
    parser.add_argument("--latest-release-tag")
    parser.add_argument("--published-build-status")
    parser.add_argument("--verify-no-public-release", action="store_true")
    parser.add_argument("--repository-response", type=Path)
    parser.add_argument("--repository-status")
    parser.add_argument("--latest-response", type=Path)
    parser.add_argument("--latest-release-status")
    args = parser.parse_args()
    try:
        if args.published_build_status is not None:
            print(published_build(args.feed, args.published_build_status))
            return 0
        if args.verify_no_public_release:
            if not all((args.repository_response, args.repository_status, args.latest_response, args.latest_release_status)):
                raise ValueError("repo and latest-release response bodies and statuses are required")
            if not no_public_release(
                args.repository_response,
                args.repository_status,
                args.latest_response,
                args.latest_release_status,
            ):
                raise ValueError("GitHub responses do not prove that no public release exists")
            print("no public release exists")
            return 0
        feed = validate(args.feed, args.artifact, args.expected_version, args.latest_release_tag)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"invalid release feed: {exc}", file=sys.stderr)
        return 1
    print(f"Writ {feed['version']} build {feed['build']} feed valid")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
