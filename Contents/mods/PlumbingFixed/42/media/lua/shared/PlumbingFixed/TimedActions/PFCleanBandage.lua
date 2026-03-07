-- require("lua/shared/TimedActions/ISCleanBandage")
-- require("PlumbingFixed/utils")

-- ---@class PFCleanBandage : ISCleanBandage
-- local PFCleanBandage = ISCleanBandage

-- local original = {
--   complete = ISCleanBandage.complete,
-- }

-- function ISCleanBandage:isValid()
--   if self.item:getContainer() ~= self.character:getInventory() then
--     return false
--   end

--   return self.waterObject:hasWater() or getPlumbedHasWater(self.waterObject)
-- end

-- function ISCleanBandage:complete()
--   local usePlumbingFixed = self.waterObject:hasExternalWaterSource() or getPlumbedHasWater(self.waterObject)

--   --- @cast f IsoObject
--   if not usePlumbingFixed then
--     return original.complete(self)
--   end

--   local primary = self.character:isPrimaryHandItem(self.item)
--   local secondary = self.character:isSecondaryHandItem(self.item)
--   self.character:getInventory():Remove(self.item)
--   local item = self.character:getInventory():AddItem(self.result)
--   sendReplaceItemInContainer(self.character:getInventory(), self.item, item)
--   if primary then
--     self.character:setPrimaryHandItem(item)
--   end
--   if secondary then
--     self.character:setSecondaryHandItem(item)
--   end
--   sendEquip(self.character)

--   local maxWaterObj = self.waterObject
--   --- @type table<number, IsoObject>
--   local sharedMaxWaterObj = {}
--   for _, src in ipairs(getPlumbedSources(self.waterObject)) do
--     local compareWater = src:getFluidAmount()
--     if maxWaterObj:getFluidAmount() == src:getFluidAmount() then
--       table.insert(sharedMaxWaterObj, src)
--     elseif maxWaterObj:getFluidAmount() < src:getFluidAmount() then
--       maxWaterObj = src
--       sharedMaxWaterObj = {}
--     end
--   end

--   local sum = 0
--   for _, src in ipairs(sharedMaxWaterObj) do
--     sum = sum + src:getFluidAmount()
--   end
--   if sum <= 1 then
--     return false
--   end

--   local divisor = #sharedMaxWaterObj
--   local removeAmt = 1.0 / divisor
--   for _, src in ipairs(sharedMaxWaterObj) do
--     local container = src:moveFluidToTemporaryContainer(removeAmt)
--     FluidContainer.DisposeContainer(container)
--   end

--   return true
-- end
