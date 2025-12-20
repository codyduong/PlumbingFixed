require("PlumbingFixed/utils")

--- @param object IsoObject
--- @param context ISContextMenu
local function showDebugMenu(object, context)
  if object == nil then return false end;
  if object:getUsesExternalWaterSource() then
    local plumbedObjects = getPlumbedSources(object);
    if #plumbedObjects > 0 then
      local option = context:addDebugOption("ContextMenu_DebugConnectedSources");
      if (option == nil) then
        return;
      end
      option.toolTip = ISToolTip:new();
      option.toolTip:initialise();
      option.toolTip:setVisible(false);
      option.toolTip:setName("Connected Barrels Info:");
      local subMenu = context:getNew(context)
      local waterTotal = 0.0;
      for i, src in ipairs(plumbedObjects) do
        --- @cast src IsoObject
        local fluidAmount = src:getFluidAmount();
        local capacity = src:getFluidCapacity();
        waterTotal = waterTotal + fluidAmount;

        local title = "Water Source "..i
        local subOption = subMenu:addOption(title)

        subOption.toolTip = ISToolTip:new();
        subOption.toolTip:initialise();
        subOption.toolTip:setVisible(false);
        subOption.toolTip:setName(title);

        local x,y,z = src:getX(), src:getY(), src:getZ();
        local customName = src:getProperty("CustomName")
        local tileName = src:getTileName();

        local description = ""
        description = description.."  Fluid = "..fluidAmount.."/"..capacity.."\n";
        description = description.."  Has Water = "..(src:hasWater() and "true" or "false").."\n";
        description = description.."  Is Tainted = "..(src:isTaintedWater() and "true" or "false").."\n";
        description = description.."  Coordinates = x:"..x..", y:"..y..", z:"..z.."\n";
        description = customName and (description.."  Custom Name = "..customName.."\n") or description;
        description = description.."  Tile Name = "..(tileName or "nil");

        subOption.toolTip.description = description
      end
      local totalDescription = ""
      totalDescription = totalDescription.."connectedSources = "..(#plumbedObjects).."\n"; 
      totalDescription = totalDescription.."connectedWaterAmounts = "..tostring(waterTotal).."\n";
      option.toolTip.description = totalDescription; 
      context:addSubMenu(option, subMenu);
      return true;
    end
  end

  return false;
end

Events.OnPreFillWorldObjectContextMenu.Add(function(player, context, worldObjects)
  -- This first object always has a duplicate in the table, which is why the loop starts at 2.
  for i = 2, #worldObjects do
    local square = worldObjects[i]:getSquare();
    local objects = square:getObjects()
    -- java array requires 0 index
    for j = 0, objects:size() - 1 do
      local object = objects:get(j)
      if showDebugMenu(object, context) then
        return
      end
    end
  end
end)