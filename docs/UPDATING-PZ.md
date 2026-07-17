# Updating to a new Project Zomboid build

Run this when PZ ships a new build and we want to target it. The mod's override surface is
**Java behavior intercepted at the Lua dispatch seam** — the six fluid primitives patched
onto `IsoObject`/`IsoThumpable` in `PFPooledPrimitives.lua`, the native fixture menu
post-processed by `PFPooledMenuFixups.lua`, and the washer machinery compensated by
`PFWasherPooling.lua` — plus shared utils that read vanilla state. No vanilla Lua function
ships as a modified copy, so reconciling an update means **diffing the decompiled Java (and
the vanilla Lua callers) between builds**, not merging function bodies.

> History: through v2.1.0 the mod shipped modified copies of three vanilla timed actions
> (`ISTakeWaterAction`, `ISWashClothing`, `ISCleanBandage`) and kept a per-build vendored
> baseline (`vendor/pz/` + `mise run vanilla-extract`/`vanilla-diff`) as the ancestor for
> 3-way merges on update. The v2.1.0 switch to patching the fluid primitives removed every
> forked vanilla function, so the baseline and its tooling were retired — they live in git
> history if the mod ever forks vanilla Lua again. Steam offers no per-version depots
> (only `public`/`unstable`/`outdatedunstable` branches), so the local snapshots below are
> the only reliable old-build reference.

## 0. Confirm the installed build

- Don't trust `%USERPROFILE%\Zomboid\version.txt` — it only rewrites when the game **launches**.
  Check the real install: Steam → PZ → Properties → Betas (branch) and the file dates of
  `F:\steamlibrary\steamapps\common\ProjectZomboid\projectzomboid.jar`, or the Steam
  `appmanifest_108600.acf` (`buildid`, `LastUpdated`, `BetaKey`). Launch once to refresh
  `version.txt` if you want the exact `42.x.y` string.
- The vanilla Lua we intercept is whatever is installed at `...\ProjectZomboid\media\lua`.

## 1. Snapshot the old build BEFORE Steam updates it

The update process needs the *previous* build to diff against, and Steam overwrites the
install in place. While the old build is still installed:

```
Rename-Item .decompiled .decompiled-<old-build>          # e.g. .decompiled-42.19
Copy-Item F:\steamlibrary\steamapps\common\ProjectZomboid\media\lua `
          .decompiled-<old-build>\media-lua -Recurse     # the Lua callers, same snapshot
```

Both stay local (`.decompiled*/` is gitignored). If Steam already updated and you have no
old decompile, the previous build is only recoverable via SteamDB manifest IDs +
DepotDownloader with a logged-in owning account — avoid needing that.

## 2. Align the type stubs (Umbrella submodule)

```
git -C Umbrella fetch --tags
git -C Umbrella checkout <matching-tag>   # e.g. 42.19.0
git add Umbrella
```
Pick the Umbrella tag matching the installed build. `mise run check` uses these stubs, so a
mismatch produces false type errors.

## 3. Re-decompile the new build

```
mise run decompile        # -> .decompiled/ (bump -DecompilerVersion if needed)
```
This is the authoritative source for **behavior** (client vs server vs synced) — signatures
from Umbrella are not enough. This is also where you confirm whether a menu/handler still
lives in Lua or has moved into Java for this build.

## 4. Diff the override surface

```
git diff --no-index .decompiled-<old-build>/source .decompiled/source -- <file>
```

Files that matter, mapped to what they can break:

- `zombie/iso/IsoObject.java` — the six patched primitives (`getFluidAmount`, `hasFluid`,
  `hasWater`, `useFluid`, `moveFluidToTemporaryContainer`, `transferFluidTo`) and the
  external-water-source state (`PFPooledPrimitives.lua`, `PFUtils.lua`).
- `zombie/iso/objects/IsoThumpable.java` — the same primitives on player-built objects.
- `zombie/iso/ISWorldObjectContextMenuLogic.java` — the native fixture menu whose options
  and tooltips `PFPooledMenuFixups.lua` rewrites (option names/params are matched by
  handler identity) and `PFConnectedMatrixPanel.lua` docks against.
- `zombie/iso/objects/IsoClothingWasher.java` (and dryer) — the Java-side water draws that
  `PFWasherPooling.lua` redistributes via `OnWaterAmountChange`.
- `media/lua` timed actions (diff the snapshot against the new install) — we don't fork
  them, but they are the Lua dispatch through which our patched primitives are reached:
  confirm they still call the fixture's methods (`obj:useFluid(...)` etc.) rather than a
  new Java path.

Three outcomes per spot:

- **No diff** — nothing to do.
- **Diff** — vanilla behavior changed; reconcile the affected guard/util/post-processor.
  Verify authority per side in the new `.decompiled/` (golden rule in
  [CLAUDE.md](../CLAUDE.md)) — never adjust a predicate just until it goes green.
- **Seam moved** — a caller left Lua for Java (the B42.19 menu is the precedent). That's a
  re-derivation: find where the behavior went and what seam replaces it; expect to extend
  the post-processor/event side rather than the primitives.

## 5. Update the build markers (only if the minimum target changed)

If we now require the newer build, update the PZ-build strings (these are **not** the mod
semver):
- `Contents/mods/PlumbingFixed/42/mod.info` → `name=PlumbingFixed (B42.<x>)` and
  `versionMin=`/`versionMax=` if applicable.
- `workshop/workshop.vdf` → the `title=... [B42.<x>+]` and "TESTED/VERIFIED WORKING IN
  B42.<x>" lines.

## 6. Test, clean up, release

- `mise run check`, then a full SP + MP pass per [TESTING.md](TESTING.md), including the
  unplumbed regression case.
- Delete `.decompiled-<old-build>/` once the update is reconciled and released.
- Then follow [RELEASING.md](RELEASING.md) (bump semver → tag → GitHub release → publish).
