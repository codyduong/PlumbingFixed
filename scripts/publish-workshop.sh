#!/usr/bin/env bash
# Publish the packaged mod to the Steam Workshop via steamcmd (updates the existing item).
#
# Page metadata lives in workshop/workshop.conf (flat key=value) and the description
# verbatim in workshop/description.bbcode. See docs/RELEASING.md.
#
# The publish TARGET (test|prod) is REQUIRED (unless -DryRun) so we're always explicit about
# which Workshop item we touch — there is no default and no env fallback.
#
# Flags (explicit — behavior is never driven by ambient env):
#   --dry-run        build + print the VDF, don't upload (defaults target to test)
#   --content-only   skip title/description/tags/visibility
# Usage: mise run publish test "changenote"   (verify, then: mise run publish prod "changenote")
#    or: bash scripts/publish-workshop.sh <test|prod> "changenote" [--dry-run] [--content-only]
set -euo pipefail
cd "$(dirname "$0")/.."

MOD_NAME="PlumbingFixed"
STEAM_USERNAME="${STEAM_USERNAME:-}"
DRY_RUN=0
CONTENT_ONLY=0
positional=()
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)      DRY_RUN=1 ;;
    --content-only) CONTENT_ONLY=1 ;;
    --)             shift; while [ $# -gt 0 ]; do positional+=("$1"); shift; done; break ;;
    -*)             echo "ERROR: unknown flag '$1'." >&2; exit 2 ;;
    *)              positional+=("$1") ;;
  esac
  shift
done
TARGET="$(printf '%s' "${positional[0]:-}" | tr '[:upper:]' '[:lower:]')"
CHANGENOTE="${positional[1]:-}"

# Escape stdin for a VDF (KeyValues) quoted value: \ -> \\, " -> \", CR dropped, LF -> \n.
vdf_escape() {
  sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\r$//' | awk 'BEGIN{ORS=""} NR>1{printf "\\n"} {printf "%s",$0}'
}

# Read a key from workshop/workshop.conf (flat key=value, single-line, '#' comments).
conf_get() {
  grep -E "^$1=" workshop/workshop.conf | head -1 | sed "s/^$1=//" | sed 's/[[:space:]]*$//'
}

# --- Load the source-of-truth metadata --------------------------------------------------
title="$(conf_get title)"; [ -n "$title" ] || title="$MOD_NAME"
APPID="${PF_APPID:-$(conf_get app_id)}"
preview_rel="$(conf_get preview)"; [ -n "$preview_rel" ] || preview_rel="preview.png"

# Resolve the publish target -> Workshop item id. Required unless --dry-run so we never
# publish to an implicit item. Dry-run defaults to 'test' (safe) and says so.
if [ -z "$TARGET" ]; then
  if [ "$DRY_RUN" = "1" ]; then
    TARGET="test"; echo "No target given; defaulting dry-run to 'test'." >&2
  else
    echo "ERROR: a target (test|prod) is required unless --dry-run." >&2
    echo "       Refusing to publish without an explicit target." >&2; exit 2
  fi
fi
case "$TARGET" in
  prod) PUBLISHED_FILE_ID="${PF_PUBLISHED_FILE_ID:-$(conf_get published_id)}" ;;
  test) PUBLISHED_FILE_ID="${PF_TEST_PUBLISHED_FILE_ID:-$(conf_get test_published_id)}" ;;
  *) echo "ERROR: unknown target '$TARGET' (expected test or prod)." >&2; exit 2 ;;
esac
[ -n "$PUBLISHED_FILE_ID" ] || {
  echo "ERROR: no item id for target '$TARGET' — set workshop/workshop.conf" >&2
  echo "       (published_id / test_published_id) or the matching PF_*_PUBLISHED_FILE_ID env." >&2; exit 2
}
# Description read verbatim (no parsing / no escaping guesswork here).
description="$(cat workshop/description.bbcode)"

