#!/usr/bin/env pwsh
# Publish the packaged mod to the Steam Workshop via steamcmd (updates the existing item).
#
# SOURCE OF TRUTH is workshop/workshop.vdf — a steamcmd KeyValues file stored verbatim. This
# script only substitutes the dynamic fields ({{PUBLISHEDFILEID}}, {{CONTENTFOLDER}},
# {{PREVIEWFILE}}, {{CHANGENOTE}}, {{VISIBILITY}}); title/description/tags are edited directly
# in that file. Visibility is per-target: prod is public, test is unlisted. See docs/RELEASING.md.
#
# The publish TARGET (test|prod) is REQUIRED (unless -DryRun) so we're always explicit about
# which Workshop item we touch — there is no default and no env fallback.
#
# Usage: pwsh -NoProfile -File scripts/publish-workshop.ps1 <test|prod> "changenote" [-DryRun]
#    or: pwsh -NoProfile -File scripts/publish-workshop.ps1 <test|prod> -ChangeNoteFile notes.bbcode
#    or: mise run publish test "Fixed multi-barrel draw on 42.19"   (verify, then: ... prod ...)
#   -ChangeNoteFile   read the changenote from a file (bbcode, may be multiline); mutually
#                     exclusive with the inline changenote argument
#   -DryRun           build + print the VDF, don't upload (defaults target to test)

param(
  [Parameter(Position = 0)]
  [string]$Target = "",
  [Parameter(Position = 1)]
  [string]$ChangeNote = "",
  [string]$ChangeNoteFile = "",
  [string]$SteamUser = $env:STEAM_USERNAME,
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-Location (Split-Path -Parent $PSScriptRoot)

$MOD_NAME = "PlumbingFixed"
$APP_ID   = "108600"
# Workshop item ids are public; test first, then prod.
$ITEM_IDS = @{ test = "3680940911"; prod = "3626008449" }

# Normalize target/changenote (strip stray surrounding quotes).
$ChangeNote = $ChangeNote.Trim('"')
$Target = $Target.Trim('"').ToLower()

# Resolve the publish target -> Workshop item id. Required unless -DryRun (defaults to test).
if (-not $Target) {
  if ($DryRun) {
    $Target = 'test'
    Write-Host "No target given; defaulting DryRun to 'test'." -ForegroundColor Yellow
  } else {
    Write-Host "ERROR: a target (test|prod) is required unless -DryRun." -ForegroundColor Red
    Write-Host "       Refusing to publish without an explicit target." -ForegroundColor Red
    exit 2
  }
}
if (-not $ITEM_IDS.ContainsKey($Target)) {
  Write-Host "ERROR: unknown target '$Target' (expected test or prod)." -ForegroundColor Red
  exit 2
}
$PublishedFileId = $ITEM_IDS[$Target]
# ERemoteStoragePublishedFileVisibility: 0 = public, 3 = unlisted. Test stays unlisted.
$Visibility = if ($Target -eq 'prod') { '0' } else { '3' }

# Changenote comes inline or from a bbcode file — never both.
if ($ChangeNoteFile) {
  if ($ChangeNote) {
    Write-Host "ERROR: pass either an inline changenote or -ChangeNoteFile, not both." -ForegroundColor Red
    exit 2
  }
  if (-not (Test-Path $ChangeNoteFile -PathType Leaf)) {
    Write-Host "ERROR: changenote file not found: $ChangeNoteFile" -ForegroundColor Red
    exit 2
  }
  $ChangeNote = (Get-Content $ChangeNoteFile -Raw).TrimEnd()
}

# --- Preconditions ----------------------------------------------------------------------
$haveSteamcmd = [bool](Get-Command steamcmd -ErrorAction SilentlyContinue)
if (-not $haveSteamcmd -and -not $DryRun) {
  Write-Host "ERROR: steamcmd not found on PATH." -ForegroundColor Red
  Write-Host "       Install it: winget install Valve.SteamCMD  (see docs/RELEASING.md)." -ForegroundColor Red
  exit 127
}
if (-not $DryRun -and -not $SteamUser) {
  $SteamUser = Read-Host "Steam username"
}

# Build fresh so we never publish stale content.
$verLine = Get-Content "Contents/mods/$MOD_NAME/42/mod.info" | Where-Object { $_ -match '^modversion=' } | Select-Object -First 1
$ver = ($verLine -split '=', 2)[1].Trim()
# Run package.ps1 as a child process so its exit code is reliably in $LASTEXITCODE.
pwsh -NoProfile -File (Join-Path $PSScriptRoot "package.ps1") "v$ver"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$contentFolder = (Resolve-Path "./dist/$MOD_NAME").Path
$previewFile   = (Resolve-Path "./preview.png").Path
if (-not $ChangeNote) { $ChangeNote = "v$ver" }

# --- Fill the stored VDF template -------------------------------------------------------
# Escape a substituted value for a VDF quoted string: backslash first, then double-quote.
# The template's static values (title/description/tags) already carry their final form.
# Newlines need no escaping — VDF quoted strings take them literally (the template's
# multiline description relies on this), so a file-sourced multiline changenote is fine.
function ConvertTo-VdfValue([string]$s) {
  ($s -replace '\\', '\\') -replace '"', '\"'
}

$template = Get-Content "workshop/workshop.vdf" -Raw
$vdf = $template.
  Replace('{{PUBLISHEDFILEID}}', $PublishedFileId).
  Replace('{{CONTENTFOLDER}}', (ConvertTo-VdfValue $contentFolder)).
  Replace('{{PREVIEWFILE}}', (ConvertTo-VdfValue $previewFile)).
  Replace('{{CHANGENOTE}}', (ConvertTo-VdfValue $ChangeNote)).
  Replace('{{VISIBILITY}}', $Visibility)

New-Item -ItemType Directory -Force -Path ".publish" | Out-Null
$vdfPath = (Join-Path (Get-Location) ".publish\workshop.vdf")
Set-Content -Path $vdfPath -Value $vdf -NoNewline -Encoding UTF8

Write-Host "Wrote VDF -> $vdfPath" -ForegroundColor Cyan
Write-Host "Content:  $contentFolder" -ForegroundColor Cyan
Write-Host "Preview:  $previewFile" -ForegroundColor Cyan
Write-Host "Target:   $Target -> item $PublishedFileId (app $APP_ID)  changenote: $ChangeNote" -ForegroundColor Cyan

if ($DryRun) {
  Write-Host "--- DRY RUN: VDF contents (not uploading) ---" -ForegroundColor Yellow
  Get-Content $vdfPath | ForEach-Object { Write-Host $_ }
  exit 0
}

Write-Host "Uploading via steamcmd..." -ForegroundColor Cyan
steamcmd +login $SteamUser +workshop_build_item "$vdfPath" +quit
if ($LASTEXITCODE -ne 0) {
  Write-Host "steamcmd failed (exit $LASTEXITCODE). Check the output above." -ForegroundColor Red
  exit $LASTEXITCODE
}
Write-Host "Published item $PublishedFileId. Verify the page at" -ForegroundColor Green
Write-Host "  https://steamcommunity.com/sharedfiles/filedetails/?id=$PublishedFileId" -ForegroundColor Green
