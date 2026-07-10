#!/usr/bin/env bash
# Decompile the installed Project Zomboid into ./.decompiled for client/server analysis.
# Uses Zomboid Decompiler (demiurgeQuantified). See CLAUDE.md ("golden rule").
# Preferred: `mise run decompile`   Direct: `bash scripts/decompile.sh`
# Override the install dir with PZ_HOME.
set -euo pipefail
cd "$(dirname "$0")/.."

GAME_PATH="${PZ_HOME:-}"
DECOMPILER_VERSION="${DECOMPILER_VERSION:-v0.3.1}"
OUT_DIR=".decompiled"
TOOLS_DIR=".tools"

if [ -z "$GAME_PATH" ]; then
  for c in \
    "$HOME/.steam/steam/steamapps/common/ProjectZomboid" \
    "$HOME/.local/share/Steam/steamapps/common/ProjectZomboid" \
    "/mnt/f/steamlibrary/steamapps/common/ProjectZomboid"; do
    [ -f "$c/projectzomboid.jar" ] && GAME_PATH="$c" && break
  done
fi
[ -n "$GAME_PATH" ] && [ -f "$GAME_PATH/projectzomboid.jar" ] || {
  echo "ERROR: ProjectZomboid install not found; pass PZ_HOME=<dir>." >&2; exit 1; }
echo "Game: $GAME_PATH"

tool="$TOOLS_DIR/ZomboidDecompiler"
if [ ! -f "$tool/bin/ZomboidDecompiler" ]; then
  echo "Downloading Zomboid Decompiler $DECOMPILER_VERSION..."
  mkdir -p "$TOOLS_DIR"
  url="https://github.com/demiurgeQuantified/ZomboidDecompiler/releases/download/$DECOMPILER_VERSION/ZomboidDecompiler.zip"
  curl -fsSL "$url" -o "$TOOLS_DIR/ZomboidDecompiler.zip"
  rm -rf "$tool"; mkdir -p "$tool"
  unzip -q -o "$TOOLS_DIR/ZomboidDecompiler.zip" -d "$tool"
  rm -f "$TOOLS_DIR/ZomboidDecompiler.zip"
  if [ ! -f "$tool/bin/ZomboidDecompiler" ]; then
    nested="$(find "$tool" -maxdepth 3 -type f -path '*/bin/ZomboidDecompiler' | head -1 || true)"
    [ -n "$nested" ] && cp -r "$(dirname "$(dirname "$nested")")/." "$tool/"
  fi
fi
[ -f "$tool/bin/ZomboidDecompiler" ] || {
  echo "ERROR: ZomboidDecompiler launcher missing after extraction ($tool)." >&2; exit 1; }
chmod +x "$tool/bin/ZomboidDecompiler" 2>/dev/null || true

# The decompiler needs Java 17+. `mise run decompile` puts the pinned Temurin 17 on PATH.
# If no java is on PATH (running this script outside mise), fall back to the game's bundled
# JRE (jre64, also Java 17).
command -v java >/dev/null 2>&1 || { [ -d "$GAME_PATH/jre64/bin" ] && export PATH="$GAME_PATH/jre64/bin:$PATH"; }

echo "Decompiling..."
( cd "$tool" && ./bin/ZomboidDecompiler "$GAME_PATH" )

produced="$(find "$tool" -type d -name output | sort | head -1 || true)"
if [ -n "$produced" ]; then
  rm -rf "$OUT_DIR"; mkdir -p "$OUT_DIR"
  cp -r "$produced/." "$OUT_DIR/"
  echo "Decompiled source -> $OUT_DIR/"
else
  echo "Decompiler finished, but no 'output' dir found under $tool; copy results into $OUT_DIR/ manually." >&2
fi
