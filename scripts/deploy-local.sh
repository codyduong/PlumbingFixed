#!/usr/bin/env bash
# Package the mod, then sync it into the local Zomboid Workshop dir for in-game testing.
# Preferred: `mise run deploy`   Direct: `bash scripts/deploy-local.sh`
# Override the game data dir with ZOMBOID_DIR (defaults to ~/Zomboid).
set -euo pipefail
cd "$(dirname "$0")/.."

MOD_NAME="PlumbingFixed"
ZOMBOID_DIR="${ZOMBOID_DIR:-$HOME/Zomboid}"

ver="$(grep '^modversion=' "Contents/mods/$MOD_NAME/42/mod.info" | head -1 | cut -d= -f2 | tr -d '\r' | xargs)"
echo "Deploying $MOD_NAME v$ver"

bash scripts/package.sh "v$ver"

target="$ZOMBOID_DIR/Workshop/$MOD_NAME"
[ -d "$ZOMBOID_DIR" ] || { echo "ERROR: Zomboid dir not found: $ZOMBOID_DIR (set ZOMBOID_DIR)." >&2; exit 1; }
rm -rf "$target"
mkdir -p "$(dirname "$target")"
cp -r "./$MOD_NAME" "$target"

echo "Synced -> $target"
echo "In-game: enable the mod under Workshop (dev) mods, then load the DebugPlumbing scenario."
