#!/bin/bash
# Build, notarise, staple and package a shippable Writ.
#
#   ./release.sh                 full run
#   ./release.sh --package-only  re-package an already-notarised dist/Writ.app
#
# Produces both artefacts, because they are not interchangeable:
#   dist/Writ-<version>.dmg   what people download — mounts, drag to Applications
#   dist/Writ-<version>.zip   what an updater or Homebrew cask fetches
#
# The DMG matters beyond looking normal. An app launched from inside a
# downloaded zip runs under Gatekeeper path randomisation, so it cannot see its
# own container reliably and "Open at Login" registers a path that vanishes. A
# DMG with an /Applications alias makes installing the obvious move.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(cat VERSION)"
APP="dist/Writ.app"
KEYCHAIN_PROFILE="${KEYCHAIN_PROFILE:-AC_PASSWORD}"

if [ "${1:-}" != "--package-only" ]; then
    : "${DEVELOPER_ID:?set DEVELOPER_ID, e.g. \"Developer ID Application: Bradley Berkman (L65VUZN7VJ)\"}"

    # Refuse to ship a release built from a dirty tree: CFBundleVersion is the
    # HEAD commit timestamp, so uncommitted work would ship under a build number
    # that already belongs to something else.
    DIRTY="$(git status --porcelain)"
    if [ -n "$DIRTY" ]; then
        echo "error: working tree is dirty — commit before releasing" >&2
        echo "$DIRTY" >&2
        exit 1
    fi

    # A release must never advertise a build lower than the one already
    # published: everyone on the higher build would be stranded, since the app
    # only offers an update when the feed's build EXCEEDS theirs. Nothing about
    # that failure is visible — those users simply stop receiving releases.
    FEED_TMP="$(mktemp)"
    API_TMP="$(mktemp)"
    REPO_TMP="$(mktemp)"
    trap 'rm -f "$FEED_TMP" "$API_TMP" "$REPO_TMP"' EXIT
    FEED_STATUS="$(curl -sSL --max-time 20 -o "$FEED_TMP" -w '%{http_code}' \
      "https://writ.braininavat.dance/appcast.json")" \
      || { echo "error: could not read published update feed" >&2; exit 1; }
    RELEASE_STATUS=""
    if [ "$FEED_STATUS" = 404 ]; then
        REPO_STATUS="$(curl -sS --max-time 20 -o "$REPO_TMP" -w '%{http_code}' \
          "https://api.github.com/repos/braininavatgroup/writ")" \
          || { echo "error: could not verify the Writ GitHub repository" >&2; exit 1; }
        RELEASE_STATUS="$(curl -sS --max-time 20 -o "$API_TMP" -w '%{http_code}' \
          "https://api.github.com/repos/braininavatgroup/writ/releases/latest")" \
          || { echo "error: could not verify whether a prior release exists" >&2; exit 1; }
        python3 tools/verify_release_feed.py "$FEED_TMP" --verify-no-public-release \
          --repository-response "$REPO_TMP" --repository-status "$REPO_STATUS" \
          --latest-response "$API_TMP" --latest-release-status "$RELEASE_STATUS" >/dev/null \
          || { echo "error: feed is missing but GitHub did not confirm a first release" >&2; exit 1; }
        PUBLISHED=0
    else
        PUBLISHED="$(python3 tools/verify_release_feed.py "$FEED_TMP" \
          --published-build-status "$FEED_STATUS")" \
          || { echo "error: could not establish the currently published build" >&2; exit 1; }
    fi
    rm -f "$FEED_TMP" "$API_TMP" "$REPO_TMP"
    trap - EXIT
    CANDIDATE="$(git log -1 --format=%ct)"
    if [ "$PUBLISHED" != "0" ] && [ "$CANDIDATE" -le "$PUBLISHED" ]; then
        echo "error: this build ($CANDIDATE) is not newer than the published one ($PUBLISHED)." >&2
        echo "       Publishing it would strand everyone already on $PUBLISHED." >&2
        exit 1
    fi

    ./build.sh --release

    echo "==> notarising"
    ditto -c -k --keepParent "$APP" dist/Writ-notarize.zip
    xcrun notarytool submit dist/Writ-notarize.zip \
          --keychain-profile "$KEYCHAIN_PROFILE" --wait
    rm -f dist/Writ-notarize.zip

    echo "==> stapling"
    xcrun stapler staple "$APP"
