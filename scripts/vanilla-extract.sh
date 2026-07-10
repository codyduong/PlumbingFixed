#!/usr/bin/env bash
# Extract the vanilla source of the functions we override (vendor/pz/overrides.manifest) from
# the installed Project Zomboid into the baseline tree, so there is an ancestor to 3-way merge
# our overrides against on the next PZ update. See docs/UPDATING-PZ.md.
# Override the install dir with PZ_HOME.
#
# Usage: mise run vanilla-extract          (writes vendor/pz/<VERSION>/)
#    or: bash scripts/vanilla-extract.sh [--out DIR]
set -euo pipefail
cd "$(dirname "$0")/.."

OUT_ROOT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT_ROOT="${2:-}"; shift ;;
    *) echo "ERROR: unknown arg '$1'." >&2; exit 2 ;;
  esac
  shift
done

GAME_PATH="${PZ_HOME:-}"
if [ -z "$GAME_PATH" ]; then
  for c in \
    "/f/steamlibrary/steamapps/common/ProjectZomboid" \
    "/mnt/f/steamlibrary/steamapps/common/ProjectZomboid" \
    "$HOME/.steam/steam/steamapps/common/ProjectZomboid" \
    "$HOME/.local/share/Steam/steamapps/common/ProjectZomboid"; do
    [ -f "$c/projectzomboid.jar" ] && GAME_PATH="$c" && break
  done
fi
LUA_ROOT="$GAME_PATH/media/lua"
[ -n "$GAME_PATH" ] && [ -d "$LUA_ROOT" ] || {
  echo "ERROR: PZ media/lua not found; set PZ_HOME=<install dir>." >&2; exit 1; }

VERSION="$(tr -d '[:space:]' < vendor/pz/VERSION)"
[ -n "$OUT_ROOT" ] || OUT_ROOT="vendor/pz/$VERSION"
MANIFEST="vendor/pz/overrides.manifest"

# Print one top-level function body: from `function T.name(` / `function T:name(` to the
# terminating column-0 `end`. Heuristic (no Lua parser): PZ declares these top-level, with the
# closing `end` at column 0 and inner ends indented. Returns non-zero if the name isn't found.
extract_fn() {
  local file="$1" name="$2" infn=0 found=0 line
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    if [ "$infn" -eq 0 ]; then
      case "$line" in
        "function "*".$name("* | "function "*":$name("* ) infn=1; printf '%s\n' "$line" ;;
      esac
    else
      printf '%s\n' "$line"
      if [ "$line" = "end" ]; then infn=0; found=1; printf '\n'; fi
    fi
  done < "$file"
  [ "$found" -eq 1 ]
}

rc=0
while IFS=$'\t' read -r relpath fns || [ -n "$relpath" ]; do
  relpath="${relpath%$'\r'}"; fns="${fns%$'\r'}"
  [ -n "$relpath" ] || continue
  case "$relpath" in \#*) continue ;; esac
  src="$LUA_ROOT/$relpath"
  [ -f "$src" ] || { echo "ERROR: vanilla file missing: $src" >&2; rc=1; continue; }
  out="$OUT_ROOT/$relpath"
  mkdir -p "$(dirname "$out")"
  : > "$out"
  for fn in $fns; do
    if ! extract_fn "$src" "$fn" >> "$out"; then
      echo "WARN: function '$fn' not found in $relpath (refactored away?)" >&2
      printf -- '-- MISSING: %s (not found at extract time)\n\n' "$fn" >> "$out"
      rc=1
    fi
  done
  echo "wrote $out"
done < "$MANIFEST"
exit $rc
