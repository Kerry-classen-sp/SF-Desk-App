#!/bin/bash
# Builds every client SF Desk hands out, from this checkout's current commit, with one Node.js version:
#   dist/SF-Desk-mac.zip            the Mac Terminal installer (also what the Mac app is made from)
#   dist/SF-Desk-windows.zip        Windows on Intel/AMD
#   dist/SF-Desk-windows-arm64.zip  Windows on ARM
#   dist/SF Desk.app, dist/SF-Desk-app.zip and dist/SF-Desk.dmg   the Mac app
# Run it on a Mac with the Xcode Command Line Tools, after committing: uncommitted edits and new files
# aren't built, and it lists any it finds before and after building.
# It pulls first (git pull --tags), so the build is of the latest commit and named after its version tag.
#
#   scripts/build-apps.sh [--npm] [node-version]    e.g. v26.12.0 (default: latest release)
#
# The npm registry is blocked on the SailPoint network, so by default the packages take this checkout's
# node_modules, after checking every package in it matches package-lock.json. --npm installs them from
# the registry with npm ci instead.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
USE_NPM=""
die() { printf '%s\n' "$*" >&2; exit 1; }

if [ "${1:-}" = "--npm" ]; then USE_NPM=1; shift; fi
[ "$(uname -s)" = "Darwin" ] || die "Build the apps on a Mac (the Mac app needs swiftc)."
cd "$ROOT"

# Bring in the latest commits and the tags GitHub made (.github/workflows/tag-version.yml), which the build
# info is named from. A branch that isn't on GitHub yet only gets the tags.
if git rev-parse -q --verify '@{upstream}' >/dev/null; then
  git pull --ff-only --tags || die "git pull failed (above). Fix that, then run this again."
else
  git fetch --tags origin || die "Couldn't fetch tags from GitHub (above). Fix that, then run this again."
fi

# The builds are made from the last commit (git archive HEAD), so edits and new files that aren't committed
# are left out. Say so before building, and again at the end where it won't scroll away.
LEFT_OUT="$(git status --porcelain --untracked-files=all)"
warn_left_out() {
  [ -n "$LEFT_OUT" ] || return 0
  {
    echo
    echo "WARNING: these changes aren't committed, so they are NOT in the build:"
    printf '%s\n' "$LEFT_OUT" | sed 's/^/  /'
    echo "Commit them and run this again to include them."
    echo
  } >&2
}
warn_left_out

VERSION="$(node -p "require('./package.json').version")"
git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null ||
  echo "Note: version $VERSION has no v$VERSION tag yet, so the build info will name an older tag." >&2

if [ -z "$USE_NPM" ]; then
  [ -d node_modules ] || die "No node_modules in $ROOT. Get them (INSTALL.md step 4), or use --npm where the registry is reachable."
  node -e '
    const fs = require("fs");
    const lock = require("./package-lock.json");
    const bad = [];
    for (const [where, pkg] of Object.entries(lock.packages)) {
      if (!where || pkg.dev) continue;
      let got = null;
      try { got = JSON.parse(fs.readFileSync(where + "/package.json", "utf8")).version; } catch {}
      if (got !== pkg.version && !(got === null && pkg.optional)) bad.push(`${where.replace(/^node_modules\//, "")} ${got ?? "missing"} (lockfile: ${pkg.version})`);
    }
    if (bad.length) {
      console.error("node_modules doesn\x27t match package-lock.json:\n  " + bad.join("\n  "));
      console.error("Refresh it (INSTALL.md step 4), or use --npm where the registry is reachable.");
      process.exit(1);
    }
  '
  export SF_DESK_NODE_MODULES="$ROOT/node_modules"
fi

NODE_VERSION="${1:-$(curl -fsS https://nodejs.org/dist/index.json | node -p 'JSON.parse(require("fs").readFileSync(0))[0].version')}"
echo "Building SF Desk $VERSION ($(git describe --always --dirty)) with Node.js $NODE_VERSION..."

scripts/build-mac-package.sh "$NODE_VERSION"
scripts/build-windows-package.sh --arch x64 "$NODE_VERSION"
scripts/build-windows-package.sh --arch arm64 "$NODE_VERSION"
scripts/build-mac-app.sh --from dist/SF-Desk-mac.zip

echo
echo "Built SF Desk $VERSION in $ROOT/dist:"
for f in "SF-Desk.dmg" "SF-Desk-app.zip" "SF-Desk-mac.zip" "SF-Desk-windows.zip" "SF-Desk-windows-arm64.zip"; do
  printf '  %-26s %s\n' "$f" "$(du -h "dist/$f" | cut -f1 | tr -d ' ')"
done
warn_left_out
