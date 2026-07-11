require("PlumbingFixed/utils")

--- @param object IsoObject | nil
--- @param context ISContextMenu
local function showDebugMenu(object, context)
  if object == nil then
    return
  end
  local plumbedObjects = getPlumbedSources(object)
  if #plumbedObjects == 0 then
    return
  end

  local option = context:addDebugOption(getText("ContextMenu_DebugConnectedSources"))
  if option == nil then
    return
  end
  option.toolTip = ISToolTip:new()
  option.toolTip:initialise()
  option.toolTip:setVisible(false)
  option.toolTip:setName("Connected Barrels Info:")
  local subMenu = context:getNew(context)
  local waterTotal = 0.0
  for i, src in ipairs(plumbedObjects) do
    --- @cast src IsoObject
    local fluidAmount = src:getFluidAmount()
    local capacity = src:getFluidCapacity()
    waterTotal = waterTotal + fluidAmount

    local title = "Water Source " .. i
    local subOption = subMenu:addOption(title)

    subOption.toolTip = ISToolTip:new()
    subOption.toolTip:initialise()
    subOption.toolTip:setVisible(false)
    subOption.toolTip:setName(title)

    local x, y, z = src:getX(), src:getY(), src:getZ()
    local customName = src:getProperty("CustomName")
    local tileName = src:getTileName()
    local name = src:getName()

    local description = ""
    description = description .. "Fluid = " .. fluidAmount .. "/" .. capacity .. "\n"
    description = description .. "Has Water = " .. tostring(src:hasWater()) .. "\n"
    description = description .. "Is Tainted = " .. tostring(src:isTaintedWater()) .. "\n"
    description = description .. "Coordinates = x:" .. x .. ", y:" .. y .. ", z:" .. z .. "\n"
    description = description .. "Custom Name = " .. tostring(customName) .. "\n"
    description = description .. "Name = " .. name .. "\n"
    description = description .. "Tile Name = " .. tostring(tileName) .. "\n"

    subOption.toolTip.description = description
  end
  local totalDescription = ""
  totalDescription = totalDescription .. "connectedSources = " .. #plumbedObjects .. "\n"
  totalDescription = totalDescription .. "connectedWaterAmounts = " .. tostring(waterTotal) .. "\n"
  option.toolTip.description = totalDescription
  context:addSubMenu(option, subMenu)
end

Events.OnPreFillWorldObjectContextMenu.Add(function(_player, context, worldObjects)
  local waterObject = findWaterObject(worldObjects)
  showDebugMenu(waterObject, context)
end)
