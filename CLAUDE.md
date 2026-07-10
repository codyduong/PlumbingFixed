# CLAUDE.md — PlumbingFixed

Project Zomboid **Build 42** mod. Fixes vanilla plumbed water fixtures (sinks, bathtubs,
washers) so a fixture draws water **equally from every barrel in the 3×3 grid above it**
instead of draining one barrel at a time. It also purifies tainted water and keeps the
wash/drink/fill context menus working against the pooled supply.

This file is the always-read entry point. Deeper detail lives in [`docs/`](docs/):
[ARCHITECTURE](docs/ARCHITECTURE.md) · [TESTING](docs/TESTING.md) ·
[RELEASING](docs/RELEASING.md) · [UPDATING-PZ](docs/UPDATING-PZ.md).

---

## ⚠️ Golden rule: do not trust a Lua global by its name

PZ exposes Java to Lua. **A method's name does not tell you where it is authoritative.**
Some state is client-only, some server-only, some synced — and getters can silently return
stale/false values on the "wrong" side. This is the #1 source of bugs in this mod.

Real landmines already hit here:
- `IsoObject:hasExternalWaterSource()` is **unreliable on the server** — the timed action
  uses `getUsesExternalWaterSource()` instead (see `PFTakeWaterAction.lua:updateUse`).
