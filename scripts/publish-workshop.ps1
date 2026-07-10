#!/usr/bin/env pwsh
# Publish the packaged mod to the Steam Workshop via steamcmd (updates the existing item).
# This UPDATES CONTENT + preview + changenote only; it does NOT overwrite the Workshop
# title/description (those stay managed on the Steam page / in-game uploader) unless you
# pass -UpdateText. Run this yourself in a terminal — steamcmd prompts for Steam Guard.
# See docs/RELEASING.md.
#
# Usage: mise run publish "Fixed multi-barrel draw on 42.19"
#    or: pwsh -NoProfile -File scripts/publish-workshop.ps1 -ChangeNote "..." -SteamUser you

param(
  [Parameter(Position = 0)]
  [string]$ChangeNote = "",
  [string]$SteamUser = $env:STEAM_USER,
  [string]$PublishedFileId = $(if ($env:PF_PUBLISHED_FILE_ID) { $env:PF_PUBLISHED_FILE_ID } else { "3626008449" }),
  [string]$AppId = $(if ($env:PF_APPID) { $env:PF_APPID } else { "108600" }),
  [switch]$UpdateText
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-Location (Split-Path -Parent $PSScriptRoot)

$MOD_NAME = "PlumbingFixed"

# mise's cmd shell can pass the arg with surrounding quotes; normalize. Also, when the
# optional changenote is omitted, cmd leaves the literal token "%usage_changenote%" —
# treat any unexpanded token as empty (the script then falls back to "v<version>").
$ChangeNote = $ChangeNote.Trim('"')
if ($ChangeNote -match '^%.*%$') { $ChangeNote = '' }

# --- Preconditions ----------------------------------------------------------------------
if (-not (Get-Command steamcmd -ErrorAction SilentlyContinue)) {
  Write-Host "ERROR: steamcmd not found on PATH." -ForegroundColor Red
  Write-Host "       Install it (https://developer.valvesoftware.com/wiki/SteamCMD) and" -ForegroundColor Red
  Write-Host "       ensure 'steamcmd' is callable. See docs/RELEASING.md." -ForegroundColor Red
  exit 127
}
if (-not $SteamUser) {
  $SteamUser = Read-Host "Steam username"
}

# Build fresh so we never publish stale content.
$verLine = Get-Content "Contents/mods/$MOD_NAME/42/mod.info" | Where-Object { $_ -match '^modversion=' } | Select-Object -First 1
$ver = ($verLine -split '=', 2)[1].Trim()
& (Join-Path $PSScriptRoot "package.ps1") "v$ver"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$contentFolder = (Resolve-Path "./$MOD_NAME").Path
$previewFile   = (Resolve-Path "./preview.png").Path
if (-not $ChangeNote) { $ChangeNote = "v$ver" }

# --- Generate the steamcmd VDF ----------------------------------------------------------
New-Item -ItemType Directory -Force -Path ".publish" | Out-Null
$vdfPath = (Join-Path (Get-Location) ".publish\workshop.vdf")

# VDF wants backslash-escaped paths.
$cf = $contentFolder -replace '\\', '\\'
$pf = $previewFile   -replace '\\', '\\'
$cn = $ChangeNote    -replace '"', "'"

$lines = @(
  '"workshopitem"'
  '{'
  "`t`"appid`" `"$AppId`""
  "`t`"publishedfileid`" `"$PublishedFileId`""
  "`t`"contentfolder`" `"$cf`""
  "`t`"previewfile`" `"$pf`""
  "`t`"changenote`" `"$cn`""
)
if ($UpdateText) {
  # Only if you explicitly want steamcmd to overwrite the Steam page text.
  $title = (Get-Content "workshop.txt" | Where-Object { $_ -match '^title=' } | Select-Object -First 1)
  if ($title) { $title = ($title -split '=', 2)[1].Trim() }
  $lines += "`t`"title`" `"$title`""
}
$lines += '}'
Set-Content -Path $vdfPath -Value $lines -Encoding ASCII

Write-Host "Wrote VDF -> $vdfPath" -ForegroundColor Cyan
Write-Host "Content:  $contentFolder" -ForegroundColor Cyan
Write-Host "Item:     $PublishedFileId (app $AppId)  changenote: $ChangeNote" -ForegroundColor Cyan
Write-Host "Uploading via steamcmd (Steam Guard prompt expected)..." -ForegroundColor Cyan

steamcmd +login $SteamUser +workshop_build_item "$vdfPath" +quit
if ($LASTEXITCODE -ne 0) {
  Write-Host "steamcmd failed (exit $LASTEXITCODE). Check the output above." -ForegroundColor Red
  exit $LASTEXITCODE
}
Write-Host "Published item $PublishedFileId." -ForegroundColor Green
