require "lua/client/ISUI/ISWorldObjectContextMenu"

local function predicateCleaningLiquid(item)
	if not item then return false end
	return item:hasComponent(ComponentType.FluidContainer) and (item:getFluidContainer():contains(Fluid.Bleach) or item:getFluidContainer():contains(Fluid.CleaningLiquid)) and (item:getFluidContainer():getAmount() >= ZomboidGlobals.CleanBloodBleachAmount)
end

local function getMoveableDisplayName(obj)
	if not obj then return nil end
	if not obj:getSprite() then return nil end
	local props = obj:getSprite():getProperties()
	if props:has("CustomName") then
		local name = props:get("CustomName")
		if props:has("GroupName") then
			name = props:get("GroupName") .. " " .. name
		end
		return Translator.getMoveableDisplayName(name)
	end
	return nil
end

function ISWorldObjectContextMenu.toggleComboWasherDryer(context, playerObj, object)
	local playerNum = playerObj:getPlayerNum()

	if not object then return end
	if not object:getContainer() then return end
	if ISWorldObjectContextMenu.isSomethingTo(object, playerNum) then return end
	if getCore():getGameMode() == "LastStand" then return end

	local objectName = object:getName() or "Combo Washer/Dryer"
	local props = object:getProperties()
	if props then
		local groupName = props:has("GroupName") and props:get("GroupName") or nil
		local customName = props:has("CustomName") and props:get("CustomName") or nil
		if groupName and customName then
			objectName = Translator.getMoveableDisplayName(groupName .. " " .. customName)
		elseif customName then
			objectName = Translator.getMoveableDisplayName(customName)
		end
	end

	local subOption = context:addOption(objectName)
	local subMenu = ISContextMenu:getNew(context)
	context:addSubMenu(subOption, subMenu)

	local option = nil
	if object:isActivated() then
		option = subMenu:addGetUpOption(getText("ContextMenu_Turn_Off"), playerObj, ISWorldObjectContextMenu.onToggleComboWasherDryer, object)
	else
		option = subMenu:addGetUpOption(getText("ContextMenu_Turn_On"), playerObj, ISWorldObjectContextMenu.onToggleComboWasherDryer, object)
	end
	local label = object:isModeWasher() and getText("ContextMenu_ComboWasherDryer_SetModeDryer") or getText("ContextMenu_ComboWasherDryer_SetModeWasher")
	if not object:getContainer():isPowered() or (object:isModeWasher() and (getPlumbedWaterAmount(object) <= 0)) then
		option.notAvailable = true
		option.toolTip = ISWorldObjectContextMenu.addToolTip()
		option.toolTip:setVisible(false)
		option.toolTip:setName(getMoveableDisplayName(object))
		if not object:getContainer():isPowered() then
			option.toolTip.description = getText("IGUI_RadioRequiresPowerNearby")
		end
		if object:isModeWasher() and (getPlumbedWaterAmount(object) <= 0) then
			if option.toolTip.description ~= "" then
				option.toolTip.description = option.toolTip.description .. "\n" .. getText("IGUI_RequiresWaterSupply")
			else
				option.toolTip.description = getText("IGUI_RequiresWaterSupply")
			end
		end
	end
	option = subMenu:addGetUpOption(label, playerObj, ISWorldObjectContextMenu.onSetComboWasherDryerMode, object, object:isModeWasher() and "dryer" or "washer")
end

local function formatWaterAmount(object, setX, amount, max)
	-- Water tiles have waterAmount=9999
	-- Piped water has waterAmount=10000
	if max >= 9999 then
		return string.format("%s: <SETX:%d> %s", object:getFluidUiName(), setX, getText("Tooltip_WaterUnlimited"))
	end
	return string.format("%s: <SETX:%d> %s / %s", object:getFluidUiName(), setX, luautils.round(amount, 2) .. "L", luautils.round(max, 2) .. "L")
end

