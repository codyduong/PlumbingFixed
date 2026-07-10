#!/usr/bin/env bash
# Publish the packaged mod to the Steam Workshop via steamcmd (updates the existing item).
#
# SOURCE OF TRUTH is workshop/workshop.vdf — a steamcmd KeyValues file stored verbatim. This
# script only substitutes the dynamic fields ({{PUBLISHEDFILEID}}, {{CONTENTFOLDER}},
# {{PREVIEWFILE}}, {{CHANGENOTE}}); title/description/tags/visibility are edited directly in
# that file. See docs/RELEASING.md.
#
# The publish TARGET (test|prod) is REQUIRED (unless --dry-run) so we're always explicit about
# which Workshop item we touch — there is no default and no env fallback.
#
# Usage: mise run publish test "changenote"   (verify, then: mise run publish prod "changenote")
#    or: bash scripts/publish-workshop.sh <test|prod> "changenote" [--dry-run]
set -euo pipefail
cd "$(dirname "$0")/.."

MOD_NAME="PlumbingFixed"
APP_ID="108600"
STEAM_USERNAME="${STEAM_USERNAME:-}"
DRY_RUN=0
positional=()
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)      DRY_RUN=1 ;;
    --)             shift; while [ $# -gt 0 ]; do positional+=("$1"); shift; done; break ;;
    -*)             echo "ERROR: unknown flag '$1'." >&2; exit 2 ;;
    *)              positional+=("$1") ;;
  esac
  shift
done
TARGET="$(printf '%s' "${positional[0]:-}" | tr '[:upper:]' '[:lower:]')"
CHANGENOTE="${positional[1]:-}"

# Resolve target -> Workshop item id (public). Required unless --dry-run (defaults to test).
if [ -z "$TARGET" ]; then
  if [ "$DRY_RUN" = "1" ]; then
    TARGET="test"; echo "No target given; defaulting dry-run to 'test'." >&2
  else
    echo "ERROR: a target (test|prod) is required unless --dry-run." >&2
    echo "       Refusing to publish without an explicit target." >&2; exit 2
  fi
fi
case "$TARGET" in
  test) PUBLISHED_FILE_ID="3680940911" ;;
  prod) PUBLISHED_FILE_ID="3626008449" ;;
  *)    echo "ERROR: unknown target '$TARGET' (expected test or prod)." >&2; exit 2 ;;
esac

# Escape a substituted value for a VDF quoted string: backslash first, then double-quote.
vdf_escape() { local s="$1"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; printf '%s' "$s"; }

# --- Preconditions ----------------------------------------------------------------------
if ! command -v steamcmd >/dev/null 2>&1 && [ "$DRY_RUN" != "1" ]; then
  echo "ERROR: steamcmd not found on PATH. Install it (see docs/RELEASING.md)." >&2; exit 127
fi

# Build fresh so we never publish stale content.
ver="$(grep -m1 '^modversion=' "Contents/mods/$MOD_NAME/42/mod.info" | cut -d= -f2 | tr -d '[:space:]')"
bash "$(dirname "$0")/package.sh" "v$ver"

content_folder="$(cd "./$MOD_NAME" && pwd)"
preview_file="$(cd "$(dirname "./preview.png")" && pwd)/$(basename "./preview.png")"
[ -n "$CHANGENOTE" ] || CHANGENOTE="v$ver"

# --- Fill the stored VDF template (literal, newline-safe substitution) -------------------
# $(cat) strips only the trailing newline; internal newlines in the description are preserved.
# Bash parameter expansion ${tpl//pat/repl} is a literal replace (no regex, no newline
# mangling) — this is the fix for the old LF -> literal "\n" bug.
tpl="$(cat workshop/workshop.vdf)"
tpl="${tpl//'{{PUBLISHEDFILEID}}'/$PUBLISHED_FILE_ID}"
tpl="${tpl//'{{CONTENTFOLDER}}'/$(vdf_escape "$content_folder")}"
tpl="${tpl//'{{PREVIEWFILE}}'/$(vdf_escape "$preview_file")}"
tpl="${tpl//'{{CHANGENOTE}}'/$(vdf_escape "$CHANGENOTE")}"

mkdir -p .publish
vdf=".publish/workshop.vdf"
printf '%s\n' "$tpl" > "$vdf"

echo "Wrote VDF -> $vdf"
echo "Content:  $content_folder"
echo "Preview:  $preview_file"
echo "Target:   $TARGET -> item $PUBLISHED_FILE_ID (app $APP_ID)  changenote: $CHANGENOTE"

if [ "$DRY_RUN" = "1" ]; then
  echo "--- DRY RUN: VDF contents (not uploading) ---"
  cat "$vdf"
  exit 0
fi

echo "Uploading via steamcmd..."
steamcmd +login "$STEAM_USERNAME" +workshop_build_item "$(pwd)/$vdf" +quit
echo "Published item $PUBLISHED_FILE_ID. Verify: https://steamcommunity.com/sharedfiles/filedetails/?id=$PUBLISHED_FILE_ID"
