#!/bin/sh
# Builds the iPhone/iPad app and installs it on a connected device, with the same version and build number
# as the desktop apps (package.json "version" and "build", copied into project.yml first).
#   ios/build-device.sh [device-id]    default: the first connected iPhone or iPad
# Needs Xcode (not only the Command Line Tools) and XcodeGen.
set -eu
cd "$(dirname "$0")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

VERSION=$(node -p "require('../package.json').version")
BUILD=$(node -p "require('../package.json').build || 0")
sed -i '' -e "s/^\(    MARKETING_VERSION: \).*/\1\"$VERSION\"/" -e "s/^\(    CURRENT_PROJECT_VERSION: \).*/\1\"$BUILD\"/" project.yml

DEVICE="${1:-$(xcrun devicectl list devices 2>/dev/null | awk '/available \(paired\)/ && /physical/ { for (i = 1; i <= NF; i++) if ($i == "(UDID)") { print $(i - 1); exit } }')}"
[ -n "$DEVICE" ] || { echo "No iPhone or iPad connected and paired. Connect one (and unlock it), or pass its id." >&2; exit 1; }

xcodegen -q
echo "Building SF Desk $VERSION build $BUILD for $DEVICE..."
xcodebuild -project SFDesk.xcodeproj -scheme SFDesk -destination "id=$DEVICE" -derivedDataPath build/dd \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration -quiet build
xcrun devicectl device install app --device "$DEVICE" "build/dd/Build/Products/Debug-iphoneos/SF Desk.app"
xcrun devicectl device process launch --terminate-existing --device "$DEVICE" com.sailpoint.sfdesk
