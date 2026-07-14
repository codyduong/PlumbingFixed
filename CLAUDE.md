# CLAUDE.md — PlumbingFixed

Project Zomboid **Build 42** mod. Fixes vanilla plumbed water fixtures (sinks, bathtubs,
washers) so a fixture draws water **equally from every barrel in the 3×3 grid above it**
instead of draining one barrel at a time. It also purifies tainted water and keeps the
wash/drink/fill context menus working against the pooled supply.

This file is the always-read entry point. Deeper detail lives in [`docs/`](docs/):
[ARCHITECTURE](docs/ARCHITECTURE.md) · [TESTING](docs/TESTING.md) ·
[RELEASING](docs/RELEASING.md) · [UPDATING-PZ](docs/UPDATING-PZ.md) ·
[LESSONS-LEARNED](docs/LESSONS-LEARNED.md).

---

## ⚠️ Golden rule: do not trust a Lua global by its name

PZ exposes Java to Lua. **A method's name does not tell you where it is authoritative.**
Some state is client-only, some server-only, some synced — and getters can silently return
stale/false values on the "wrong" side. This is the #1 source of bugs in this mod.

Real landmines already hit here:
- `IsoObject:hasExternalWaterSource()` is **unreliable on the server** — the mod gates on
  `getUsesExternalWaterSource()` instead (via `isMultiSource` in `utils.lua`, the guard for
  every patched primitive in `PFPooledPrimitives.lua`).
