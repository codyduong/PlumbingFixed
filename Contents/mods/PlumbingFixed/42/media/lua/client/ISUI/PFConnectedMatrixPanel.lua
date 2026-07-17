require("ISUI/ISPanel")
require("ISUI/ISButton")
require("lua/client/ISUI/ISWorldObjectContextMenu")
require("DebugUIs/PFBarrelFluidWindow")
require("PlumbingFixed/PFUtils")
require("PFModOptions")

-- 3x3 grid of the barrels a plumbed fixture pools from, docked LEFT of the world context
-- menu (right when the screen edge is in the way) and shown only while the fixture's own
-- fluid submenu (Drink / Wash / ...) is on screen — it lives and dies with the menu,
-- unlike a free-floating window. Each cell is a capacity-scaled fluid bar: the
-- tallest-capacity barrel in the pool spans the full cell and smaller barrels get a
-- blocked-out headroom band, so sub-standard capacity reads at a glance without numbers.
-- Concrete per-fluid amounts live in the cell hover tooltip, hovering a cell highlights
-- that barrel's world sprite, and in debug/admin mode clicking a cell opens the mod's
-- per-barrel fluid editor (PFBarrelFluidWindow) for just that barrel. Gamepad: DPad-left
-- from the fixture menu steps into the grid; DPad navigates, A edits, B / right edge
-- returns to the menu.

local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local PAD = 8
local GAP = 4
local CELL_W = 48
local CELL_H = 64
local GRID_W = CELL_W * 3 + GAP * 2
local GRID_H = CELL_H * 3 + GAP * 2
local BAR_THICK = 48

-- Pool-bar positions, matching the insertion order of the PFModOptions.poolBarPosition
-- combo items (getValue() is the 1-based item index).
local POS_LEFT = 1
local POS_RIGHT = 2
local POS_TOP = 3
local POS_BOTTOM = 4

local gradientTex = getTexture("media/ui/Fluids/fluid_gradient.png")
local bubblesTex = getTexture("media/ui/Fluids/bubbles_seamless.png")

--- @param menu ISContextMenu
--- @return boolean
local function menuHasFluidOption(menu)
  for _, option in ipairs(menu.options) do
    -- Same identification as PFPooledMenuFixups: the Java-built fixture options carry
    -- their real handler in param1 (addGetUpOption wrapper), Empty in onSelect.
    local callback = option.param1
    if callback == ISWorldObjectContextMenu.onDrink or callback == ISWorldObjectContextMenu.onWashClothing
      or callback == ISWorldObjectContextMenu.onWashYourself or option.onSelect == ISWorldObjectContextMenu.onFluidEmpty then
      return true
    end
  end
  return false
end

--- The fixture's own fluid submenu (the one holding Drink / Wash / Empty), so the grid
--- only shows while that tab is open. Falls back to the root menu when the options sit
--- there directly.
--- @param menu ISContextMenu
--- @return ISContextMenu?
local function findFixtureMenu(menu)
  if menuHasFluidOption(menu) then
    return menu
  end
  for _, option in ipairs(menu.options) do
    if option.subOption then
      local subMenu = menu:getSubMenu(option.subOption)
      local found = subMenu and findFixtureMenu(subMenu)
      if found then
        return found
      end
    end
  end
  return nil
end

--- One grid square of the pool. An ISButton for its hover/tooltip/click plumbing, but
--- entirely custom-drawn (render is overridden; the button chrome is disabled).
--- @class PFMatrixCell: ISButton
--- @field coords { x: integer, y: integer, z: integer }
--- @field source IsoObject? re-resolved every frame by the panel
--- @field capacity number
--- @field parent PFConnectedMatrixPanel
PFMatrixCell = ISButton:derive("PFMatrixCell")

--- @class PFConnectedMatrixPanel: ISPanel
--- @field playerNum integer
--- @field context ISContextMenu
--- @field watchMenu ISContextMenu the fixture's fluid submenu; the grid shows only while it does
--- @field watchHadFluidOption boolean whether watchMenu held a fluid option at open (false = root-menu fallback)
--- @field fixture { x: integer, y: integer, z: integer }
--- @field cells PFMatrixCell[]
--- @field cellGrid PFMatrixCell[][] cells by visual [row][col] (1..3) for gamepad navigation
--- @field poolBar PFPoolBar
--- @field maxCapacity number
--- @field highlighted { x: integer, y: integer, z: integer } | nil
--- @field joyfocus table? joypad data while the grid has gamepad focus
--- @field joyRow integer
--- @field joyCol integer
--- @field instance PFConnectedMatrixPanel?
PFConnectedMatrixPanel = ISPanel:derive("PFConnectedMatrixPanel")

