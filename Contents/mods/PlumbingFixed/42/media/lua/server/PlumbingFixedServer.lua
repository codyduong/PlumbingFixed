require("PlumbingFixed/utils")
require("PlumbingFixed/TimedActions/PFTakeWaterAction")
require("PlumbingFixed/TimedActions/PFWashClothing")
require("PlumbingFixed/TimedActions/PFCleanBandage")
require("PlumbingFixed/DebugRig")

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
    -- Resolve the same pooled source the client picked; only a container-backed source
    -- (barrel) can be edited — a reserve source (bathtub) has no container to mutate.
    local obj = findPlumbedSourceAt(args.x, args.y, args.z)
    local container = obj and obj:getFluidContainer()
    local fluid = type(args.fluid) == "string" and Fluid.Get(args.fluid) or nil
    if obj and container and fluid and type(args.amount) == "number" and args.amount > 0 then
      container:addFluid(fluid, args.amount)
      obj:transmitCompleteItemToClients()
    end
  elseif command == "emptyBarrel" then
    local obj = findPlumbedSourceAt(args.x, args.y, args.z)
    local container = obj and obj:getFluidContainer()
    if obj and container then
      container:Empty()
      obj:transmitCompleteItemToClients()
    end
  end
end)

-- DebugLog.setLogSeverity(DebugType.Mod, LogSeverity.All)
DebugLog.log(DebugType.Mod, "PlumbingFixed - initialized on server")
