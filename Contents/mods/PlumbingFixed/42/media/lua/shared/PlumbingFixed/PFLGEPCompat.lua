local LGEP_MOD_ID = "LGExtendedPlumbing"

--- @type boolean?
local lgepActive = nil

--- @return boolean
local function isLGEPActive()
  if lgepActive == nil then
    lgepActive = false
    local mods = getActivatedMods()
    for i = 0, mods:size() - 1 do
      local id = mods:get(i)
      -- getActivatedMods() ids carry a leading '\' as of B42 (see its own doc comment);
      -- matched either way so this reads the same regardless of build.
      if id == LGEP_MOD_ID or id == "\\" .. LGEP_MOD_ID then
        lgepActive = true
        break
      end
    end
  end
  return lgepActive
end

--- Ambient declaration only - never assigned a real table here. `LGEP = LGEP` is a no-op
--- whether or not LG Extended Plumbing is installed (reads back whatever is already there,
--- nil or its real table); it exists purely so emmylua_check has a typed declaration site
--- for the global instead of silently treating every read of it as untyped. LGEP itself
--- defines this table for real in its own LGEPCore.lua (`LGEP = LGEP or {}`) - we never
--- create it and never require any of its files.
--- @class LGEPModule
--- @field isGhost fun(object: IsoObject): boolean
--- @type LGEPModule?
LGEP = LGEP

--- The LG Extended Plumbing ghost standing on a fixture's centre square, or nil.
--- @param waterObject IsoObject a plumbed FIXTURE (getUsesExternalWaterSource() == true)
--- @return IsoObject?
function findLGEPGhost(waterObject)
  if not isLGEPActive() or LGEP == nil or LGEP.isGhost == nil then
    return nil -- LG Extended Plumbing not installed, or its module isn't up yet
  end
  local sq = waterObject:getSquare()
  if sq == nil then
    return nil
  end
  local centerSrc = findPlumbedSourceAt(sq:getX(), sq:getY(), sq:getZ() + 1)
  if centerSrc ~= nil and LGEP.isGhost(centerSrc) then
    return centerSrc
  end
  return nil
end

--- Called from getPlumbedSources, one of the hottest paths in the mod (every
--- getFluidAmount/hasFluid/hasWater/useFluid/... on every plumbed fixture) - deliberately
--- no DebugLog.log here. Lua evaluates a log call's arguments before the call, so an
--- unconditional log would pay for a string concat on every such call whether or not the
--- log category is being watched; see the note on findLGEPWaterObject below, which logs
--- once per right-click instead.
--- @param waterObject IsoObject
--- @return boolean
function isDeferredToLGEP(waterObject)
  return findLGEPGhost(waterObject) ~= nil
end