--- @param x number
--- @param y number
--- @param coords { x: integer, y: integer, z: integer }
--- @param panel PFConnectedMatrixPanel
function PFMatrixCell:new(x, y, coords, panel)
  local o = ISButton.new(self, x, y, CELL_W, CELL_H, "", panel, nil)
  o:setEnable(false)
  --- @cast o PFMatrixCell
  o.displayBackground = false
  o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
  o.coords = coords
  o.source = nil
  o.capacity = 0
  return o
end

function PFMatrixCell:onMouseDown(x, y)
  ISButton.onMouseDown(self, x, y)
  -- Act on mouse-DOWN: this click lands outside the context menu, which hides itself on
  -- the same event (ISContextMenu:onMouseDownOutside); by mouse-up the panel is gone, so
  -- an ISButton onclick (mouse-up based) would never fire.
  self.parent:onCellClick(self)
end

function PFMatrixCell:render()
  if self.source == nil then
    self:drawRect(0, 0, self.width, self.height, 0.35, 0.08, 0.08, 0.08)
    self:drawRectBorder(0, 0, self.width, self.height, 0.25, 0.4, 0.4, 0.4)
    if self.joypadFocused then
      self:drawRectBorder(0, 0, self.width, self.height, 1.0, 1, 1, 1)
    end
    return
  end

  local barH = self.height
  if self.parent.maxCapacity > 0 and self.capacity < self.parent.maxCapacity then
    barH = math.max(math.floor(self.height * self.capacity / self.parent.maxCapacity), 4)
  end
  local barY = self.height - barH

  -- Blocked-out headroom: capacity this barrel lacks relative to the pool's largest.
  if barY > 0 then
    self:drawRect(0, 0, self.width, barY, 0.6, 0.12, 0.12, 0.12)
  end

  -- ISFluidBar-style bar: black backdrop + gradient, bottom-anchored fluid fill.
  self:drawRect(0, barY, self.width, barH, 1.0, 0, 0, 0)
  self:drawTextureScaled(gradientTex, 0, barY, self.width, barH, 0.15, 1, 1, 1)

  local ratio = self.capacity > 0 and math.min(self.source:getFluidAmount() / self.capacity, 1.0) or 0
  local innerH = barH - 4
  local fillH = math.ceil(innerH * ratio)
  if fillH > 0 then
    local container = self.source:getFluidContainer()
    local color = container and container:getColor() or Fluid.Water:getColor()
    local fillY = barY + 2 + innerH - fillH
    self:drawRect(
      2,
      fillY,
      self.width - 4,
      fillH,
      1.0,
      color:getRedFloat(),
      color:getGreenFloat(),
      color:getBlueFloat()
    )
    self:drawTextureTiledYOffset(bubblesTex, 2, fillY, self.width - 4, fillH, 1.0, 1.0, 1.0, 0.2)
  end
  self:drawRectBorder(0, barY, self.width, barH, 1.0, 0.6, 0.6, 0.6)

  -- Hide the button hover indicator if not in debug
  if isClient() then
    if not getSpecificPlayer(self.parent.playerNum):getRole():hasCapability(Capability.UseDebugContextMenu) then
      return
    end
  elseif not isDebugEnabled() then
    return
  end
  self:setEnable(true)

  if self:isMouseOver() then
    self:drawRect(0, 0, self.width, self.height, 0.2, 1, 1, 1)
  end
  if self.joypadFocused then
    self:drawRectBorder(0, 0, self.width, self.height, 1.0, 1, 1, 1)
  end
end

--- Pooled-total bar spanning the grid: every connected barrel's fluid combined, drawn as
--- stacked segments separated by fluid type (registry order; no numbers — the hover
--- tooltip carries them). An ISButton purely for its tooltip plumbing; it has no click.
--- @class PFPoolBar: ISButton
--- @field vertical boolean
--- @field segments { color: Color, amount: number } []
--- @field capacity number
PFPoolBar = ISButton:derive("PFPoolBar")

--- @param x number
--- @param y number
--- @param width number
--- @param height number
function PFPoolBar:new(x, y, width, height)
  local o = ISButton.new(self, x, y, width, height, "", nil, nil)
  --- @cast o PFPoolBar
  o.displayBackground = false
  o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
  o.vertical = height >= width
  o.segments = {}
  o.capacity = 0
  return o
