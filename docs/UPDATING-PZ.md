# Updating to a new Project Zomboid build

Run this when PZ ships a new build and we want to target it. The mod **overrides vanilla Lua
by name**, so a new build can silently change a function we patched. We defend against that with
a **committed vendored baseline** of the exact vanilla functions we override
(`vendor/pz/<VERSION>/`), so an update becomes a normal 3-way merge instead of a hand-copy.

## How the baseline works

- `vendor/pz/overrides.manifest` — the source of truth for *which* vanilla functions we shadow.
  TAB-separated: `<vanilla path under media/lua>\t<space-separated function names>`.
- `vendor/pz/VERSION` — the build the committed baseline was extracted from (e.g. `42.19`).
- `vendor/pz/<VERSION>/<path>` — verbatim vanilla source of just those functions. **Never
  hand-edit or reformat these** — they must stay byte-identical to vanilla so merges are clean
  (they're excluded from stylua/emmylua via `.styluaignore` + `.emmyrc.json`).
- `mise run vanilla-extract` regenerates the baseline from the installed game (idempotent).
- `mise run vanilla-diff` extracts the manifest functions from the **current** install and
  `git diff`s them against the committed baseline — one command to see upstream drift.

> The menu layer is **not** in the manifest. As of B42.19 the fixture water menu is built in
> native Java (`zombie/iso/ISWorldObjectContextMenuLogic`), which binds Drink/Fill/Wash/Clean
> options to our Lua handlers by name and routes them into the timed actions we already
> override. So we override at the **action seam**, not the menu — there is nothing to vendor
> for it. See [ARCHITECTURE.md](ARCHITECTURE.md).

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
from Umbrella are not enough. This is also where you confirm whether a menu/handler still lives
in Lua or has moved into Java for this build.

## 3. See what drifted

```
mise run vanilla-diff
```
This prints, per overridden function, how the newly-installed vanilla differs from our committed
baseline. Three cases:

- **No diff** — vanilla is unchanged; our override needs no reconciliation.
- **Diff** — vanilla changed; do a 3-way merge (step 4).
- **Function missing** (extract flags it) — vanilla refactored or removed it (e.g. moved into
  Java). This is a **re-derivation**: read `.decompiled/` to find where the behavior went and
  what seam replaces it, rather than merging.

## 4. Merge each changed function (Path A)

For a low-drift function, let git do the 3-way merge instead of eyeballing it. Base = the
committed baseline, *ours* = our override file, *theirs* = the new vanilla:

```
git merge-file -p \
  Contents/mods/.../PFTakeWaterAction.lua \      # ours
  vendor/pz/<VERSION>/shared/TimedActions/ISTakeWaterAction.lua \   # base
  <new-vanilla>/shared/TimedActions/ISTakeWaterAction.lua \         # theirs
  > merged && mv merged Contents/mods/.../PFTakeWaterAction.lua
```
Resolve any conflict markers, keeping the pooled-water behavior and the "early-return to
`original` when not plumbed" guard so unplumbed flows stay vanilla. Verify authority in
`.decompiled/` for anything touching water state (per the golden rule in
[CLAUDE.md](../CLAUDE.md)) — SP and MP can run the same method on different sides.

## 5. Prefer wrapping over copying (Path C)

Whenever the new vanilla exposes a seam that lets us **delegate to the captured original**
instead of re-pasting its body, take it — it shrinks what we have to re-merge next time.
Concretely: capture `local original = { method = ISFoo.method }`, then in our override handle
only the plumbed case and `return original.method(self, ...)` otherwise. If a function drops
out of the manifest this way (we no longer copy its body), remove it from
`vendor/pz/overrides.manifest`. The B42.19 menu removal is the extreme case of this — the whole
menu file went away because Java now drives it into our action overrides.

## 6. Re-baseline and commit

Once the overrides compile and behave:

```
# update vendor/pz/VERSION to the new build, and overrides.manifest if the set of
# overridden functions changed, then:
mise run vanilla-extract        # regenerate vendor/pz/<VERSION>/ from the install
mise run check                  # stylua + emmylua_check must pass
git add vendor/ Contents/ Umbrella
```
Re-running `vanilla-extract` must produce **no** further git diff (idempotent). Commit the new
baseline together with the reconciled overrides so the *next* update is a clean merge against
this build.

## 7. Update the build markers (only if the minimum target changed)

If we now require the newer build, update the PZ-build strings (these are **not** the mod
semver):
- `Contents/mods/PlumbingFixed/42/mod.info` → `name=PlumbingFixed (B42.<x>)` and
  `versionMin=`/`versionMax=` if applicable.
- `workshop/workshop.vdf` → the `title=... [B42.<x>+]` and "TESTED/VERIFIED WORKING IN
  B42.<x>" lines.

## 8. Test + release

- Full SP + MP pass per [TESTING.md](TESTING.md), including the unplumbed regression case.
- Then follow [RELEASING.md](RELEASING.md) (bump semver → tag → GitHub release → publish).
