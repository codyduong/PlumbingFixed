require("lua/shared/TimedActions/ISCleanBandage")
require("PlumbingFixed/utils")

---@class PFCleanBandage : ISCleanBandage
local _PFCleanBandage = ISCleanBandage

local original = {
  isValid = ISCleanBandage.isValid,
  complete = ISCleanBandage.complete,
}

function ISCleanBandage:isValid()
  if self.item:getContainer() ~= self.character:getInventory() then
    return false
  end
  -- getUsesExternalWaterSource() is the server-authoritative synced plumbing flag; see the
  -- golden rule in CLAUDE.md and PFTakeWaterAction.
  if not self.waterObject:getUsesExternalWaterSource() then
    return original.isValid(self)
  end
  return getPlumbedWaterAmount(self.waterObject) > 0
end

function ISCleanBandage:complete()
  if not self.waterObject:getUsesExternalWaterSource() then
    return original.complete(self)
  end

  -- Item swap (mirrors vanilla ISCleanBandage:complete).
  local primary = self.character:isPrimaryHandItem(self.item)
  local secondary = self.character:isSecondaryHandItem(self.item)
  self.character:getInventory():Remove(self.item)
  local item = self.character:getInventory():AddItem(self.result)
  sendReplaceItemInContainer(self.character:getInventory(), self.item, item)
  if primary then
    self.character:setPrimaryHandItem(item)
  end
  if secondary then
    self.character:setSecondaryHandItem(item)
  end
  sendEquip(self.character)

  -- Vanilla consumes 1 unit via waterObject:useFluid(1), which drains the single external
  -- source; draw it evenly from the pooled 3x3 instead. drawFromPool returns a
  -- Java-managed container we must dispose (its side effect is the pooled drain).
  FluidContainer.DisposeContainer(drawFromPool(self.waterObject, 1))

  return true
end
