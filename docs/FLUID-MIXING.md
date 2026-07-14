# Fluid mixing — where we are, where this is going

Tracking document for the holistic overhaul of how the pooled water supply treats
non-water fluids. Water-only extraction is vanilla behavior, but it is ill-defined and
fragile the moment someone plumbs anything else (a beer-only barrel, a bleach stash).
The long-term direction is to make mixing a first-class, controllable behavior instead
of an exclusion rule. This doc records the current state, the target design, and every
code site that has to change — so incremental work stays aimed at the same end state.

## Current state (v2.x)

The pool **excludes** non-water sources rather than failing or contaminating:

- `isViableWaterSource` (`utils.lua`) is the single predicate: a source is drawable iff
  its container is entirely water-category (Water / TaintedWater / CarbonatedWater per
  42.19 `fluids.txt`) or it is a reserve-water source with no `FluidContainer`. Empty
  containers pass vacuously and contribute 0.
- **Draws** (`removeWaterTopDown`, and every clamp via `getPlumbedWaterAmount`) operate
  on viable sources only. Tainted water is purified to Water on draw; the fixture always
  hands over pure Water. `removeWaterTopDown` clamps to the viable total because the
  washer path (`PFWasherPooling`) re-draws a Java-side delta that never saw the filter.
- **Totals** (`getPlumbedFluidAmount`, `getPlumbedWaterCapacity`) stay unfiltered: menus
  list everything sitting in the pool even though only the viable subset is drawable.
- **`hasPlumbedWater`** is true iff any viable source holds water — a gasoline barrel in
  the grid is skipped rather than disqualifying the whole supply (vanilla likewise skips
  barrels one by one via `FindExternalWaterSource`, it just has no category check at
  selection).
- The multi-source **gate** (`isMultiSource` on the unfiltered scan) decides pooled vs
  vanilla mode from rig shape alone, so behavior doesn't flip-flop with barrel contents.

## Target design

Barrels mix **indiscriminately**: the pooled source draws from all barrels, whatever
they hold, unless the player opts a barrel out.

- **Sluice gate** (or similar buildable/attachable): installing one on a barrel removes
  it from pool consideration. This replaces the water-category check as the exclusion
  mechanism — exclusion becomes a player decision, not a fluid-type rule.
- **Fixture-side controls**: options on the fixture for what/how to draw.
- **Deterministic consumption math**: tasks must be able to compute *exactly* which
  fluids and how much of each a draw will consume — required because:
  - some fluids carry **calories**, and tooltips must show them for players with the
    nutrition perk;
  - the UI should warn about **deadly/poisonous mixtures** before the player drinks;
  - MP requires client-predicted figures to match the server draw.
- Vanilla precedent: `createSampleAndPurifyWater` passes non-water through fixture
  draws proportionally; today we hand over pure Water instead.

## Change map (stubs in code)

Every site marked `FUTURE(fluid-mixing)` or listed here must move together:

| Site | Today | Under mixing |
|------|-------|--------------|
| `utils.lua` `isViableWaterSource` | water-category check | per-barrel opt-out (sluice gate) |
| `utils.lua` `removeWaterTopDown` purify loop | only water-category reaches it; tainted→Water | non-water routes through the existing passthrough branch; decide purify policy |
| `utils.lua` `getPlumbedWaterAmount` vs `getPlumbedFluidAmount` | diverge on non-viable sources | converge (everything drawable) or split by fixture setting |
| `utils.lua` `movePlumbedFluidToTemporaryContainer` / `transferPlumbedFluidTo` | synthesize pure Water | must hand over the real mixture |
| `PFPooledMenuFixups.lua` tooltips | pooled totals, no fluid breakdown | calorie / danger annotations, per-fluid figures |
| `PFWasherPooling.lua` `restoreDrawn` | restores TaintedWater | restore the actual drawn mixture from the snapshot ratios |

## Open questions

- Draw ordering for mixtures: keep Fullest-First leveling per barrel, or draw
  proportionally across fluids within each barrel (vanilla-style)?
- Does purification (tainted→water) survive as a fixture property, a sandbox option,
  or disappear under mixing?
- Sluice gate implementation: new tile object, modData flag on the barrel, or context
  menu toggle? MP sync path for whichever it is.

Deferred to a later version. Do not partially implement — the exclusion rule and the
mixing design are alternatives, not layers.
