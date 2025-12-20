require("lua/shared/TimedActions/ISTakeWaterAction")
require("PlumbingFixed/utils")

---@class ISTakeWaterActionOverride : ISTakeWaterAction
---@field externalWaterSources? IsoObject[]
local ISTakeWaterActionOverride = ISTakeWaterAction

local original = {
  -- isValid = ISTakeWaterAction.isValid,
  updateUse = ISTakeWaterAction.updateUse,
  -- start = ISTakeWaterAction.start,
  getDuration = ISTakeWaterAction.getDuration,
}

-- don't put in table, will fuck up metatable stuff
local originalNew = ISTakeWaterAction.new

---@return boolean
function ISTakeWaterAction:isValid()
  if self.item and not self.item:getContainer() then return false end

  --- @cast self ISTakeWaterActionOverride
  if self.externalWaterSources == nil or #self.externalWaterSources == 0 then
    return self.waterObject:hasFluid()
  end

  for _, src in ipairs(self.externalWaterSources) do
    if src:hasFluid() then
      return true
    end
  end

  return false
end

---@param targetDelta number
function ISTakeWaterAction:updateUse(targetDelta)
  --- @cast self ISTakeWaterActionOverride
  if self.externalWaterSources == nil or #self.externalWaterSources == 0 then
    return original.updateUse(self, targetDelta)
  end

  if self.waterUnit and self.waterUnit > 0 then
    local usedTarget = self.waterUnit * targetDelta;

    local currentUsedAmount = 0;
    if self.item ~= nil then
      if self.item:getFluidContainer() then
        currentUsedAmount = self.item:getFluidContainer():getAmount();
      end
    else
      currentUsedAmount = self.startThirst - (self.character:getStats():get(CharacterStat.THIRST) * 2);
    end
    local usedSoFar = currentUsedAmount - self.startUsedAmount;

    local toUseAmount = math.max(0, usedTarget - usedSoFar);
    self:transferFromMax(toUseAmount);
  end
end

---@param _amount number
function ISTakeWaterAction:transferFromMax(_amount)
  local maxWaterObj = self.waterObject;
  --- @cast self {externalWaterSources: IsoObject[]}
  for _, src in ipairs(self.externalWaterSources) do
    local compareWater = src:getFluidAmount()
    if maxWaterObj:getFluidAmount() < src:getFluidAmount() then
      maxWaterObj = src
    end
  end

  if _amount <= 0 or maxWaterObj:getFluidAmount() <= 0 then
    return;
  end
  
  --We transfer to a new container, empty it, then refill with clean water to 
  --emulate the old behavior of filtering water. Most likely breaks compat with
  --almost any other plumbing mod that modifies the default 3x3 plumbing behavior
  ---@cast self ISTakeWaterAction
  if self.item then
    local fluidContainer = maxWaterObj:moveFluidToTemporaryContainer(_amount);
    fluidContainer:Empty()
    fluidContainer:addFluid(Fluid.Water, _amount);
    fluidContainer:transferTo(self.item:getFluidContainer());
    FluidContainer.DisposeContainer(fluidContainer);
    self.item:syncItemFields();
    sendItemStats(self.item)
  else
    local fluidContainer = maxWaterObj:moveFluidToTemporaryContainer(_amount);
    fluidContainer:Empty()
    fluidContainer:addFluid(Fluid.Water, _amount);
    self.character:DrinkFluid(fluidContainer, 1);
    FluidContainer.DisposeContainer(fluidContainer);
  end
end

---@param character IsoPlayer
---@param item InventoryItem?
---@param waterObject IsoObject
---@param waterTaintedCL boolean
---@return ISTakeWaterAction
function ISTakeWaterAction:new(character, item, waterObject, waterTaintedCL) 
  if not waterObject:getUsesExternalWaterSource() then
    return originalNew(self, character, item, waterObject, waterTaintedCL);
  end

  ---@cast ISBaseTimedAction.new fun(character: IsoPlayer): ISTakeWaterActionOverride
  local o = ISBaseTimedAction.new(self, character);
	o.item = item;
  o.waterObject = waterObject;
  o.waterTaintedCL = waterTaintedCL;
  o.externalWaterSources = getPlumbedSources(waterObject);
  local waterAvailable = getPlumbedWaterAmount(waterObject);

  if o.item ~= nil then
		if o.item:getFluidContainer() then
			o.startUsedAmount = o.item:getFluidContainer():getAmount();
			o.endUsedAmount = o.item:getFluidContainer():getCapacity();
		  o.waterUnit = math.min(o.endUsedAmount - o.startUsedAmount, waterAvailable)
    end
  else
    local thirst = o.character:getStats():get(CharacterStat.THIRST) * 2;
    local waterNeeded = math.min(thirst, waterAvailable);
    o.waterUnit = waterNeeded;
    o.startUsedAmount = 0.0;
    o.startThirst = thirst;
    o.endUsedAmount = math.min(o.waterUnit, 1.0)
  end
    
	o.maxTime = o:getDuration()
	return o
end
