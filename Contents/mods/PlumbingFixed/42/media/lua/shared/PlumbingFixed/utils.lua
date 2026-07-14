--- Patch based on PFPooledPrimitives
--- @class IsoObject
--- @field __PFraw PFRawBound

---@param waterObject IsoObject
---@param predicate fun(src: IsoObject): boolean
---@return IsoObject[]
function getPlumbedSources(waterObject, predicate)
  local sources = {}
  if not isPlumbed(waterObject) then
    return sources
  end
  local sq = waterObject:getSquare()
  if not sq then
    return sources
  end

  local x, y, z = sq:getX(), sq:getY(), sq:getZ()
  for ix = -1, 1 do
    for iy = -1, 1 do
      local src = findPlumbedSourceAt(x + ix, y + iy, z + 1)
      if src ~= nil then
        if predicate and predicate(src) or true then
          table.insert(sources, src)
        end
      end
    end
  end
  return sources
end

--- Drawable water-category fluid across the pool (the subset removeWaterTopDown moves).
--- @param waterObject IsoObject
--- @return number
function getPlumbedWaterAmount(waterObject)
  local sources = getPlumbedSources(waterObject)
  if not isMultiSource(sources) then
    return getWaterAmount(waterObject)
  end

  local amount = 0.0
  for _, src in ipairs(sources) do
    amount = amount + getWaterAmount(src)
  end
  return amount
end

--- Vanilla-parity getFluidAmount(): total fluid of any type across the pool.
--- @param waterObject IsoObject
--- @return number
function getPlumbedFluidAmount(waterObject)
  local sources = getPlumbedSources(waterObject)
  if not isMultiSource(sources) then
    return waterObject.__PFraw:getFluidAmount()
  end

  local amount = 0.0
  for _, src in ipairs(sources) do
    amount = amount + src:getFluidAmount()
  end
  return amount
end

--- Vanilla-parity hasWater(): fluid present and every non-empty source is entirely
--- water-category.
--- @param waterObject IsoObject
--- @return boolean
function hasPlumbedWater(waterObject)
  local sources = getPlumbedSources(waterObject)
  if not isMultiSource(sources) then
    return waterObject.__PFraw:hasWater()
  end

  local hasAny = false
  for _, src in ipairs(sources) do
    local container = src:getFluidContainer()
    if container:getAmount() > 0 then
      if not container:isAllCategory(FluidCategory.Water) then
        return false
      end
      hasAny = true
    end
  end
  return hasAny
end

--- @param waterObject IsoObject
--- @return number
function getPlumbedWaterCapacity(waterObject)
  local sources = getPlumbedSources(waterObject)
  if not isMultiSource(sources) then
    return waterObject:getFluidCapacity()
  end

  local capacity = 0.0
  for _, src in ipairs(sources) do
    capacity = capacity + src:getFluidCapacity()
  end
  return capacity
end

--- Water-category fluid in the object's own container. Reserve-water sources (no
--- container, e.g. bathtubs) report through getFluidAmount().
--- @param waterObject IsoObject
--- @return number
function getWaterAmount(waterObject)
  local container = waterObject:getFluidContainer()
  if container == nil then
    -- No FluidContainer: a reserve-water source (waterPiped + waterAmount reserve, e.g. a
    -- bathtub) exposes its water only through getFluidAmount(), which reads the reserve.
    -- Returns 0 for a genuinely dry / non-source object.
    return waterObject:getFluidAmount()
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
  local sources = getPlumbedSources(waterObject)
  if not isMultiSource(sources) then
    return waterObject.__PFraw:moveFluidToTemporaryContainer(amount)
  end

  --- @type table<number, { obj: IsoObject, amt: number }>
  local list = {}
  for _, src in ipairs(sources) do
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

--- Single dispatch point for pooled draws (docs/WASHER-POOLING.md). The only policy today
--- is Fullest-First (removeWaterTopDown, the v1 behavior); a future sandbox option will
--- select between Fullest-First and Round-Robin here, applying to every consumer at once.
--- @param waterObject IsoObject
--- @param amount number
--- @return FluidContainer container Java-managed; the caller must dispose it
function drawFromPool(waterObject, amount)
  return removeWaterTopDown(waterObject, amount)
end

--- Vanilla-parity useFluid(): pooled draw clamped to drawable water.
--- @param waterObject IsoObject
--- @param amount number
--- @return number used
function usePlumbedFluid(waterObject, amount)
  if not isMultiSource(getPlumbedSources(waterObject)) then
    return waterObject.__PFraw:useFluid(amount)
  end

  local used = math.max(0, math.min(amount, getPlumbedWaterAmount(waterObject)))
  if used > 0 then
    FluidContainer.DisposeContainer(drawFromPool(waterObject, used))
  end
  return used
end

--- Vanilla-parity moveFluidToTemporaryContainer(): drains the pool, hands back clean
--- Water (vanilla likewise purifies external-source draws).
--- @param waterObject IsoObject
--- @param amount number
--- @return FluidContainer container Java-managed; the caller must dispose it
function movePlumbedFluidToTemporaryContainer(waterObject, amount)
  if not isMultiSource(getPlumbedSources(waterObject)) then
    return waterObject.__PFraw:moveFluidToTemporaryContainer(amount)
  end

  local transferAmount = math.max(0, math.min(amount, getPlumbedWaterAmount(waterObject)))
  if transferAmount > 0 then
    FluidContainer.DisposeContainer(drawFromPool(waterObject, transferAmount))
  end
  local container = FluidContainer.CreateContainer()
  container:setCapacity(transferAmount)
  container:addFluid(Fluid.Water, transferAmount)
  return container
end

--- Vanilla-parity transferFluidTo(): drains the pool, adds clean Water to the target.
--- @param waterObject IsoObject
--- @param target FluidContainer
--- @param amount number
--- @return number used
function transferPlumbedFluidTo(waterObject, target, amount)
  if not isMultiSource(getPlumbedSources(waterObject)) then
    return waterObject.__PFraw:transferFluidTo(target, amount)
  end
  if target == nil then
    return 0
  end

  local used = math.max(0, math.min(amount, target:getFreeCapacity(), getPlumbedWaterAmount(waterObject)))
  if used > 0 then
    FluidContainer.DisposeContainer(drawFromPool(waterObject, used))
    target:addFluid(Fluid.Water, used)
  end
  return used
end

--- @param x number
--- @param y number
--- @param z number
--- @return IsoObject?
function findPlumbedSourceAt(x, y, z)
  local sq = getCell():getGridSquare(x, y, z)
  if sq == nil then
    return nil
  end
  return IsoObject.FindWaterSourceOnSquare(sq)
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
  return waterObject:getUsesExternalWaterSource() or isPlumbedFlag
end

--- @param player IsoPlayer?
--- @return boolean
function PFIsAdmin(player)
  if player == nil then
    return false
  end
  local role = player:getRole()
  return role ~= nil and role:getName() == "admin"
end

--- @param sources IsoObject[]
--- @return boolean
function isMultiSource(sources)
  return #sources > 1
end
