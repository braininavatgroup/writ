#!/usr/bin/env python3
"""Validate every source marker and site page in Writ's executable feature map,
and that browser-pages.json walks every mapped site page with text it serves."""
import json
import os
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
MAP = Path(os.environ.get("WRIT_FEATURE_MAP", ROOT / "features/features.json"))
WALK = Path(os.environ.get("WRIT_BROWSER_PAGES", ROOT / "browser-pages.json"))
PUBLIC = ROOT / "site/public"


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
    try:
        walked = {page["path"]: page for page in json.loads(WALK.read_text())["pages"]}
    except (OSError, json.JSONDecodeError, KeyError, TypeError) as error:
        print(f"browser walk pages cannot be read: {error}")
        return 1
    for entry in feature_map["site"]:
        source = ROOT / entry.get("source", "")
        try:
            relative = source.relative_to(PUBLIC)
            body = source.read_text()
        except (ValueError, OSError):
            failures.append(f"{entry.get('id', '<missing>')}: not a readable page under site/public")
            continue
        path = "/" if relative.parent == Path(".") else f"/{relative.parent.as_posix()}/"
        assertions = walked.get(path, {}).get("assertions") or []
        if not assertions:
            failures.append(f"{entry.get('id')}: browser-pages.json does not walk {path}")
        for assertion in assertions:
            if assertion.get("text", "") not in body:
                failures.append(f"{entry.get('id')}: browser walk expects {assertion.get('text')!r}, which {source.relative_to(ROOT)} lacks")
    if failures:
        print("; ".join(failures))
        return 1
    print(f"{len(feature_map['app'])} app controls, {len(feature_map['site'])} site pages, all walked in the browser")
    return 0


if __name__ == "__main__":
    sys.exit(main())
