require("lua/client/ISUI/ISWorldObjectContextMenu")
require("PlumbingFixed/utils")

-- B42.19 builds the fixture water menu in native Java (zombie/iso/ISWorldObjectContextMenuLogic).
-- It gates and labels each option from the fixture's OWN fluid amount, which for a plumbed
-- fixture resolves to a SINGLE found barrel (IsoObject.getFluidAmount -> checkExternalFluidSource),
-- not the pooled 3x3 total this mod draws from. The timed actions we override already draw
-- pooled, but two things are still computed from that one barrel and are wrong for us:
--   * the Drink / Wash tooltip water figures (cosmetic under-report), and
--   * the Wash "not available" grey-out (functional: a near-empty lead barrel disables washing
--     even when the pool has plenty).
-- The Java menu fires OnFillWorldObjectContextMenu *after* it is built, so we post-process it
-- here: find the plumbed fixture, then rewrite the affected options in place. We do NOT rebuild
-- the menu (it is native) and we do NOT re-route the actions (our timed-action overrides handle
-- the pooled draw). See docs/ARCHITECTURE.md.
--
-- Options are identified by their bound callback (robust across locales). Java adds them via
-- ISContextMenuWrapper.addGetUpOption, which stores the real callback in `option.param1` (the
-- getUp wrapper sits in `option.onSelect`). Tooltip numbers are rewritten with getText-anchored
-- gsub so the pattern tracks the game's own localization.

local WATER_LABEL = getText("ContextMenu_WaterName")

--- Debug-only sanity marker: lets us (and users running -debug) assert which options the
--- mod rewrote. Invariant: unplumbed fixtures never get this marker because none of the
--- fix* functions run for them.
--- @param tt table
local function markModified(tt)
  if getDebug() then
    tt.description = tt.description .. " <BR> Modified by Plumbing Fixed"
  end
end

--- Drink tooltip: vanilla formatWaterAmount renders "<amount>L / <cap>L". Rewrite to pooled.
--- @param option table
--- @param pooled number
--- @param pooledCap number
local function fixDrinkTooltip(option, pooled, pooledCap)
  local tt = option.toolTip
  if not tt or type(tt.description) ~= "string" then
    return
  end
  local replaced
  tt.description, replaced = tt.description:gsub("[%d%.]+L%s*/%s*[%d%.]+L", function()
    return string.format("%.2fL / %.2fL", pooled, pooledCap)
  end, 1)
  if replaced > 0 then
    markModified(tt)
  end
end

--- Wash tooltip: setWashClothingTooltip / the yourself option render "<Water>: <shown> / <req>"
--- and grey the option out from the single-barrel amount. Rewrite <shown> to min(pooled, req)
--- and recompute the grey-out against the pool (items: pooled < req; yourself: pooled < 1,
--- matching vanilla's thresholds).
--- @param option table
--- @param pooled number
--- @param yourself boolean
local function fixWashOption(option, pooled, yourself)
  local tt = option.toolTip
  if not tt or type(tt.description) ~= "string" then
    return
  end
  local required = tt.description:match(WATER_LABEL .. ":%s*[%d%.]+%s*/%s*([%d%.]+)")
  if not required then
    return
  end
  local req = tonumber(required) or 0

  if yourself then
    option.notAvailable = (pooled < 1) or nil
  else
    option.notAvailable = (pooled < req) or nil
  end

  local shown = string.format("%.2f", math.min(pooled, req))
  tt.description = tt.description:gsub(WATER_LABEL .. ":%s*[%d%.]+%s*/%s*[%d%.]+", function()
    return WATER_LABEL .. ": " .. shown .. " / " .. required
  end, 1)
  markModified(tt)
end

--- Recursively walk a context menu and its submenus, patching pooled-water options in place.
--- @param menu ISContextMenu?
--- @param pooled number
--- @param pooledCap number
local function patchMenu(menu, pooled, pooledCap)
  if not menu then
    return
  end
  for _, option in ipairs(menu.options) do
    local callback = option.param1 -- real handler under the addGetUpOption wrapper
    if callback == ISWorldObjectContextMenu.onDrink then
      fixDrinkTooltip(option, pooled, pooledCap)
    elseif callback == ISWorldObjectContextMenu.onWashClothing then
      fixWashOption(option, pooled, false)
    elseif callback == ISWorldObjectContextMenu.onWashYourself then
      fixWashOption(option, pooled, true)
    end
    if option.subOption then
      patchMenu(menu:getSubMenu(option.subOption), pooled, pooledCap)
    end
  end
end

Events.OnFillWorldObjectContextMenu.Add(function(_player, context, worldObjects, test)
  if test then
    return
  end
  local waterObject = findWaterObject(worldObjects)
  if not waterObject or not waterObject:getUsesExternalWaterSource() then
    return
  end
  patchMenu(context, getPlumbedWaterAmount(waterObject), getPlumbedWaterCapacity(waterObject))
end)
