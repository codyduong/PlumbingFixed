require("ISUI/ISCollapsableWindow")
require("PlumbingFixed/PFUtils")

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local PAD = 10
local BTN_H = FONT_HGT_SMALL + 6
local ROW_H = BTN_H * 2 + PAD * 2

--- @class PFBarrelFluidWindow : ISCollapsableWindow
--- @field playerNum integer
--- @field barrelCoords { x: integer, y: integer, z: integer }[]
--- @field rows table[]
--- @field instance PFBarrelFluidWindow?
PFBarrelFluidWindow = ISCollapsableWindow:derive("PFBarrelFluidWindow")

--- Rows identify barrels by square coordinates, not object references: after a server
--- edit the object is retransmitted and a captured reference would go stale, so every
--- lookup re-resolves through the shared findPlumbedSourceAt (utils.lua).

--- Live per-barrel debug block (the detail the old Connected Sources sub-menu listed one
--- source at a time). Rebuilt each frame so it never goes stale after a server edit.
--- @param coords { x: integer, y: integer, z: integer }
--- @return string
local function barrelDebugText(coords)
  local obj = findPlumbedSourceAt(coords.x, coords.y, coords.z)
  if obj == nil then
    return "No fluid object at x:" .. coords.x .. ", y:" .. coords.y .. ", z:" .. coords.z
  end
  local desc = ""
  desc = desc .. "Fluid = " .. obj:getFluidAmount() .. "/" .. obj:getFluidCapacity() .. "\n"
  desc = desc .. "Has Water = " .. tostring(obj:hasWater()) .. "\n"
  desc = desc .. "Is Tainted = " .. tostring(obj:isTaintedWater()) .. "\n"
  desc = desc .. "Coordinates = x:" .. coords.x .. ", y:" .. coords.y .. ", z:" .. coords.z .. "\n"
  desc = desc .. "Custom Name = " .. tostring(obj:getProperty("CustomName")) .. "\n"
  desc = desc .. "Name = " .. obj:getName() .. "\n"
  desc = desc .. "Tile Name = " .. tostring(obj:getTileName()) .. "\n"
  return desc
end

--- Open the editor for a list of fluid-holding world objects (rig barrels or any
--- plumbed sources). Replaces any previously open instance.
--- @param playerNum integer
--- @param fluidObjects IsoObject[]
function PFBarrelFluidWindow.open(playerNum, fluidObjects)
  if PFBarrelFluidWindow.instance then
    PFBarrelFluidWindow.instance:close()
  end
  local width = 520
  local height = ROW_H * #fluidObjects + PAD * 2 + 16 + 32 -- 16 = title bar, 32 for bottom pad
  local ui = PFBarrelFluidWindow:new(
    (getCore():getScreenWidth() - width) / 2,
    (getCore():getScreenHeight() - height) / 2,
    width,
    height,
    playerNum,
    fluidObjects
  )
  ui:initialise()
  ui:addToUIManager()
  PFBarrelFluidWindow.instance = ui
end

function PFBarrelFluidWindow:new(x, y, width, height, playerNum, fluidObjects)
  local o = ISCollapsableWindow.new(self, x, y, width, height)
  --- @cast o PFBarrelFluidWindow
  o.title = getText("IGUI_PFBarrelFluidsTitle")
  o.playerNum = playerNum
  o.barrelCoords = {}
  for _, obj in ipairs(fluidObjects) do
    table.insert(o.barrelCoords, { x = obj:getX(), y = obj:getY(), z = obj:getZ() })
  end
  o.rows = {}
  return o
end