end

function PFPoolBar:render()
  self:drawRect(0, 0, self.width, self.height, 1.0, 0, 0, 0)
  self:drawTextureScaled(gradientTex, 0, 0, self.width, self.height, 0.15, 1, 1, 1)

  local innerX, innerY = 2, 2
  local innerW, innerH = self.width - 4, self.height - 4
  local span = self.vertical and innerH or innerW
  local filledPx = 0.0
  if self.capacity > 0 then
    local filled = 0.0
    for _, segment in ipairs(self.segments) do
      filled = filled + segment.amount
      local toPx = math.min(math.ceil(span * filled / self.capacity), span)
      local px = toPx - filledPx
      if px > 0 then
        local c = segment.color
        if self.vertical then
          -- bottom-anchored, stacking upward
          self:drawRect(
            innerX,
            innerY + span - toPx,
            innerW,
            px,
            1.0,
            c:getRedFloat(),
            c:getGreenFloat(),
            c:getBlueFloat()
          )
        else
          -- left-anchored, stacking rightward
          self:drawRect(
            innerX + filledPx,
            innerY,
            px,
            innerH,
            1.0,
            c:getRedFloat(),
            c:getGreenFloat(),
            c:getBlueFloat()
          )
        end
      end
      filledPx = toPx
    end
  end
  if filledPx > 0 then
    if self.vertical then
      self:drawTextureTiledYOffset(bubblesTex, innerX, innerY + span - filledPx, innerW, filledPx, 1.0, 1.0, 1.0, 0.2)
    else
      self:drawTextureTiledYOffset(bubblesTex, innerX, innerY, filledPx, innerH, 1.0, 1.0, 1.0, 0.2)
    end
  end
  self:drawRectBorder(0, 0, self.width, self.height, 1.0, 0.6, 0.6, 0.6)
end

--- Attach beside `context` for a plumbed fixture; replaces any previous instance.
--- @param playerNum integer
--- @param context ISContextMenu
--- @param waterObject IsoObject
function PFConnectedMatrixPanel.open(playerNum, context, waterObject)
  if PFConnectedMatrixPanel.instance then
    PFConnectedMatrixPanel.instance:removeSelf()
  end
  local sq = waterObject:getSquare()
  if sq == nil then
    return
  end
  local pos = PFModOptions.poolBarPosition:getValue()
  local width = PAD * 2 + GRID_W
  local height = PAD * 3 + FONT_HGT_SMALL + GRID_H
  if pos == POS_LEFT or pos == POS_RIGHT then
    width = width + BAR_THICK + GAP
  elseif pos == POS_TOP or pos == POS_BOTTOM then
    height = height + BAR_THICK + GAP
  end
  local ui = PFConnectedMatrixPanel:new(0, 0, width, height, playerNum, context, sq)
  ui:setVisible(false)
  ui:initialise()
  ui:addToUIManager()
  -- Gamepad: DPad-left from the fixture menu steps into the grid (docked on the left).
  -- Instance-level override on that one menu; removeSelf clears it. Falls through to the
  -- class behavior while the grid is hidden (submenu back-navigation).
  ui.watchMenu.onJoypadDirLeft = function(menu)
    if ui:getIsVisible() then
      setJoypadFocus(playerNum, ui)
    else
      ISContextMenu.onJoypadDirLeft(menu)
    end
  end
  PFConnectedMatrixPanel.instance = ui
end

--- @param playerNum integer
--- @param context ISContextMenu
--- @param square IsoGridSquare
function PFConnectedMatrixPanel:new(x, y, width, height, playerNum, context, square)
  local o = ISPanel.new(self, x, y, width, height)
  --- @cast o PFConnectedMatrixPanel
  o.backgroundColor = { r = 0, g = 0, b = 0, a = 0.8 }
  o.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
  o.playerNum = playerNum
  o.context = context
  local fixtureMenu = findFixtureMenu(context)
  o.watchMenu = fixtureMenu or context
  o.watchHadFluidOption = fixtureMenu ~= nil
  o.fixture = { x = square:getX(), y = square:getY(), z = square:getZ() }
  o.cells = {}
  o.cellGrid = { {}, {}, {} }
  o.maxCapacity = 0
  o.highlighted = nil
  o.joyfocus = nil
  o.joyRow = 2
  o.joyCol = 3 -- enter from the right edge, nearest the menu
  return o
end

