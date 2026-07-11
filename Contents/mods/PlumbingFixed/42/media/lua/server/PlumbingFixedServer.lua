require("PlumbingFixed/TimedActions/PFTakeWaterAction")
require("PlumbingFixed/TimedActions/PFWashClothing")
require("PlumbingFixed/TimedActions/PFCleanBandage")
require("PlumbingFixed/DebugRig")

--- Find the object holding a FluidContainer on a square (a rig barrel, but works for any
--- fluid-holding world object).
--- @param x number
--- @param y number
--- @param z number
--- @return IsoObject?
local function findFluidObjectAt(x, y, z)
  local sq = getCell():getGridSquare(x, y, z)
  if sq == nil then
    return nil
  end
  local objects = sq:getObjects()
  for i = 0, objects:size() - 1 do
    local obj = objects:get(i)
    if obj:getFluidContainer() ~= nil then
      return obj
    end
  end
  return nil
end

-- MP counterparts of the client debug tools (PFTestRigMenu / PFBarrelFluidWindow): the
-- world is server-authoritative, so clients only send coordinates and the server
-- re-checks the same capability the client menus were gated on before mutating anything.
Events.OnClientCommand.Add(function(module, command, player, args)
  if module ~= "PlumbingFixed" or type(args) ~= "table" then
    return
  end
  if not player:getRole():hasCapability(Capability.UseDebugContextMenu) then
    return
  end
  if type(args.x) ~= "number" or type(args.y) ~= "number" or type(args.z) ~= "number" then
    return
  end
  if (command == "addBarrelFluid" or command == "emptyBarrel") and player:getAccessLevel() ~= "admin" then
    return
  end

  if command == "spawnTestRig" then
    local barrels = PFDebugRig.build(math.floor(args.x), math.floor(args.y), math.floor(args.z), true)
    PFDebugRig.fillEqualTainted(barrels, 15)
  elseif command == "addBarrelFluid" then
    local obj = findFluidObjectAt(args.x, args.y, args.z)
    local fluid = type(args.fluid) == "string" and Fluid.Get(args.fluid) or nil
    if obj and fluid and type(args.amount) == "number" and args.amount > 0 then
      obj:getFluidContainer():addFluid(fluid, args.amount)
      obj:transmitCompleteItemToClients()
    end
  elseif command == "emptyBarrel" then
    local obj = findFluidObjectAt(args.x, args.y, args.z)
    if obj then
      obj:getFluidContainer():Empty()
      obj:transmitCompleteItemToClients()
    end
  end
end)

-- DebugLog.setLogSeverity(DebugType.Mod, LogSeverity.All)
DebugLog.log(DebugType.Mod, "PlumbingFixed - initialized on server")
