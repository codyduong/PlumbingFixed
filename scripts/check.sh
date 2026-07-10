#!/usr/bin/env bash
# Lint + type-check the mod's Lua. Mirrors .github/workflows/lua.yml.
# Preferred: `mise run check`   Direct: `bash scripts/check.sh`
set -euo pipefail
cd "$(dirname "$0")/.."

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' not found. $2" >&2; exit 127; }; }
need stylua        "Run 'mise install' (or: cargo install stylua --version 2.3.1)."
need emmylua_check "Run 'mise install' (or: cargo install emmylua_check --version 0.18.0)."

failed=0
echo "==> stylua --check --syntax Lua51 ."
stylua --check --syntax Lua51 . || failed=1
echo "==> emmylua_check . -c .emmyrc.json"
emmylua_check . -c .emmyrc.json || failed=1

if [ "$failed" -ne 0 ]; then echo "Lua checks FAILED." >&2; exit 1; fi
echo "All Lua checks passed."
