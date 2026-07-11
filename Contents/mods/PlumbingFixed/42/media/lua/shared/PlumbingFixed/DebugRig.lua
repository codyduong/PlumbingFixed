-- Programmatic PlumbingFixed test rig, extracted from the DebugPlumbing scenario so it can
-- be built anywhere: the scenario composes two of them (plumbed + unplumbed control), and
-- in MP an admin can spawn one at the clicked square (server-side via OnClientCommand —
-- see client/DebugUIs/PFTestRigMenu.lua and server/PlumbingFixedServer.lua).
--
-- ONE rig, relative to the origin (x, y, z):
--   platform  x..x+2, y..y+2   walled floor at z, open floor at z+1
--   barrels   4 at z+1         returned EMPTY — the caller picks the fluids
--   sink      (x+1, y+1, z)    plumbed or not per the `plumbed` argument
--   stairs    (x, y+5, z)      up to the barrel floor
-- Walls extend one square past the platform (x+3 / y+3), so the footprint including the
-- stair run is x..x+3, y..y+5 on both z and z+1 — that whole box is cleared first.

PFDebugRig = {}

-- Cleared/occupied extent relative to the origin (inclusive tile counts).
PFDebugRig.WIDTH = 4
PFDebugRig.DEPTH = 6
PFDebugRig.LEVELS = 2

--- @param sq IsoGridSquare
--- @param spriteName string
--- @param dir "N" | "W"
local function CreateObject(sq, spriteName, dir)
  local modData = {}
  modData["need:Base.Plank"] = "2"
  modData["need:Base.Nails"] = "2"

  local cell = getWorld():getCell()
  local north = dir == "N"
  local javaObject = IsoThumpable.new(cell, sq, spriteName, north, modData)

  javaObject:setCanPassThrough(false)
  javaObject:setCanBarricade(true)
  javaObject:setThumpDmg(8)
  javaObject:setIsContainer(false)
  javaObject:setIsDoor(false)
  javaObject:setIsDoorFrame(false)
  javaObject:setCrossSpeed(1.0)
  javaObject:setBlockAllTheSquare(false)
  javaObject:setName("WoodenWallFrame")
  javaObject:setIsDismantable(false)
  javaObject:setCanBePlastered(false)
  javaObject:setIsHoppable(false)
  javaObject:setIsThumpable(true)
  javaObject:setModData(copyTable(modData))
  javaObject:setMaxHealth(50)
  javaObject:setHealth(50)
  javaObject:setBreakSound("BreakObject")
  javaObject:setSpecialTooltip(false)

  return javaObject
end

--- @param sq IsoGridSquare
--- @param spriteName string
--- @param health integer
local function CreateBarrel(sq, spriteName, health)
  local modData = {}
  modData["need:Base.Plank"] = "4"
  modData["need:Base.Nails"] = "4"
  modData["need:Base.Garbagebag"] = "4"

  local cell = getWorld():getCell()
  local north = false
  local javaObject = IsoThumpable.new(cell, sq, spriteName, north, modData)

  javaObject:setCanPassThrough(false)
  javaObject:setCanBarricade(false)
  javaObject:setThumpDmg(8)
  javaObject:setIsContainer(false)
  javaObject:setIsDoor(false)
  javaObject:setIsDoorFrame(false)
  javaObject:setCrossSpeed(1.0)
  javaObject:setBlockAllTheSquare(true)
  javaObject:setName("Rain Collector Barrel")
  javaObject:setIsDismantable(true)
  javaObject:setCanBePlastered(false)
  javaObject:setIsHoppable(false)
  javaObject:setIsThumpable(true)
  javaObject:setModData(copyTable(modData))
  javaObject:setMaxHealth(health)
  javaObject:setHealth(health)
  javaObject:setBreakSound("BreakObject")
  javaObject:setSpecialTooltip(true)

  -- The entity script is what gives the barrel its FluidContainer. Vanilla builds do this
  -- before AddSpecialObject (MORainCollectorBarrel.lua, ISBuildIsoEntity.lua) and treat a
  -- missing script as an error — a silent skip here is how rig barrels ended up with no
  -- fluid capacity.
  local info = SpriteConfigManager.getObjectInfoFromSprite(spriteName)
  ---@diagnostic disable-next-line: unnecessary-if
  if info and info:getScript() and info:getScript():getParent() then
    local gameEntityScript = info:getScript():getParent()
    local isFirstTimeCreated = true
    GameEntityFactory.CreateIsoObjectEntity(javaObject, gameEntityScript, isFirstTimeCreated)
  else
    DebugLog.log(DebugType.Mod, "PlumbingFixed (PFDebugRig) ERROR: no entity script for sprite " .. spriteName)
  end

  return javaObject
