---@param waterObject IsoObject
---@return IsoObject[]
function getPlumbedSources(waterObject)
  local sources = {}
  if not isPlumbed(waterObject) then
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
      -- getGridSquare returns nil for unloaded squares
      local topSq = cell:getGridSquare(x + ix, y + iy, z + 1)
      if topSq ~= nil then
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
                and (obj:hasWater() or getWaterAmount(obj) > 0 or obj:getFluidAmount() == 0)
              )
            )
          then
            table.insert(sources, obj)
          end
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
    amount = amount + getWaterAmount(src)
  end
  if amount == 0.0 then
    amount = getWaterAmount(waterObject)
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
--- @return number
function getWaterAmount(waterObject)
  local container = waterObject:getFluidContainer()
  -- typically means its empty
  if container == nil then
    return 0
  end

  return container:getSpecificFluidAmount(Fluid.Water)
    + container:getSpecificFluidAmount(Fluid.TaintedWater)
    + container:getSpecificFluidAmount(Fluid.CarbonatedWater)
end

--- @param waterObject IsoObject
--- @param amount number
--- @return FluidContainer
function removeWaterTopDown(waterObject, amount)
  DebugLog.log(
    DebugType.Mod,
    "PlumbingFixed (utils) - removeWaterTopDown called with: " .. waterObject:toString() .. ", " .. tostring(amount)
  )
  local srcs = getPlumbedSources(waterObject)

  if #srcs == 0 then
    local container = waterObject:moveFluidToTemporaryContainer(amount)
    return container
  end

  --- @type table<number, { obj: IsoObject, amt: number }>
  local list = {}
  for _, src in ipairs(srcs) do
    --- @cast src IsoObject
    table.insert(list, { obj = src, amt = getWaterAmount(src) })
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

    local extractionStep = 0.0
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

  local completeMixed = FluidContainer:CreateContainer()
  for i = 1, #list do
    local item = list[i]
    local original = getWaterAmount(item.obj)
    local toRemove = original - item.amt
    if toRemove > 0 then
      -- purify only tainted water
      local mixed = item.obj:moveFluidToTemporaryContainer(toRemove)
      local allFluids = Fluid.getAllFluids()
      for j = 0, allFluids:size() - 1 do
        local fluid = allFluids:get(j)

        local specificFluidAmount = mixed:getSpecificFluidAmount(fluid)
        if fluid == Fluid.TaintedWater then
          completeMixed:addFluid(Fluid.Water, specificFluidAmount)
        else
          completeMixed:addFluid(fluid, specificFluidAmount)
        end
      end
      FluidContainer.DisposeContainer(mixed)
    end
  end
  DebugLog.log(DebugType.Mod, "PlumbingFixed (utils.removeWaterTopDown) - " .. completeMixed:toString())

  return completeMixed
end

--- @param x number
--- @param y number
--- @param z number
--- @return IsoObject?
function findFluidObjectAt(x, y, z)
  local sq = getCell():getGridSquare(x, y, z)
  if sq == nil then
    return nil
  end
  local objects = sq:getObjects()
  for i = 0, objects:size() - 1 do
    local obj = objects:get(i)
    if
      instanceof(obj, "IsoWorldInventoryObject")
      and not instanceof(obj, "IsoDeadBody")
      and not instanceof(obj, "IsoMovingObject")
      and not obj:getFluidContainer() ~= nil
    then
      return obj
    end
  end
  return nil
end

--- returns the waterObject (that needs adjusting) if there is one
--- @param worldObjects IsoObject[]
--- @return IsoObject?
function findWaterObject(worldObjects)
  for i = 1, #worldObjects do
    local square = worldObjects[i]:getSquare()
    local objects = square:getObjects()
    -- java array requires 0 index
    for j = 0, objects:size() - 1 do
      local object = objects:get(j)
      if object ~= nil and isPlumbed(object) then
        local plumbed = getPlumbedSources(object)
        if #plumbed > 0 then
          return object
        end
      end
    end
  end
end

--- @param waterObject IsoObject
--- @return boolean
function isPlumbed(waterObject)
  local isPlumbedFlag = waterObject:getModData().canBeWaterPiped == false
  return waterObject:hasExternalWaterSource() or waterObject:getUsesExternalWaterSource() or isPlumbedFlag
end