ISWorldObjectContextMenu.doDrinkWaterMenu = function(object, player, context)
	local playerObj = getSpecificPlayer(player)
	local thirst = playerObj:getStats():get(CharacterStat.THIRST)
	--if thirst <= 0 then
	--	return;
	--end
	if object:getSquare():getBuilding() ~= playerObj:getBuilding() then return end;
	if instanceof(object, "IsoClothingDryer") then return end
	if instanceof(object, "IsoClothingWasher") then return end
	local option = context:addGetUpOption(getText("ContextMenu_Drink"), worldobjects, ISWorldObjectContextMenu.onDrink, object, player);
	local units = math.min(math.ceil(thirst / 0.1), 10)
	units = math.min(units, getPlumbedWaterAmount(object))
	local tooltip = ISWorldObjectContextMenu.addToolTip()
	local tx1 = getTextManager():MeasureStringX(tooltip.font, getText("Tooltip_food_Thirst") .. ":") + 20
	local tx2 = getTextManager():MeasureStringX(tooltip.font, object:getFluidUiName() .. ":") + 20
	local tx = math.max(tx1, tx2)
	local waterAmount = getPlumbedWaterAmount(object);
	local waterMax = getPlumbedWaterCapacity(object);
	tooltip.description = tooltip.description ..formatWaterAmount(object, tx, waterAmount, waterMax);
		--	tooltip.description = tooltip.description .. string.format("%s: <SETX:%d> -%d / %d <LINE> %s",
		--getText("Tooltip_food_Thirst"), tx, math.min(units * 10, thirst * 100), thirst * 100,
		--formatWaterAmount(tx, waterAmount, waterMax))
	if object:isTaintedWater() and getSandboxOptions():getOptionByName("EnableTaintedWaterText"):getValue() then
		tooltip.description = tooltip.description .. " <BR> <RGB:1,0.5,0.5> " .. getText("Tooltip_item_TaintedWater")
	end
	option.toolTip = tooltip;
	option.iconTexture = getTexture("Item_WaterDrop");
end


ISWorldObjectContextMenu.doWashClothingMenu = function(sink, player, context)
	local playerObj = getSpecificPlayer(player)
	if sink:getSquare():getBuilding() ~= playerObj:getBuilding() then return end;
	local playerInv = playerObj:getInventory()
	local washYourself = false
	local washEquipment = false
	local washList = {}
	local soapList = {}
	local noSoap = true

	washYourself = ISWashYourself.GetRequiredWater(playerObj) > 0

	local barList = playerInv:getItemsFromType("Soap2", true)
	for i=0, barList:size() - 1 do
		local item = barList:get(i)
		table.insert(soapList, item)
	end

	local bottleList = playerInv:getAllEvalRecurse(predicateCleaningLiquid)
	for i=0, bottleList:size() - 1 do
		local item = bottleList:get(i)
		table.insert(soapList, item)
	end

	local washClothing = {}
	local clothingInventory = playerInv:getItemsFromCategory("Clothing")
	for i=0, clothingInventory:size() - 1 do
		local item = clothingInventory:get(i)
		-- Wasn't able to reproduce the wash 'Blooo' bug, don't know the exact cause so here's a fix...
		if not item:isHidden() and (item:hasBlood() or item:hasDirt()) and not item:hasTag(ItemTag.BREAK_WHEN_WET) then
			if washEquipment == false then
				washEquipment = true
			end
			table.insert(washList, item)
			table.insert(washClothing, item)
		end
	end

	local washOther = {}
	local dirtyRagInventory = playerInv:getAllTag(ItemTag.CAN_BE_WASHED, ArrayList.new())
	for i=0, dirtyRagInventory:size() - 1 do
		local item = dirtyRagInventory:get(i)
		if item:getJobDelta() == 0 then
			if washEquipment == false then
				washEquipment = true
			end
			table.insert(washList, item)
			table.insert(washOther, item)
		end
	end

	local washWeapon = {}
	local weaponInventory = playerInv:getItemsFromCategory("Weapon")
	for i=0, weaponInventory:size() - 1 do
		local item = weaponInventory:get(i)
		if item:hasBlood() then
			if washEquipment == false then
				washEquipment = true
			end
			table.insert(washList, item)
			table.insert(washWeapon, item)
		end
	end

	local washContainer = {}
	local containerInventory = playerInv:getItemsFromCategory("Container")
	for i=0, containerInventory:size() - 1 do
		local item = containerInventory:get(i)
		if not item:isHidden() and (item:hasBlood() or item:hasDirt()) then
			washEquipment = true
			table.insert(washList, item)
			table.insert(washContainer, item)
		end
	end

	-- Sort items from least-bloody to most-bloody.
	table.sort(washList, ISWorldObjectContextMenu.compareClothingBlood)
	table.sort(washClothing, ISWorldObjectContextMenu.compareClothingBlood)
	table.sort(washOther, ISWorldObjectContextMenu.compareClothingBlood)
	table.sort(washWeapon, ISWorldObjectContextMenu.compareClothingBlood)
	table.sort(washContainer, ISWorldObjectContextMenu.compareClothingBlood)

	if washYourself or washEquipment then
		local mainOption = context:addOption(getText("ContextMenu_Wash"), nil, nil);
		local mainSubMenu = ISContextMenu:getNew(context)
		context:addSubMenu(mainOption, mainSubMenu)

