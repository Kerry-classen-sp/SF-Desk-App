#!/bin/sh
# Builds the iPhone app's host as a Mac app, to test it without Xcode or an iPhone:
#   ios/build-mac-test.sh            builds ios/build/SF Desk iPhone Test.app
#   ios/build-mac-test.sh --run      and opens it, signing in with the Salesforce login page
#   ios/build-mac-test.sh --selftest builds it and runs its self-test with the Salesforce CLI's token
#                                    (screenshots and results.json in ios/build/selftest)
set -eu
cd "$(dirname "$0")/.."
ROOT=$(pwd)
./ios/build-core.sh

APP="$ROOT/ios/build/SF Desk iPhone Test.app"
VERSION=$(sed -n 's/.*"version": "\(.*\)".*/\1/p' package.json | head -1)
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -R ios/SFDesk/Generated/web ios/SFDesk/Generated/core-bundle.js "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.sailpoint.sfdesk.iphonetest</string>
  <key>CFBundleName</key><string>SF Desk iPhone Test</string>
  <key>CFBundleExecutable</key><string>SFDeskTest</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>0</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>SFDeskLoginURL</key><string>https://sailpoint.my.salesforce.com</string>
  <key>NSCalendarsFullAccessUsageDescription</key><string>SF Desk shows your meetings in Time Entry so you can log them as Deal Supports.</string>
  <key>NSCalendarsUsageDescription</key><string>SF Desk shows your meetings in Time Entry so you can log them as Deal Supports.</string>
</dict></plist>
EOF

swiftc -O -D DEBUG -target "$(uname -m)-apple-macos13.0" -parse-as-library \
  -o "$APP/Contents/MacOS/SFDeskTest" ios/SFDesk/Host/*.swift ios/SFDesk/App/*.swift
codesign --force --sign - "$APP" >/dev/null
echo "Built $APP"

case "${1:-}" in
  --run) open "$APP" ;;
  --selftest)
    OUT="$ROOT/ios/build/selftest"
    rm -rf "$OUT" "$ROOT/ios/build/selftest-data"
    TOKEN=$(sf org auth show-access-token --json 2>/dev/null | sed -n 's/.*"accessToken": "\(.*\)".*/\1/p' | head -1) || true
    [ -n "$TOKEN" ] || TOKEN=$(sf org display --json | sed -n 's/.*"accessToken": "\(.*\)".*/\1/p' | head -1)
    INSTANCE=$(sf org display --json | sed -n 's/.*"instanceUrl": "\(.*\)".*/\1/p' | head -1)
    SFDESK_TEST_INSTANCE="${INSTANCE%/}" SFDESK_TEST_TOKEN="$TOKEN" SFDESK_SELFTEST="$OUT" SFDESK_DATA="$ROOT/ios/build/selftest-data" \
      "$APP/Contents/MacOS/SFDeskTest"
    cat "$OUT/results.json"
    ;;
esac
