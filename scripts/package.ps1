#!/usr/bin/env pwsh
# Validate mod.info versions against the release tag, then assemble dist/PlumbingFixed in
# the exact layout Steam Workshop / the game expects. (The inner folder must be named
# PlumbingFixed — that's what lands in the mods dir — but staging lives under dist/ so the
# build output doesn't shadow the repo name at the root.)
#
# SIBLING SCRIPT: scripts/package.sh is the Unix/CI twin. Keep the version validation and
# the build/copy steps IDENTICAL in both — any drift ships a broken layout. See docs/RELEASING.md.
# Usage: mise run package v1.3.14  (or: pwsh -NoProfile -File scripts/package.ps1 v1.3.14)

param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$Tag
)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)

$MOD_NAME = "PlumbingFixed"

# mise's cmd shell can pass the arg with surrounding quotes ("v1.3.13"); normalize.
$Tag = $Tag.Trim('"')
# Strip leading 'v' (v1.0.0 -> 1.0.0) to match the Zomboid modversion format.
$expected = $Tag.TrimStart('v', 'V')
Write-Host "Validating mod versions against: $expected" -ForegroundColor Cyan

$infoFiles = Get-ChildItem -Path "./Contents/mods/$MOD_NAME" -Recurse -Filter "mod.info"
if (-not $infoFiles) {
  Write-Host "ERROR: No mod.info files found to validate." -ForegroundColor Red
  exit 1
}
foreach ($file in $infoFiles) {
  $line = Get-Content $file.FullName | Where-Object { $_ -match '^modversion=' } | Select-Object -First 1
  $fileVersion = if ($line) { ($line -split '=', 2)[1].Trim() } else { $null }
  if (-not $fileVersion) {
    Write-Host "ERROR: Could not find 'modversion=' in: $($file.FullName)" -ForegroundColor Red
    exit 1
  }
  if ($fileVersion -ne $expected) {
    Write-Host "ERROR: Version mismatch in $($file.FullName)" -ForegroundColor Red
    Write-Host "   Expected: $expected" -ForegroundColor Red
    Write-Host "   Found:    $fileVersion" -ForegroundColor Red
    Write-Host "   (Run 'mise run bump $expected' to fix.)" -ForegroundColor Yellow
    exit 1
  }
  Write-Host "  OK: $($file.FullName) ($fileVersion)" -ForegroundColor Green
}
Write-Host "All mod.info versions match. Packaging..." -ForegroundColor Cyan

# --- Assemble the build dir (identical structure to scripts/package.sh) -----------------
$STAGE = "dist/$MOD_NAME"
if (Test-Path $STAGE) { Remove-Item -Recurse -Force -Path $STAGE }
New-Item -ItemType Directory -Force -Path $STAGE | Out-Null
Copy-Item ./Contents -Recurse "$STAGE/Contents"
Copy-Item ./preview.png "$STAGE/preview.png"
# build 41 compat: promote 41/mod.info + poster and 42/media to the mod root
Copy-Item "./Contents/mods/$MOD_NAME/41/*" -Recurse "$STAGE/Contents/mods/$MOD_NAME/"
Copy-Item "./Contents/mods/$MOD_NAME/42/media" -Recurse "$STAGE/Contents/mods/$MOD_NAME/"
Remove-Item "$STAGE/Contents/mods/$MOD_NAME/41" -Recurse -Force
Remove-Item "$STAGE/Contents/mods/$MOD_NAME/common/.gitkeep" -Force

Write-Host "Packaging complete for $MOD_NAME -> ./$STAGE" -ForegroundColor Green