function PFBarrelFluidWindow:createChildren()
  ISCollapsableWindow.createChildren(self)
  local top = self:titleBarHeight() + PAD

  -- Either in SP or admin in MP
  local canModify = not isClient() or PFIsAdmin(getSpecificPlayer(self.playerNum))

  for i, coords in ipairs(self.barrelCoords) do
    local row = { coords = coords }
    local x = PAD
    local y = top + (i - 1) * ROW_H

    -- Reserve sources (bathtubs) have no FluidContainer, so they are display-only: their
    -- values still show (label + info tooltip) but the fluid edits have nothing to act on.
    local source = findPlumbedSourceAt(coords.x, coords.y, coords.z)
    local rowModifiable = canModify and source ~= nil and source:getFluidContainer() ~= nil

    row.label = ISLabel:new(
      x,
      y,
      BTN_H,
      getText("IGUI_PFBarrelLabel", i, coords.x, coords.y, coords.z),
      1,
      1,
      1,
      1,
      UIFont.Small,
      true
    )
    row.label:initialise()
    self:addChild(row.label)

    local controlY = y + BTN_H + 2
    row.combo = ISComboBox:new(x, controlY, 160, BTN_H)
    row.combo:initialise()
    row.combo:setEnabled(rowModifiable)
    self:addChild(row.combo)
    -- Label with the internal type string, not getTranslatedName(): translations
    -- intentionally alias fluids the player shouldn't distinguish (e.g. EN maps
    -- Fluid_Name_TaintedWater to "Water"), which is ambiguous in a debug editor.
    local fluids = Fluid.getAllFluids()
    for j = 0, fluids:size() - 1 do
      local fluid = fluids:get(j)
      row.combo:addOptionWithData(fluid:getFluidTypeString(), fluid:getFluidTypeString())
      if fluid == Fluid.TaintedWater then
        row.combo.selected = row.combo:getOptionCount()
      end
    end
    x = x + 160 + PAD

    row.amountBox = ISTextEntryBox:new("15", x, controlY, 56, BTN_H)
    row.amountBox.font = UIFont.Small
    row.amountBox:initialise()
    row.amountBox:instantiate()
    row.amountBox:setOnlyNumbers(true)
    row.amountBox:setEditable(rowModifiable)
    self:addChild(row.amountBox)
    x = x + 56 + PAD

    row.addButton = ISButton:new(x, controlY, 56, BTN_H, getText("IGUI_DebugMenu_Add"), self, function()
      self:onAdd(row)
    end)
    row.addButton:initialise()
    row.addButton:setEnable(rowModifiable)
    self:addChild(row.addButton)
    x = x + 56 + PAD

    row.emptyButton = ISButton:new(x, controlY, 56, BTN_H, getText("ContextMenu_Empty"), self, function()
      self:onEmpty(row)
    end)
    row.emptyButton:initialise()
    row.emptyButton:setEnable(rowModifiable)
    self:addChild(row.emptyButton)
    x = x + 56 + PAD

    row.fluidBar =
      ISFluidBar:new(self.width - PAD - (BTN_H * 2), y, BTN_H * 2, ROW_H - PAD, getSpecificPlayer(self.playerNum))
    row.fluidBar:initialise()
    row.fluidBar:setContainer(source and source:getFluidContainer() or nil)
    self:addChild(row.fluidBar)

    -- Info affordance carrying the full per-barrel debug block that the old sub-menu
    -- listed one source at a time (tooltip refreshed live in prerender).
    row.infoButton = ISButton:new(row.fluidBar.x - PAD - BTN_H, y, BTN_H, BTN_H, "?", nil, nil)
    row.infoButton:initialise()
    self:addChild(row.infoButton)

    table.insert(self.rows, row)
  end
end

function PFBarrelFluidWindow:prerender()
  ISCollapsableWindow.prerender(self)
  -- Re-resolve every frame: server edits retransmit the barrel, which replaces the
  -- object (and its container) under us.
  for _, row in ipairs(self.rows) do
    local source = findPlumbedSourceAt(row.coords.x, row.coords.y, row.coords.z)
    row.fluidBar:setContainer(source and source:getFluidContainer() or nil)
    row.infoButton:setTooltip(barrelDebugText(row.coords))
  end
end

--- @param row table
function PFBarrelFluidWindow:onAdd(row)
  local amount = tonumber(row.amountBox:getInternalText()) or 0
  local fluidType = row.combo:getOptionData(row.combo.selected)
  if amount <= 0 or not fluidType then
    return
  end
  if isClient() then
    sendClientCommand(getSpecificPlayer(self.playerNum), "PlumbingFixed", "addBarrelFluid", {
      x = row.coords.x,
      y = row.coords.y,
      z = row.coords.z,
      fluid = fluidType,
      amount = amount,
    })
  else
    local obj = findPlumbedSourceAt(row.coords.x, row.coords.y, row.coords.z)
    local container = obj and obj:getFluidContainer()
    if container then
      container:addFluid(Fluid.Get(fluidType), amount)
    end
  end
end

--- @param row table
function PFBarrelFluidWindow:onEmpty(row)
  if isClient() then
    sendClientCommand(getSpecificPlayer(self.playerNum), "PlumbingFixed", "emptyBarrel", {
      x = row.coords.x,
      y = row.coords.y,
      z = row.coords.z,
    })
  else
    local obj = findPlumbedSourceAt(row.coords.x, row.coords.y, row.coords.z)
    local container = obj and obj:getFluidContainer()
    if container then
      container:Empty()
    end
  end
end

function PFBarrelFluidWindow:close()
  ISCollapsableWindow.close(self)
  self:removeFromUIManager()
  if PFBarrelFluidWindow.instance == self then
    PFBarrelFluidWindow.instance = nil
  end
end
