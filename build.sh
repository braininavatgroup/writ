#!/bin/bash
# Build MicPriority.app. Everything stays on this external volume — the internal
# disk has under 300MB free.
set -e
cd "$(dirname "$0")"

APP="MicPriority.app"
BUILD_DIR=".build/release"

echo "==> compiling"
swift build -c release --scratch-path .build

echo "==> assembling bundle"
rm -rf "dist/$APP"
mkdir -p "dist/$APP/Contents/MacOS" "dist/$APP/Contents/Resources"
cp "$BUILD_DIR/MicPriority" "dist/$APP/Contents/MacOS/MicPriority"

cat > "dist/$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>        <string>MicPriority</string>
    <key>CFBundleIdentifier</key>        <string>dance.braininavat.micpriority</string>
    <key>CFBundleName</key>              <string>MicPriority</string>
    <key>CFBundleDisplayName</key>       <string>Mic Priority</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key>           <string>1</string>
    <key>LSMinimumSystemVersion</key>    <string>13.0</string>
    <key>LSUIElement</key>               <true/>
    <key>NSPrincipalClass</key>          <string>NSApplication</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>MicPriority reads the list of audio input devices to enforce your priority order. It never records audio.</string>
</dict>
PLIST
echo "</plist>" >> "dist/$APP/Contents/Info.plist"

echo "==> ad-hoc signing"
codesign --force --deep -s - "dist/$APP"

echo "==> done: dist/$APP"
