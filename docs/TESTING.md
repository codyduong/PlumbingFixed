# Testing

Every change must be verified in **both single-player and a local multiplayer server** — the
mod's timed actions can run server-side while the menu that created them ran client-side
(see [ARCHITECTURE.md](ARCHITECTURE.md) → client/server data flow).

## 1. Deploy your working copy

```
mise run check     # lint + types first
mise run deploy    # packages + syncs to ~/Zomboid/Workshop/PlumbingFixed
```

`deploy` copies the built mod into `%USERPROFILE%\Zomboid\Workshop\PlumbingFixed` — the dir
PZ loads "workshop (dev)" mods from. Enable **PlumbingFixed** in the in-game Mods list
(Workshop tab) before starting a game. (You can alternatively symlink/copy into
`%USERPROFILE%\Zomboid\mods\` if you prefer the local-mods list.)

## 2. Single-player with the debug scenario

Launch PZ in **debug mode** (Steam → PZ → Properties → Launch Options: add `-debug`, or run
`ProjectZomboid64ShowConsole.bat`). Debug mode unlocks:

- The **debug scenario picker** — pick **"Plumbing Fixed Debug"** (`debugScenarios.DebugPlumbing`
  in `client/DebugUIs/Scenarios/DebugPlumbing.lua`). It spawns a walled 3×3 of rain barrels
  with varying fluid levels over a plumbed sink, an unplumbed mixed-fluid setup, stairs, and a
  dirty/bloody loadout for wash testing. Start location `x8350 y7190 z0`.
- The **"Connected Sources"** right-click inspector (`PFPlumbedConnectedMenu.lua`) — shows
  each barrel's fluid/capacity/tainted state and the pooled totals. Use this to confirm the
  pool is read correctly.

Check, on the plumbed sink:
- **Drink** and **Fill a container** — draws pull evenly from the fullest barrels (watch the
  inspector totals drop across barrels, not one-at-a-time).
- **Wash** (yourself / clothing / container / weapon) — consumes from the pool; the bloody
  shirt / dirty bandages from the scenario are the fixtures.
- **Tainted → clean**: tainted barrels should yield clean water (purification in
  `removeWaterTopDown`).
- The **unplumbed** sink in the scenario must behave like vanilla (regression guard).

## 3. Multiplayer (local dedicated server)

The gotchas live here. Stand up a local server and connect a client:

- Start `F:\steamlibrary\steamapps\common\ProjectZomboid\StartServer64.bat` (or
  `ProjectZomboidServer.bat`), enable the mod in the server's mod list, then connect via
  Steam → Host/Join to `127.0.0.1`.
- Repeat the drink / fill / wash checks. Watch for behavior that works in SP but not MP —
  that's usually a predicate read on the wrong side.

## 4. Logs

- `DebugLog.log(DebugType.Mod, ...)` lines (the mod is instrumented throughout) appear in the
  console window and in `%USERPROFILE%\Zomboid\console.txt`. To raise verbosity, uncomment
  `DebugLog.setLogSeverity(DebugType.Mod, LogSeverity.All)` in
  `server/PlumbingFixedServer.lua` while testing.
- Server-side logs: `%USERPROFILE%\Zomboid\server-console.txt`.
- Lua errors surface in-game and in `console.txt`; search for `PlumbingFixed`.

## 5. Before you commit

- `mise run check` is green.
- SP **and** MP verified for any code path you touched.
- No new `FluidContainer` leaks (every temp container disposed).
