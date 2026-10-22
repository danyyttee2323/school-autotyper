#!/bin/sh
# Builds AutoTyper.app next to this script.
set -e
cd "$(dirname "$0")"
APP=AutoTyper.app
mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos14.0" autotyper.swift -o "$APP/Contents/MacOS/AutoTyper"
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
echo "Built $(pwd)/$APP"
echo "New build = new signature: press Start once and click Grant Access to re-allow it."
