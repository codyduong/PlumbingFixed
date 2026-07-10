function ISCleanBandage:isValid()
	if self.item:getContainer() ~= self.character:getInventory() then return false end
	return self.waterObject:hasWater()
end

function ISCleanBandage:complete()
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

	if instanceof(self.waterObject, "IsoWorldInventoryObject") then
		self.waterObject:useFluid(1)
	else
		if self.waterObject:useFluid(1) > 0 then
			self.waterObject:transmitModData()
		end
	end

	return true;
end