- `isPlumbed()` (our util) folds together `getUsesExternalWaterSource()` **OR**
  `modData.canBeWaterPiped == false`. Which predicate is correct depends on **which side the
  caller runs on**. This is now settled: every pooled code path guards through
  `isMultiSource()` → `getUsesExternalWaterSource()` (server-authoritative).
  See [KNOWN LANDMINES](#known-landmines).

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
| `mise run package v1.3.14` | Validate versions + assemble `dist/PlumbingFixed` |
| `mise run deploy <client\|server\|all>` | Package + sync (client=Workshop dev dir, server=`.testhost` mods dir) |
| `mise run testhost [--reset]` | Ephemeral local dedicated server for MP testing (state in `.testhost/`) |
| `mise run publish <test\|prod> "note"` | Upload to Steam Workshop via steamcmd (required test/prod target; run it yourself; Steam Guard) |

Each task shells out to a PowerShell `scripts/<name>.ps1`, which you can also run directly
(`pwsh -File scripts/<name>.ps1`). The one exception is `scripts/package.sh` — a CI-only
twin of `package.ps1` for the Linux release job; keep the two identical when touching packaging.
Task arguments are declared with mise's `usage` spec, so `mise run bump --help` documents them.
`emmylua_check`/`stylua` must be on PATH (that's what `mise install` guarantees).

**Secrets / local overrides:** `cp mise.local.toml.example mise.local.toml` and set
`STEAM_USERNAME` + `STEAM_PASSWORD` (and optional `PZ_HOME`, `ZOMBOID_DIR`, item ids).
`mise.local.toml` is git-ignored and auto-loaded with higher precedence; its `[env]` feeds
`mise run publish`. **`STEAM_PASSWORD` is age-encrypted and mise decrypts it transparently —
never decrypt, print, or trial-and-error it, and move `mise.local.toml` out of the repo tree
before agent-driven mise work.** See [docs/LESSONS-LEARNED.md](docs/LESSONS-LEARNED.md).

---

## Layout & override architecture

Mod content lives under `Contents/mods/PlumbingFixed/` with PZ's multi-build layout:
- `42/media/lua/...` — the real mod (Build 42).
- `41/` — a **stub** (`mod.info` + `poster.png` only, no Lua) for B41 compatibility metadata.
- `common/` — empty placeholder (`.gitkeep`).

Steam Workshop page metadata is **source-controlled** as `workshop/workshop.vdf` — a steamcmd
KeyValues file stored **verbatim** (title/description/tags/appid). `scripts/publish-workshop.*`
only substitute the dynamic fields (`{{PUBLISHEDFILEID}}` and `{{VISIBILITY}}` per target —
prod public, test unlisted — `{{CONTENTFOLDER}}`/`{{PREVIEWFILE}}` built paths,
`{{CHANGENOTE}}`) — no bbcode/conf conversion. **steamcmd is the only publish path.**
See [docs/RELEASING.md](docs/RELEASING.md).

Lua roots under `42/media/lua/`:

| File | Side | Overrides / provides |
|------|------|----------------------|
| `shared/PlumbingFixed/PFUtils.lua` | shared | core: `getPlumbedSources`, `getPlumbedWaterAmount` (water-category), `getPlumbedFluidAmount` / `hasPlumbedWater` (vanilla-parity reads), `getPlumbedWaterCapacity`, `getWaterAmount`, `removeWaterTopDown`, `findWaterObject`, `isPlumbed` |
| `shared/PlumbingFixed/DebugRig.lua` | shared | `PFDebugRig`: buildable/clearable test rig (3×3 + 4 empty barrels + sink + stairs), reused by the scenario, the MP spawn command, and SP spawning |
| `shared/PlumbingFixed/PFPooledPrimitives.lua` | shared | patches the six fixture fluid primitives (`getFluidAmount`, `hasFluid`, `hasWater`, `useFluid`, `moveFluidToTemporaryContainer`, `transferFluidTo`) via `__classmetatables` on `IsoObject` + `IsoThumpable`, guarded by `isMultiSource`; the vanilla timed actions run untouched and pool through these |
| `client/PlumbingFixedClient.lua` | client | `require`s the shared primitives patch on the client |
| `client/ISUI/PFPooledMenuFixups.lua` | client | `OnFillWorldObjectContextMenu` post-processor: rewrites Drink/Wash tooltips + Wash grey-out to pooled totals; debug-mode "Modified by Plumbing Fixed" marker |
| `client/DebugUIs/PFPlumbedConnectedMenu.lua` | client | debug "Connected Sources" inspector + "Configure Barrel Fluids..." |
| `client/DebugUIs/PFBarrelFluidWindow.lua` | client | per-barrel fluid editor window (debug; MP edits go through the server) |
| `client/DebugUIs/PFTestRigMenu.lua` | client | mod option (PZAPI.ModOptions) + "Spawn PlumbingFixed Test Rig" debug context option |
| `client/DebugUIs/Scenarios/DebugPlumbing.lua` | client | the `DebugPlumbing` test scenario (two rigs via `PFDebugRig` + loadout) |
| `server/PlumbingFixed/PFWasherPooling.lua` | server | event-driven (`OnWaterAmountChange` + `EveryOneMinute`) pooling for running washers, whose draws happen Java-side and bypass the Lua primitives |
| `server/PlumbingFixedServer.lua` | server | `require`s the shared primitives patch on the server; `OnClientCommand` handlers for rig spawn / barrel fluid edits (capability-gated) |

**Patch pattern**: `PFPooledPrimitives.lua` captures each class's six vanilla fluid
methods into a local,
then reassigns the entries of the class's method table in place
(`__classmetatables[Class].__index`, which Kahlua dispatches userdata calls through). The
overrides are one-line delegates to the pooled utils, which self-guard: not
`isMultiSource` → call the vanilla method as `obj.__PFraw:method(...)` — a proxy bound to
the object by a function `__index` on the method table's metatable (PZ's
`KahluaThread.tableget` passes the **original receiver** to a function `__index` anywhere
in the lookup chain, and only consults it after the method table misses, so real dispatch
never pays for it). Kahlua **flattens
inherited methods into each concrete class's table**, so `IsoObject` and `IsoThumpable`
are patched separately. This covers every *Lua* caller (vanilla actions and third-party mods alike);
Java-internal callers bypass it — hence `PFPooledMenuFixups` (native menu) and
`PFWasherPooling` (washer machinery). Full walkthrough + the water algorithm in
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

- **`hasExternalWaterSource()` vs `getUsesExternalWaterSource()` vs `isPlumbed()`** — resolved:
  every patched primitive in `PFPooledPrimitives.lua` guards on `isMultiSource()` →
  `getUsesExternalWaterSource()`, the server-authoritative synced flag (per `IsoObject.java`:
  persisted to save bits + network-synced). `hasExternalWaterSource()` is a client-only
  transient that reads false on the server. `isPlumbed()` (which also folds in the
  `canBeWaterPiped` modData hack) feeds that guard and the shared `utils.lua` scan. (B42.19
  moved the fixture menu to native Java, which removed the client-side menu predicate we
  previously had to reconcile against the action-side one.) Still verify authority per side
  (§Golden rule) before any future predicate change.
- **Lua-dispatch only:** the `__classmetatables` patch intercepts Lua callers exclusively. Java
  code calling `getFluidAmount()`/`useFluid()` internally (native context menu, washer update
  loop, `hasFluid`/`hasWater` bodies) never sees it — that's why `hasFluid`/`hasWater` are
  patched explicitly and why `PFPooledMenuFixups`/`PFWasherPooling` must stay.
- **Fluid mixing:** non-water sources are **excluded from the pool, not disqualifying** —
  `isViableWaterSource` (`utils.lua`) gates every draw and water figure, and
  `getWaterAmount` sums by `FluidCategory.Water` membership (read from each fluid's
  `Categories` in `fluids.txt`, so new water-category fluids are picked up automatically —
  Water/Tainted/Carbonated as of 42.19); tainted water is purified to Water on draw. Totals
  (`getPlumbedFluidAmount`/`getPlumbedWaterCapacity`) stay deliberately unfiltered, so they
  diverge from `getPlumbedWaterAmount` when non-water sits in a barrel. The holistic end
  state (indiscriminate mixing + per-barrel opt-out) is tracked in
  [docs/FLUID-MIXING.md](docs/FLUID-MIXING.md) — keep the `FUTURE(fluid-mixing)` stubs
  aligned with it.
- **B41 stub ships 42 media:** `scripts/package.*` promote `42/media` into the mod root that
  the B41 `mod.info` points at, so a real B41 client would load B42 Lua (likely broken).
  Treated as an open decision (keep the stub vs drop B41), not changed yet.
- **`getModData().canBeWaterPiped == false`** is how the debug scenario marks a sink plumbed
  (`DebugPlumbing.lua`); real in-game plumbing sets `usesExternalWaterSource`. Test both.
