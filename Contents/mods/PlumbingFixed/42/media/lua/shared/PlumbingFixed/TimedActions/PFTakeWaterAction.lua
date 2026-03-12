-- Overrides ISTakeWaterAction.lua

require("lua/shared/TimedActions/ISTakeWaterAction")
require("PlumbingFixed/utils")

---@class PFTakeWaterAction : ISTakeWaterAction
local PFTakeWaterAction = ISTakeWaterAction

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
  if self.item and not self.item:getContainer() then
    return false
  end

  if not self.waterObject:getUsesExternalWaterSource() then
    return self.waterObject:hasFluid()
  end

  DebugLog.log(DebugType.Mod, "PlumbingFixed (PFTakeWaterAction:isValid) last result "..tostring(getPlumbedWaterAmount(self.waterObject)))
  return getPlumbedWaterAmount(self.waterObject) > 0
end

---@param targetDelta number
function ISTakeWaterAction:updateUse(targetDelta)
  -- DebugLog.log(DebugType.Mod, "PlumbingFixed (PFTakeWaterAction:updateUse) called with targetDelta "..tostring(targetDelta))

  -- DebugLog.log(DebugType.Mod, "PlumbingFixed (PFTakeWaterAction:updateUse) self.waterObject "..tostring(self.waterObject:toString()))
  
  -- DebugLog.log(DebugType.Mod, "PlumbingFixed (PFTakeWaterAction:updateUse) self.waterObject:hasExternalWaterSource() "..tostring(self.waterObject:hasExternalWaterSource()))

  -- DebugLog.log(DebugType.Mod, "PlumbingFixed (PFTakeWaterAction:updateUse) self.waterObject:getUsesExternalWaterSource() "..tostring(self.waterObject:getUsesExternalWaterSource()))

  -- It seems like hasExternalWaterSource() is unreliable on the server
  -- so we'll have to use getUsesExternalWaterSource here

  --- @cast self PFTakeWaterAction
  if self:getUsesExternalWaterSource() ~= true then
    return original.updateUse(self, targetDelta)
  end

  DebugLog.log(DebugType.Mod, "PlumbingFixed (PFTakeWaterAction:updateUse) self.waterUnit "..tostring(self.waterUnit))
  if self.waterUnit and self.waterUnit > 0 then
    local usedTarget = self.waterUnit * targetDelta

    local currentUsedAmount = 0
    if self.item ~= nil then
      if self.item:getFluidContainer() then
        currentUsedAmount = self.item:getFluidContainer():getAmount()
      end
    else
      currentUsedAmount = self.startThirst - (self.character:getStats():get(CharacterStat.THIRST) * 2)
    end
    local usedSoFar = currentUsedAmount - self.startUsedAmount

    local toUseAmount = math.max(0, usedTarget - usedSoFar)
    
    DebugLog.log(DebugType.Mod, "PlumbingFixed (PFTakeWaterAction:updateUse) usedSoFar "..tostring(usedSoFar))
    DebugLog.log(DebugType.Mod, "PlumbingFixed (PFTakeWaterAction:updateUse) toUseAmount "..tostring(usedSoFar))
    self:transferFromMax(toUseAmount)
  end
end

---@param _amount number
function ISTakeWaterAction:transferFromMax(_amount)
  local mixed = removeWaterTopDown(self.waterObject, _amount)
  local fluidContainer = FluidContainer.CreateContainer()
  fluidContainer:canAddFluid(Fluid.Water)
  fluidContainer:setCapacity(10000)

  --We transfer to a new container, empty it, then refill with clean water to
  --emulate the old behavior of filtering water. Most likely breaks compat with
  --almost any other plumbing mod that modifies the default 3x3 plumbing behavior
  ---@cast self ISTakeWaterAction
  if self.item then
    DebugLog.log(DebugType.Mod, "PlumbingFixed (PFTakeWaterAction:transferFromMax) - transfering "..tostring(_amount).." "..fluidContainer:getUiName().." to item")
    fluidContainer:addFluid(Fluid.Water, _amount)
    fluidContainer:transferTo(self.item:getFluidContainer())
    self.item:syncItemFields()
    sendItemStats(self.item)
  else
    DebugLog.log(DebugType.Mod, "PlumbingFixed (PFTakeWaterAction:transferFromMax) - drinking "..tostring(_amount).." "..fluidContainer:getUiName())
    fluidContainer:addFluid(Fluid.Water, _amount)
    self.character:DrinkFluid(fluidContainer, 1)
  end
  FluidContainer.DisposeContainer(fluidContainer)
end

---@param character IsoPlayer
---@param item InventoryItem?
---@param waterObject IsoObject
---@param waterTaintedCL boolean
---@return ISTakeWaterAction
function ISTakeWaterAction:new(character, item, waterObject, waterTaintedCL)
  if not waterObject:getUsesExternalWaterSource() then
    DebugLog.log(DebugType.Mod, "PlumbingFixed (PFTakeWaterAction:new) - NOT using custom constructor")
    return originalNew(self, character, item, waterObject, waterTaintedCL)
  end
  DebugLog.log(DebugType.Mod, "PlumbingFixed (PFTakeWaterAction:new) - using custom constructor")

  ---@cast ISBaseTimedAction.new fun(character: IsoPlayer): PFTakeWaterAction
  local o = ISBaseTimedAction.new(self, character)
  o.item = item
  o.waterObject = waterObject
  o.waterTaintedCL = waterTaintedCL
  -- o.externalWaterSources = getPlumbedSources(waterObject)
  local waterAvailable = getPlumbedWaterAmount(waterObject)

  if o.item ~= nil then
    if o.item:getFluidContainer() then
      o.startUsedAmount = o.item:getFluidContainer():getAmount()
      o.endUsedAmount = o.item:getFluidContainer():getCapacity()
      o.waterUnit = math.min(o.endUsedAmount - o.startUsedAmount, waterAvailable)
    end
  else
    local thirst = o.character:getStats():get(CharacterStat.THIRST) * 2
    local waterNeeded = math.min(thirst, waterAvailable)
    o.waterUnit = waterNeeded
    o.startUsedAmount = 0.0
    o.startThirst = thirst
    o.endUsedAmount = math.min(o.waterUnit, 1.0)
  end

  o.maxTime = o:getDuration()
  return o
end
