#!/bin/bash
# Xcode build step for the App Store build: copies the server, its node_modules, Node.js and the icon from
# dist/SF Desk.app into the app being built, and signs their binaries with the build's identity (Node.js in
# the app's sandbox). Xcode signs the app itself afterwards.
set -eu
SRC="$SRCROOT/../../dist/SF Desk.app/Contents/Resources"
DEST="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
[ -x "$SRC/node/bin/node" ] && [ -d "$SRC/app/node_modules" ] ||
  { echo "error: No $SRC. Build it first: scripts/build-mac-app.sh --from dist/SF-Desk-mac.zip" >&2; exit 1; }

mkdir -p "$DEST"
rm -rf "$DEST/app" "$DEST/node"
ditto "$SRC/app" "$DEST/app"
# The Mac and Windows installers' sources aren't used by the server, and App Store Connect rejects the app's
# source Info.plist there as a broken nested app.
rm -rf "$DEST/app/mac" "$DEST/app/windows"
ditto "$SRC/node" "$DEST/node"
cp "$SRC/AppIcon.icns" "$DEST/AppIcon.icns"
xattr -cr "$DEST"

IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
[ -n "$IDENTITY" ] || IDENTITY=-
find "$DEST/app" "$DEST/node" -type f -print0 | while IFS= read -r -d '' f; do
  case "$(file -b "$f")" in
    *Mach-O*executable*) codesign -f -s "$IDENTITY" --entitlements "$SRCROOT/Helper.entitlements" "$f" ;;
    *Mach-O*) codesign -f -s "$IDENTITY" "$f" ;;
  esac
done