--		if #soapList < 1 then
--			mainOption.notAvailable = true;
--			local tooltip = ISWorldObjectContextMenu.addToolTip();
--			tooltip:setName("Need soap.");
--			mainOption.toolTip = tooltip;
--			return;
--		end
		local soapRemaining = 0;
		if soapList and #soapList >= 1 then
			soapRemaining = ISWashClothing.GetSoapRemaining(soapList)
		end
		local waterRemaining = getPlumbedWaterAmount(sink)

		if washYourself then
			local soapRequired = ISWashYourself.GetRequiredSoap(playerObj)
			local waterRequired = ISWashYourself.GetRequiredWater(playerObj)
			local option = mainSubMenu:addGetUpOption(getText("ContextMenu_Yourself"), playerObj, ISWorldObjectContextMenu.onWashYourself, sink, soapList)
			local tooltip = ISWorldObjectContextMenu.addToolTip()
			if soapRemaining < soapRequired then
				tooltip.description = tooltip.description .. getText("IGUI_Washing_WithoutSoap") .. " <LINE> "
			else
				tooltip.description = tooltip.description .. getText("IGUI_Washing_Soap") .. ": " .. round(math.min(soapRemaining, soapRequired), 2) .. " / " .. tostring(soapRequired) .. " <LINE> "
			end
			tooltip.description = tooltip.description .. getText("ContextMenu_WaterName") .. ": " .. round(math.min(waterRemaining, waterRequired), 2) .. " / " .. tostring(waterRequired)
			local visual = playerObj:getHumanVisual()
			local bodyBlood = 0
			local bodyDirt = 0
			for i=1,BloodBodyPartType.MAX:index() do
				local part = BloodBodyPartType.FromIndex(i-1)
				bodyBlood = bodyBlood + visual:getBlood(part)
				bodyDirt = bodyDirt + visual:getDirt(part)
			end
			if bodyBlood > 0 then
				tooltip.description = tooltip.description .. " <LINE> " .. getText("Tooltip_clothing_bloody") .. ": " .. math.ceil(bodyBlood / BloodBodyPartType.MAX:index() * 100) .. " / 100"
			end
			if bodyDirt > 0 then
				tooltip.description = tooltip.description .. " <LINE> " .. getText("Tooltip_clothing_dirty") .. ": " .. math.ceil(bodyDirt / BloodBodyPartType.MAX:index() * 100) .. " / 100"
			end
			option.toolTip = tooltip
			if waterRemaining < 1 then
				option.notAvailable = true
			end
		end

		if washEquipment then
			if #washList > 0 then
				local soapRequired = 0
				local waterRequired = 0
				local option = nil
				if #washClothing > 0 then
					soapRequired, waterRequired = ISWorldObjectContextMenu.calculateSoapAndWaterRequired(washClothing)
					noSoap = soapRequired < soapRemaining
					option = mainSubMenu:addGetUpOption(getText("ContextMenu_WashAllClothing"), playerObj, ISWorldObjectContextMenu.onWashClothing, sink, soapList, washClothing, nil, noSoap);
					ISWorldObjectContextMenu.setWashClothingTooltip(soapRemaining, waterRemaining, washClothing, option)
				end
				if #washContainer > 0 then
					soapRequired, waterRequired = ISWorldObjectContextMenu.calculateSoapAndWaterRequired(washContainer)
					noSoap = soapRequired < soapRemaining
					option = mainSubMenu:addGetUpOption(getText("ContextMenu_WashAllContainer"), playerObj, ISWorldObjectContextMenu.onWashClothing, sink, soapList, washContainer, nil, noSoap);
					ISWorldObjectContextMenu.setWashClothingTooltip(soapRemaining, waterRemaining, washContainer, option)
				end
				if #washWeapon > 0 then
					soapRequired, waterRequired = ISWorldObjectContextMenu.calculateSoapAndWaterRequired(washWeapon)
					noSoap = soapRequired < soapRemaining
					option = mainSubMenu:addGetUpOption(getText("ContextMenu_WashAllWeapon"), playerObj, ISWorldObjectContextMenu.onWashClothing, sink, soapList, washWeapon, nil, noSoap);
					ISWorldObjectContextMenu.setWashClothingTooltip(soapRemaining, waterRemaining, washWeapon, option)
				end
				if #washOther > 0 then
					soapRequired, waterRequired = ISWorldObjectContextMenu.calculateSoapAndWaterRequired(washOther)
					noSoap = soapRequired < soapRemaining
					option = mainSubMenu:addGetUpOption(getText("ContextMenu_WashAllOther"), playerObj, ISWorldObjectContextMenu.onWashClothing, sink, soapList, washOther, nil, noSoap);
					ISWorldObjectContextMenu.setWashClothingTooltip(soapRemaining, waterRemaining, washOther, option)
				end
			end
			for i,item in ipairs(washList) do
				local soapRequired = ISWashClothing.GetRequiredSoap(item)
				local waterRequired = ISWashClothing.GetRequiredWater(item)
				local tooltip = ISWorldObjectContextMenu.addToolTip();
				if (soapRemaining < soapRequired) then
					tooltip.description = tooltip.description .. getText("IGUI_Washing_WithoutSoap") .. " <LINE> "
					noSoap = true;
				else
					tooltip.description = tooltip.description .. getText("IGUI_Washing_Soap") .. ": " .. tostring(math.min(soapRemaining, soapRequired)) .. " / " .. tostring(soapRequired) .. " <LINE> "
					noSoap = false;
				end
				tooltip.description = tooltip.description .. getText("ContextMenu_WaterName") .. ": " .. string.format("%.2f", math.min(waterRemaining, waterRequired)) .. " / " .. tostring(waterRequired)
				if (item:IsClothing() or item:IsInventoryContainer()) and (item:getBloodLevel() > 0) then
					tooltip.description = tooltip.description .. " <LINE> " .. getText("Tooltip_clothing_bloody") .. ": " .. math.ceil(item:getBloodLevel()) .. " / 100"
				end
				if item:IsWeapon() and (item:getBloodLevel() > 0) then
					tooltip.description = tooltip.description .. " <LINE> " .. getText("Tooltip_clothing_bloody") .. ": " .. math.ceil(item:getBloodLevel() * 100) .. " / 100"
				end
				if item:IsClothing() and item:getDirtyness() > 0 then
					tooltip.description = tooltip.description .. " <LINE> " .. getText("Tooltip_clothing_dirty") .. ": " .. math.ceil(item:getDirtyness()) .. " / 100"
				end
				local option = mainSubMenu:addGetUpOption(getText("ContextMenu_WashClothing", item:getDisplayName()), playerObj, ISWorldObjectContextMenu.onWashClothing, sink, soapList, nil, item, noSoap);
				option.toolTip = tooltip;
				option.itemForTexture = item
				if (waterRemaining < waterRequired) then
					option.notAvailable = true;
				end
			end
		end
	end
