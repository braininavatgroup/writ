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

# Universal by default: Setapp requires a fat binary, and Intel Macs still run
# macOS 13. There is no runtime cost — Apple silicon executes the arm64 slice
# and ignores the other. The only price is a couple of MB and a slower build.
ARCHS=(--arch arm64 --arch x86_64)
[ "$MODE" = "--fast" ] && ARCHS=(--arch arm64)

echo "==> compiling ${ARCHS[*]}"
swift build -c release --scratch-path .build "${ARCHS[@]}"

# A universal build lands in a merged folder; a single-arch build does not.
BIN=".build/apple/Products/Release/Writ"
[ -f "$BIN" ] || BIN=".build/release/Writ"

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
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key>           <string>1</string>
    <key>LSMinimumSystemVersion</key>    <string>13.0</string>
    <key>LSUIElement</key>               <true/>
    <key>NSPrincipalClass</key>          <string>NSApplication</string>
    <key>NSHumanReadableCopyright</key>  <string>Copyright © 2026. All rights reserved.</string>
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
    echo "==> next: notarise"
    echo "    ditto -c -k --keepParent dist/$APP dist/Writ.zip"
    echo "    xcrun notarytool submit dist/Writ.zip --keychain-profile AC_PASSWORD --wait"
    echo "    xcrun stapler staple dist/$APP"
else
    echo "==> ad-hoc signing (local use only)"
    codesign --force --deep -s - --entitlements "$ENTITLEMENTS" "dist/$APP"
fi

echo "==> architectures: $(lipo -archs "dist/$APP/Contents/MacOS/Writ")"
echo "==> done: dist/$APP"
