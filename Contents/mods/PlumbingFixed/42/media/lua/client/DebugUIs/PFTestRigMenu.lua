require("PlumbingFixed/DebugRig")
require("PFModOptions")

if isDebugEnabled() then
  local spawnRigOption = PFModOptions.options:addTickBox(
    "spawnTestRig",
    getText("IGUI_PFSpawnTestRigOption"),
    false,
    getText("IGUI_PFSpawnTestRigTooltip", PFDebugRig.WIDTH, PFDebugRig.DEPTH)
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

    local parent = context:addDebugOption(getText("ContextMenu_PFSpawnTestRig"), nil, nil)
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
      option.toolTip.description = getText("ContextMenu_PFSpawnRigTooltip", PFDebugRig.WIDTH, PFDebugRig.DEPTH)
        .. " "
        .. fixtureDesc
    end

    addSpawnOption(getText("ContextMenu_PFSinkRig"), "sink", getText("ContextMenu_PFFixtureSink"))
    addSpawnOption(getText("ContextMenu_PFWasherRig"), "washer", getText("ContextMenu_PFFixtureWasher"))
  end)
end
