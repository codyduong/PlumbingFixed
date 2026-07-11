require("PlumbingFixed/DebugRig")

-- Always-available mod options (Options -> Mods), NOT sandbox options: these are
-- client-side switches, present regardless of the save/server. Sandbox options remain the
-- place for anything that changes simulation behavior (e.g. a future barrel-flow setting).
local options = PZAPI.ModOptions:create("PlumbingFixed", "Plumbing Fixed")
local spawnRigOption = options:addTickBox(
  "spawnTestRig",
  "Enable 'Spawn Test Rig' (DO NOT ENABLE UNLESS YOU KNOW WHAT YOU ARE DOING)",
  false,
  "Adds a debug/admin-only right-click option that CLEARS a "
    .. PFDebugRig.WIDTH
    .. "x"
    .. PFDebugRig.DEPTH
    .. " area (two floors!) and builds the PlumbingFixed barrel/sink test rig there. "
    .. "For mod development only."
)

Events.OnPreFillWorldObjectContextMenu.Add(function(player, context, worldObjects)
  if not spawnRigOption:getValue() then
    return
  end
  -- Same debug gate as PFPlumbedConnectedMenu (mirrors vanilla DebugContextMenu).
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
      -- MP: the world is server-authoritative; ask the server to build (it re-checks the
      -- capability — see server/PlumbingFixedServer.lua).
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
