#!/usr/bin/env pwsh
# Publish the packaged mod to the Steam Workshop via steamcmd (updates the existing item).
#
# Page metadata lives in workshop/workshop.conf (flat key=value) and the description
# verbatim in workshop/description.bbcode. See docs/RELEASING.md.
#
# The publish TARGET (test|prod) is REQUIRED (unless -DryRun) so we're always explicit about
# which Workshop item we touch — there is no default and no env fallback.
#
# Usage: pwsh -NoProfile -File scripts/publish-workshop.ps1 <test|prod> "changenote" [flags]
#    or: mise run publish test "Fixed multi-barrel draw on 42.19"   (verify, then: ... prod ...)
# Flags (explicit — behavior is never driven by ambient env):
#   -DryRun      / --dry-run        build + print the VDF, don't upload (defaults target to test)
#   -ContentOnly / --content-only   skip title/description/tags/visibility

param(
  [Parameter(Position = 0)]
  [string]$Target = "",
  [Parameter(Position = 1)]
  [string]$ChangeNote = "",
  [string]$SteamUser = $env:STEAM_USERNAME,
  [string]$AppId = $env:PF_APPID,
  [switch]$ContentOnly,
  [switch]$DryRun,
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$ExtraArgs
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-Location (Split-Path -Parent $PSScriptRoot)

# Accept POSIX-style flag aliases (--dry-run / --content-only) for parity with the .sh twin.
foreach ($a in $ExtraArgs) {
  switch -Exact ($a) {
    '--dry-run' { $DryRun = $true }
    '--content-only' { $ContentOnly = $true }
    default { Write-Host "ERROR: unknown argument '$a'." -ForegroundColor Red; exit 2 }
  }
}

$MOD_NAME = "PlumbingFixed"

# Normalize target/changenote (strip stray surrounding quotes).
$ChangeNote = $ChangeNote.Trim('"')
$Target = $Target.Trim('"').ToLower()

# Escape a string for a VDF (KeyValues) quoted value.
function ConvertTo-VdfValue([string]$s) {
  if ($null -eq $s) { return "" }
  $s = $s -replace '\\', '\\'   # backslash first
  $s = $s -replace '"', '\"'
  # $s = $s -replace "`r", ''
  # $s = $s -replace "`n", '\n'
  # $s = $s -replace "`t", '\t'
  return $s
}

# Map a visibility word to steamcmd's integer. steamcmd's VDF takes an int here.
$visibilityMap = @{ public = 0; friendsonly = 1; private = 2; unlisted = 3 }

# --- Load the source-of-truth metadata --------------------------------------------------
# workshop/workshop.conf: flat key=value, single-line values, '#' comments.
$conf = @{}
foreach ($line in Get-Content "workshop/workshop.conf") {
  $t = $line.Trim()
  if (-not $t -or $t.StartsWith('#')) { continue }
  $kv = $t -split '=', 2
  if ($kv.Count -eq 2) { $conf[$kv[0].Trim()] = $kv[1].Trim() }
}
# Description is read verbatim (no parsing / no escaping guesswork here). Trim the file's
# trailing newline so the VDF matches the bash twin (its $(cat) strips trailing newlines).
$description = (Get-Content "workshop/description.bbcode" -Raw)
if ($null -eq $description) { $description = "" } else { $description = $description -replace '\r?\n\z', '' }

$title = if ($conf.title) { $conf.title } else { $MOD_NAME }
if (-not $AppId) { $AppId = $conf.app_id }
$previewRel = if ($conf.preview) { $conf.preview } else { "preview.png" }

# Resolve the publish target -> Workshop item id. Required unless -DryRun so we never publish
# to an implicit item. Dry-run defaults to 'test' (safe) and says so.
if (-not $Target) {
  if ($DryRun) {
    $Target = 'test'
    Write-Host "No -Target given; defaulting DryRun to 'test'." -ForegroundColor Yellow
  } else {
    Write-Host "ERROR: -Target is required (test|prod) unless -DryRun." -ForegroundColor Red
    Write-Host "       Refusing to publish without an explicit target." -ForegroundColor Red
    exit 2
  }
}
switch ($Target) {
  'prod' { $PublishedFileId = if ($env:PF_PUBLISHED_FILE_ID) { $env:PF_PUBLISHED_FILE_ID } else { $conf.published_id } }
  'test' { $PublishedFileId = if ($env:PF_TEST_PUBLISHED_FILE_ID) { $env:PF_TEST_PUBLISHED_FILE_ID } else { $conf.test_published_id } }
  default {
    Write-Host "ERROR: unknown target '$Target' (expected test or prod)." -ForegroundColor Red
    exit 2
  }
}
if (-not $PublishedFileId) {
  Write-Host "ERROR: no item id for target '$Target' — set it in workshop/workshop.conf" -ForegroundColor Red
  Write-Host "       (published_id / test_published_id) or the matching PF_*_PUBLISHED_FILE_ID env." -ForegroundColor Red
  exit 2
}

# tags: manifest ';'-separated -> VDF form (comma-separated). Best-effort validation against
# the game's media/WorkshopTags.txt when PZ_HOME is set; otherwise pass through.
$tags = @($conf.tags -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($env:PZ_HOME) {
  $tagsFile = Join-Path $env:PZ_HOME "media/WorkshopTags.txt"
  if (Test-Path $tagsFile) {
    $allowed = Get-Content $tagsFile | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    foreach ($tg in $tags) {
      if ($allowed -notcontains $tg) {
        Write-Host "WARN: tag '$tg' not in $tagsFile" -ForegroundColor Yellow
      }
    }
  }
}

# visibility word -> steamcmd int.
$visWord = if ($conf.visibility) { $conf.visibility.ToLower() } else { "public" }
if (-not $visibilityMap.ContainsKey($visWord)) {
  Write-Host "ERROR: unknown visibility '$($conf.visibility)' (expected public/friendsOnly/private/unlisted)." -ForegroundColor Red
  exit 1
}
$visibility = $visibilityMap[$visWord]

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
# Run package.ps1 as a child process so its exit code is reliably in $LASTEXITCODE
# (calling it with '&' leaves $LASTEXITCODE $null on success — and $null -ne 0 is true).
pwsh -NoProfile -File (Join-Path $PSScriptRoot "package.ps1") "v$ver"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$contentFolder = (Resolve-Path "./$MOD_NAME").Path
$previewFile   = (Resolve-Path "./$previewRel").Path
if (-not $ChangeNote) { $ChangeNote = "v$ver" }

# --- Generate the steamcmd VDF ----------------------------------------------------------
New-Item -ItemType Directory -Force -Path ".publish" | Out-Null
$vdfPath = (Join-Path (Get-Location) ".publish\workshop.vdf")

# VDF wants backslash-escaped paths.
$cf = $contentFolder -replace '\\', '\\'
$pf = $previewFile   -replace '\\', '\\'

$lines = @(
  '"workshopitem"'
  '{'
  "`t`"appid`" `"$AppId`""
  "`t`"publishedfileid`" `"$PublishedFileId`""
  "`t`"contentfolder`" `"$cf`""
  "`t`"previewfile`" `"$pf`""
  "`t`"changenote`" `"$(ConvertTo-VdfValue $ChangeNote)`""
)
if (-not $ContentOnly) {
  $lines += "`t`"title`" `"$(ConvertTo-VdfValue $title)`""
  $lines += "`t`"description`" `"$(ConvertTo-VdfValue $description)`""
  $lines += "`t`"tags`" `"$(ConvertTo-VdfValue ($tags -join ','))`""
  $lines += "`t`"visibility`" `"$visibility`""
}
$lines += '}'
Set-Content -Path $vdfPath -Value $lines -Encoding UTF8

Write-Host "Wrote VDF -> $vdfPath" -ForegroundColor Cyan
Write-Host "Content:  $contentFolder" -ForegroundColor Cyan
Write-Host "Preview:  $previewFile" -ForegroundColor Cyan
if (-not $ContentOnly) {
  Write-Host "Title:    $title  (+ description from workshop/description.bbcode)" -ForegroundColor Cyan
  Write-Host "Tags:     $($tags -join ', ')   Visibility: $visWord ($visibility)" -ForegroundColor Cyan
}
Write-Host "Target:   $Target -> item $PublishedFileId (app $AppId)  changenote: $ChangeNote" -ForegroundColor Cyan

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