function PFConnectedMatrixPanel:createChildren()
  ISPanel.createChildren(self)
  local xPrimary = not PFModOptions.matrixAxisXPrimary:getValue()
  local pos = PFModOptions.poolBarPosition:getValue()
  local top = PAD * 2 + FONT_HGT_SMALL
  local gridX = pos == POS_LEFT and (PAD + BAR_THICK + GAP) or PAD
  local gridTop = pos == POS_TOP and (top + BAR_THICK + GAP) or top

  if pos == POS_LEFT or pos == POS_RIGHT then
    local barX = pos == POS_LEFT and PAD or (gridX + GRID_W + GAP)
    self.poolBar = PFPoolBar:new(barX, gridTop, BAR_THICK, GRID_H)
  else
    local barY = pos == POS_TOP and top or (gridTop + GRID_H + GAP)
    self.poolBar = PFPoolBar:new(gridX, barY, GRID_W, BAR_THICK)
  end
  self.poolBar:initialise()
  self:addChild(self.poolBar)

  for dy = -1, 1 do
    for dx = -1, 1 do
      -- X-primary (default): rows share Y, columns vary X. Unchecked: transposed.
      local row = xPrimary and (dy + 1) or (dx + 1)
      local col = xPrimary and (dx + 1) or (dy + 1)
      local cell = PFMatrixCell:new(
        gridX + col * (CELL_W + GAP),
        gridTop + row * (CELL_H + GAP),
        { x = self.fixture.x + dx, y = self.fixture.y + dy, z = self.fixture.z + 1 },
        self
      )
      cell:initialise()
      self:addChild(cell)
      table.insert(self.cells, cell)
      self.cellGrid[row + 1][col + 1] = cell
    end
  end
end

--- Concrete per-fluid amounts, grouped by translated name: vanilla intentionally aliases
--- fluids the player shouldn't distinguish (EN maps Fluid_Name_TaintedWater to "Water"),
--- so aliased fluids sum into one line rather than leaking the distinction.
--- @param source IsoObject
--- @return string
function PFConnectedMatrixPanel.cellTooltipText(source)
  local lines = {}
  local container = source:getFluidContainer()
  --- @cast container FluidContainer?
  if container ~= nil then
    local byName = {}
    local order = {}
    local allFluids = Fluid.getAllFluids()
    for i = 0, allFluids:size() - 1 do
      local fluid = allFluids:get(i)
      local amount = container:getSpecificFluidAmount(fluid)
      if amount > 0 then
        local name = fluid:getTranslatedName()
        if byName[name] == nil then
          byName[name] = 0
          table.insert(order, name)
        end
        byName[name] = byName[name] + amount
      end
    end
    for _, name in ipairs(order) do
      table.insert(lines, string.format("%s: %.2f L", name, byName[name]))
    end
    table.insert(
      lines,
      getText(
        "IGUI_PFMatrixCellTotal",
        string.format("%.2f", container:getAmount()),
        string.format("%.2f", container:getCapacity())
      )
    )
  else
    -- Reserve source (no FluidContainer, e.g. a bathtub): water reserve via getFluidAmount().
    table.insert(lines, string.format("%s: %.2f L", Fluid.Water:getTranslatedName(), source:getFluidAmount()))
  end
  return table.concat(lines, "\n")
end

--- Lifecycle runs in update() (called even while invisible, unlike prerender): remove
--- when the whole menu is gone, show/hide with the fixture submenu, track position.
function PFConnectedMatrixPanel:update()
  ISPanel.update(self)
  local rootVisible = self.context:getIsVisible()
  local watchVisible = self.watchMenu:getIsVisible()
  -- Joypad single-menu mode hides the root while a submenu shows, so the panel only dies
  -- when the whole chain is gone.
  if not rootVisible and not watchVisible then
    self:removeSelf()
    return
  end

  -- Non-world owners (inventory, fluid UIs, ...) recycle the same menu instances without
  -- refiring OnFillWorldObjectContextMenu, and recycling clear()s the options in place —
  -- so our fluid options vanishing means the menu no longer belongs to this fixture.
  if self.watchHadFluidOption and not menuHasFluidOption(self.watchMenu) then
    self:removeSelf()
    return
  end

  -- Only while the fixture's fluid submenu (Drink / Wash / ...) is on screen.
  if not watchVisible then
    if self:getIsVisible() then
      self:setVisible(false)
      self:clearHighlight()
    end
    return
  end
  self:setVisible(true)

  -- Dock left of the menu (right when the screen edge is in the way) — the right side is
  -- where submenus and option tooltips open.
  local xanchor = self.context
  local yanchor = self.watchMenu
  local x = xanchor:getX() - self.width - GAP
  if x < 0 then
    x = xanchor:getX() + xanchor:getWidth() + GAP
  end
  local y = math.min(yanchor:getY(), getCore():getScreenHeight() - self.height)
  self:setX(math.min(math.max(x, 0), getCore():getScreenWidth() - self.width))
  self:setY(math.max(y, 0))
