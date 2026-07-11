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

    local parent = context:addDebugOption("Spawn PlumbingFixed Test Rig", nil, nil)
    if parent == nil then
      return
    end
    local subMenu = ISContextMenu:getNew(context)
    context:addSubMenu(parent, subMenu)

    --- @param name string
    --- @param fixture "sink" | "washer"
    --- @param fixtureDesc string
    local function addSpawnOption(name, fixture, fixtureDesc)
      local option = subMenu:addOption(name, nil, function()
        if isClient() then
          sendClientCommand(playerObj, "PlumbingFixed", "spawnTestRig", { x = x, y = y, z = z, fixture = fixture })
        else
          local barrels = PFDebugRig.build(x, y, z, true, fixture)
          PFDebugRig.fillEqualTainted(barrels, 15)
        end
      end)
      option.toolTip = ISToolTip:new()
      option.toolTip:initialise()
      option.toolTip:setVisible(false)
      option.toolTip:setName(name)
      option.toolTip.description = "Clears "
        .. PFDebugRig.WIDTH
        .. "x"
        .. PFDebugRig.DEPTH
        .. " tiles (two floors) at the clicked square and builds a plumbed test rig there"
        .. " (4 barrels, 15L tainted water each; edit via Configure Barrel Fluids). "
        .. fixtureDesc
    end

    addSpawnOption("Sink Rig", "sink", "Fixture: sink.")
    addSpawnOption(
      "Washer Rig",
      "washer",
      "Fixture: clothing washer -- needs power and dirty clothing inside; a wash cycle"
        .. " runs 90 in-game minutes at 1 unit/min (see docs/WASHER-POOLING.md)."
    )
  end)
end