- `isPlumbed()` (our util) folds together `hasExternalWaterSource()` **OR**
  `getUsesExternalWaterSource()` **OR** `modData.canBeWaterPiped == false`. Which one is
  correct depends on **which side the caller runs on** (client context menu vs server timed
  action). There is an in-progress investigation here — see [KNOWN LANDMINES](#known-landmines).

**Before overriding or relying on any vanilla API, verify it three ways:**
1. **Which vanilla dir defines the caller?** `client/` runs on the client, `server/` on the
   server, `shared/` on both. Read the real source at
   `F:\steamlibrary\steamapps\common\ProjectZomboid\media\lua\{client,server,shared}`.
2. **What does the Java actually do?** Decompile and read it: `mise run decompile` →
   `.decompiled/`. Check whether the method mutates authoritative state, reads a synced
   field, or is a client-only convenience.
3. **Test both paths.** Reproduce in **single-player AND a local dedicated server** — a fix
   that works in SP can be wrong in MP because isValid/updateUse/complete may run server-side
   while the context menu that built the action ran client-side. See [docs/TESTING.md](docs/TESTING.md).

Never "fix" a symptom by swapping predicates until green. Find the authoritative source first.

---

## Toolchain (mise)

All tooling is pinned in [`mise.toml`](mise.toml). One-time: install
[mise](https://mise.jdx.dev) (`winget install jdx.mise`), then:

```
mise install          # provisions stylua 2.3.1, emmylua_check 0.18.0, Temurin JDK 17 (decompiler)
mise tasks            # list workflows;  `mise run <task> --help` shows a task's arguments
```

| Task | What it does |
|------|--------------|
| `mise run check` | stylua + emmylua_check (mirrors CI `.github/workflows/lua.yml`) |
| `mise run decompile` | Decompile the installed game into `.decompiled/` for analysis |
| `mise run bump 1.3.14` | Set `modversion` in both `mod.info` files |
| `mise run package v1.3.14` | Validate versions + assemble `./PlumbingFixed` |
| `mise run deploy` | Package + sync into the local Zomboid Workshop dir for testing |
| `mise run publish <test\|prod> "note"` | Upload to Steam Workshop via steamcmd (required test/prod target; run it yourself; Steam Guard) |

Each task has a **cross-platform** implementation — a POSIX `scripts/<name>.sh` (used on
Unix via `run`) and a PowerShell `scripts/<name>.ps1` (used on Windows via `run_windows`) —
so you can also run either directly (`bash scripts/<name>.sh` / `pwsh -File scripts/<name>.ps1`).
Task arguments are declared with mise's `usage` spec, so `mise run bump --help` documents them.
`emmylua_check`/`stylua` must be on PATH (that's what `mise install` guarantees).

**Secrets / local overrides:** `cp mise.local.toml.example mise.local.toml` and set
`STEAM_USER` (and optional `PZ_HOME`, `ZOMBOID_DIR`, item ids). `mise.local.toml` is
git-ignored and auto-loaded with higher precedence; its `[env]` feeds `mise run publish`.

---

## Layout & override architecture

Mod content lives under `Contents/mods/PlumbingFixed/` with PZ's multi-build layout:
- `42/media/lua/...` — the real mod (Build 42).
- `41/` — a **stub** (`mod.info` + `poster.png` only, no Lua) for B41 compatibility metadata.
- `common/` — empty placeholder (`.gitkeep`).

Steam Workshop page metadata is **source-controlled** under `workshop/`:
`workshop/workshop.conf` (flat `key=value`: title/tags/visibility/ids/preview) and
`workshop/description.bbcode` (the BBCode description, read verbatim). `scripts/publish-workshop.*`
turn these into the steamcmd VDF. **steamcmd is the only publish path** — the in-game uploader
(which read the now-removed `workshop.txt`) is no longer supported. See [docs/RELEASING.md](docs/RELEASING.md).

Lua roots under `42/media/lua/`:

| File | Side | Overrides / provides |
|------|------|----------------------|
| `shared/PlumbingFixed/utils.lua` | shared | core: `getPlumbedSources`, `getPlumbedWaterAmount`, `getPlumbedWaterCapacity`, `getWaterAmount`, `removeWaterTopDown`, `findWaterObject`, `isPlumbed` |
| `shared/PlumbingFixed/TimedActions/PFTakeWaterAction.lua` | shared | `ISTakeWaterAction:{isValid,updateUse,transferFromMax,new}` |
| `shared/PlumbingFixed/TimedActions/PFWashClothing.lua` | shared | `ISWashClothing:{isValid,complete}` |
| `client/ISUI/PFWorldObjectContextMenu.lua` | client | `ISWorldObjectContextMenu.*` menu builders + `Events.OnFillWorldObjectContextMenu` |
| `client/DebugUIs/Scenarios/DebugPlumbing.lua` | client | the `DebugPlumbing` test scenario (barrels + plumbed sink) |
| `server/PlumbingFixedServer.lua` | server | `require`s the shared timed actions on the server |

**Override pattern** (used everywhere): `require("lua/.../ISFoo")` to load vanilla, capture
originals in a local `original = { method = ISFoo.method }` table, then reassign
`function ISFoo:method() ... end`. `new` is captured in its own local (`originalNew`) —
putting it in the table breaks metatable resolution. Because we mutate the **global table
in place**, every vanilla caller transparently gets the patched behavior. Load order (mod
after vanilla) is what makes this work. Full walkthrough + the water algorithm in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

---

## Source-of-truth paths

- **Vanilla Lua** (what we override): `F:\steamlibrary\steamapps\common\ProjectZomboid\media\lua\{client,server,shared}` — this is the *installed* build (currently 42.x unstable).
- **Java type stubs** (EmmyLua): `Umbrella/` submodule, pinned to the matching game tag (now `42.19.0`). Signatures only — not behavior.
- **Decompiled Java** (behavior/authority): `.decompiled/` via `mise run decompile` (gitignored).

Keep these three aligned with the installed build. When the game updates, follow
[docs/UPDATING-PZ.md](docs/UPDATING-PZ.md).

---

## Conventions

- **Formatting:** stylua, **Lua 5.1**, 2-space indent (`.stylua.toml`). Build output is
  ignored via `.styluaignore`.
- **Types:** EmmyLua annotations (`---@param`, `---@return`, `---@class`, `---@cast`);
  config in `.emmyrc.json`. `mise run check` must pass before commit (CI enforces it).
- **Naming:** mod-owned globals/files are prefixed `PF` / `getPlumbed*`. Overrides keep the
  vanilla name so callers resolve to us.
- **Fluid containers are Java-managed:** temp containers from
  `moveFluidToTemporaryContainer` / `FluidContainer.CreateContainer()` must be disposed with
  `FluidContainer.DisposeContainer(...)`. Leaks are silent.
- **Commits:** [Conventional Commits](https://www.conventionalcommits.org) —
  `type(scope): summary` (`feat`, `fix`, `docs`, `chore`, `build`, `ci`, `refactor`, `perf`,
  `test`). Keep the subject imperative and concise; use the body for a short bullet list when
  useful. No `Co-Authored-By` trailer (owner takes attribution).

## Dev loop

1. Edit Lua under `Contents/mods/PlumbingFixed/42/media/lua/`.
2. `mise run check` (lint + types).
3. `mise run deploy` (sync to `~/Zomboid/Workshop/PlumbingFixed`).
4. Launch PZ → enable the mod → load the **DebugPlumbing** scenario; verify multi-barrel
   draw, drink, wash, fill. Then repeat on a **local dedicated server** for MP. See
   [docs/TESTING.md](docs/TESTING.md).

## Release / update

- Cut a release: [docs/RELEASING.md](docs/RELEASING.md) (bump → package → tag → GitHub
  release via CI → `mise run publish`).
- Move to a new PZ build: [docs/UPDATING-PZ.md](docs/UPDATING-PZ.md) (bump Umbrella,
  re-decompile, diff overridden functions, reconcile, retest).

---

## Known landmines

- **`hasExternalWaterSource()` vs `getUsesExternalWaterSource()` vs `isPlumbed()`** — an
  active, unresolved investigation (see the current uncommitted diff in
  `PFTakeWaterAction.lua` and `PFWorldObjectContextMenu.lua`). Do **not** finalize a
  predicate swap without verifying authority per side (§Golden rule). This is deferred code
  work, not a scaffolding change.
- **Fluid mixing:** plumbed barrels currently have all fluids converted to water on draw
  (`removeWaterTopDown` purifies tainted→water and pools everything). Storing non-water
  (gasoline/bleach) above a plumbed fixture is a known inadvertent behavior — see
  `workshop/description.bbcode`.
- **B41 stub ships 42 media:** `scripts/package.*` promote `42/media` into the mod root that
  the B41 `mod.info` points at, so a real B41 client would load B42 Lua (likely broken).
  Treated as an open decision (keep the stub vs drop B41), not changed yet.
- **`getModData().canBeWaterPiped == false`** is how the debug scenario marks a sink plumbed
  (`DebugPlumbing.lua`); real in-game plumbing sets `usesExternalWaterSource`. Test both.
