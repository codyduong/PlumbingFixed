#!/usr/bin/env pwsh
# Package the mod, then sync it into the local Zomboid Workshop dir so the game loads your
# working copy for in-game testing (SP or a local server). See docs/TESTING.md.
# Preferred: `mise run deploy`   Direct: `pwsh -NoProfile -File scripts/deploy-local.ps1`

param(
  # Zomboid user data dir (contains mods/, Workshop/). Override with -ZomboidDir or $env:ZOMBOID_DIR.
  [string]$ZomboidDir = $(if ($env:ZOMBOID_DIR) { $env:ZOMBOID_DIR } else { Join-Path $HOME "Zomboid" })
)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)

$MOD_NAME = "PlumbingFixed"

# Derive the current version from 42/mod.info so packaging validation passes trivially.
$modInfo = "Contents/mods/$MOD_NAME/42/mod.info"
$verLine = Get-Content $modInfo | Where-Object { $_ -match '^modversion=' } | Select-Object -First 1
$ver = ($verLine -split '=', 2)[1].Trim()
Write-Host "Deploying $MOD_NAME v$ver" -ForegroundColor Cyan

# Build (validates + assembles ./PlumbingFixed). Run as a child process so its exit code is
# reliably in $LASTEXITCODE (calling with '&' leaves it $null on success — $null -ne 0 is true).
pwsh -NoProfile -File (Join-Path $PSScriptRoot "package.ps1") "v$ver"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$target = Join-Path $ZomboidDir "Workshop\$MOD_NAME"
if (-not (Test-Path $ZomboidDir)) {
  Write-Host "ERROR: Zomboid dir not found: $ZomboidDir (pass -ZomboidDir)." -ForegroundColor Red
  exit 1
}

# Clean sync: remove the old deploy, copy the fresh build in.
if (Test-Path $target) { Remove-Item -Recurse -Force $target }
New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
Copy-Item "./$MOD_NAME" $target -Recurse -Force

Write-Host "Synced -> $target" -ForegroundColor Green
Write-Host "In-game: enable the mod under Workshop (dev) mods, then load the DebugPlumbing scenario." -ForegroundColor Cyan
