#!/usr/bin/env bash
# Set the mod's semver (modversion) in every mod.info so the copies never drift.
# This is the mod's OWN version (== the release git tag), NOT the targeted PZ build
# (the "B42.x" marker in 42/mod.info name= and workshop.txt) — see docs/UPDATING-PZ.md.
# Usage: mise run bump 1.3.14   (or: bash scripts/bump-version.sh 1.3.14)
set -euo pipefail
cd "$(dirname "$0")/.."

version="${1:-}"
[ -n "$version" ] || { echo "ERROR: usage: bump-version.sh <version>" >&2; exit 1; }
ver="${version#v}"; ver="${ver#V}"
if ! [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR: version must be X.Y.Z (got '$version')." >&2; exit 1
fi

for info in Contents/mods/PlumbingFixed/41/mod.info Contents/mods/PlumbingFixed/42/mod.info; do
  [ -f "$info" ] || { echo "ERROR: missing $info" >&2; exit 1; }
  grep -q '^modversion=' "$info" || { echo "ERROR: no 'modversion=' in $info" >&2; exit 1; }
  tmp="$(mktemp)"
  sed "s/^modversion=.*/modversion=$ver/" "$info" > "$tmp" && mv "$tmp" "$info"
  echo "  set modversion=$ver in $info"
done
echo "Version set to $ver. Next: commit, tag v$ver, then 'mise run package v$ver'."
