#!/bin/sh
# Builds the iPad app for release and uploads it to App Store Connect for TestFlight, with the same
# version and build number as the desktop apps (package.json, copied into project.yml first).
#   ios/testflight.sh            archive and upload
#   ios/testflight.sh --export   archive and export the .ipa to ios/build/export instead, without uploading
# Needs Xcode and XcodeGen, membership of the Apple Developer team in project.yml, and an app in App Store
# Connect with the bundle id com.sailpoint.sfdesk (see docs/IOS.md). Signs in to App Store Connect with the
# account in Xcode > Settings > Accounts, or with an App Store Connect API key when ASC_KEY_PATH, ASC_KEY_ID
# and ASC_ISSUER_ID are set. Each upload needs a new build number: run scripts/build-apps.sh first.
set -eu
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

VERSION=$(node -p "require('../package.json').version")
BUILD=$(node -p "require('../package.json').build || 0")
sed -i '' -e "s/^\(    MARKETING_VERSION: \).*/\1\"$VERSION\"/" -e "s/^\(    CURRENT_PROJECT_VERSION: \).*/\1\"$BUILD\"/" project.yml

EXPORT_ONLY=""
[ "${1:-}" = "--export" ] && EXPORT_ONLY=1
AUTH=""
if [ -n "${ASC_KEY_PATH:-}" ]; then
  AUTH="-authenticationKeyPath $ASC_KEY_PATH -authenticationKeyID ${ASC_KEY_ID:?Set ASC_KEY_ID} -authenticationKeyIssuerID ${ASC_ISSUER_ID:?Set ASC_ISSUER_ID}"
fi

ARCHIVE="build/SFDesk-$VERSION-$BUILD.xcarchive"
xcodegen -q
echo "Archiving SF Desk $VERSION build $BUILD (Release)..."
rm -rf "$ARCHIVE"
# shellcheck disable=SC2086
xcodebuild -project SFDesk.xcodeproj -scheme SFDesk -configuration Release -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" -allowProvisioningUpdates $AUTH -quiet archive

OPTIONS=ExportOptions.plist
if [ -n "$EXPORT_ONLY" ]; then
  OPTIONS=build/ExportOptions-local.plist
  sed 's|<string>upload</string>|<string>export</string>|' ExportOptions.plist > "$OPTIONS"
  echo "Exporting the .ipa to ios/build/export..."
else
  echo "Uploading to App Store Connect..."
fi
# shellcheck disable=SC2086
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$OPTIONS" -exportPath build/export \
  -allowProvisioningUpdates $AUTH
if [ -n "$EXPORT_ONLY" ]; then
  echo "Exported SF Desk $VERSION build $BUILD to ios/build/export."
else
  echo "Uploaded SF Desk $VERSION build $BUILD. It shows in App Store Connect > TestFlight once processed (about 10-30 minutes)."
fi
