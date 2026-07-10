#!/usr/bin/env pwsh
# Set the mod's version (modversion) in every mod.info so the two copies never drift.
# This is the mod's OWN semver (e.g. 1.3.14) and must equal the release git tag (v1.3.14) —
# scripts/package.* enforce that. It is NOT the targeted PZ build (e.g. "B42.15"); that
# marker lives in 42/mod.info `name=` and workshop.txt and is changed only when retargeting
# a new game build — see docs/UPDATING-PZ.md.
#
# Usage: mise run bump 1.3.14   (or: pwsh -NoProfile -File scripts/bump-version.ps1 1.3.14)

param(
  [Parameter(Mandatory = $true, Position = 0)]
  [string]$Version
)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)

# mise's cmd shell can pass the arg with surrounding quotes; normalize, then accept
# "v1.3.14" or "1.3.14" and store the bare semver.
$ver = $Version.Trim('"').TrimStart('v', 'V')
if ($ver -notmatch '^\d+\.\d+\.\d+$') {
  Write-Host "ERROR: version must be X.Y.Z (got '$Version')." -ForegroundColor Red
  exit 1
}

$infos = @(
  "Contents/mods/PlumbingFixed/41/mod.info",
  "Contents/mods/PlumbingFixed/42/mod.info"
)

foreach ($info in $infos) {
  if (-not (Test-Path $info)) {
    Write-Host "ERROR: missing $info" -ForegroundColor Red
    exit 1
  }
  $content = Get-Content -Raw $info
  if ($content -notmatch '(?m)^modversion=') {
    Write-Host "ERROR: no 'modversion=' line in $info" -ForegroundColor Red
    exit 1
  }
  # Preserve the file's existing line endings; only swap the version value.
  $updated = [regex]::Replace($content, '(?m)^(modversion=).*$', "`${1}$ver")
  # -NoNewline so we don't append an extra trailing newline beyond what was there.
  Set-Content -Path $info -Value $updated -NoNewline
  Write-Host "  set modversion=$ver in $info" -ForegroundColor Green
}

Write-Host "Version set to $ver. Next: commit, tag v$ver, then 'mise run package v$ver'." -ForegroundColor Cyan
