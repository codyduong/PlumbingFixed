# Architecture

How PlumbingFixed changes vanilla behavior, and the water-distribution algorithm.

## The problem it fixes

When mains water is shut off, PZ lets you plumb a fixture (sink/bathtub/washer) and feed it
from a 3×3 array of rain barrels on the floor **above** it. Vanilla drains **one barrel at a
time** until empty. PlumbingFixed pools the whole grid and draws **evenly from the fullest
barrels**, so levels stay balanced.

## Override strategy

PZ loads its own Lua first; mods load after. Every override file:

1. `require`s the vanilla module so the global table exists
   (e.g. `require("lua/shared/TimedActions/ISTakeWaterAction")`).
2. Captures the originals it still needs into a local table:
   `local original = { updateUse = ISTakeWaterAction.updateUse, ... }`.
   `new` is captured **separately** (`local originalNew = ISTakeWaterAction.new`) because
   storing a constructor in that table interferes with metatable resolution.
3. Reassigns methods on the **global table in place**:
   `function ISTakeWaterAction:isValid() ... end`.

Because the table is mutated in place, all existing callers (vanilla and other mods) resolve
to the patched methods. Each override early-returns to the captured original when the object
is **not** plumbed, so unplumbed/vanilla flows are untouched.

### What overrides what

| Vanilla symbol | Override file | Notes |
|----------------|---------------|-------|
| `ISTakeWaterAction:{isValid,updateUse,transferFromMax,new}` | `shared/.../PFTakeWaterAction.lua` | drink & fill-container from the pool |
| `ISWashClothing:{isValid,complete}` | `shared/.../PFWashClothing.lua` | wash consumes from the pool |
| `ISWorldObjectContextMenu.{doDrinkWaterMenu,doWashClothingMenu,doFluidContainerMenu,onDrink,onTakeWater,toggleComboWasherDryer,formatWaterAmount}` + `Events.OnFillWorldObjectContextMenu` | `client/.../PFWorldObjectContextMenu.lua` | rebuilds the menus using pooled totals |
| debug inspector via `Events.OnPreFillWorldObjectContextMenu` | `client/DebugUIs/PFPlumbedConnectedMenu.lua` | shows per-barrel info (debug mode only) |
| `debugScenarios.DebugPlumbing` | `client/DebugUIs/Scenarios/DebugPlumbing.lua` | builds a test world |
| (server bootstrap) | `server/PlumbingFixedServer.lua` | `require`s the shared timed actions server-side |

`shared/.../PFCleanBandage.lua` is **entirely commented out** (legacy/disabled). The
clean-bandage menu code in `PFWorldObjectContextMenu.lua` is likewise commented out.

## Core utilities (`shared/PlumbingFixed/utils.lua`)

- `getPlumbedSources(waterObject) -> IsoObject[]` — if the fixture is plumbed, scans the 3×3
  grid on `z+1` and returns every barrel-like object (has `water`/`waterPiped` flag, or an
  `IsoThumpable` with fluid capacity). Excludes inventory/dead-body/moving objects.
- `getWaterAmount(obj)` — sums Water + TaintedWater + CarbonatedWater in the object's
  `FluidContainer` (0 if none).
- `getPlumbedWaterAmount` / `getPlumbedWaterCapacity` — pooled totals across all sources
  (fall back to the fixture itself when nothing is plumbed).
- `findWaterObject(worldObjects)` — from a right-clicked square, returns the plumbed fixture
  that actually has sources (drives the context-menu hook).
- `isPlumbed(obj)` — `hasExternalWaterSource()` OR `getUsesExternalWaterSource()` OR
  `modData.canBeWaterPiped == false`. **See the golden rule in [CLAUDE.md](../CLAUDE.md):**
  which term is authoritative depends on the calling side; this predicate is under active
  review.

## The distribution algorithm — `removeWaterTopDown(waterObject, amount)`

Removes `amount` of water from the pool, always taking from the **fullest** barrels first so
the grid levels out (a "water-leveling" / top-down pour):

1. Build `list = { {obj, amt=getWaterAmount(obj)} , ... }` for every source.
2. Loop until `amount` is satisfied:
   - Sort descending by `amt`.
   - Count how many share the current top level (`count`), find the next level down.
   - Drain the top `count` barrels down toward the next level; if `amount` runs out mid-layer,
     split the remainder evenly across those `count` barrels.
3. Apply the computed deltas: pull each barrel's delta into a temp container via
   `moveFluidToTemporaryContainer`, **converting TaintedWater → Water** (purification), and
   merge everything into one `completeMixed` `FluidContainer`, which is returned.

Callers (`PFTakeWaterAction:transferFromMax`, `PFWashClothing:complete`) then transfer that
container into the item/character (or dispose it) and **must** `FluidContainer.DisposeContainer`
temporaries — these are Java-managed and leak silently otherwise.

## Client ↔ server data flow (why side matters)

`Events.OnFillWorldObjectContextMenu` builds the menu on the **client**. Selecting an option
enqueues an `ISTakeWaterAction`/`ISWashClothing`, whose `isValid` / `updateUse` / `complete`
can run on the **server** in MP. So a value read while building the menu (client) may differ
from the same read inside the action (server) — this is exactly why
`hasExternalWaterSource()` (unreliable server-side) was swapped for
`getUsesExternalWaterSource()` in `updateUse`. Always confirm which side a code path runs on
before choosing a predicate. Verify against `.decompiled/` (`mise run decompile`).
