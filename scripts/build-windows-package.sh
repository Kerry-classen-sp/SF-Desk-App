#!/bin/bash
# Builds dist/SF-Desk-windows.zip, for every 64-bit Windows PC: the app, its node_modules and Node.js for
# both Intel/AMD (runtime/x64) and ARM (runtime/arm64, e.g. Snapdragon) PCs, plus the double-click
# installer (windows/package), which installs the Node.js that suits the PC. Run it anywhere npm and
# nodejs.org are reachable (any OS); the people installing need neither.
#   scripts/build-windows-package.sh [node-version]    e.g. v26.11.1 (default: latest release)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/dist"
ZIP=SF-Desk-windows.zip
ARCHES="x64 arm64"
STAGE="$OUT/SF Desk for Windows"
NODE_VERSION="${1:-$(curl -fsS https://nodejs.org/dist/index.json | node -p 'JSON.parse(require("fs").readFileSync(0)).find((r) => !r.version.includes("-")).version')}"

rm -rf "$STAGE" "$OUT/$ZIP"
mkdir -p "$STAGE/app" "$STAGE/runtime"

# The committed app, as on the current commit (not uncommitted edits, .env or data/).
git -C "$ROOT" archive HEAD | tar -x -C "$STAGE/app"

# Dependencies from the lockfile. better-sqlite3 ships prebuilt binaries for every platform in
# its package, so installing on Linux or macOS still gives a tree that runs on Windows.
# SF_DESK_NODE_MODULES copies an existing node_modules instead (see build-mac-package.sh).
if [ -n "${SF_DESK_NODE_MODULES:-}" ]; then
  cp -R "$SF_DESK_NODE_MODULES" "$STAGE/app/node_modules"
else
  (cd "$STAGE/app" && npm ci --omit=dev --ignore-scripts --no-audit --no-fund)
fi
for ARCH in $ARCHES; do test -f "$STAGE/app/node_modules/better-sqlite3/prebuilds/win32-$ARCH.node"; done

# Node.js for each kind of Windows PC, checked against nodejs.org's published checksums.
TMP="$(mktemp -d)"
curl -fsSL -o "$TMP/SHASUMS256.txt" "https://nodejs.org/dist/$NODE_VERSION/SHASUMS256.txt"
for ARCH in $ARCHES; do
  NODE_NAME="node-$NODE_VERSION-win-$ARCH"
  curl -fsSL -o "$TMP/$NODE_NAME.zip" "https://nodejs.org/dist/$NODE_VERSION/$NODE_NAME.zip"
  (cd "$TMP" && grep " $NODE_NAME.zip\$" SHASUMS256.txt | { command -v sha256sum >/dev/null && sha256sum -c - || shasum -a 256 -c -; })
  mkdir -p "$STAGE/runtime/$ARCH"
  unzip -q -j "$TMP/$NODE_NAME.zip" "$NODE_NAME/node.exe" "$NODE_NAME/LICENSE" -d "$STAGE/runtime/$ARCH"
done
rm -rf "$TMP"

cp "$ROOT/windows/package/Install SF Desk.cmd" "$ROOT/windows/package/READ ME FIRST.txt" "$STAGE/"
# Notepad shows CRLF line endings best.
awk '{ printf "%s\r\n", $0 }' "$ROOT/RELEASE-NOTES.md" > "$STAGE/Release Notes.txt"
printf 'SF Desk %s build %s (%s, %s), Node.js %s for Windows x64 and arm64\n' "$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$STAGE/app/package.json" | head -1)" \
  "$(sed -n 's/.*"build": *\([0-9]*\).*/\1/p' "$STAGE/app/package.json" | head -1 | grep . || echo 0)" \
  "$(git -C "$ROOT" describe --always --dirty)" "$(git -C "$ROOT" log -1 --format=%cs)" "$NODE_VERSION" | tee "$OUT/VERSION-windows.txt" > "$STAGE/app/VERSION.txt"

(cd "$OUT" && zip -qry "$ZIP" "SF Desk for Windows")
rm -rf "$STAGE"
echo "Built $OUT/$ZIP ($(du -h "$OUT/$ZIP" | cut -f1)): $(cat "$OUT/VERSION-windows.txt")"
