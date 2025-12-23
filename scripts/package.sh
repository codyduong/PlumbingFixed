#!/bin/bash

set -e

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
  # Extract version line, remove 'version=', and trim whitespace/newlines (handles Windows CRLF)
  FILE_VERSION=$(grep "^version=" "$file" | cut -d'=' -f2 | tr -d '\r' | xargs)
  
  if [ "$FILE_VERSION" != "$EXPECTED_VERSION" ]; then
    echo "❌ Version Mismatch in file: $file"
    echo "   Expected: $EXPECTED_VERSION"
    echo "   Found:  $FILE_VERSION"
    exit 1
  else 
    echo "✅ Match: $file ($FILE_VERSION)"
  fi
done

echo "All mod.info versions match. Proceeding to package..."

rm -rf "./$MOD_NAME"
mkdir -p "./$MOD_NAME"
cp -r ./Contents "./$MOD_NAME/Contents"
cp ./preview.png "./$MOD_NAME/preview.png"
cp ./workshop.txt "./$MOD_NAME/workshop.txt"
# build 41 compat
cp -r "./Contents/mods/$MOD_NAME/41/"* "./$MOD_NAME/Contents/mods/$MOD_NAME/"
rm -r "./$MOD_NAME/Contents/mods/$MOD_NAME/41"
rm "./$MOD_NAME/Contents/mods/$MOD_NAME/common/.gitkeep"

echo "Packaging complete for $MOD_NAME"