end

--- Attach a built object to its square the way ISBuildIsoEntity:create does: add,
--- mark explored (containers must not spawn loot), recalc the square so sprites/collision
--- resolve (skipping this is how rig objects sometimes rendered without sprites), transmit.
--- @param sq IsoGridSquare
--- @param obj IsoObject
local function placeSpecialObject(sq, obj)
  sq:AddSpecialObject(obj)
  obj:setExplored(true)
  sq:RecalcAllWithNeighbours(true)
  obj:transmitCompleteItemToClients()
end

--- Get the square, creating it if that part of the world has never been loaded.
--- @param x integer
--- @param y integer
--- @param z integer
local function forceGetSquare(x, y, z)
  local sq = getCell():getGridSquare(x, y, z)
  if sq == nil then
    sq = getCell():createNewGridSquare(x, y, z, false)
  end
  return sq
end

--- @param sq IsoGridSquare
local function createWallW(sq)
  placeSpecialObject(sq, CreateObject(sq, "carpentry_02_100", "W"))
end

--- @param sq IsoGridSquare
local function createWallN(sq)
  placeSpecialObject(sq, CreateObject(sq, "carpentry_02_101", "N"))
end

--- @param x integer
--- @param y integer
--- @param z integer
--- @param sprite string
local function createBarrelOnSq(x, y, z, sprite)
  local sq = forceGetSquare(x, y, z)
  local barrel = CreateBarrel(sq, sprite, 500)
  placeSpecialObject(sq, barrel)
  return barrel
end

--- @param x integer
--- @param y integer
--- @param z integer
--- @param walls boolean
--- @param tile? string
local function threeByThree(x, y, z, walls, tile)
  for i = 0, 2 do
    for j = 0, 2 do
      local sq = forceGetSquare(x + i, y + j, z)
      sq:addFloor(tile or "carpentry_02_56")
      if walls then
        if i == 0 then
          createWallW(sq)
        end
        if j == 0 then
          createWallN(sq)
        end
        if i == 2 then
          sq = forceGetSquare(x + i + 1, y + j, z)
          createWallW(sq)
        end
        if j == 2 then
          sq = forceGetSquare(x + i, y + j + 1, z)
          createWallN(sq)
        end
      end
    end
  end
end

--- @param x integer
--- @param y integer
--- @param z integer
--- @param plumbed boolean
local function createSinkOnSq(x, y, z, plumbed)
  local sq = forceGetSquare(x, y, z)
  sq:addTileObject("fixtures_sinks_01_32")
  local sink = sq:getObjectWithSprite("fixtures_sinks_01_32")
  if sink and plumbed then
    sink:getModData().canBeWaterPiped = false
    sink:setUsesExternalWaterSource(true)
    sink:transmitModData()
  end
  sq:RecalcAllWithNeighbours(true)
  if sink and isServer() then
    sink:transmitCompleteItemToClients()
  end
  return sink
end

--- Spawn a real IsoClothingWasher
--- (0-3 are the combo washer/dryer, per newtiledefinitions.tiles).
--- @param x integer
--- @param y integer
--- @param z integer
--- @param plumbed boolean
local function createWasherOnSq(x, y, z, plumbed)
  local sq = forceGetSquare(x, y, z)
  local washer = IsoClothingWasher.new(getCell(), sq, getSprite("appliances_laundry_01_4"))
  washer:setMovedThumpable(true)
  washer:createContainersFromSpriteProperties()
  for i = 1, washer:getContainerCount() do
    washer:getContainerByIndex(i - 1):setExplored(true)
  end
  placeSpecialObject(sq, washer)
  if plumbed then
    washer:getModData().canBeWaterPiped = false
    washer:setUsesExternalWaterSource(true)
    washer:transmitModData()
    washer:sendObjectChange(IsoObjectChange.USES_EXTERNAL_WATER_SOURCE, { value = true })
  end
  sq:RecalcAllWithNeighbours(true)
  return washer
end

local GENERATOR_OFFSET_X = 1
local GENERATOR_OFFSET_Y = 5

