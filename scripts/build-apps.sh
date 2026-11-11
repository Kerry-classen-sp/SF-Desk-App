#!/bin/bash
# Makes a new build of every client SF Desk hands out, start to finish:
#   1. pulls (git pull --tags), then commits anything uncommitted, so nothing is left out;
#   2. raises the build number in package.json ("build"), keeping the version, sets the iPhone app's version
#      and build number to match (ios/project.yml), and commits that;
#   3. pushes, opens a pull request into main and merges it;
#   4. tags main v<version>-build.<build> and pushes the tag;
#   5. builds from main, so each build names that tag:
#        dist/SF-Desk-mac.zip            the Mac Terminal installer (also what the Mac app is made from)
#        dist/SF-Desk-windows.zip        Windows, on Intel/AMD and ARM PCs
#        dist/SF Desk.app, dist/SF-Desk-app.zip and dist/SF-Desk.dmg   the Mac app
# A new version (package.json "version") is a separate, deliberate change; this only counts builds.
#
#   scripts/build-apps.sh [--npm] [node-version]    e.g. v26.12.0 (default: latest release, not pre-releases)
#
# Run it on a Mac with the Xcode Command Line Tools and the GitHub CLI (gh) signed in. The npm registry is
# blocked on the SailPoint network, so by default the packages take this checkout's node_modules, after
# checking every package in it matches package-lock.json. --npm installs them with npm ci instead.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
USE_NPM=""
die() { printf '%s\n' "$*" >&2; exit 1; }

if [ "${1:-}" = "--npm" ]; then USE_NPM=1; shift; fi
NODE_ARG="${1:-}"
[ "$(uname -s)" = "Darwin" ] || die "Build the apps on a Mac (the Mac app needs swiftc)."
command -v gh >/dev/null && gh auth status >/dev/null 2>&1 || die "Install the GitHub CLI and sign in (gh auth login): the build merges into main."
cd "$ROOT"

BRANCH="$(git branch --show-current)"
[ -n "$BRANCH" ] || die "Check out a branch first (you're on a detached commit)."

# Dependencies are checked before anything is committed or pushed.
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
NODE_VERSION="${NODE_ARG:-$(curl -fsS https://nodejs.org/dist/index.json | node -p 'JSON.parse(require("fs").readFileSync(0)).find((r) => !r.version.includes("-")).version')}"

# 1. Latest commits and tags, then everything uncommitted.
git fetch --tags origin || die "Couldn't fetch from GitHub (above)."
if git rev-parse -q --verify '@{upstream}' >/dev/null; then
  git pull --ff-only --tags || die "git pull failed (above). Fix that, then run this again."
fi
VERSION="$(node -p "require('./package.json').version")"
BUILD=$(( $(node -p "require('./package.json').build || 0") + 1 ))
NAME="SF Desk $VERSION build $BUILD"
TAG="v$VERSION-build.$BUILD"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && die "Tag $TAG already exists. Pull main (git pull --tags) and run this again."

# Builds reach main through a pull request, so a build started on main gets its own branch.
if [ "$BRANCH" = "main" ]; then
  BRANCH="build/$VERSION-$BUILD"
  git switch -c "$BRANCH"
fi

if [ -n "$(git status --porcelain --untracked-files=all)" ]; then
  echo "Committing these uncommitted changes, so they're in $NAME:"
  git status --short --untracked-files=all | sed 's/^/  /'
  git add -A
  git commit -q -m "Changes for $NAME"
fi

# 2. The build number.
node -e '
  const fs = require("fs");
  const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
  const out = {};
  for (const [k, v] of Object.entries(pkg)) { if (k !== "build") out[k] = v; if (k === "version") out.build = Number(process.argv[1]); }
  fs.writeFileSync("package.json", JSON.stringify(out, null, 2) + "\n");
' "$BUILD"
# The iPhone app (ios/project.yml) carries the same version and build number.
sed -i '' -e "s/^\(    MARKETING_VERSION: \).*/\1\"$VERSION\"/" -e "s/^\(    CURRENT_PROJECT_VERSION: \).*/\1\"$BUILD\"/" ios/project.yml
git commit -q -m "$NAME" package.json ios/project.yml

# 3. Into main.
git push -u origin "$BRANCH"
PR="$(gh pr list --head "$BRANCH" --base main --state open --json number -q '.[0].number')"
if [ -z "$PR" ]; then
  gh pr create --base main --head "$BRANCH" --title "$NAME" \
    --body "Made by scripts/build-apps.sh: everything on \`$BRANCH\` as $NAME (tag \`$TAG\`)."
  PR="$(gh pr list --head "$BRANCH" --base main --state open --json number -q '.[0].number')"
else
  [ "$(gh pr view "$PR" --json isDraft -q .isDraft)" = "false" ] || gh pr ready "$PR"
fi
[ -n "$PR" ] || die "Couldn't find the pull request for $BRANCH."
# GitHub needs a moment to work out whether a new pull request can merge.
for try in 1 2 3 4 5 6; do
  gh pr merge "$PR" --merge && break
  [ "$try" = 6 ] && die "Couldn't merge pull request #$PR (above). Merge it on GitHub, then run this again."
  sleep 10
done
git switch main
git pull --ff-only --tags

# 4. The build's tag, on the merge.
git tag -a "$TAG" -m "$NAME" HEAD
git push origin "$TAG"

# 5. The builds, from main.
echo "Building $NAME ($(git describe --always --dirty)) with Node.js $NODE_VERSION..."
# The Windows download builds alongside the Mac ones (they share no files); the Mac app is made from the
# Mac installer zip, so those two go in turn. The Windows output is shown once it's done.
WIN_LOG="$(mktemp)"
scripts/build-windows-package.sh "$NODE_VERSION" > "$WIN_LOG" 2>&1 &
WIN_PID=$!
scripts/build-mac-package.sh "$NODE_VERSION"
scripts/build-mac-app.sh --from dist/SF-Desk-mac.zip
WIN_OK=0; wait "$WIN_PID" || WIN_OK=$?
cat "$WIN_LOG"; rm -f "$WIN_LOG"
[ "$WIN_OK" = 0 ] || die "The Windows download didn't build (above)."
rm -f dist/SF-Desk-windows-arm64.zip dist/VERSION-windows-*.txt # from before one download served both

echo
echo "Built $NAME ($TAG, merged in pull request #$PR) in $ROOT/dist:"
for f in "SF-Desk.dmg" "SF-Desk-app.zip" "SF-Desk-mac.zip" "SF-Desk-windows.zip"; do
  printf '  %-26s %s\n' "$f" "$(du -h "dist/$f" | cut -f1 | tr -d ' ')"
done
