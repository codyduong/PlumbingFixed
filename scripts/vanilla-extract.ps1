#!/usr/bin/env pwsh
# Extract the vanilla source of the functions we override (vendor/pz/overrides.manifest) from
# the installed Project Zomboid into the baseline tree, so there is an ancestor to 3-way merge
# our overrides against on the next PZ update. See docs/UPDATING-PZ.md.
# Override the install dir with -GamePath or $env:PZ_HOME.
#
# Usage: mise run vanilla-extract          (writes vendor/pz/<VERSION>/)
#    or: pwsh -NoProfile -File scripts/vanilla-extract.ps1 [-Out DIR]

param(
  [string]$GamePath = $env:PZ_HOME,
  [string]$Out = ""
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
Set-Location (Split-Path -Parent $PSScriptRoot)

if (-not $GamePath) {
  $candidates = @(
    "F:\steamlibrary\steamapps\common\ProjectZomboid",
    "C:\Program Files (x86)\Steam\steamapps\common\ProjectZomboid"
  )
  $GamePath = $candidates | Where-Object { $_ -and (Test-Path (Join-Path $_ "projectzomboid.jar")) } | Select-Object -First 1
}
$luaRoot = if ($GamePath) { Join-Path $GamePath "media/lua" } else { $null }
if (-not $luaRoot -or -not (Test-Path $luaRoot)) {
  Write-Host "ERROR: PZ media/lua not found; set -GamePath or `$env:PZ_HOME." -ForegroundColor Red; exit 1
}

$version = (Get-Content "vendor/pz/VERSION" -Raw).Trim()
if (-not $Out) { $Out = "vendor/pz/$version" }
$manifest = "vendor/pz/overrides.manifest"

# Extract one top-level function body: from `function T.name(` / `function T:name(` to the
# terminating column-0 `end`. Case-sensitive (-clike/-ceq) to match Lua + the bash twin.
function Get-Fn($file, $name) {
  $inFn = $false; $found = $false
  $acc = New-Object System.Collections.Generic.List[string]
  foreach ($line in [System.IO.File]::ReadAllLines($file)) {
    if (-not $inFn) {
      if ($line -clike "function *.$name(*" -or $line -clike "function *:$name(*") { $inFn = $true; $acc.Add($line) }
    } else {
      $acc.Add($line)
      if ($line -ceq 'end') { $inFn = $false; $found = $true; $acc.Add('') }
    }
  }
  return @{ found = $found; lines = $acc }
}

$rc = 0
foreach ($raw in [System.IO.File]::ReadAllLines($manifest)) {
  if (-not $raw -or $raw.StartsWith('#')) { continue }
  $parts = $raw -split "`t", 2
  $relpath = $parts[0].Trim()
  if (-not $relpath) { continue }
  $fns = if ($parts.Count -gt 1) { $parts[1].Trim() -split '\s+' } else { @() }
  $src = Join-Path $luaRoot $relpath
  if (-not (Test-Path $src)) { Write-Host "ERROR: vanilla file missing: $src" -ForegroundColor Red; $rc = 1; continue }
  $destAbs = Join-Path (Get-Location) (Join-Path $Out $relpath)
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destAbs) | Out-Null
  $acc = New-Object System.Collections.Generic.List[string]
  foreach ($fn in $fns) {
    $r = Get-Fn $src $fn
    if ($r.found) { $acc.AddRange($r.lines) }
    else {
      Write-Host "WARN: function '$fn' not found in $relpath (refactored away?)" -ForegroundColor Yellow
      $acc.Add("-- MISSING: $fn (not found at extract time)"); $acc.Add(''); $rc = 1
    }
  }
  # LF-terminated to keep the committed baseline identical to the bash twin's output.
  [System.IO.File]::WriteAllText($destAbs, (($acc -join "`n") + "`n"))
  Write-Host "wrote $(Join-Path $Out $relpath)"
}
exit $rc
