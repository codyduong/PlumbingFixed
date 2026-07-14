require("PlumbingFixed/utils")

--- @class PFRawBound
--- @field getFluidAmount fun(self: PFRawBound): number
--- @field hasFluid fun(self: PFRawBound): boolean
--- @field hasWater fun(self: PFRawBound): boolean
--- @field useFluid fun(self: PFRawBound, amount: number): number
--- @field moveFluidToTemporaryContainer fun(self: PFRawBound, amount: number): FluidContainer
--- @field transferFluidTo fun(self: PFRawBound, target: FluidContainer, amount: number): number

--- Kahlua dispatches userdata method calls through `__classmetatables[Class].__index`,
--- a plain Lua table, and flattens inherited methods into each concrete class's own table
---
--- PZ's Kahlua (KahluaThread.tableget) passes the ORIGINAL receiver to a function
--- `__index` anywhere in the lookup chain, and consults it only after the method table.
--- @param class any
local function installPooledPrimitives(class)
  --- @type IsoObject
  local index = __classmetatables[class].__index

  local vanilla = rawget(index, "__PFvanilla")
  if vanilla == nil then
    vanilla = {
      getFluidAmount = index.getFluidAmount,
      hasFluid = index.hasFluid,
      hasWater = index.hasWater,
      useFluid = index.useFluid,
      moveFluidToTemporaryContainer = index.moveFluidToTemporaryContainer,
      transferFluidTo = index.transferFluidTo,
    }
    rawset(index, "__PFvanilla", vanilla)
  end

  setmetatable(index, {
    __index = function(obj, key)
      if key == "__PFraw" then
        return setmetatable({}, {
          __index = function(_, method)
            return function(_, ...)
              return vanilla[method](obj, ...)
            end
          end,
        })
      end
    end,
  })

  function index:getFluidAmount()
    return getPlumbedFluidAmount(self)
  end

  function index:hasFluid()
    return self:getFluidAmount() > 0
  end

  function index:hasWater()
    return hasPlumbedWater(self)
  end

  function index:useFluid(amount)
    return usePlumbedFluid(self, amount)
  end

  function index:moveFluidToTemporaryContainer(amount)
    return movePlumbedFluidToTemporaryContainer(self, amount)
  end

  function index:transferFluidTo(target, amount)
    return transferPlumbedFluidTo(self, target, amount)
  end
end

installPooledPrimitives(IsoObject.class)
installPooledPrimitives(IsoThumpable.class)

DebugLog.log(DebugType.Mod, "PlumbingFixed - pooled fluid primitives installed")
