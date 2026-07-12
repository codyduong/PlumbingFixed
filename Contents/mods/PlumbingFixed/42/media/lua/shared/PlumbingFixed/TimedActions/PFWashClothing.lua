require("lua/shared/TimedActions/ISWashClothing")
require("PlumbingFixed/utils")

---@class PFWashClothing : ISWashClothing
local _PFWashClothing = ISWashClothing

local original = {
  isValid = ISWashClothing.isValid,
  complete = ISWashClothing.complete,
}

function ISWashClothing:isValid()
  if not isMultiSource(self.sink) then
    return original.isValid(self)
  end

  if getPlumbedWaterAmount(self.sink) < ISWashClothing.GetRequiredWater(self.item) then
    return false
  end
  -- A dirty bandage is converted into a different item.
  if not isClient() and self.item:getContainer() ~= self.character:getInventory() then
    return false
  end
  return true
end

function ISWashClothing:complete()
  if not isMultiSource(self.sink) then
    return original.complete(self)
  end

  local item = self.item
  local water = ISWashClothing.GetRequiredWater(item)
  local isRemoved = false
  if instanceof(item, "Clothing") or instanceof(item, "InventoryContainer") then
    local coveredParts = BloodClothingType.getCoveredParts(item:getBloodClothingType())
    ---@diagnostic disable-next-line: unnecessary-if
    if coveredParts then
      for j = 0, coveredParts:size() - 1 do
        if self.noSoap == false then
          self:useSoap(item, coveredParts:get(j))
        end
        item:setBlood(coveredParts:get(j), 0)
        item:setDirt(coveredParts:get(j), 0)
      end
    end
    if instanceof(item, "Clothing") then
      ---@diagnostic disable-next-line: undefined-field
      item:setWetness(100)
      ---@diagnostic disable-next-line: undefined-field
      item:setDirtiness(0)
    end
  ---@diagnostic disable-next-line: unnecessary-if
  elseif item:getItemAfterCleaning() then
    isRemoved = true
    local newItemType = item:getItemAfterCleaning()
    self.character:getInventory():Remove(item)
    sendRemoveItemFromContainer(self.character:getInventory(), item)
    local newItem = self.character:getInventory():AddItem(newItemType)
    newItem:setFavorite(item:isFavorite())
    sendAddItemToContainer(self.character:getInventory(), newItem)
  else
    self:useSoap(item, nil)
  end

  item:setBloodLevel(0)
  -- if we haven't already removed item
  if not isRemoved then
    --sync Wetness, Dirtyness, BloodLevel
    syncItemFields(self.character, item)
  end
  syncVisuals(self.character)
  self.character:updateHandEquips()

  if self.character:isPrimaryHandItem(item) then
    self.character:setPrimaryHandItem(item)
  end
  if self.character:isSecondaryHandItem(item) then
    self.character:setSecondaryHandItem(item)
  end

  FluidContainer.DisposeContainer(drawFromPool(self.sink, water))

  return true
end
