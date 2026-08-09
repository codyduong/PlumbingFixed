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
- `modData.canBeWaterPiped` sounds like a plumbed-state flag but tracks **Plumb-option
  eligibility** (`false` = "plumb action consumed", not "is plumbed"). `isPlumbed()` (our
  util) originally folded it in as an OR alongside `getUsesExternalWaterSource()`; the
  disjunct was redundant (vanilla always writes both together) and a false-positive trap,
  so it was dropped — `isPlumbed()` now reads `getUsesExternalWaterSource()` alone, and
  every pooled code path guards through `isMultiSource()` → `getUsesExternalWaterSource()`
  (server-authoritative). See [KNOWN LANDMINES](#known-landmines).

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

All tooling is pinned in [`mise.toml`](mise.toml). The actual scripts live in
[`tooling/`](tooling/) — a **git submodule** sourced from
[Project-Zomboid-Template](https://github.com/codyduong/Project-Zomboid-Template), pinned to
a tag (currently `v0.2.0`), not tracking `main`. `mise.toml` here is a thin per-repo shim
over it — a mod-agnostic script library shared across mod repos, factored out so toolchain
fixes reach every mod that syncs. One-time: install
[mise](https://mise.jdx.dev) (`winget install jdx.mise`), then:

```
git submodule update --init
mise install          # provisions emmylua_formatter 0.24.0 (luafmt), emmylua_check 0.18.0, Temurin JDK 17 (decompiler)
mise tasks            # list workflows;  `mise run <task> --help` shows a task's arguments
```

| Task | What it does |
|------|--------------|
| `mise run check` | luafmt + emmylua_check (mirrors CI `.github/workflows/lua.yml`) |
| `mise run decompile 42.20.2` | Decompile the installed game into `.decompiled/42.20.2/` for analysis |
| `mise run bump 1.3.14` | Set `modversion` in both `mod.info` files |
| `mise run package v1.3.14` | Validate versions + assemble `dist/PlumbingFixed` |
| `mise run deploy <client\|server\|all>` | Package + sync (client=Workshop dev dir, server=`.testhost` mods dir) |
| `mise run testhost [--reset]` | Ephemeral local dedicated server for MP testing (state in `.testhost/`) |
| `mise run publish <test\|prod> "note"` | Upload to Steam Workshop via steamcmd (required test/prod target; run it yourself; Steam Guard) |
| `mise run sync-template` | Pull the latest `tooling/` (Project-Zomboid-Template) commit; review + commit the bump |
| `mise run sync-umbrella [version]` | Pin the `Umbrella` type-stub submodule to a PZ build tag (latest available tag if omitted) |

Every task is cross-platform: each `tooling/scripts/<name>` has both a `.ps1` and a `.sh`
twin, and `mise.toml` picks the right one per OS (`run` = the sh command, used on
Linux/macOS; `run_windows` = the pwsh command, used on Windows — mise's own per-OS task
mechanism). Both are also runnable directly (`pwsh -File tooling/scripts/<name>.ps1` /
`bash tooling/scripts/<name>.sh`). `publish` additionally needs **`jq`** on Linux/macOS (to
read `workshop/item-ids.json`); `decompile`/`testhost` auto-detect the platform's default
Steam install path (override with `$PZ_HOME` / pass a path, same as Windows). Task arguments
are declared with mise's `usage` spec, so `mise run bump --help` documents them.
`emmylua_check`/`luafmt` must be on PATH (that's what `mise install` guarantees).

**Keeping `tooling/` in sync / diverging**: `mise run sync-template` updates the submodule
and stages the bump for review. To pin/skip, just don't run it. To fully vendor and drop the
submodule link: `git submodule deinit tooling && git rm tooling`, then copy the scripts in
directly — see the template's
[docs/USING-THIS-TEMPLATE.md](https://github.com/codyduong/Project-Zomboid-Template/blob/main/docs/USING-THIS-TEMPLATE.md).
Do **not** edit `tooling/` in place here — changes belong in the template repo. `.emmyrc.json`,
`.luafmt.toml`, `.vscode/`, `.claude/settings.json`, `mise.toml`, and the doc files are
**not** submoduled (position/name-sensitive or meant to diverge per mod) — they were
one-time-scaffolded from the template and are owned by this repo from here on.

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
KeyValues file stored **verbatim** (title/description/tags/appid). `tooling/scripts/publish-workshop.*`
only substitute the dynamic fields (`{{PUBLISHEDFILEID}}` and `{{VISIBILITY}}` per target —
prod public, test unlisted — `{{CONTENTFOLDER}}`/`{{PREVIEWFILE}}` built paths,
`{{CHANGENOTE}}`) — no bbcode/conf conversion. **steamcmd is the only publish path.**
See [docs/RELEASING.md](docs/RELEASING.md).

Lua roots under `42/media/lua/`:

| File | Side | Overrides / provides |
|------|------|----------------------|
| `shared/PlumbingFixed/PFUtils.lua` | shared | core: `getPlumbedSources`, `getPlumbedWaterAmount` (water-category), `getPlumbedFluidAmount` / `hasPlumbedWater` (vanilla-parity reads), `getPlumbedWaterCapacity`, `getWaterAmount`, `removeWaterTopDown`, `findWaterObject`, `isPlumbed` |
| `shared/PlumbingFixed/DebugRig.lua` | shared | `PFDebugRig`: buildable/clearable test rig (3×3 + 4 empty barrels + sink + stairs), reused by the scenario, the MP spawn command, and SP spawning |
| `shared/PlumbingFixed/PFPooledPrimitives.lua` | shared | patches the seven fixture fluid primitives (`getFluidAmount`, `hasFluid`, `hasWater`, `useFluid`, `moveFluidToTemporaryContainer`, `transferFluidTo`, `getFluidCapacity`) via `__classmetatables` on `IsoObject` + `IsoThumpable`, guarded by `isMultiSource`; the vanilla timed actions run untouched and pool through these |
| `client/PlumbingFixedClient.lua` | client | `require`s the shared primitives patch on the client |
| `client/ISUI/PFPooledMenuFixups.lua` | client | `OnFillWorldObjectContextMenu` post-processor: rewrites Drink/Wash tooltips + Wash grey-out to pooled totals; debug-mode "Modified by Plumbing Fixed" marker |
| `client/PFModOptions.lua` | client | single `PZAPI.ModOptions` page: grid-axis tickbox + pool-bar position combo; debug options attach to it behind their own gate |
| `client/ISUI/PFConnectedMatrixPanel.lua` | client | 3×3 connected-barrels grid docked to the world context menu (lives/dies with it): capacity-scaled fluid bars + a pooled-total bar (stacked per-fluid segments; left/right/top/bottom via mod option), hover = per-fluid tooltip + world-sprite highlight, debug/admin click opens the mod's per-barrel fluid editor (`PFBarrelFluidWindow`) for that barrel |
| `client/DebugUIs/PFBarrelFluidWindow.lua` | client | per-barrel fluid editor window (fluid picker + amount + Add/Empty + live fluid bar), opened by a matrix cell click; MP edits go through the server commands |
| `client/DebugUIs/PFTestRigMenu.lua` | client | debug "Spawn Test Rig" tickbox (on `PFModOptions`) + "Spawn PlumbingFixed Test Rig" debug context option |
| `client/DebugUIs/Scenarios/DebugPlumbing.lua` | client | the `DebugPlumbing` test scenario (two rigs via `PFDebugRig` + loadout) |
| `server/PlumbingFixed/PFWasherPooling.lua` | server | event-driven (`OnWaterAmountChange` + `EveryOneMinute`) pooling for running washers, whose draws happen Java-side and bypass the Lua primitives |
| `server/PlumbingFixedServer.lua` | server | `require`s the shared primitives patch on the server; `OnClientCommand` handlers for rig spawn + barrel fluid edits (capability-gated; the fluid edits additionally admin-gated) |

**Patch pattern**: `PFPooledPrimitives.lua` captures each class's seven vanilla fluid
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
- **Decompiled Java** (behavior/authority): `.decompiled/<version>/source` via `mise run
  decompile <version>` (gitignored); `.decompiled/<version>/media/lua` is the matching
  vanilla Lua snapshot, one folder per PZ build so two builds can be diffed side by side.

Keep these three aligned with the installed build. When the game updates, follow
[docs/UPDATING-PZ.md](docs/UPDATING-PZ.md).

---

## Conventions

- **Formatting:** luafmt (`emmylua_formatter`, same ecosystem as `emmylua_check`), **Lua
  5.1**, 2-space indent (`.luafmt.toml` holds only deviations from `luafmt
  --dump-default-config`). Build output is ignored via `.luafmtignore`. It also formats
  EmmyLua doc comments (tag alignment, `---@tag` normalization) — don't fight the aligner.
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
  transient that reads false on the server. `isPlumbed()` (a straight read of that flag)
  feeds that guard and the shared `utils.lua` scan. (B42.19
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
- **B41 stub ships 42 media:** `tooling/scripts/package.*` promote `42/media` into the mod root that
  the B41 `mod.info` points at, so a real B41 client would load B42 Lua (likely broken).
  Treated as an open decision (keep the stub vs drop B41), not changed yet.
- **`modData.canBeWaterPiped` is Plumb-eligibility, not plumbed-ness.** Vanilla sets it
  `true` when a player places a moved `waterPiped` fixture ("needs re-plumbing"; gates the
  native Plumb menu option), and `false` only in `ISPlumbItem:complete` / the server
  `plumbObject` command — in both cases on the same lines as `setUsesExternalWaterSource(true)`,
  so `false` never occurs without the authoritative flag. Absent means "never moved", which
  in a room pre-water-shutoff is an infinite *city-water* source (`IsoObject.isWaterInfinite`).
  `isPlumbed()` therefore ignores it and reads `getUsesExternalWaterSource()` alone (the OR
  on `canBeWaterPiped == false` was dropped as redundant + a false-positive trap);
  `DebugRig.lua` sets both flags to mirror vanilla plumbing exactly.
- **`require()` paths are relative to `media/lua/{shared,client,server}/` — never prefix
  with `lua/`.** Vanilla's `require(f)` (`LuaManager.java`) resolves `f` by prepending each
  registered search root (`media/lua/shared/`, `media/lua/client/`, ...) to the given path
  and looking up that exact concatenated string; it never strips a redundant leading `lua/`.
  `require("lua/client/ISUI/ISWorldObjectContextMenu")` (present in `PFConnectedMatrixPanel.lua`
  / `PFPooledMenuFixups.lua` from 2026-07-10 until fixed) therefore could never resolve —
  confirmed by grepping the entire vanilla Lua tree, which has zero `require("lua/...")`
  calls; every vanilla and mod require here uses the bare form, e.g. `require("ISUI/ISPanel")`.
  It logged a `require(...) failed` warning on every load but caused no functional breakage,
  because `LoadDirBase` always finishes loading every vanilla ("game") file before any mod
  file runs (`gameFiles` are prepended to `modFiles` in the combined load list) — so the
  vanilla global the `require` was reaching for already existed by the time our code ran.
  **Do not treat that as a safety net**: a missing/renamed vanilla file, a require target
  that isn't part of the always-loaded vanilla set, or a future loader change would turn the
  same mistake into a hard `attempt to index nil value` at the point of use instead of a
  harmless warning at load time. A `require(...) failed` warning in the log is always a real
  bug — chase it to a wrong path, not a false positive to silence.
- **`getFluidCapacity()` is patched, but deliberately not exposed through `PFUtils.lua`'s own
  non-multi-source fallbacks the way the original six are.** `PFPooledMenuFixups.lua`'s
  tooltip fixups compute pooled capacity via `getPlumbedWaterCapacity()` directly and never
  needed the primitive patched — it was added later, purely so third-party mods reading
  capacity through the standard Lua method (e.g. Take A Bath And Shower's own Drink/Fill
  tooltip calling `bathingObj:getFluidCapacity()` on a plumbed fixture) get a pooled figure
  consistent with the pooled `getFluidAmount()` they also read, instead of vanilla's
  single-barrel capacity paired against our pooled amount (which visibly showed amount >
  capacity). `getPlumbedWaterCapacity()`'s own single-source fallback (`PFUtils.lua`) calls
  `waterObject.__PFraw:getFluidCapacity()`, not `waterObject:getFluidCapacity()` — calling the
  patched method directly from inside the util that backs it would recurse.
