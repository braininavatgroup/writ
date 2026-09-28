#!/usr/bin/env python3
"""Validate every source marker and site page in Writ's executable feature map."""
import json
import os
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
MAP = Path(os.environ.get("WRIT_FEATURE_MAP", ROOT / "features/features.json"))


def main() -> int:
    try:
        feature_map = json.loads(MAP.read_text())
    except (OSError, json.JSONDecodeError) as error:
        print(f"feature map cannot be read: {error}")
        return 1
    failures = []
    ids = [entry.get("id") for entry in feature_map["app"]]
    if not all(ids) or len(ids) != len(set(ids)):
        failures.append("app feature ids are missing or duplicated")
    for entry in [*feature_map["app"], *feature_map["site"]]:
        source = ROOT / entry.get("source", "")
        marker = entry.get("marker", "")
        try:
            body = source.read_text()
        except OSError:
            body = ""
        if not marker or marker not in body:
            failures.append(f"{entry.get('id', '<missing>')}: {source.relative_to(ROOT)} lacks {marker!r}")
    if failures:
        print("; ".join(failures))
        return 1
    print(f"{len(feature_map['app'])} app controls, {len(feature_map['site'])} site pages")
    return 0


if __name__ == "__main__":
    sys.exit(main())
