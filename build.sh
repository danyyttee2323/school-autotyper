#!/bin/sh
# Builds AutoTyper.app next to this script.
set -e
cd "$(dirname "$0")"
APP=AutoTyper.app
mkdir -p "$APP/Contents/MacOS"
# Universal binary so it runs on both Apple Silicon and Intel Macs.
TMP=$(mktemp -d)
for ARCH in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$ARCH-apple-macos14.0" autotyper.swift -o "$TMP/$ARCH"
done
lipo -create "$TMP/arm64" "$TMP/x86_64" -output "$APP/Contents/MacOS/AutoTyper"
rm -rf "$TMP"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.autotyper</string>
  <key>CFBundleName</key><string>AutoTyper</string>
  <key>CFBundleExecutable</key><string>AutoTyper</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF
codesign --force -s - "$APP"
rm -f AutoTyper.zip
ditto -c -k --norsrc --noextattr --noacl --keepParent "$APP" AutoTyper.zip  # no local ._ metadata files
echo "Built $(pwd)/$APP and AutoTyper.zip"
echo "New build = new signature: press Start once and click Grant Access to re-allow it."