end


local CleanBandages = {}

function CleanBandages.onCleanOne(playerObj, type, waterObject, recipe)
	local playerInv = playerObj:getInventory()
	local item = playerInv:getFirstTypeRecurse(type)
	if not item then return end
	ISInventoryPaneContextMenu.transferIfNeeded(playerObj, item)
	if not luautils.walkAdj(playerObj, waterObject:getSquare(), true) then return end
	ISTimedActionQueue.add(ISCleanBandage:new(playerObj, item, waterObject, recipe))
end

function CleanBandages.onCleanMultiple(playerObj, type, waterObject, recipe)
	local playerInv = playerObj:getInventory()
	local items = playerInv:getSomeTypeRecurse(type, getPlumbedWaterAmount(waterObject))
	if items:isEmpty() then return end
	ISInventoryPaneContextMenu.transferIfNeeded(playerObj, items)
	if not luautils.walkAdj(playerObj, waterObject:getSquare(), true) then return end
	for i=1,items:size() do
		local item = items:get(i-1)
		ISTimedActionQueue.add(ISCleanBandage:new(playerObj, item, waterObject, recipe))
	end
end

function CleanBandages.onCleanAll(playerObj, waterObject, itemData)
	local waterRemaining = getPlumbedWaterAmount(waterObject)
	if waterRemaining < 1 then return end
	local playerInv = playerObj:getInventory()
	local items = ArrayList.new()
	local itemToRecipe = {}
	for _,data in ipairs(itemData) do
		local first = items:size()
		playerInv:getSomeTypeRecurse(data.itemType, waterRemaining - items:size(), items)
		for i=first,items:size()-1 do
			itemToRecipe[items:get(i)] = data.recipe
		end
		if waterRemaining <= items:size() then
			break
		end
	end
	if items:isEmpty() then return end
	ISInventoryPaneContextMenu.transferIfNeeded(playerObj, items)
	if not luautils.walkAdj(playerObj, waterObject:getSquare(), true) then return end
	for i=1,items:size() do
		local item = items:get(i-1)
		local recipe = itemToRecipe[item]
		ISTimedActionQueue.add(ISCleanBandage:new(playerObj, item, waterObject, recipe))
	end