end

function PFConnectedMatrixPanel:prerender()
  -- Re-resolve sources every frame: server edits retransmit the barrel, which replaces
  -- the object (and its container) under us.
  local selected = self:selectedCell()
  self.maxCapacity = 0
  for _, cell in ipairs(self.cells) do
    local source = findPlumbedSourceAt(cell.coords.x, cell.coords.y, cell.coords.z)
    cell.source = source
    cell.capacity = 0
    -- ISButton shows its tooltip for joypadFocused as well as mouse-over.
    cell.joypadFocused = cell == selected
    if source then
      local capacity = source:getFluidCapacity()
      if capacity <= 0 then
        capacity = source:getFluidAmount() -- reserve source: render as a full bar
      end
      cell.capacity = capacity
      self.maxCapacity = math.max(self.maxCapacity, capacity)
      cell.tooltip = PFConnectedMatrixPanel.cellTooltipText(source)
    else
      cell.tooltip = nil
    end
  end

  self:updatePoolBar()
  self:updateHighlight()
  ISPanel.prerender(self)
end

--- Aggregate the pool for the total bar: per-fluid segments in registry order (reserve
--- sources count as Water), plus the tooltip lines (grouped by translated name, same
--- aliasing rationale as cellTooltipText).
function PFConnectedMatrixPanel:updatePoolBar()
  local segments = {}
  local byName = {}
  local order = {}
  local total = 0.0
  local capacity = 0.0
  local reserveWater = 0.0
  for _, cell in ipairs(self.cells) do
    capacity = capacity + cell.capacity
    if cell.source and cell.source:getFluidContainer() == nil then
      reserveWater = reserveWater + cell.source:getFluidAmount()
    end
  end

  local allFluids = Fluid.getAllFluids()
  for i = 0, allFluids:size() - 1 do
    local fluid = allFluids:get(i)
    local amount = 0.0
    for _, cell in ipairs(self.cells) do
      local container = cell.source and cell.source:getFluidContainer()
      if container then
        amount = amount + container:getSpecificFluidAmount(fluid)
      end
    end
    if fluid == Fluid.Water then
      amount = amount + reserveWater
    end
    if amount > 0 then
      table.insert(segments, { color = fluid:getColor(), amount = amount })
      total = total + amount
      local name = fluid:getTranslatedName()
      if byName[name] == nil then
        byName[name] = 0
        table.insert(order, name)
      end
      byName[name] = byName[name] + amount
    end
  end

  local lines = {}
  for _, name in ipairs(order) do
    table.insert(lines, string.format("%s: %.2f L", name, byName[name]))
  end
  table.insert(lines, getText("IGUI_PFMatrixCellTotal", string.format("%.2f", total), string.format("%.2f", capacity)))
  self.poolBar.segments = segments
  self.poolBar.capacity = capacity
  self.poolBar.tooltip = table.concat(lines, "\n")
end

--- The gamepad-selected cell, or nil when the grid has no gamepad focus.
--- @return PFMatrixCell?
function PFConnectedMatrixPanel:selectedCell()
  if self.joyfocus == nil then
    return nil
  end
  return self.cellGrid[self.joyRow][self.joyCol]
end

function PFConnectedMatrixPanel:updateHighlight()
  --- @type PFMatrixCell?
  local hovered = nil
  --- @type IsoObject?
  local hoveredSource = nil
  local selected = self:selectedCell()
  if selected and selected.source then
    hovered = selected
    hoveredSource = selected.source
  end
  if hovered == nil then
    for _, cell in ipairs(self.cells) do
      if cell.source and cell:isMouseOver() then
        hovered = cell
        hoveredSource = cell.source
        break
      end
    end
  end

  local previous = self.highlighted
  if previous and (hovered == nil or previous.x ~= hovered.coords.x or previous.y ~= hovered.coords.y) then
    local prevObj = findPlumbedSourceAt(previous.x, previous.y, previous.z)
    if prevObj then
      prevObj:setHighlighted(self.playerNum, false)
    end
    self.highlighted = nil
  end
  if hovered and hoveredSource then
    -- Re-applied every frame: a retransmit swaps the object, losing its highlight flag.
    hoveredSource:setHighlighted(self.playerNum, true, false)
    self.highlighted = hovered.coords
  end
