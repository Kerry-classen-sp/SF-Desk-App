#!/bin/sh
# Builds the native Mac app (mac/app) for the App Store, sandboxed, and uploads it to App Store Connect for
# TestFlight, with the same version and build number as the other apps (package.json, copied into project.yml).
#   mac/appstore/testflight.sh            archive and upload
#   mac/appstore/testflight.sh --export   archive and export the .pkg to mac/appstore/build/export instead
#   mac/appstore/testflight.sh --run      a Debug build, opened here, to try the sandboxed app
# Needs Xcode, XcodeGen and dist/SF Desk.app of this version and build (scripts/build-apps.sh). Signs in to App
# Store Connect like ios/testflight.sh: the account in Xcode, or ASC_KEY_PATH, ASC_KEY_ID and ASC_ISSUER_ID.
set -eu
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

VERSION=$(node -p "require('../../package.json').version")
BUILD=$(node -p "require('../../package.json').build || 0")
BUILT="../../dist/SF Desk.app/Contents/Resources/app/VERSION.txt"
grep -q "^SF Desk $VERSION build $BUILD " "$BUILT" 2>/dev/null ||
  { echo "dist/SF Desk.app isn't SF Desk $VERSION build $BUILD. Run scripts/build-apps.sh first." >&2; exit 1; }
sed -i '' -e "s/^\(    MARKETING_VERSION: \).*/\1\"$VERSION\"/" -e "s/^\(    CURRENT_PROJECT_VERSION: \).*/\1\"$BUILD\"/" project.yml

AUTH=""
if [ -n "${ASC_KEY_PATH:-}" ]; then
  AUTH="-authenticationKeyPath $ASC_KEY_PATH -authenticationKeyID ${ASC_KEY_ID:?Set ASC_KEY_ID} -authenticationKeyIssuerID ${ASC_ISSUER_ID:?Set ASC_ISSUER_ID}"
fi
xcodegen -q

if [ "${1:-}" = "--run" ]; then
  # shellcheck disable=SC2086
  xcodebuild -project SFDeskMac.xcodeproj -scheme SFDeskMac -configuration Debug -derivedDataPath build/dd \
    -allowProvisioningUpdates $AUTH -quiet build
  osascript -e 'quit app "SF Desk"' 2>/dev/null || true
  open "build/dd/Build/Products/Debug/SF Desk.app"
  exit 0
fi

ARCHIVE="build/SFDeskMac-$VERSION-$BUILD.xcarchive"
echo "Archiving SF Desk for Mac $VERSION build $BUILD (Release)..."
rm -rf "$ARCHIVE"
# shellcheck disable=SC2086
xcodebuild -project SFDeskMac.xcodeproj -scheme SFDeskMac -configuration Release -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" -allowProvisioningUpdates $AUTH -quiet archive

OPTIONS=ExportOptions.plist
if [ "${1:-}" = "--export" ]; then
  OPTIONS=build/ExportOptions-local.plist
  sed 's|<string>upload</string>|<string>export</string>|' ExportOptions.plist > "$OPTIONS"
  echo "Exporting the .pkg to mac/appstore/build/export..."
else
  echo "Uploading to App Store Connect..."
fi
# shellcheck disable=SC2086
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OPTIONS" -exportPath build/export \
  -allowProvisioningUpdates $AUTH
if [ "${1:-}" = "--export" ]; then
  echo "Exported SF Desk for Mac $VERSION build $BUILD to mac/appstore/build/export."
else
  echo "Uploaded SF Desk for Mac $VERSION build $BUILD. It shows in App Store Connect > TestFlight > macOS once processed."
fi