end

function CleanBandages.getAvailableItems(items, playerObj, recipeName, itemType)
	local recipe = getScriptManager():getRecipe(recipeName)
	if not recipe then return nil end
	local playerInv = playerObj:getInventory()
	local count = playerInv:getCountTypeRecurse(itemType)
	if count == 0 then return end
	table.insert(items, { itemType = itemType, count = count, recipe = recipe })
end

function CleanBandages.setSubmenu(subMenu, item, waterObject)
	local itemType = item.itemType
	local count = item.count
	local recipe = item.recipe
	local waterRemaining = getPlumbedWaterAmount(waterObject)

	local tooltip = nil
	local notAvailable = false
	if waterObject:isTaintedWater() and getSandboxOptions():getOptionByName("EnableTaintedWaterText"):getValue() then
		tooltip = ISWorldObjectContextMenu.addToolTip()
		tooltip.description =  " <RGB:1,0.5,0.5> " .. getText("Tooltip_item_TaintedWater")
		tooltip.maxLineWidth = 512
		notAvailable = true
	else
		tooltip = ISRecipeTooltip.addToolTip()
		tooltip.character = getSpecificPlayer(subMenu.player)
		tooltip.recipe = recipe
		tooltip:setName(recipe:getName())
		local resultItem = getScriptManager():FindItem(recipe:getResult():getFullType())
		if resultItem and resultItem:getNormalTexture() and resultItem:getNormalTexture():getName() ~= "Question_On" then
			tooltip:setTexture(resultItem:getNormalTexture():getName())
		end
	end

	if count > 1 then
		local subOption = subMenu:addOption(recipe:getName())
		local subMenu2 = ISContextMenu:getNew(subMenu)
		subMenu:addSubMenu(subOption, subMenu2)

		local option1 = subMenu2:addActionsOption(getText("ContextMenu_One"), CleanBandages.onCleanOne, itemType, waterObject, recipe)
		option1.toolTip = tooltip
		option1.notAvailable = notAvailable

		local option2 = subMenu2:addActionsOption(getText("ContextMenu_AllWithCount", math.min(count, waterRemaining)), CleanBandages.onCleanMultiple, itemType, waterObject, recipe)
		option2.toolTip = tooltip
		option2.notAvailable = notAvailable
	else
		local option = subMenu:addActionsOption(recipe:getName(), CleanBandages.onCleanOne, itemType, waterObject, recipe)
		option.toolTip = tooltip
		option.notAvailable = notAvailable
	end
