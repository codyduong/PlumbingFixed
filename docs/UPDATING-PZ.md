# Updating to a new Project Zomboid build

Run this when PZ ships a new build and we want to target it. The mod **overrides vanilla Lua
by name**, so a new build can silently change a function we patched — this runbook re-aligns
the three sources of truth and diffs what changed.

## 0. Confirm the installed build

- Don't trust `%USERPROFILE%\Zomboid\version.txt` — it only rewrites when the game **launches**.
  Check the real install: Steam → PZ → Properties → Betas (branch) and the file dates of
  `F:\steamlibrary\steamapps\common\ProjectZomboid\projectzomboid.jar`, or the Steam
  `appmanifest_108600.acf` (`buildid`, `LastUpdated`, `BetaKey`). Launch once to refresh
  `version.txt` if you want the exact `42.x.y` string.
- The vanilla Lua we override is whatever is installed at `...\ProjectZomboid\media\lua`.

## 1. Align the type stubs (Umbrella submodule)

```
git -C Umbrella fetch --tags
git -C Umbrella checkout <matching-tag>   # e.g. 42.19.0
git add Umbrella
```
Pick the Umbrella tag matching the installed build. `mise run check` uses these stubs, so a
mismatch produces false type errors.

## 2. Re-decompile the game

```
mise run decompile        # -> .decompiled/ (bump -DecompilerVersion if needed)
```
This is the authoritative source for **behavior** (client vs server vs synced) — signatures
from Umbrella are not enough.

## 3. Diff the functions we override

For each symbol in [ARCHITECTURE.md](ARCHITECTURE.md) → "What overrides what", compare our
override against the **new** vanilla source at `...\ProjectZomboid\media\lua\...`:

- `ISTakeWaterAction` — `lua/shared/TimedActions/ISTakeWaterAction.lua`
- `ISWashClothing` — `lua/shared/TimedActions/ISWashClothing.lua`
- `ISWorldObjectContextMenu` — `lua/client/ISUI/ISWorldObjectContextMenu.lua`

Look for: changed method signatures, new/removed fields our code reads, new early-returns,
and any fluid/container API changes. Where behavior/authority is unclear, read `.decompiled/`.
Re-check every entry in [CLAUDE.md](../CLAUDE.md) → "Known landmines" against the new source.

## 4. Reconcile the overrides

Update our Lua to match the new vanilla shape while preserving the pooled-water behavior.
Keep the "early-return to `original` when not plumbed" guard so unplumbed flows stay vanilla.

## 5. Update the build markers (only if the minimum target changed)

If we now require the newer build, update the PZ-build strings (these are **not** the mod
semver):
- `Contents/mods/PlumbingFixed/42/mod.info` → `name=PlumbingFixed (B42.<x>)` and
  `versionMin=`/`versionMax=` if applicable.
- `workshop/workshop.conf` → `title=... [B42.<x>+]`, and `workshop/description.bbcode` → the
  "TESTED/VERIFIED WORKING IN B42.<x>" line.

## 6. Test + release

- Full SP + MP pass per [TESTING.md](TESTING.md), including the unplumbed regression case.
- Then follow [RELEASING.md](RELEASING.md) (bump semver → tag → GitHub release → publish).
