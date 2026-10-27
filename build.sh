#!/bin/sh
# Builds PandaPal.app with swiftc directly, after running the behaviour tests. Usage: ./build.sh
# (No Swift package: the package manager in Command Line Tools 27.0 cannot build manifests on this Mac.)
set -e
cd "$(dirname "$0")"
mkdir -p build Vendor

# Lottie, for the kawaii style: downloaded once from the official release and checked against its published checksum
LOTTIE_URL=https://github.com/airbnb/lottie-ios/releases/download/4.5.2/Lottie.xcframework.zip
LOTTIE_SHA=92206ff6af80373903767214ac16215838f6da11dedca789c0439299b46b6694
if [ ! -d Vendor/Lottie.xcframework ]; then
  curl -sL -o Vendor/Lottie.xcframework.zip "$LOTTIE_URL"
  echo "$LOTTIE_SHA  Vendor/Lottie.xcframework.zip" | shasum -a 256 -c -
  unzip -q -o Vendor/Lottie.xcframework.zip -d Vendor/
fi
FW=Vendor/Lottie.xcframework/macos-arm64_x86_64

swiftc -o build/check Sources/PandaPal/Brain.swift Sources/PandaPal/Personality.swift Tests/main.swift && ./build/check

APP=build/PandaPal.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -target arm64-apple-macos26.0 -F "$FW" -framework Lottie \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -o "$APP/Contents/MacOS/PandaPal" Sources/PandaPal/*.swift
cp -R "$FW/Lottie.framework" "$APP/Contents/Frameworks/"
cp Art/*.json "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>PandaPal</string>
  <key>CFBundleIdentifier</key><string>dev.luffy2095.pandapal</string>
  <key>CFBundleName</key><string>PandaPal</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.3</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
</dict></plist>
PLIST
codesign --force --deep -s - "$APP"
echo "built $APP"