fi

# Verify the thing being shipped, not the thing that was built. Stapling
# rewrites the bundle, so this has to run after it.
echo "==> verifying"
xcrun stapler validate "$APP"
spctl -a -vvv -t exec "$APP" 2>&1 | grep -q 'source=Notarized Developer ID' \
    || { echo "error: Gatekeeper did not report a notarised build" >&2; exit 1; }
echo "    Gatekeeper: accepted, source=Notarized Developer ID"

echo "==> packaging"
rm -f "dist/Writ-$VERSION.zip" "dist/Writ-$VERSION.dmg"
ditto -c -k --keepParent "$APP" "dist/Writ-$VERSION.zip"

STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Writ" -srcfolder "$STAGE" \
        -ov -format UDZO "dist/Writ-$VERSION.dmg"
rm -rf "$STAGE"

# The DMG carries its own notarisation ticket so the download validates offline,
# even before it is opened. Submitting it is fast now that the identity has
# history; the first ever submission on a new identity is held for deep analysis.
if [ "${1:-}" != "--package-only" ]; then
    echo "==> notarising the disk image"
    xcrun notarytool submit "dist/Writ-$VERSION.dmg" \
          --keychain-profile "$KEYCHAIN_PROFILE" --wait
    xcrun stapler staple "dist/Writ-$VERSION.dmg"
fi

# The update feed is uploaded with immutable versioned GitHub Release assets.
# Pages redirects its stable feed URL to the latest published release.
echo "==> writing the update feed"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"

mkdir -p dist
python3 - "$VERSION" "$BUILD" <<'PY'
import json, re, sys
from pathlib import Path
import hashlib

version, build = sys.argv[1], int(sys.argv[2])

# These notes are shown verbatim in an alert, so they have to read as prose.
# Naive line-slicing produced headings, half-sentences and the indentation of
# wrapped Markdown — take whole bullets, unwrap them, and drop the syntax.
lines, section = open("CHANGELOG.md").read().splitlines(), False
bullets, current = [], None
for line in lines:
    if line.startswith("## "):
        if section:
            break            # next version — stop at the first section only
        section = True
        continue
    if not section or line.startswith("#"):
        continue
    if line.startswith("- "):
        if current:
            bullets.append(current)
        current = line[2:].strip()
    elif line.strip() and current:
        current += " " + line.strip()   # continuation of a wrapped bullet
    elif not line.strip() and current:
        bullets.append(current)
        current = None
if current:
    bullets.append(current)

def clean(text):
    text = re.sub(r"\*\*(.+?)\*\*", r"\1", text)   # bold
    text = re.sub(r"`(.+?)`", r"\1", text)         # code
    return re.sub(r"\s+", " ", text).strip()

notes = "\n".join("• " + clean(b) for b in bullets[:6]) or f"Writ {version}"

artifact = Path(f"dist/Writ-{version}.dmg")
feed = {
    "version": version,
    "build": build,
    "url": f"https://github.com/braininavatgroup/writ/releases/download/v{version}/Writ-{version}.dmg",
    "sha256": hashlib.sha256(artifact.read_bytes()).hexdigest(),
    "notes": notes,
}
with open("dist/appcast.json", "w") as f:
    json.dump(feed, f, indent=2)
    f.write("\n")
print(f"    dist/appcast.json  ->  {version} build {build}, {len(bullets)} notes")
PY

echo
echo "==> shippable:"
ls -lh "dist/Writ-$VERSION.dmg" "dist/Writ-$VERSION.zip" | awk '{print "    " $9, $5}'
echo "    sha256 (dmg): $(shasum -a 256 "dist/Writ-$VERSION.dmg" | cut -d' ' -f1)"
echo "    sha256 (zip): $(shasum -a 256 "dist/Writ-$VERSION.zip" | cut -d' ' -f1)"
echo
echo "==> upload dist/Writ-$VERSION.dmg, dist/Writ-$VERSION.zip, and dist/appcast.json to immutable release v$VERSION"
