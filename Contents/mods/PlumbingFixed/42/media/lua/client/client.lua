require("PlumbingFixed/utils")

Events.OnPreFillWorldObjectContextMenu.Add(function(player, context, worldObjects)
  for i = 2, #worldObjects do
    local waterObject = worldObjects[i];
    resyncFluidAmounts(waterObject)
    if waterObject:getUsesExternalWaterSource() then
      local waterTotal = getPlumbedWaterAmount(waterObject);
      -- hack, we need to subtract the current water because we scanned it already
      --- @type number
      local addedWater = math.min(waterTotal - waterObject:getFluidAmount(), waterObject:getFluidCapacity());
      local syncedTo = waterObject:FindExternalWaterSource();
      local data = syncedTo:getModData();
      data.PlumbingFixed = {
        waterToRemove = addedWater,
      };
      syncedTo:setModData(data);
      syncedTo:addFluid(FluidType.Water, addedWater);
    end
  end
end)
