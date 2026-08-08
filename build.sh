#!/bin/bash
# Build Writ.app.
#
#   ./build.sh              universal (arm64 + x86_64), ad-hoc signed — default
#   ./build.sh --fast       arm64 only, for quick local iteration
#   ./build.sh --release    universal + hardened runtime, signed with Developer ID
#                           (set DEVELOPER_ID), ready for notarisation
#   ./build.sh --appstore   universal + App Sandbox, for Mac App Store only
#
# Sandboxing is deliberately NOT the default. It is required only by the Mac App
# Store, and it confines the app to its own preferences container — which
# silently orphaned saved device rankings across a bundle identifier change.
# Setapp and direct sales want Developer ID + notarisation, not the sandbox.
set -e
cd "$(dirname "$0")"

APP="Writ.app"
BUNDLE_ID="dance.braininavat.writ"
MODE="${1:-}"

# Version lives in one file. CFBundleVersion is the COMMIT TIMESTAMP, and the
# updater compares that — version STRINGS must never be compared, because "1.10"
# sorts below "1.9" as text.
#
# It was the commit count, which is not monotonic once branches are squash-
# merged: a build cut from a branch counts the branch's commits, and main counts
# one commit for the whole squashed merge. A branch build genuinely produced 20
# while the main it merged into produced 18 — publish that and everyone who took
# 20 is stranded, because no future main build can ever exceed it.
#
# A commit timestamp only ever increases, whatever the branch topology.
VERSION="$(cat VERSION)"
BUILD="$(git log -1 --format=%ct 2>/dev/null || echo 1)"

# Both keys are optional and both gate a feature: with no feed URL the app makes
# no network requests and hides "Check for Updates", and with no support address
# it hides "Contact Support". Ship them empty until the site exists.
UPDATE_FEED="${WRIT_UPDATE_FEED:-}"
SUPPORT_EMAIL="${WRIT_SUPPORT_EMAIL:-}"

# Universal by default: Setapp requires a fat binary, and Intel Macs still run
# macOS 13. There is no runtime cost — Apple silicon executes the arm64 slice
# and ignores the other. The only price is a couple of MB and a slower build.
ARCHS=(--arch arm64 --arch x86_64)
[ "$MODE" = "--fast" ] && ARCHS=(--arch arm64)

echo "==> compiling ${ARCHS[*]}"
swift build -c release --scratch-path .build "${ARCHS[@]}"

# A universal build lands in a merged folder, a single-arch build does not — and
# the merged folder SURVIVES a later single-arch build. Picking it by existence
# meant --fast silently bundled whatever the last universal build produced, so
# the path is chosen by mode instead.
if [ "$MODE" = "--fast" ]; then
    BIN=".build/release/Writ"
else
    BIN=".build/apple/Products/Release/Writ"
fi
[ -f "$BIN" ] || { echo "error: no binary at $BIN" >&2; exit 1; }

echo "==> assembling bundle"
rm -rf "dist/$APP"
mkdir -p "dist/$APP/Contents/MacOS" "dist/$APP/Contents/Resources"
cp "$BIN" "dist/$APP/Contents/MacOS/Writ"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "dist/$APP/Contents/Resources/"

cat > "dist/$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>        <string>Writ</string>
    <key>CFBundleIdentifier</key>        <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>              <string>Writ</string>
    <key>CFBundleDisplayName</key>       <string>Writ</string>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key>           <string>${BUILD}</string>
    <key>LSMinimumSystemVersion</key>    <string>13.0</string>
    <key>LSUIElement</key>               <true/>
    <key>NSPrincipalClass</key>          <string>NSApplication</string>
    <key>NSHumanReadableCopyright</key>  <string>Copyright © 2026 Bradley Berkman. All rights reserved.</string>
    <key>WritUpdateFeedURL</key>         <string>${UPDATE_FEED}</string>
    <key>WritSupportEmail</key>          <string>${SUPPORT_EMAIL}</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Writ shows a live input level so you can confirm your microphone is being heard. Audio is measured and discarded — never recorded, saved or sent anywhere.</string>
</dict>
</plist>
PLIST

ENTITLEMENTS="Writ.entitlements"
[ "$MODE" = "--appstore" ] && ENTITLEMENTS="Writ-appstore.entitlements"

if [ "$MODE" = "--release" ] || [ "$MODE" = "--appstore" ]; then
    : "${DEVELOPER_ID:?set DEVELOPER_ID, e.g. \"Developer ID Application: Your Name (TEAMID)\"}"
    echo "==> signing with Developer ID + hardened runtime"
    # --options runtime is mandatory for notarisation.
    codesign --force --deep --timestamp --options runtime \
             --entitlements "$ENTITLEMENTS" \
             -s "$DEVELOPER_ID" "dist/$APP"
    codesign --verify --strict --verbose=2 "dist/$APP"
    echo "==> next: ./release.sh   (notarise, staple, package)"
else
    echo "==> ad-hoc signing (local use only)"
    codesign --force --deep -s - --entitlements "$ENTITLEMENTS" "dist/$APP"
fi

echo "==> architectures: $(lipo -archs "dist/$APP/Contents/MacOS/Writ")"
echo "==> done: dist/$APP  ($VERSION build $BUILD)"
