#!/bin/sh
# Builds PandaPal.app with swiftc directly, after running the behaviour tests. Usage: ./build.sh
# (No Swift package: the package manager in Command Line Tools 27.0 cannot build manifests on this Mac.)
set -e
cd "$(dirname "$0")"
mkdir -p build

swiftc -o build/check Sources/PandaPal/Brain.swift Sources/PandaPal/Personality.swift Sources/PandaPal/Rewards.swift Sources/PandaPal/Words.swift Sources/PandaPal/Agents.swift Tests/main.swift
./build/check      # its own line, so set -e stops the build when a test fails

APP=build/PandaPal.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/AppIcon.icns Resources/hook.sh "$APP/Contents/Resources/"
swiftc -O -swift-version 5 -target arm64-apple-macos26.0 -o "$APP/Contents/MacOS/PandaPal" Sources/PandaPal/*.swift
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>PandaPal</string>
  <key>CFBundleIdentifier</key><string>dev.luffy2095.pandapal</string>
  <key>CFBundleName</key><string>PandaPal</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.1.0</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
</dict></plist>
PLIST
codesign --force --deep --options runtime -s - "$APP"   # hardened runtime: no code injection
echo "built $APP"
