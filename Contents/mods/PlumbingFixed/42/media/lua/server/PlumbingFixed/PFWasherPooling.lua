require("PlumbingFixed/utils")

-- Barrels carrying a ratio snapshot that still need stop-cleanup, keyed "x:y:z".
-- In-memory by design: a cleanup aid, not correctness data (the snapshot itself lives in
-- the barrel's modData and survives restarts; a resumed cycle re-registers it here).
--- @type table<string, { x: integer, y: integer, z: integer }>
local watched = {}

local reentrant = false

--- @param x integer
--- @param y integer
--- @param z integer
--- @return string
local function posKey(x, y, z)
  return x .. ":" .. y .. ":" .. z
end

--- @param obj IsoObject
--- @return boolean
local function isRunningWasher(obj)
  if instanceof(obj, "IsoClothingWasher") then
    --- @cast obj IsoClothingWasher
    return obj:isActivated()
  end
  if instanceof(obj, "IsoCombinationWasherDryer") then
    --- @cast obj IsoCombinationWasherDryer
    return obj:isActivated() and obj:isModeWasher()
  end
  if instanceof(obj, "IsoStackedWasherDryer") then
    --- @cast obj IsoStackedWasherDryer
    return obj:isWasherActivated()
  end
  return false
end

--- Scan the 3x3 below the barrel for a plumbed, actively RUNNING washer. Requiring a
--- running washer (not just any plumbed fixture) is what keeps direct barrel operations
--- (ISEmptyRainBarrelAction's useFluid/emptyFluid on the barrel itself) from being
--- mistaken for washer draws — they fire the same event on the same object.
--- @param barrel IsoObject
--- @return IsoObject?
local function findRunningWasherBelow(barrel)
  local sq = barrel:getSquare()
  if sq == nil then
    return nil
  end
  local x, y, z = sq:getX(), sq:getY(), sq:getZ()
  for ix = -1, 1 do
    for iy = -1, 1 do
      local below = getCell():getGridSquare(x + ix, y + iy, z - 1)
      if below ~= nil then
        local objects = below:getObjects()
        for j = 0, objects:size() - 1 do
          local obj = objects:get(j)
          if obj ~= nil and obj:getUsesExternalWaterSource() and isRunningWasher(obj) then
            return obj
          end
        end
      end
    end
  end
  return nil
end

--- Record the barrel's current mix ratios in its modData (or clear the key if empty).
--- Only consulted when a draw empties the barrel outright, destroying the live ratios.
--- @param barrel IsoObject
local function writeSnapshot(barrel)
  local container = barrel:getFluidContainer()
  if container == nil or container:isEmpty() then
    barrel:getModData().PF_snapshotRatios = nil
    return
  end
  local snapshot = {}
  local fluids = Fluid.getAllFluids()
  for i = 0, fluids:size() - 1 do
    local fluid = fluids:get(i)
    local ratio = container:getRatioForFluid(fluid)
    if ratio > 0 then
      snapshot[fluid:getFluidTypeString()] = ratio
    end
  end
  barrel:getModData().PF_snapshotRatios = snapshot
end

--- Put back exactly what the draw removed. Draws are proportional slices, so the
--- surviving ratios reconstruct the removed mix bit-exactly; only a draw that emptied
--- the barrel loses them — then the modData snapshot (written after the previous draw)
--- stands in, or TaintedWater as the pessimistic guess (cannot launder).
--- @param barrel IsoObject
--- @param container FluidContainer
--- @param delta number
local function restoreDrawn(barrel, container, delta)
  if container:getAmount() > 0 then
    -- Capture every ratio before the first add — adding shifts the live ratios.
    local entries = {}
    local fluids = Fluid.getAllFluids()
    for i = 0, fluids:size() - 1 do
      local fluid = fluids:get(i)
      local ratio = container:getRatioForFluid(fluid)
      if ratio > 0 then
        table.insert(entries, { fluid = fluid, ratio = ratio })
      end
    end
    for _, entry in ipairs(entries) do
      container:addFluid(entry.fluid, delta * entry.ratio)
    end
    return
  end

  --- @type table<string, number>?
  local snapshot = barrel:getModData().PF_snapshotRatios
  if snapshot ~= nil then
    for fluidType, ratio in pairs(snapshot) do
      container:addFluid(Fluid.Get(fluidType), delta * ratio)
    end
    return
  end
  container:addFluid(Fluid.TaintedWater, delta)
end

Events.OnWaterAmountChange.Add(function(object, previousAmount)
  if reentrant then
    return
  end
  local container = object:getFluidContainer()
  if container == nil then
    return
  end

  local delta = previousAmount - container:getAmount()
  if delta <= 0 then
    -- Fluid was ADDED via IsoObject.addFluid (a pour): ratios changed, so refresh an
    -- existing snapshot to keep the emptied-barrel fallback accurate.
    if object:getModData().PF_snapshotRatios ~= nil then
      writeSnapshot(object)
    end
    return
  end

  local washer = findRunningWasherBelow(object)
  if washer == nil then
    return
  end

  DebugLog.log(
    DebugType.Mod,
    "PlumbingFixed (PFWasherPooling) - pooling washer draw of " .. tostring(delta) .. " from " .. object:toString()
  )
  reentrant = true
  restoreDrawn(object, container, delta)
  FluidContainer.DisposeContainer(drawFromPool(washer, delta))

  -- Snapshot bookkeeping: only the barrel currently losing water carries one; register
  -- it for stop-cleanup. Sync every pool barrel's fluid state to clients (same call
  -- vanilla ISFluidTransferAction uses).
  writeSnapshot(object)
  for _, src in ipairs(getPlumbedSources(washer)) do
    if src ~= object then
      src:getModData().PF_snapshotRatios = nil
    end
    src:sync()
  end
  local sq = object:getSquare()
  if sq ~= nil then
    watched[posKey(sq:getX(), sq:getY(), sq:getZ())] = { x = sq:getX(), y = sq:getY(), z = sq:getZ() }
  end
  reentrant = false
end)

-- Stop-cleanup: Java's setActivated(false) fires no Lua event, so poll on the washer's
-- own cadence. Once no washer below a watched barrel is running (power loss, cycle done,
-- pool dry, or toggled off), drop the snapshot — modData only lingers if the session
-- ends mid-cycle, and a resumed cycle cleans it up on its next stop.
Events.EveryOneMinute.Add(function()
  for key, pos in pairs(watched) do
    local sq = getCell():getGridSquare(pos.x, pos.y, pos.z)
    if sq ~= nil then
      local barrel = IsoObject.FindWaterSourceOnSquare(sq)
      if barrel == nil then
        watched[key] = nil
      elseif findRunningWasherBelow(barrel) == nil then
        barrel:getModData().PF_snapshotRatios = nil
        watched[key] = nil
      end
    end
    -- Unloaded square: keep the entry and retry next minute.
  end
end)