# tags: manifest ';'-separated -> VDF form (comma-separated). Best-effort validation against
# the game's media/WorkshopTags.txt when PZ_HOME is set; otherwise pass through.
tags_raw="$(conf_get tags)"
tags_csv=""
IFS=';' read -r -a _tags <<< "$tags_raw"
for tg in "${_tags[@]}"; do
  tg="$(printf '%s' "$tg" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
  [ -n "$tg" ] || continue
  if [ -n "${PZ_HOME:-}" ] && [ -f "$PZ_HOME/media/WorkshopTags.txt" ]; then
    if ! grep -qxF "$tg" "$PZ_HOME/media/WorkshopTags.txt"; then
      echo "WARN: tag '$tg' not in $PZ_HOME/media/WorkshopTags.txt" >&2
    fi
  fi
  tags_csv="${tags_csv:+$tags_csv,}$tg"
done

# visibility word -> steamcmd int.
vis_word="$(conf_get visibility)"; [ -n "$vis_word" ] || vis_word="public"
case "$vis_word" in
  public|Public) visibility=0 ;;
  friendsOnly|friendsonly) visibility=1 ;;
  private|Private) visibility=2 ;;
  unlisted|Unlisted) visibility=3 ;;
  *) echo "ERROR: unknown visibility '$vis_word' (expected public/friendsOnly/private/unlisted)." >&2; exit 1 ;;
esac

if ! command -v steamcmd >/dev/null 2>&1 && [ "$DRY_RUN" != "1" ]; then
  echo "ERROR: steamcmd not found on PATH." >&2
  echo "       Install it: winget install Valve.SteamCMD  (see docs/RELEASING.md)." >&2; exit 127
fi
if [ "$DRY_RUN" != "1" ] && [ -z "$STEAM_USER" ]; then read -r -p "Steam username: " STEAM_USER; fi

ver="$(grep '^modversion=' "Contents/mods/$MOD_NAME/42/mod.info" | head -1 | cut -d= -f2 | tr -d '\r' | xargs)"
bash scripts/package.sh "v$ver"

content="$(cd "./$MOD_NAME" && pwd)"
preview="$(pwd)/$preview_rel"
[ -n "$CHANGENOTE" ] || CHANGENOTE="v$ver"

cn_esc="$(printf '%s' "$CHANGENOTE" | vdf_escape)"
title_esc="$(printf '%s' "$title" | vdf_escape)"
desc_esc="$(printf '%s' "$description" | vdf_escape)"
tags_esc="$(printf '%s' "$tags_csv" | vdf_escape)"

mkdir -p .publish
vdf="$(pwd)/.publish/workshop.vdf"
{
  printf '"workshopitem"\n{\n'
  printf '\t"appid" "%s"\n' "$APPID"
  printf '\t"publishedfileid" "%s"\n' "$PUBLISHED_FILE_ID"
  printf '\t"contentfolder" "%s"\n' "$content"
  printf '\t"previewfile" "%s"\n' "$preview"
  printf '\t"changenote" "%s"\n' "$cn_esc"
  if [ "$CONTENT_ONLY" != "1" ]; then
    printf '\t"title" "%s"\n' "$title_esc"
    printf '\t"description" "%s"\n' "$desc_esc"
    printf '\t"tags" "%s"\n' "$tags_esc"
    printf '\t"visibility" "%s"\n' "$visibility"
  fi
  printf '}\n'
} > "$vdf"

echo "Wrote VDF -> $vdf"
echo "Content: $content"
echo "Preview: $preview"
if [ "$CONTENT_ONLY" != "1" ]; then
  echo "Title:   $title  (+ description from workshop/description.bbcode)"
  echo "Tags:    $tags_csv   Visibility: $vis_word ($visibility)"
fi
echo "Target: $TARGET -> item $PUBLISHED_FILE_ID (app $APPID)  changenote: $CHANGENOTE"

if [ "$DRY_RUN" = "1" ]; then
  echo "--- DRY RUN: VDF contents (not uploading) ---"
  cat "$vdf"
  exit 0
fi

echo "Uploading via steamcmd (Steam Guard prompt expected)..."
steamcmd +login "$STEAM_USERNAME" +workshop_build_item "$vdf" +quit
echo "Published item $PUBLISHED_FILE_ID. Verify: https://steamcommunity.com/sharedfiles/filedetails/?id=$PUBLISHED_FILE_ID"
