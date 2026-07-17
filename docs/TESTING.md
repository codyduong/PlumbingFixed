# Testing

Every change must be verified in **both single-player and a local multiplayer server** — the
mod's timed actions can run server-side while the menu that created them ran client-side
(see [ARCHITECTURE.md](ARCHITECTURE.md) → client/server data flow).

## 1. Deploy your working copy

```
mise run check             # lint + types first
mise run deploy client     # -> %USERPROFILE%\Zomboid\Workshop\PlumbingFixed (SP / client)
mise run deploy server     # -> .testhost\mods\PlumbingFixed (the ephemeral dedicated server)
mise run deploy all        # both
```

The target is **required** — a deploy never silently touches a location you didn't intend.
`client` feeds the "workshop (dev)" dir the game client loads from (enable **PlumbingFixed**
in the in-game Mods list, Workshop tab). `server` feeds the ephemeral testhost (§3), *not*
your real `~\Zomboid` — your own installation never becomes the test playground.

## 2. Single-player with the debug scenario

Launch PZ in **debug mode** (Steam → PZ → Properties → Launch Options: add `-debug`, or run
`ProjectZomboid64ShowConsole.bat`). Debug mode unlocks:

- The **debug scenario picker** — pick **"Plumbing Fixed Debug"**
  (`client/DebugUIs/Scenarios/DebugPlumbing.lua`). It builds two test rigs via the shared
  builder (`shared/PlumbingFixed/DebugRig.lua`): a **plumbed** rig (3×3 walls, 4 barrels
  with staggered tainted water, plumbed sink, stairs) and an **unplumbed control** rig
  (fluid-cocktail barrel, vanilla-behaving sink), plus a dirty/bloody loadout for wash
  testing. Start location `x8350 y7190 z0`.
- The **Connected Barrels grid** (`PFConnectedMatrixPanel.lua`) — docks beside the
  right-click menu on any pooled fixture (two or more connected barrels; for every player,
  not just debug): a 3×3 grid of
  capacity-scaled fluid bars plus a pooled-total bar (stacked per-fluid segments; position
  set by mod option, default right); hovering a cell or the bar shows concrete per-fluid
  amounts, and hovering a cell highlights that barrel's world sprite. In debug/admin,
  **clicking a cell opens the per-barrel fluid editor** (`PFBarrelFluidWindow.lua`: fluid
  picker + amount + Add/Empty + live fluid bar) for that barrel, so you can set up any
  fluid scenario without rebuilding the rig.
- The **debug tooltip marker** — rewritten Drink/Wash tooltips carry
  "Modified by Plumbing Fixed". **Invariant check: the unplumbed control sink must NEVER
  show the marker** (the mod must not touch unplumbed behavior).

Check, on the plumbed sink:
- **Drink** and **Fill a container** — draws pull evenly from the fullest barrels (watch the
  grid's bars drop across barrels, not one-at-a-time).
- **Wash** (yourself / clothing / container / weapon) — consumes from the pool.
- **Tainted → clean**: tainted barrels should yield clean water (purification in
  `removeWaterTopDown`).
- The **unplumbed** control rig must behave pure vanilla (regression guard + no marker).

### Spawning a rig anywhere

Options → Mods → **Plumbing Fixed** → enable
**"Enable 'Spawn Test Rig' (PZ TESTING, DO NOT ENABLE UNLESS YOU KNOW WHAT YOU ARE DOING)"**.
With that mod option on *and* debug/admin rights, right-click any square → **Spawn
PlumbingFixed Test Rig**: clears the 4×6 footprint (two floors!) at the clicked square and
builds a plumbed rig with 15L tainted water per barrel. The double gate exists because
admin+debug is common on private servers — without the opt-in, mod users could wipe their
base with a stray debug click.

## 3. Multiplayer (ephemeral dedicated server)

The gotchas live here. The **testhost** runs a real dedicated server without touching your
game install or `~\Zomboid`:

```
mise run deploy server     # sync the mod into the testhost
mise run testhost          # first run: steamcmd downloads app 380870 (~4 GB, anonymous)
mise run testhost --reset  # nuke .testhost\ and start a fresh world
```

- The server binary lives in `.tools\pzserver` (Steam app **380870**, branch `unstable` —
  must match the installed game's build or the client is refused). All world/config/db
  state lives in the git-ignored `.testhost\` via `-cachedir`; seed configs
  (`Mods=\PlumbingFixed`, no-zombie sandbox) come from the source-controlled `testhost/`
  dir on first boot.
- Why not `~\Zomboid`: the dedicated server runs **non-Steam** (no `-Dzomboid.steam=1`), so
  it never scans `Zomboid\Workshop` — and pointing it at your real dir would make your own
  install the canary playground.
- Connect from a **normally-launched** client (mod enabled from §1): Join → `127.0.0.1`,
  port `16261`, account **admin** / **pztest** (created on first boot via
  `-adminusername`/`-adminpassword`). The admin role carries `UseDebugContextMenu`, so
  cell-click fluid editing in the Connected Barrels grid and (with the mod option on) rig
  spawning both work; rig builds and fluid edits are sent to the server via
  `sendClientCommand` and re-validated there.
- Spawn a rig next to you (no teleporting needed), then repeat the §2 checks. Watch for
  behavior that works in SP but not MP — that's usually a predicate read on the wrong side.

## 4. Logs

- `DebugLog.log(DebugType.Mod, ...)` lines (the mod is instrumented throughout) appear in the
  console window and in `%USERPROFILE%\Zomboid\console.txt`. To raise verbosity, uncomment
  `DebugLog.setLogSeverity(DebugType.Mod, LogSeverity.All)` in
  `server/PlumbingFixedServer.lua` while testing.
- Testhost server logs: `.testhost\server-console.txt`.
- Lua errors surface in-game and in `console.txt`; search for `PlumbingFixed`.

## 5. Before you commit

- `mise run check` is green.
- SP **and** MP verified for any code path you touched.
- The unplumbed control sink shows no marker and behaves vanilla.
- No new `FluidContainer` leaks (every temp container disposed).
