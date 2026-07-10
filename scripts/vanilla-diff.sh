#!/usr/bin/env bash
# Show how the installed vanilla has drifted from our committed baseline, for exactly the
# functions we override. Run this first when moving to a new PZ build. See docs/UPDATING-PZ.md.
#
# Usage: mise run vanilla-diff   (or: bash scripts/vanilla-diff.sh)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < vendor/pz/VERSION)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

bash scripts/vanilla-extract.sh --out "$tmp" >/dev/null

echo "Drift: committed vendor/pz/$VERSION  ->  installed vanilla"
git --no-pager diff --no-index --ignore-cr-at-eol "vendor/pz/$VERSION" "$tmp" || true
