#!/usr/bin/env pwsh
# Lint + type-check the mod's Lua. Mirrors .github/workflows/lua.yml.
# Preferred: `mise run check`   Direct: `pwsh -NoProfile -File scripts/check.ps1`

$ErrorActionPreference = 'Stop'
# Native (exe) non-zero exits should NOT throw here — we inspect $LASTEXITCODE ourselves
# so both checks always run. (Guard for PS 7.3+ where this defaults to $true.)
$PSNativeCommandUseErrorActionPreference = $false

# Run from repo root regardless of where the script was invoked from.
Set-Location (Split-Path -Parent $PSScriptRoot)

function Test-Tool {
  param([string]$Name, [string]$Hint)
  if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: '$Name' not found. $Hint" -ForegroundColor Red
    exit 127
  }
}

Test-Tool stylua        "Run 'mise install' (or: cargo install stylua --version 2.3.1)."
Test-Tool emmylua_check "Run 'mise install' (or: cargo install emmylua_check --version 0.18.0)."

$failed = $false

Write-Host "==> stylua --check --syntax Lua51 ." -ForegroundColor Cyan
stylua --check --syntax Lua51 .
if ($LASTEXITCODE -ne 0) { $failed = $true }

Write-Host "==> emmylua_check . -c .emmyrc.json" -ForegroundColor Cyan
emmylua_check . -c .emmyrc.json
if ($LASTEXITCODE -ne 0) { $failed = $true }

if ($failed) {
  Write-Host "Lua checks FAILED." -ForegroundColor Red
  exit 1
}
Write-Host "All Lua checks passed." -ForegroundColor Green