--- @param x integer
--- @param y integer
--- @param z integer
local function createGeneratorOnSq(x, y, z)
  local sq = forceGetSquare(x, y, z)
  local generator = IsoGenerator.new(instanceItem("Base.Generator"), getCell(), sq)
  generator:setConnected(true)
  generator:setFuel(100)
  generator:setActivated(true)
  return generator
end

--- @param x integer rig origin x
--- @param y integer rig origin y
--- @param z integer rig origin z
function PFDebugRig.powerGenerator(x, y, z)
  local sq = getCell():getGridSquare(x + GENERATOR_OFFSET_X, y + GENERATOR_OFFSET_Y, z)
  if sq == nil then
    return
  end
  local objects = sq:getObjects()
  for i = 0, objects:size() - 1 do
    local obj = objects:get(i)
    if instanceof(obj, "IsoGenerator") then
      --- @cast obj IsoGenerator
      obj:setConnected(true)
      obj:setFuel(100)
      obj:setActivated(true)
      return
    end
  end
end

--- Remove everything (except the natural floor and dropped items) from the rig's
--- footprint, so spawning over existing walls/trees/furniture can't produce a broken rig.
--- transmitRemoveItemFromSquare is the MP-aware removal vanilla moveables use.
--- @param x integer
--- @param y integer
--- @param z integer
function PFDebugRig.clear(x, y, z)
  for i = 0, PFDebugRig.WIDTH - 1 do
    for j = 0, PFDebugRig.DEPTH - 1 do
      for k = 0, PFDebugRig.LEVELS - 1 do
        local sq = getCell():getGridSquare(x + i, y + j, z + k)
        if sq ~= nil then
          local objects = sq:getObjects()
          for n = objects:size() - 1, 0, -1 do
            local obj = objects:get(n)
            if obj ~= sq:getFloor() and not instanceof(obj, "IsoWorldInventoryObject") then
              sq:transmitRemoveItemFromSquare(obj)
            end
          end
        end
      end
    end
  end
end

--- Clear the footprint, then build one rig. Runs on the authoritative side (SP world or
--- the server); every created object transmits itself to clients. The barrels come back
--- EMPTY — the caller chooses the fluids (the scenario and the MP spawn command want
--- different loadouts).
--- @param x integer
--- @param y integer
--- @param z integer
--- @param plumbed boolean plumb the fixture (false = vanilla-behaving control rig)
--- @param fixture? "sink" | "washer" fixture under the barrels (default "sink")
--- @return IsoThumpable[] barrels the 4 barrels on the floor above the fixture
function PFDebugRig.build(x, y, z, plumbed, fixture)
  fixture = fixture or "sink"
  PFDebugRig.clear(x, y, z)

  threeByThree(x, y, z, true)
  threeByThree(x, y, z + 1, false)

  local barrels = {}
  table.insert(barrels, createBarrelOnSq(x, y, z + 1, "carpentry_02_122"))
  table.insert(barrels, createBarrelOnSq(x, y + 1, z + 1, "carpentry_02_124"))
  table.insert(barrels, createBarrelOnSq(x + 2, y, z + 1, "carpentry_02_54"))
  table.insert(barrels, createBarrelOnSq(x + 2, y + 1, z + 1, "carpentry_02_120"))

  ---@diagnostic disable-next-line: unnecessary-if -- checker over-narrows `fixture or "sink"`
  if fixture == "washer" then
    createWasherOnSq(x + 1, y + 1, z, plumbed)
    createGeneratorOnSq(x + GENERATOR_OFFSET_X, y + GENERATOR_OFFSET_Y, z)
  else
    createSinkOnSq(x + 1, y + 1, z, plumbed)
  end

  local stairs = ISWoodenStairs:new(
    "carpentry_02_88",
    "carpentry_02_89",
    "carpentry_02_90",
    "carpentry_02_96",
    "carpentry_02_97",
    "carpentry_02_98",
    "carpentry_02_94",
    "carpentry_02_95"
  )
  stairs:create(x, y + 5, z, true, "carpentry_02_96")

  return barrels
end

--- Default barrel loadout for spawned rigs: the same amount of tainted water in every
--- barrel (exercises purification and keeps the equal-draw symmetric).
--- @param barrels IsoThumpable[]
--- @param amountEach number
function PFDebugRig.fillEqualTainted(barrels, amountEach)
  for _, barrel in ipairs(barrels) do
    barrel:getFluidContainer():addFluid(Fluid.TaintedWater, amountEach)
    barrel:transmitCompleteItemToClients()
  end
end
