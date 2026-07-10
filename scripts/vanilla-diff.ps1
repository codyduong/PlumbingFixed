#!/usr/bin/env pwsh
# Show how the installed vanilla has drifted from our committed baseline, for exactly the
# functions we override. Run this first when moving to a new PZ build. See docs/UPDATING-PZ.md.
#
# Usage: mise run vanilla-diff   (or: pwsh -NoProfile -File scripts/vanilla-diff.ps1)

param([string]$GamePath = $env:PZ_HOME)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-Location (Split-Path -Parent $PSScriptRoot)

$version = (Get-Content "vendor/pz/VERSION" -Raw).Trim()
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("pf-vanilla-" + [Guid]::NewGuid().ToString('N'))
try {
  & (Join-Path $PSScriptRoot "vanilla-extract.ps1") -GamePath $GamePath -Out $tmp | Out-Null
  Write-Host "Drift: committed vendor/pz/$version  ->  installed vanilla"
  git --no-pager diff --no-index --ignore-cr-at-eol "vendor/pz/$version" $tmp
} finally {
  if (Test-Path $tmp) { Remove-Item -Recurse -Force $tmp }
}
