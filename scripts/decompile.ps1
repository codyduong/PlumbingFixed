#!/usr/bin/env pwsh
# Decompile the installed Project Zomboid into ./.decompiled/<version>/ for client/server
# analysis, alongside a same-build snapshot of the vanilla Lua callers.
# Uses Zomboid Decompiler (demiurgeQuantified, Vineflower-based, supports 42.13+).
# Preferred: `mise run decompile 42.20`   Direct: `pwsh -NoProfile -File scripts/decompile.ps1 -Version 42.20`
#
# Why: the Umbrella stubs tell you a Java method's SIGNATURE, but not whether it is
# client-authoritative, server-authoritative, or synced. Reading the decompiled source is
# how we verify what an API ACTUALLY does before overriding it. See CLAUDE.md ("golden rule").
#
# Each build's output lands in its own folder (.decompiled/<version>/source,
# .decompiled/<version>/media/lua) so the old and new builds sit side by side for diffing —
# see docs/UPDATING-PZ.md.

param(
  # Project Zomboid install dir. Override with -GamePath or $env:PZ_HOME.
  [string]$GamePath = $env:PZ_HOME,
  # PZ build string identifying the output folder, e.g. "42.20". Required — auto-detection
  # from version.txt is unreliable (only rewrites on launch; see docs/UPDATING-PZ.md §0).
  [Parameter(Mandatory = $true)]
  [string]$Version,
  # Pinned decompiler release. Bump when the game updates if a newer one is needed.
  [string]$DecompilerVersion = "v0.3.1",
  [string]$OutDir  = ".decompiled",
  [string]$ToolsDir = ".tools"
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-Location (Split-Path -Parent $PSScriptRoot)

# --- Resolve the game path --------------------------------------------------------------
if (-not $GamePath) {
  $candidates = @(
    "F:\steamlibrary\steamapps\common\ProjectZomboid",
    "C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid",
    (Join-Path ${env:ProgramFiles(x86)} "Steam\steamapps\common\ProjectZomboid")
  )
  $GamePath = $candidates | Where-Object { $_ -and (Test-Path (Join-Path $_ "projectzomboid.jar")) } | Select-Object -First 1
}
if (-not $GamePath -or -not (Test-Path (Join-Path $GamePath "projectzomboid.jar"))) {
  Write-Host "ERROR: Could not find ProjectZomboid install (projectzomboid.jar)." -ForegroundColor Red
  Write-Host "       Pass -GamePath '<dir>' or set `$env:PZ_HOME." -ForegroundColor Red
  exit 1
}
$GamePath = (Resolve-Path $GamePath).Path
Write-Host "Game: $GamePath" -ForegroundColor Cyan

# --- Ensure the decompiler is present ---------------------------------------------------
$toolRoot = Join-Path $ToolsDir "ZomboidDecompiler"
$batPath  = Join-Path $toolRoot "bin\ZomboidDecompiler.bat"
if (-not (Test-Path $batPath)) {
  Write-Host "Downloading Zomboid Decompiler $DecompilerVersion..." -ForegroundColor Cyan
  New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
  $zip = Join-Path $ToolsDir "ZomboidDecompiler.zip"
  $url = "https://github.com/demiurgeQuantified/ZomboidDecompiler/releases/download/$DecompilerVersion/ZomboidDecompiler.zip"
  Invoke-WebRequest -Uri $url -OutFile $zip
  if (Test-Path $toolRoot) { Remove-Item -Recurse -Force $toolRoot }
  Expand-Archive -Path $zip -DestinationPath $toolRoot -Force
  Remove-Item $zip -Force
  # The zip may nest everything one level deep; normalize so bin/ is directly under $toolRoot.
  if (-not (Test-Path $batPath)) {
    $nested = Get-ChildItem $toolRoot -Directory | Where-Object { Test-Path (Join-Path $_.FullName "bin\ZomboidDecompiler.bat") } | Select-Object -First 1
    if ($nested) { Get-ChildItem $nested.FullName -Force | Move-Item -Destination $toolRoot -Force }
  }
}
if (-not (Test-Path $batPath)) {
  Write-Host "ERROR: ZomboidDecompiler.bat not found after extraction ($toolRoot)." -ForegroundColor Red
  Write-Host "       Download manually from https://github.com/demiurgeQuantified/ZomboidDecompiler/releases" -ForegroundColor Red
  exit 1
}

# --- Run it -----------------------------------------------------------------------------
# The decompiler needs Java 17+. `mise run decompile` puts the pinned Temurin 17 on PATH.
# If no java is on PATH (running this script outside mise), fall back to the game's bundled
# JRE (jre64, also Java 17).
if (-not (Get-Command java -ErrorAction SilentlyContinue)) {
  $jreBin = Join-Path $GamePath "jre64\bin"
  if (Test-Path $jreBin) { $env:PATH = "$jreBin;$env:PATH" }
}

Write-Host "Decompiling..." -ForegroundColor Cyan
Push-Location $toolRoot
try {
  & (Join-Path "bin" "ZomboidDecompiler.bat") "$GamePath"
  $code = $LASTEXITCODE
} finally {
  Pop-Location
}
if ($code -ne 0) {
  Write-Host "ERROR: decompiler exited with code $code." -ForegroundColor Red
  exit $code
}

# --- Relocate output into .decompiled/<version>/source ---------------------------------
$produced = Get-ChildItem $toolRoot -Recurse -Directory -Filter "output" -ErrorAction SilentlyContinue |
  Sort-Object LastWriteTime -Descending | Select-Object -First 1
$versionOut = Join-Path (Get-Location) (Join-Path $OutDir $Version)
$sourceOut  = Join-Path $versionOut "source"
if ($produced) {
  if (Test-Path $sourceOut) { Remove-Item -Recurse -Force $sourceOut }
  New-Item -ItemType Directory -Force -Path $sourceOut | Out-Null
  Copy-Item (Join-Path $produced.FullName "*") $sourceOut -Recurse -Force
  Write-Host "Decompiled source -> $OutDir/$Version/source/" -ForegroundColor Green
} else {
  Write-Host "Decompiler finished, but no 'output' folder was found under $toolRoot." -ForegroundColor Yellow
  Write-Host "Look inside $toolRoot for the results and copy them into $sourceOut manually." -ForegroundColor Yellow
}

# --- Snapshot vanilla game resources from the SAME install, alongside the Java -----------
# Mirrors the game's own media/ layout under the version folder (media/lua for now; other
# media/ subfolders can be added the same way later) so two builds sit side by side for a
# straight `git diff --no-index`.
$mediaOut = Join-Path $versionOut "media"
if (Test-Path $mediaOut) { Remove-Item -Recurse -Force $mediaOut }
New-Item -ItemType Directory -Force -Path $mediaOut | Out-Null
Copy-Item (Join-Path $GamePath "media\lua") $mediaOut -Recurse -Force
Write-Host "Vanilla Lua snapshot -> $OutDir/$Version/media/lua/" -ForegroundColor Green