end

ISWorldObjectContextMenu.doRecipeUsingWaterMenu = function(waterObject, playerNum, context)
	local playerObj = getSpecificPlayer(playerNum)
	local playerInv = playerObj:getInventory()

	local waterRemaining = getPlumbedWaterAmount(waterObject)
	if waterRemaining < 1 then return end

	-- It would perhaps be better to allow *any* recipes that require water to take water from a clicked-on
	-- water-containing object.  This would be similar to how RecipeManager.isNearItem() works.
	-- We would need to pass the water-containing object to RecipeManager, or pick one in isNearItem().

	local items = {}
	CleanBandages.getAvailableItems(items, playerObj, "Base.Clean Bandage", "Base.BandageDirty")
	CleanBandages.getAvailableItems(items, playerObj, "Base.Clean Denim Strips", "Base.DenimStripsDirty")
	CleanBandages.getAvailableItems(items, playerObj, "Base.Clean Leather Strips", "Base.LeatherStripsDirty")
	CleanBandages.getAvailableItems(items, playerObj, "Base.Clean Rag", "Base.RippedSheetsDirty")

	if #items == 0 then return end

	ISRecipeTooltip.releaseAll()

	-- If there's a single item type, don't display the extra submenu.
	if #items == 1 then
		CleanBandages.setSubmenu(context, items[1], waterObject)
		return
	end

	local subMenu = ISContextMenu:getNew(context)
	local subOption = context:addOption(getText("ContextMenu_CleanBandageEtc"))
	context:addSubMenu(subOption, subMenu)

	local numItems = 0
	for _,item in ipairs(items) do
		numItems = numItems + item.count
	end
	local option = subMenu:addActionsOption(getText("ContextMenu_AllWithCount", math.min(numItems, waterRemaining)), CleanBandages.onCleanAll, waterObject, items)
	if waterObject:isTaintedWater() and getSandboxOptions():getOptionByName("EnableTaintedWaterText"):getValue() then
		tooltip = ISWorldObjectContextMenu.addToolTip()
		tooltip.description =  " <RGB:1,0.5,0.5> " .. getText("Tooltip_item_TaintedWater")
		tooltip.maxLineWidth = 512
		option.toolTip = tooltip
		option.notAvailable = true
	end

	for _,item in ipairs(items) do
		CleanBandages.setSubmenu(subMenu, item, waterObject)
	end
end

ISWorldObjectContextMenu.onTakeWater = function(worldobjects, waterObject, waterContainerList, waterContainer, player)
	local playerObj = getSpecificPlayer(player)
	local playerInv = playerObj:getInventory()
	local waterAvailable = getPlumbedWaterAmount(waterObject)

	if not waterContainerList or #waterContainerList == 0 then
		waterContainerList = {};
		table.insert(waterContainerList, waterContainer);
	end

	local didWalk = false

	for i,item in ipairs(waterContainerList) do
		-- first case, fill an empty bottle
		if item:canStoreWater() and not item:isWaterSource() then
			if not didWalk and (not waterObject:getSquare() or not luautils.walkAdj(playerObj, waterObject:getSquare(), true)) then
				return
			end
			didWalk = true
			local returnToContainer = item:getContainer():isInCharacterInventory(playerObj) and item:getContainer()
			ISWorldObjectContextMenu.transferIfNeeded(playerObj, item)
			ISTimedActionQueue.add(ISTakeWaterAction:new(playerObj, item, waterObject, waterObject:isTaintedWater()));
			if returnToContainer and (returnToContainer ~= playerInv) then
				ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(playerObj, item, playerInv, returnToContainer))
			end
		elseif item:canStoreWater() and item:isWaterSource() then -- second case, a bottle contain some water, we just fill it
			if not didWalk and (not waterObject:getSquare() or not luautils.walkAdj(playerObj, waterObject:getSquare(), true)) then
				return
			end
			didWalk = true
			local returnToContainer = item:getContainer():isInCharacterInventory(playerObj) and item:getContainer()
			if playerObj:getPrimaryHandItem() ~= item and playerObj:getSecondaryHandItem() ~= item then
			end
			ISWorldObjectContextMenu.transferIfNeeded(playerObj, item)
			ISTimedActionQueue.add(ISTakeWaterAction:new(playerObj, item, waterObject, waterObject:isTaintedWater()));
			if returnToContainer then
				ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(playerObj, item, playerInv, returnToContainer))
			end
		elseif item:getFluidContainer() then --Fluid item
			if not didWalk and (not waterObject:getSquare() or not luautils.walkAdj(playerObj, waterObject:getSquare(), true)) then
				return
			end
			didWalk = true
			local returnToContainer = item:getContainer():isInCharacterInventory(playerObj) and item:getContainer()
			ISWorldObjectContextMenu.transferIfNeeded(playerObj, item)
			ISTimedActionQueue.add(ISTakeWaterAction:new(playerObj, item, waterObject, waterObject:isTaintedWater()));
			if returnToContainer and (returnToContainer ~= playerInv) then
				ISTimedActionQueue.add(ISInventoryTransferUtil.newInventoryTransferAction(playerObj, item, playerInv, returnToContainer))
			end
		end
	end
