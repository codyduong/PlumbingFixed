require("lua/shared/TimedActions/ISWashYourself")
require("PlumbingFixed/utils")

---@class PFWashYourself : ISWashYourself
local _PFWashYourself = ISWashYourself

local original = {
  isValid = ISWashYourself.isValid,
  complete = ISWashYourself.complete,
  getDuration = ISWashYourself.getDuration,
}

function ISWashYourself:isValid()
  if not isMultiSource(self.sink) then
    return original.isValid(self)
  end
  -- Vanilla has no water gate at all; gate on the pool to match the menu grey-out.
  return getPlumbedWaterAmount(self.sink) >= 1
end

function ISWashYourself:complete()
  if not isMultiSource(self.sink) then
    return original.complete(self)
  end

  local visual = self.character:getHumanVisual()
  local waterUsed = 0
  for i = 1, BloodBodyPartType.MAX:index() do
    local part = BloodBodyPartType.FromIndex(i - 1)
    if self:washPart(visual, part) then
      waterUsed = waterUsed + 1
      -- using soap provides a modest happiness boost
      if self.soaps then
        self.character:getStats():remove(CharacterStat.UNHAPPINESS, 2)
      end
      if waterUsed >= getPlumbedWaterAmount(self.sink) then
        break
      end
    end
  end

  self:removeAllMakeup()

  sendHumanVisual(self.character)

  FluidContainer.DisposeContainer(drawFromPool(self.sink, waterUsed))

  return true
end

function ISWashYourself:getDuration()
  if not isMultiSource(self.sink) then
    return original.getDuration(self)
  end
  if self.character:isTimedActionInstant() then
    return 1
  end
  local waterUnits = math.min(ISWashYourself.GetRequiredWater(self.character), getPlumbedWaterAmount(self.sink))
  if self.soaps and self.soaps:isEmpty() then
    return waterUnits * 126
  else
    return waterUnits * 70
  end
end
