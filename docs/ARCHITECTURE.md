# Architecture

How PlumbingFixed changes vanilla behavior, and the water-distribution algorithm.

## The problem it fixes

When mains water is shut off, PZ lets you plumb a fixture (sink/bathtub/washer) and feed it
from a 3×3 array of rain barrels on the floor **above** it. Vanilla drains **one barrel at a
time** until empty. PlumbingFixed pools the whole grid and draws **evenly from the fullest
barrels**, so levels stay balanced.

## Patch strategy: pooled fluid primitives

Every vanilla action (and third-party Lua such as WashingMenusImproved) reads and
consumes fixture water through six `IsoObject` methods;
`shared/PlumbingFixed/PFPooledPrimitives.lua` patches those methods at the dispatch
layer, so the timed actions themselves run untouched and still pool. PZ's Kahlua
runtime resolves `obj:method()` through a plain Lua
table at `__classmetatables[Class].__index`. The patch captures the six vanilla functions
into a local, then reassigns the table entries in place — the standard
capture-then-reassign override pattern (verified in-game: the entries are plain
reassignable functions and dispatch honors them). The captures are stashed on the method
table itself (`rawget`/`rawset` `__PFvanilla`): the table is Java-side and can survive
PZ's several-per-session Lua state reloads, and re-capturing on a reload would grab our
own overrides as "vanilla" and make the fallback recurse — a reload reuses the stash and
only rebinds the overrides and metatable to the fresh state's globals. Every other method on the table is
untouched, so non-fluid dispatch pays nothing. Kahlua flattens inherited methods into each
concrete class's own table, so `IsoObject` and `IsoThumpable` are patched separately.

The overrides are one-line delegates; the pooled utils guard themselves. Each falls back
to the vanilla method as `obj.__PFraw:method(...)` — the patch gives the method table a
metatable whose function `__index` mints a proxy bound to the object: PZ's Kahlua
(`KahluaThread.tableget`) passes the **original receiver** to a function `__index`
anywhere in the lookup chain (unlike standard Lua, which rebases onto the handler table),
and consults it only after the method table itself misses, so real method dispatch never
reaches the handler. The fallback fires unless `isMultiSource`: plumbed via the
server-authoritative `getUsesExternalWaterSource()` with more than one source. So barrels,
single-source fixtures, and unplumbed objects keep vanilla behavior exactly, and a pooled
path can never re-enter the override layer (fallbacks call vanilla directly).

**History — why the dispatch layer.** Through v2.0.0 the mod overrode four vanilla timed
actions wholesale (`PFTakeWaterAction`, `PFWashClothing`, `PFWashYourself`,
`PFCleanBandage` — re-pasted bodies with pooled reads/draws) plus, pre-42.19, the Lua
context-menu builder. We switched because that shape kept breaking: every PZ update meant
re-diffing the copied bodies ([UPDATING-PZ.md](UPDATING-PZ.md)), B42.19 deleted the Lua
menu builder outright (now native Java), and third-party actions never pooled. Patching
the six primitives sits *below* every Lua caller, so nothing vanilla is re-pasted and
unknown callers pool for free.

### The six primitives

| Primitive | Pooled behavior | Vanilla Lua callers served |
|-----------|-----------------|----------------------------|
| `getFluidAmount()` | `getPlumbedFluidAmount` (TOTAL fluid, any type — vanilla parity) | `ISWashClothing:isValid`, `ISTakeWaterAction` (`new`, `transferFluid` guard), `ISWashYourself` (`complete` clamp, `getDuration`) |
| `hasFluid()` | pooled total fluid > 0 | `ISTakeWaterAction:isValid` |
| `hasWater()` | `hasPlumbedWater` (any viable source holds water) | `ISCleanBandage:isValid` |
| `useFluid(amt)` | dispose `drawFromPool(self, min(amt, pooled))`; return used | `ISWashClothing`, `ISWashYourself`, `ISCleanBandage` completes |
| `moveFluidToTemporaryContainer(amt)` | drain pool; return a clean-Water container | `ISTakeWaterAction` drink path |
| `transferFluidTo(target, amt)` | drain pool; add clean Water to target; return used | `ISTakeWaterAction` item-fill path |

`hasFluid`/`hasWater` need their own entries because their Java bodies call
`getFluidAmount()` **in Java**, which never dispatches through the Lua table. The two
transfer primitives hand the caller pure Water rather than the drawn mix, matching vanilla
Java (which purifies external-source draws) and the mod's purification behavior.

Reads are vanilla-parity **fluid** figures; write clamps use `getPlumbedWaterAmount`,
which counts `FluidCategory.Water` fluid in **viable** sources only
(`isViableWaterSource`: contents entirely water-category — a gasoline barrel is skipped,
not disqualifying), because `removeWaterTopDown` draws only from viable sources; clamping
a draw to the possibly-larger unfiltered total would ask the leveling loop for water the
pool doesn't hold. The two quantities only differ when non-water fluid is stored in a
barrel — see [FLUID-MIXING.md](FLUID-MIXING.md).

**Java-internal callers bypass this patch entirely.** That is why two other pieces exist:
the native context menu (`PFPooledMenuFixups`, below) and the washer update loop
(`server/PlumbingFixed/PFWasherPooling.lua`, an `OnWaterAmountChange`/`EveryOneMinute`
system that rebalances washer draws after the fact).

