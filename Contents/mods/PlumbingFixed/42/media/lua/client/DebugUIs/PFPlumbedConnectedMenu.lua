require("PlumbingFixed/utils")
require("DebugUIs/PFBarrelFluidWindow")

--- @param player integer
--- @param object IsoObject | nil
--- @param context ISContextMenu
local function showDebugMenu(player, object, context)
  if object == nil then
    return
  end
  local plumbedObjects = getPlumbedSources(object)
  if #plumbedObjects == 0 then
    return
  end

  local option = context:addDebugOption(getText("ContextMenu_DebugConnectedSources"), nil, function()
    PFBarrelFluidWindow.open(player, plumbedObjects)
  end)
  if option == nil then
    return
  end

  local waterTotal = 0.0
  for _, src in ipairs(plumbedObjects) do
    --- @cast src IsoObject
    waterTotal = waterTotal + src:getFluidAmount()
  end

  option.toolTip = ISToolTip:new()
  option.toolTip:initialise()
  option.toolTip:setVisible(false)
  option.toolTip:setName(getText("ContextMenu_PFConnectedBarrelsInfo"))
  local totalDescription = ""
  totalDescription = totalDescription .. "connectedSources = " .. #plumbedObjects .. "\n"
  totalDescription = totalDescription .. "connectedWaterAmounts = " .. tostring(waterTotal) .. "\n"
  option.toolTip.description = totalDescription
end

Events.OnPreFillWorldObjectContextMenu.Add(function(player, context, worldObjects)
  -- Same debug gate as vanilla DebugContextMenu.doDebugMenu: without it the option
  -- shows for every player (addDebugOption itself does not check debug mode).
  if isClient() then
    if not getSpecificPlayer(player):getRole():hasCapability(Capability.UseDebugContextMenu) then
      return
    end
  elseif not isDebugEnabled() then
    return
  end
  local waterObject = findWaterObject(worldObjects)
  showDebugMenu(player, waterObject, context)
end)
