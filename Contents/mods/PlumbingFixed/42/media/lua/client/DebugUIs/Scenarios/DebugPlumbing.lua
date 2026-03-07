require("PlumbingFixed/utils")

if debugScenarios == nil then
  debugScenarios = {}
end

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

  --javaObject:setWaterAmount(waterAmount)
  --javaObject:setTaintedWater(waterAmount > 0 and sq:isOutside())

  local info = SpriteConfigManager.getObjectInfoFromSprite(spriteName)
  if info and info:getScript() and info:getScript():getParent() then
    local gameEntityScript = info:getScript():getParent()
    local isFirstTimeCreated = true
    GameEntityFactory.CreateIsoObjectEntity(javaObject, gameEntityScript, isFirstTimeCreated)
  end

  return javaObject
end

--- @param sq IsoGridSquare
local function createWallW(sq)
  local javaObject = CreateObject(sq, "carpentry_02_100", "W")
  sq:AddSpecialObject(javaObject)
  javaObject:transmitCompleteItemToClients()
end

--- @param sq IsoGridSquare
local function createWallN(sq)
  local javaObject = CreateObject(sq, "carpentry_02_101", "N")
  sq:AddSpecialObject(javaObject)
  javaObject:transmitCompleteItemToClients()
end

--- @param x integer
--- @param y integer
--- @param z integer
local function fuckYouSq(x, y, z)
  local sq = getCell():getGridSquare(x, y, z)
  if sq == nil then
    sq = getCell():createNewGridSquare(x, y, z, false)
  end
  return sq
end

--- @param x integer
--- @param y integer
--- @param z integer
--- @param sprite string
local function createBarrelOnSq(x, y, z, sprite)
  local sq = fuckYouSq(x, y, z)
  local barrel = CreateBarrel(sq, sprite, 500)
  sq:AddSpecialObject(barrel)
  barrel:transmitCompleteItemToClients()
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
      local sq = fuckYouSq(x + i, y + j, z)
      sq:addTileObject(tile or "carpentry_02_56")
      if walls then
        if i == 0 then
          createWallW(sq)
        end
        if j == 0 then
          createWallN(sq)
        end
        if i == 2 then
          sq = fuckYouSq(x + i + 1, y + j, z)
          createWallW(sq)
        end
        if j == 2 then
          sq = fuckYouSq(x + i, y + j + 1, z)
          createWallN(sq)
        end
      end
    end
  end
end

debugScenarios.DebugPlumbing = {
  name = "Plumbing Fixed Debug",
  forceLaunch = true,
  startLoc = { x = 8350, y = 7190, z = 0 },
  -- ?8353x7188
  setSandbox = function()
    SandboxVars.VehicleEasyUse = true
    SandboxVars.Zombies = 5
    SandboxVars.FoodLoot = 1
    SandboxVars.WeaponLoot = 1
    SandboxVars.OtherLoot = 1
    SandboxVars.WaterShutModifier = -1
    SandboxVars.FireSpread = false
    SandboxVars.Helicopter = 1
  end,
  onStart = function()
    local chr = getPlayer()
    local inv = chr:getInventory()

    chr:clearWornItems()
    chr:getInventory():clear()
    chr:getInventory():AddItem("Base.PipeWrench")
    for i = 1, 3 do
      local bottle = chr:getInventory():AddItem("Base.WaterDispenserBottle")
      bottle:getFluidContainer():removeFluid(i * 5)
      chr:getInventory():AddItem("Base.BandageDirty")
    end

    local shirt = chr:getInventory():AddItem("Base.Shirt_HawaiianRed")
    ---@cast shirt Clothing
    shirt:addRandomDirt()
    shirt:addRandomBlood()
    chr:setWornItem(shirt:getBodyLocation(), shirt)

    local clothe = inv:AddItem("Base.Trousers_Denim");
		clothe:getVisual():setTextureChoice(2);
    ---@cast clothe Clothing
    clothe:addRandomBlood();
    clothe:addRandomBlood();
    chr:setWornItem(clothe:getBodyLocation(), clothe)

    chr:addBlood(BloodBodyPartType.Torso_Upper, false, false, false);
		chr:addBlood(BloodBodyPartType.Torso_Upper, false, false, false);
		chr:addBlood(BloodBodyPartType.Torso_Upper, false, false, false);

    threeByThree(8349, 7184, 0, true)
    threeByThree(8349, 7184, 1, false)

    local barrels = {}
    table.insert(barrels, createBarrelOnSq(8349, 7184, 1, "carpentry_02_122"))
    table.insert(barrels, createBarrelOnSq(8349, 7185, 1, "carpentry_02_124"))
    table.insert(barrels, createBarrelOnSq(8351, 7184, 1, "carpentry_02_54"))
    table.insert(barrels, createBarrelOnSq(8351, 7185, 1, "carpentry_02_120"))

    local centerSq = getCell():getGridSquare(8350, 7185, 0)
    centerSq:addTileObject("fixtures_sinks_01_32")
    local sink = centerSq:getObjectWithSprite("fixtures_sinks_01_32")
    sink:setUsesExternalWaterSource(true)

    for i, barrel in ipairs(barrels) do
      --- @cast barrel IsoThumpable
      barrel:getFluidContainer():addFluid(Fluid.Water, 15 * i)
    end

    -- local stair = fuckYouSq(8349, 7189, 0)
    local stairs = ISWoodenStairs:new("carpentry_02_88", "carpentry_02_89", "carpentry_02_90", "carpentry_02_96", "carpentry_02_97", "carpentry_02_98", "carpentry_02_94", "carpentry_02_95");
    -- local sprite = "carpentry_02_88";
    -- if north then
    --   sprite = "carpentry_02_96";
    -- end
    stairs:create(8349, 7189, 0, true, "carpentry_02_96")
  end,
}
