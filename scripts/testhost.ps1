#!/usr/bin/env pwsh
# Ephemeral local dedicated server for MP testing — keeps your real game install and
# %USERPROFILE%\Zomboid completely untouched:
#   - the PZ Dedicated Server (Steam app 380870, anonymous download) lives in .tools/pzserver
#   - ALL server state (configs, world, db, mods) lives in the git-ignored .testhost/ via
#     -cachedir; seed configs come from the source-controlled testhost/ dir
#   - first boot creates the admin account from -adminusername/-adminpassword
# Blow the world away and start fresh: -Reset. See docs/TESTING.md.
#
# Usage: mise run testhost [--reset]
#    or: pwsh -NoProfile -File scripts/testhost.ps1 [-Reset] [-AdminPassword pw] [-Branch unstable]

param(
  [switch]$Reset,
  # Localhost-only throwaway credentials (the admin account is created on first boot).
  [string]$AdminPassword = "pztest",
  # Steam branch of the dedicated server; must MATCH the installed game's build or the
  # client is refused at connect (version check). B42 unstable lives on "unstable".
  [string]$Branch = "unstable",
  [string]$ServerDir = ".tools/pzserver",
  [string]$CacheDir = ".testhost"
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-Location (Split-Path -Parent $PSScriptRoot)

# --- Install the dedicated server (one-time, ~4 GB, anonymous — no Steam Guard) ---------
$javaExe = Join-Path $ServerDir "jre64\bin\java.exe"
if (-not (Test-Path $javaExe)) {
  if (-not (Get-Command steamcmd -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: steamcmd not found on PATH (winget install Valve.SteamCMD)." -ForegroundColor Red
    exit 127
  }
  $absServerDir = Join-Path (Get-Location) $ServerDir
  Write-Host "Installing PZ Dedicated Server (app 380870, branch '$Branch') -> $absServerDir" -ForegroundColor Cyan
  Write-Host "First run downloads ~4 GB." -ForegroundColor Yellow
  steamcmd +force_install_dir "$absServerDir" +login anonymous +app_update 380870 -beta $Branch validate +quit
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path $javaExe)) {
    Write-Host "ERROR: steamcmd install failed (exit $LASTEXITCODE). If the branch name is wrong," -ForegroundColor Red
    Write-Host "       list branches with: steamcmd +login anonymous +app_info_print 380870 +quit" -ForegroundColor Red
    exit 1
  }
}

# --- Provision the ephemeral cachedir ----------------------------------------------------
if ($Reset -and (Test-Path $CacheDir)) {
  Write-Host "Resetting testhost world: removing $CacheDir" -ForegroundColor Yellow
  Remove-Item -Recurse -Force $CacheDir
}
New-Item -ItemType Directory -Force -Path (Join-Path $CacheDir "Server") | Out-Null
# Seed configs only when missing so a running world's tweaks survive restarts;
# --reset is the way back to the canonical repo presets.
foreach ($f in @("servertest.ini", "servertest_SandboxVars.lua")) {
  $dst = Join-Path $CacheDir "Server\$f"
  if (-not (Test-Path $dst)) { Copy-Item (Join-Path "testhost" $f) $dst }
}

# --- Deploy the mod into the testhost ----------------------------------------------------
pwsh -NoProfile -File (Join-Path $PSScriptRoot "deploy-local.ps1") server -ServerCacheDir $CacheDir
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

# --- Launch (foreground; the server console stays interactive) ---------------------------
# Mirrors the install's own StartServer64.bat (classpath java/;java/projectzomboid.jar,
# -Dzomboid.steam=1 — a Steam-mode game client can only join a Steam-enabled server) with
# saner memory than its 16g default, plus our -cachedir and admin bootstrap args. We invoke
# java directly because the bat only forwards two arguments (%1 %2).
$absCacheDir = (Resolve-Path $CacheDir).Path
Write-Host "Starting dedicated server (cachedir: $absCacheDir)" -ForegroundColor Cyan
Write-Host "Connect from a normal game client: Join -> 127.0.0.1:16261, account 'admin' / '$AdminPassword'" -ForegroundColor Cyan
Push-Location $ServerDir
try {
  # Argument array so PowerShell passes each token verbatim (unquoted -D flags get split).
  $javaArgs = @(
    '-Djava.awt.headless=true', '-Dzomboid.steam=1', '-Dzomboid.znetlog=1',
    '-XX:+UseZGC', '-XX:-CreateCoredumpOnCrash', '-XX:-OmitStackTraceInFastThrow',
    '-Xms2g', '-Xmx3g',
    '-Djava.library.path=natives/;natives/win64/;.',
    '-cp', 'java/;java/projectzomboid.jar',
    'zombie.network.GameServer',
    '-statistic', '0',
    "-cachedir=$absCacheDir",
    '-adminusername', 'admin',
    '-adminpassword', $AdminPassword
  )
  & ".\jre64\bin\java.exe" @javaArgs
  exit $LASTEXITCODE
} finally {
  Pop-Location
}