end

function ISWorldObjectContextMenu.doFluidContainerMenu(context, object, player)
	local playerObj = getSpecificPlayer(player)
	local containerName = getMoveableDisplayName(object) or object:getFluidUiName();
	local option = context:addOption(containerName, nil, nil)

	local mainSubMenu = ISContextMenu:getNew(context)
	context:addSubMenu(option, mainSubMenu)

	local isTrough = false;
	-- so i can add my specifics thing for feeding trough (as it can have food too) in this context option.
	if instanceof(object, "IsoFeedingTrough") then
		context.troughSubmenu = mainSubMenu;
		context.dontShowLiquidOption = true;
		isTrough = true;
	end

	--[[
    local tooltip = ISWorldObjectContextMenu.addToolTip()
    tooltip:setName(fetch.fluidcontainer:getFluidContainer():getContainerName())
    local amountString = getText("Fluid_Amount") .. ":";
    local tx = getTextManager():MeasureStringX(tooltip.font, amountString) + 20
    tooltip.description = string.format("%s: <SETX:%d> %d / %s", amountString, tx, fetch.fluidcontainer:getFluidContainer():getAmount() * 1000, (tostring(fetch.fluidcontainer:getFluidContainer():getCapacity() * 1000) .. " mL"))
     if fetch.fluidcontainer:getFluidContainer():isHiddenAmount() then
        tooltip.description = "Unknown";
    end
    tooltip.maxLineWidth = 512
    option.toolTip = tooltip
    ]]--

	-- distance test removed as per team meeting [SPIF-2281] - spurcival
	--if playerObj:DistToSquared(object:getX() + 0.5, object:getY() + 0.5) < 2 * 2 then
		if not isTrough then
			mainSubMenu:addOption(getText("Fluid_Show_Info"), player, ISWorldObjectContextMenu.onFluidInfo, object:getFluidContainer());
		end
		mainSubMenu:addOption(getText("Fluid_Transfer_Fluids"), player, ISWorldObjectContextMenu.onFluidTransfer, object:getFluidContainer());
	--end

	if object:hasFluid() then
		ISWorldObjectContextMenu.doDrinkWaterMenu(object, player, mainSubMenu);
		ISWorldObjectContextMenu.doFillFluidMenu(object, player, mainSubMenu);
	end
	if object:hasWater() then
		ISWorldObjectContextMenu.doWashClothingMenu(object, player, mainSubMenu);
	end

	if object:hasFluid() and getPlumbedWaterCapacity(object) < 9999 then	-- capacity >= 9999 means infinite water.
		mainSubMenu:addOption(getText("Fluid_Empty"), player, ISWorldObjectContextMenu.onFluidEmpty, object:getFluidContainer());
	end

	return mainSubMenu;
end
