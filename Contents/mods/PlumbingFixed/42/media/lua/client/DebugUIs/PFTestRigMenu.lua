require("PlumbingFixed/DebugRig")

if isDebugEnabled() then
  local options = PZAPI.ModOptions:create("PlumbingFixed", "Plumbing Fixed")
  local spawnRigOption = options:addTickBox(
    "spawnTestRig",
    "Enable 'Spawn Test Rig'",
    false,
    "Adds a debug/admin-only right-click option that CLEARS a "
      .. PFDebugRig.WIDTH
      .. "x"
      .. PFDebugRig.DEPTH
      .. " area (two floors!) and builds the PlumbingFixed barrel/sink test rig there. "
      .. "For mod development only -- DO NOT ENABLE unless you know what you are doing. "
      .. "In multiplayer this requires admin access."
  )

  Events.OnPreFillWorldObjectContextMenu.Add(function(player, context, worldObjects)
    if not spawnRigOption:getValue() then
      return
    end
    local playerObj = getSpecificPlayer(player)
    if isClient() then
      if not playerObj:getRole():hasCapability(Capability.UseDebugContextMenu) then
        return
      end
    elseif not isDebugEnabled() then
      return
    end

    local sq = worldObjects[1] and worldObjects[1]:getSquare() or playerObj:getSquare()
    if sq == nil then
      return
    end
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()

    local option = context:addDebugOption("Spawn PlumbingFixed Test Rig", nil, function()
      if isClient() then
        sendClientCommand(playerObj, "PlumbingFixed", "spawnTestRig", { x = x, y = y, z = z })
      else
        local barrels = PFDebugRig.build(x, y, z, true)
        PFDebugRig.fillEqualTainted(barrels, 15)
      end
    end)
    if option ~= nil then
      option.toolTip = ISToolTip:new()
      option.toolTip:initialise()
      option.toolTip:setVisible(false)
      option.toolTip:setName("Spawn PlumbingFixed Test Rig")
      option.toolTip.description = "Clears "
        .. PFDebugRig.WIDTH
        .. "x"
        .. PFDebugRig.DEPTH
        .. " tiles (two floors) at the clicked square and builds a plumbed test rig there"
        .. " (4 barrels, 15L tainted water each; edit via Configure Barrel Fluids)."
    end
  end)
end
