#!/usr/bin/env pwsh
# Package the mod, then sync it where the game loads it for local testing. The TARGET is
# required so a deploy never silently touches a location you didn't intend:
#   client — %USERPROFILE%\Zomboid\Workshop\<mod>   (the "workshop (dev)" dir the CLIENT
#            loads from; Steam-mode only, so a dedicated server never sees it)
#   server — <ServerCacheDir>\mods\<mod>            (the local-mods dir a dedicated server
#            scans; defaults to the ephemeral .testhost cachedir, NOT your real ~\Zomboid)
#   all    — both of the above
# See docs/TESTING.md.
#
# Usage: mise run deploy <client|server|all>
#    or: pwsh -NoProfile -File scripts/deploy-local.ps1 <client|server|all>
#          [-ZomboidDir <dir>] [-ServerCacheDir <dir>]

param(
  [Parameter(Position = 0)]
  [string]$Target = "",
  # Zomboid user data dir the CLIENT uses. Override with -ZomboidDir or $env:ZOMBOID_DIR.
  [string]$ZomboidDir = $(if ($env:ZOMBOID_DIR) { $env:ZOMBOID_DIR } else { Join-Path $HOME "Zomboid" }),
  # Cachedir the dedicated server runs with (-cachedir=...). Default: the ephemeral testhost.
  [string]$ServerCacheDir = ".testhost"
)

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)

$MOD_NAME = "PlumbingFixed"

# mise's cmd shell can pass the arg with surrounding quotes; normalize.
$Target = $Target.Trim('"').ToLower()
if ($Target -notin @('client', 'server', 'all')) {
  Write-Host "ERROR: a target (client|server|all) is required." -ForegroundColor Red
  exit 2
}

# Derive the current version from 42/mod.info so packaging validation passes trivially.
$modInfo = "Contents/mods/$MOD_NAME/42/mod.info"
$verLine = Get-Content $modInfo | Where-Object { $_ -match '^modversion=' } | Select-Object -First 1
$ver = ($verLine -split '=', 2)[1].Trim()
Write-Host "Deploying $MOD_NAME v$ver ($Target)" -ForegroundColor Cyan

# Build (validates + assembles dist/PlumbingFixed). Run as a child process so its exit code
# is reliably in $LASTEXITCODE (calling with '&' leaves it $null on success).
pwsh -NoProfile -File (Join-Path $PSScriptRoot "package.ps1") "v$ver"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if ($Target -in @('client', 'all')) {
  if (-not (Test-Path $ZomboidDir)) {
    Write-Host "ERROR: Zomboid dir not found: $ZomboidDir (pass -ZomboidDir)." -ForegroundColor Red
    exit 1
  }
  $clientTarget = Join-Path $ZomboidDir "Workshop\$MOD_NAME"
  if (Test-Path $clientTarget) { Remove-Item -Recurse -Force $clientTarget }
  New-Item -ItemType Directory -Force -Path (Split-Path $clientTarget) | Out-Null
  Copy-Item "./dist/$MOD_NAME" $clientTarget -Recurse -Force
  Write-Host "Synced (client, Workshop dev) -> $clientTarget" -ForegroundColor Green
}

if ($Target -in @('server', 'all')) {
  $serverTarget = Join-Path $ServerCacheDir "mods\$MOD_NAME"
  if (Test-Path $serverTarget) { Remove-Item -Recurse -Force $serverTarget }
  New-Item -ItemType Directory -Force -Path (Split-Path $serverTarget) | Out-Null
  Copy-Item "./dist/$MOD_NAME/Contents/mods/$MOD_NAME" $serverTarget -Recurse -Force
  Write-Host "Synced (dedicated server) -> $serverTarget" -ForegroundColor Green
}

if ($Target -in @('client', 'all')) {
  Write-Host "In-game: enable the mod under Workshop (dev) mods, then load the DebugPlumbing scenario." -ForegroundColor Cyan
}
