#!/usr/bin/env bash
# Publish the packaged mod to the Steam Workshop via steamcmd (updates the existing item).
# Updates CONTENT + preview + changenote only (not the Steam page text). Run it yourself —
# steamcmd prompts for Steam Guard. See docs/RELEASING.md.
# Config via env (see mise.local.toml): STEAM_USER, PF_APPID, PF_PUBLISHED_FILE_ID.
# Usage: mise run publish "changenote"   (or: bash scripts/publish-workshop.sh "changenote")
set -euo pipefail
cd "$(dirname "$0")/.."

MOD_NAME="PlumbingFixed"
CHANGENOTE="${1:-}"
STEAM_USER="${STEAM_USER:-}"
APPID="${PF_APPID:-108600}"
PUBLISHED_FILE_ID="${PF_PUBLISHED_FILE_ID:-3626008449}"

command -v steamcmd >/dev/null 2>&1 || {
  echo "ERROR: steamcmd not found on PATH (https://developer.valvesoftware.com/wiki/SteamCMD)." >&2
  echo "       See docs/RELEASING.md." >&2; exit 127; }
[ -n "$STEAM_USER" ] || read -r -p "Steam username: " STEAM_USER

ver="$(grep '^modversion=' "Contents/mods/$MOD_NAME/42/mod.info" | head -1 | cut -d= -f2 | tr -d '\r' | xargs)"
bash scripts/package.sh "v$ver"

content="$(cd "./$MOD_NAME" && pwd)"
preview="$(pwd)/preview.png"
[ -n "$CHANGENOTE" ] || CHANGENOTE="v$ver"

mkdir -p .publish
vdf="$(pwd)/.publish/workshop.vdf"
cat > "$vdf" <<EOF
"workshopitem"
{
	"appid" "$APPID"
	"publishedfileid" "$PUBLISHED_FILE_ID"
	"contentfolder" "$content"
	"previewfile" "$preview"
	"changenote" "${CHANGENOTE//\"/\'}"
}
EOF

echo "Wrote VDF -> $vdf"
echo "Item: $PUBLISHED_FILE_ID (app $APPID)  changenote: $CHANGENOTE"
echo "Uploading via steamcmd (Steam Guard prompt expected)..."
steamcmd +login "$STEAM_USER" +workshop_build_item "$vdf" +quit
echo "Published item $PUBLISHED_FILE_ID."
