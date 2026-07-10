function ISTakeWaterAction:isValid()
	if self.item and not self.item:getContainer() then return false end
	return self.waterObject:hasFluid() and not self.character:hasFullInventory()
end

function ISTakeWaterAction:updateUse(targetDelta)
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
        self:transferFluid(toUseAmount);
    end
end

function ISTakeWaterAction:new(character, item, waterObject, waterTaintedCL)
	local o = ISBaseTimedAction.new(self, character)
	o.item = item;
    o.waterObject = waterObject;
    o.waterTaintedCL = waterTaintedCL;

    local waterAvailable = o.waterObject:getFluidAmount();
    if o.item ~= nil then
		if o.item:getFluidContainer() then
			o.startUsedAmount = o.item:getFluidContainer():getAmount();
			o.endUsedAmount = o.item:getFluidContainer():getCapacity();
			local freeInventoryCapacity = character:getFreeInventoryCapacity();
			if o.item:isEquipped() or character:isEquippedClothing(o.item) then
               freeInventoryCapacity = freeInventoryCapacity/ZomboidGlobals.EquippedOrWornEncumbranceMultiplier;
            end
		    o.waterUnit = math.min(math.min(o.endUsedAmount - o.startUsedAmount, waterAvailable), freeInventoryCapacity);
        end
    else
        local thirst = o.character:getStats():get(CharacterStat.THIRST) * 2
        local waterNeeded = math.min(thirst, waterAvailable)
        o.waterUnit = waterNeeded
        o.startUsedAmount = 0.0
        o.startThirst = thirst;
        o.endUsedAmount = math.min(o.waterUnit, 1.0)
    end
    
	o.maxTime = o:getDuration()
	return o
end

