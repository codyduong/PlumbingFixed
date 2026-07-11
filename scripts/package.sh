#!/bin/bash
# CI-ONLY twin of scripts/package.ps1, kept for the Linux release job
# (.github/workflows/release.yml) — the only .sh script in this repo; local dev uses the
# .ps1 scripts. Keep the version validation and the build/copy steps IDENTICAL to
# package.ps1 — any drift ships a broken layout. See docs/RELEASING.md.

set -e

# Anchor to repo root so the relative paths below work regardless of caller cwd
# (matches package.ps1's Set-Location behavior).
cd "$(dirname "$0")/.."

MOD_NAME="PlumbingFixed"
INPUT_TAG="$1"

# 1. Validation Step
if [ -z "$INPUT_TAG" ]; then
  echo "Error: No tag name provided. Usage: ./package.sh <tag_name>"
  exit 1
fi

# Strip leading 'v' if present (e.g., v1.0.0 -> 1.0.0) to match Zomboid format
EXPECTED_VERSION="${INPUT_TAG#v}"

echo "Validating mod versions against: $EXPECTED_VERSION"

# Find all mod.info files inside the specific path structure
# Structure: ./Contents/mods/PlumbingFixed/*/mod.info
FOUND_FILES=$(find "./Contents/mods/$MOD_NAME" -name "mod.info")

if [ -z "$FOUND_FILES" ]; then
  echo "Error: No mod.info files found to validate."
  exit 1
fi

for file in $FOUND_FILES; do
    # FIX: Look for 'modversion=' instead of 'version='
    # 1. grep: finds the line starting with modversion=
    # 2. cut: splits by = and takes the second part
    # 3. tr: deletes carriage returns (Windows compat)
    # 4. xargs: trims leading/trailing whitespace
    FILE_VERSION=$(grep "^modversion=" "$file" | cut -d'=' -f2 | tr -d '\r' | xargs)
    
    # Check if we actually found a version string
    if [ -z "$FILE_VERSION" ]; then
        echo "❌ Could not find 'modversion=' line in: $file"
        echo "   (Make sure the file contains 'modversion=X.X.X')"
        exit 1
    fi

    if [ "$FILE_VERSION" != "$EXPECTED_VERSION" ]; then
        echo "❌ Version Mismatch in file: $file"
        echo "   Expected: $EXPECTED_VERSION"
        echo "   Found:    $FILE_VERSION"
        exit 1
    else 
        echo "✅ Match: $file ($FILE_VERSION)"
    fi
done

echo "All mod.info versions match. Proceeding to package..."

STAGE="dist/$MOD_NAME"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -r ./Contents "$STAGE/Contents"
cp ./preview.png "$STAGE/preview.png"
# build 41 compat
cp -r "./Contents/mods/$MOD_NAME/41/"* "$STAGE/Contents/mods/$MOD_NAME/"
cp -r "./Contents/mods/$MOD_NAME/42/media" "$STAGE/Contents/mods/$MOD_NAME/"
rm -r "$STAGE/Contents/mods/$MOD_NAME/41"
rm "$STAGE/Contents/mods/$MOD_NAME/common/.gitkeep"

echo "Packaging complete for $MOD_NAME -> $STAGE"