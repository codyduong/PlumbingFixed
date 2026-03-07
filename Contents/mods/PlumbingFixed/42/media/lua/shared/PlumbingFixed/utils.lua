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
    local water = container:getSpecificFluidAmount(Fluid.Water)
    local taintedWater = container:getSpecificFluidAmount(Fluid.TaintedWater)
    local carbonatedWater = container:getSpecificFluidAmount(Fluid.CarbonatedWater)
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
    capacity = waterObject:getFluidCapacity()
  end

  return capacity
end

--- @param waterObject IsoObject
--- @return boolean
function getPlumbedHasWater(waterObject)
  local sources = getPlumbedSources(waterObject)

  if waterObject:hasWater() then
    return true
  end

  for _, src in ipairs(sources) do
    local hasWater = src:hasWater()
    if hasWater then
      return true
    end
  end

  return false
end

--- @param waterObject IsoObject
--- @param amount number
function removeWaterTopDown(waterObject, amount)
  local srcs = getPlumbedSources(waterObject)

  if #srcs == 0 then
    local container = waterObject:moveFluidToTemporaryContainer(amount)
    FluidContainer.DisposeContainer(container)
  end

  --- @type table<number, { obj: IsoObject, amt: number }>
  local list = {}
  for _, src in ipairs(srcs) do
    table.insert(list, { obj = src, amt = src:getFluidAmount() })
  end

  local remaining = amount
  while remaining > 0.0001 do -- Threshold for float precision
    -- 2. Sort descending
    table.sort(list, function(a, b)
      return a.amt > b.amt
    end)

    -- 3. Find how many share the top value
    local count = 0
    local topAmt = list[1].amt
    for i = 1, #list do
      if list[i].amt >= topAmt - 0.0001 then -- Float safe comparison
        count = i
      else
        break
      end
    end

    -- 4. Determine how much we can drop these 'count' containers
    local nextAmt = (count < #list) and list[count + 1].amt or 0
    local diff = topAmt - nextAmt
    local totalAvailableInLayer = diff * count

    local extractionStep = 0
    if totalAvailableInLayer > remaining then
      -- We only need a fraction of this gap
      extractionStep = remaining / count
      remaining = 0
    else
      -- We drain this entire layer to match the next level
      extractionStep = diff
      remaining = remaining - totalAvailableInLayer
    end

    -- 5. Apply the extraction to our tracking list
    for i = 1, count do
      list[i].amt = list[i].amt - extractionStep
    end
  end

  for _, item in ipairs(list) do
    local original = item.obj:getFluidAmount()
    local toRemove = original - item.amt
    if toRemove > 0 then
      local container = item.obj:moveFluidToTemporaryContainer(toRemove)
      FluidContainer.DisposeContainer(container)
    end
  end
end