end

function PFConnectedMatrixPanel:clearHighlight()
  if self.highlighted then
    local obj = findPlumbedSourceAt(self.highlighted.x, self.highlighted.y, self.highlighted.z)
    if obj then
      obj:setHighlighted(self.playerNum, false)
    end
    self.highlighted = nil
  end
end

function PFConnectedMatrixPanel:removeSelf()
  self:clearHighlight()
  self.watchMenu.onJoypadDirLeft = nil -- restore the class handler
  if self.joyfocus then
    setJoypadFocus(self.playerNum, nil)
  end
  self:setVisible(false)
  self:removeFromUIManager()
  if PFConnectedMatrixPanel.instance == self then
    PFConnectedMatrixPanel.instance = nil
  end
end

-- Gamepad navigation: DPad moves the selected cell; A opens the editor on it; B (or
-- DPad-right past the right edge) hands focus back to the fixture menu.

function PFConnectedMatrixPanel:onGainJoypadFocus(joypadData)
  self.joyfocus = joypadData
end

function PFConnectedMatrixPanel:onLoseJoypadFocus(_joypadData)
  self.joyfocus = nil
end

function PFConnectedMatrixPanel:focusMenu()
  setJoypadFocus(self.playerNum, self.watchMenu:getIsVisible() and self.watchMenu or self.context)
end

function PFConnectedMatrixPanel:onJoypadDirUp(_joypadData)
  self.joyRow = math.max(1, self.joyRow - 1)
end

function PFConnectedMatrixPanel:onJoypadDirDown(_joypadData)
  self.joyRow = math.min(3, self.joyRow + 1)
end

function PFConnectedMatrixPanel:onJoypadDirLeft(_joypadData)
  self.joyCol = math.max(1, self.joyCol - 1)
end

function PFConnectedMatrixPanel:onJoypadDirRight(_joypadData)
  if self.joyCol >= 3 then
    self:focusMenu()
  else
    self.joyCol = self.joyCol + 1
  end
end

function PFConnectedMatrixPanel:onJoypadDown(button, _joypadData)
  if button == Joypad.AButton then
    local cell = self:selectedCell()
    if cell then
      self:onCellClick(cell)
    end
  elseif button == Joypad.BButton then
    self:focusMenu()
  end
end

function PFConnectedMatrixPanel:render()
  ISPanel.render(self)
  self:drawTextCentre(getText("IGUI_PFConnectedBarrelsTitle"), self.width / 2, PAD, 1, 1, 1, 1, UIFont.Small)
end

--- Debug/admin only: open the mod's per-barrel fluid editor (PFBarrelFluidWindow) for
--- just the clicked barrel — finer-grained than the vanilla fluid UI (arbitrary fluid
--- type + amount, Add/Empty, MP edits via the capability-gated server commands).
--- @param cell PFMatrixCell
function PFConnectedMatrixPanel:onCellClick(cell)
  local playerObj = getSpecificPlayer(self.playerNum)
  if isClient() then
    if not playerObj:getRole():hasCapability(Capability.UseDebugContextMenu) then
      return
    end
  elseif not isDebugEnabled() then
    return
  end
  local source = findPlumbedSourceAt(cell.coords.x, cell.coords.y, cell.coords.z)
  if source == nil then
    return
  end
  PFBarrelFluidWindow.open(self.playerNum, { source })
end

Events.OnFillWorldObjectContextMenu.Add(function(player, context, worldObjects, test)
  if test then
    return
  end
  -- Every real fill recycles the per-player menu instance (ISContextMenu.get), so a
  -- panel left from an earlier right-click is stale now — its watched submenu may even
  -- get recycled into this menu's subMenuPool. Drop it before any early return.
  if PFConnectedMatrixPanel.instance then
    PFConnectedMatrixPanel.instance:removeSelf()
  end
  if not PFModOptions.showMatrix:getValue() then
    return
  end
  local waterObject = findWaterObject(worldObjects)
  if not waterObject or not isMultiSource(getPlumbedSources(waterObject)) then
    return
  end
  PFConnectedMatrixPanel.open(player, context, waterObject)
end)