### The menu layer

The B42.19 fixture water menu (Drink / Fill / Wash / Clean Bandage) is built natively in
Java (`zombie/iso/ISWorldObjectContextMenuLogic`) and dispatches to the Lua handlers **by
name at call time**, which construct the vanilla timed actions — pooled via the primitives
above. But the Java menu gates and labels from the
fixture's single found barrel (Java-side reads), so **`client/ISUI/PFPooledMenuFixups.lua`**
post-processes the built menu in place: pooled Drink/Wash water figures and the Wash
availability grey-out. `client/ISUI/PFConnectedMatrixPanel.lua` docks a 3×3
connected-barrels grid beside that menu (capacity-scaled fluid bars; hover shows per-fluid
amounts and highlights the barrel's world sprite; in debug/admin, clicking a cell opens the
mod's per-barrel fluid editor `client/DebugUIs/PFBarrelFluidWindow.lua` for that barrel —
fluid picker + amount + Add/Empty, with MP edits sent through the capability-gated server
commands). Debug tooling: `client/DebugUIs/Scenarios/DebugPlumbing.lua` (test world).
The bootstraps `client/PlumbingFixedClient.lua` / `server/PlumbingFixedServer.lua` just
`require` the shared primitives patch on each side.

Caveat: the vanilla *fixture* Clean-Bandage menu looks broken in B42.19 — `CleanBandages`
and its `onClean*` handlers are **file-local** in `ISWorldObjectContextMenu.lua`, so Java's
`getFunctionObject("CleanBandages.*")` / `callLuaClass("CleanBandages", …)` resolve to nil
(they look up the global env). The primitives still pool any caller that reaches
`ISCleanBandage`; we don't try to repair the upstream menu, and its batch count is left alone.

## Core utilities (`shared/PlumbingFixed/PFUtils.lua`)

- `getPlumbedSources(waterObject) -> IsoObject[]` — if the fixture is plumbed, scans the 3×3
  grid on `z+1` and returns every barrel-like object (has `water`/`waterPiped` flag, or an
  `IsoThumpable` with fluid capacity). Excludes inventory/dead-body/moving objects.
- `getWaterAmount(obj)` — sums every `FluidCategory.Water` fluid in the object's
  `FluidContainer` (category membership comes from the fluid definitions, so new
  water-category fluids count automatically); with no container, reads the reserve via
  `getFluidAmount()`.
- `isViableWaterSource(src)` — the drawable-source predicate: contents entirely
  water-category (empty passes; reserve sources always). Draws and water figures skip
  non-viable sources; totals include them ([FLUID-MIXING.md](FLUID-MIXING.md)).
- `getPlumbedWaterAmount` (viable sources) / `getPlumbedWaterCapacity` (all sources) —
  pooled totals (fall back to the fixture itself when nothing is plumbed).
- `findWaterObject(worldObjects)` — from a right-clicked square, returns the plumbed fixture
  that actually has sources (used by the debug inspector menu).
- `isPlumbed(obj)` — `getUsesExternalWaterSource()` (server-authoritative) OR
  `modData.canBeWaterPiped == false` (the debug-scenario hack). Feeds the shared scan, and
  through it every primitive's `isMultiSource` guard. **See the golden rule in
  [CLAUDE.md](../CLAUDE.md).**

## The distribution algorithm — `removeWaterTopDown(waterObject, amount)`

Removes `amount` of water from the pool, always taking from the **fullest** barrels first so
the grid levels out (a "water-leveling" / top-down pour):

1. Build `list = { {obj, amt=getWaterAmount(obj)} , ... }` for every **viable** source
   (`isViableWaterSource`), and clamp `amount` to their total — the washer path
   (`PFWasherPooling`) re-draws a Java-side delta that can exceed the drawable pool.
2. Loop until `amount` is satisfied:
   - Sort descending by `amt`.
   - Count how many share the current top level (`count`), find the next level down.
   - Drain the top `count` barrels down toward the next level; if `amount` runs out mid-layer,
     split the remainder evenly across those `count` barrels.
3. Apply the computed deltas: pull each barrel's delta into a temp container via
   `moveFluidToTemporaryContainer`, **converting TaintedWater → Water** (purification), and
   merge everything into one `completeMixed` `FluidContainer`, which is returned.

Callers (the patched primitives in `PFPooledPrimitives.lua`) then transfer clean water to
the item/character (or just dispose the draw) and **must** `FluidContainer.DisposeContainer`
temporaries — these are Java-managed and leak silently otherwise.

## Client ↔ server data flow (why side matters)

Native Java (`ISWorldObjectContextMenuLogic`) builds the fixture menu on the **client** and
binds each option to the vanilla Lua handlers. Selecting one enqueues an
`ISTakeWaterAction`/`ISWashClothing`, whose `isValid` / `updateUse` / `complete` can run on the
**server** in MP. So a value read while building the menu (client) may differ from the same
read inside the action (server) — this is exactly why the primitives' `isMultiSource` guard
rests on `getUsesExternalWaterSource()` (server-authoritative synced flag) and not
`hasExternalWaterSource()` (client-only transient, reads false on the server). The patch is
`shared/`, so both Lua states dispatch identically. Always confirm which side a code path
runs on before choosing a predicate. Verify against `.decompiled/` (`mise run decompile`).
