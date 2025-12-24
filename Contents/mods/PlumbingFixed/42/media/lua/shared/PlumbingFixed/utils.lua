---@param waterObject IsoObject
---@return IsoObject[]
function getPlumbedSources(waterObject)
  local sources = {}
  if not waterObject:hasExternalWaterSource() then
    return sources
  end
  local sq = waterObject:getSquare()
  if not sq then
    return sources
  end

  local x, y, z = sq:getX(), sq:getY(), sq:getZ()
  local cell = waterObject:getCell()

  -- Scan the 3x3 grid on the floor above (z + 1)
  for ix = -1, 1 do
    for iy = -1, 1 do
      local topSq = cell:getGridSquare(x + ix, y + iy, z + 1)

      local objects = topSq:getObjects()
      -- Iterate through all objects on that square
      for i = 0, objects:size() - 1 do
        local obj = objects:get(i)
        local props = obj:getProperties()
        local hasWaterFlag = (props ~= nil) and props:has(IsoFlagType.water)
        local hasWaterPipedFlag = (props ~= nil) and props:has(IsoFlagType.waterPiped)

        if
          not instanceof(obj, "IsoWorldInventoryObject")
          and not instanceof(obj, "IsoDeadBody")
          and not instanceof(obj, "IsoMovingObject")
          and (
            hasWaterFlag
            or hasWaterPipedFlag
            or (
              instanceof(obj, "IsoThumpable")
              and obj:getFluidCapacity() > 0.0
              and (obj:hasWater() or obj:getFluidAmount() == 0)
            )
          )
        then
          table.insert(sources, obj)
        end
      end
    end
  end
  return sources
end

--- @param waterObject IsoObject
--- @return number
function getPlumbedWaterAmount(waterObject)
  local sources = getPlumbedSources(waterObject)
  local amount = 0.0

  for _, src in ipairs(sources) do
    local container = src:getFluidContainer()
    local water = container:getSpecificFluidAmount(Fluid.Get(FluidType.Water))
    local taintedWater = container:getSpecificFluidAmount(Fluid.Get(FluidType.TaintedWater))
    local carbonatedWater = container:getSpecificFluidAmount(Fluid.Get(FluidType.CarbonatedWater))
    amount = amount + water + taintedWater + carbonatedWater
  end
  if amount == 0.0 then
    amount = waterObject:getFluidAmount()
  end

  return amount
end

--- @param waterObject IsoObject
--- @return number
function getPlumbedWaterCapacity(waterObject)
  local sources = getPlumbedSources(waterObject)
  local capacity = 0.0

  for _, src in ipairs(sources) do
    capacity = capacity + src:getFluidCapacity()
  end
  if capacity == 0.0 then
    capacity = waterObject:getFluidAmount()
  end

  return capacity
end
