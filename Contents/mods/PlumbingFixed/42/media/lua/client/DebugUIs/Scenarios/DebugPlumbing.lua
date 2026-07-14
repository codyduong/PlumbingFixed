require("PlumbingFixed/PFUtils")
require("PlumbingFixed/DebugRig")

if debugScenarios == nil then
  debugScenarios = {}
end

debugScenarios.DebugPlumbing = {
  name = "Plumbing Fixed Debug",
  forceLaunch = true,
  startLoc = { x = 8350, y = 7190, z = 0 },
  setSandbox = function()
    SandboxVars.VehicleEasyUse = true
    SandboxVars.Zombies = 5
    SandboxVars.FoodLoot = 1
    SandboxVars.WeaponLoot = 1
    SandboxVars.OtherLoot = 1
    SandboxVars.WaterShutModifier = -1
    SandboxVars.ElecShutModifier = -1
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
      ---@cast bottle InventoryItem
      bottle:getFluidContainer():removeFluid(i * 5)
      chr:getInventory():AddItem("Base.BandageDirty")
    end

    local shirt = chr:getInventory():AddItem("Base.Shirt_HawaiianRed")
    ---@cast shirt Clothing
    shirt:addRandomDirt()
    shirt:addRandomBlood()
    chr:setWornItem(shirt:getBodyLocation(), shirt)

    local clothe = inv:AddItem("Base.Trousers_Denim")
    ---@cast clothe Clothing
    clothe:getVisual():setTextureChoice(2)
    clothe:addRandomBlood()
    clothe:addRandomBlood()
    chr:setWornItem(clothe:getBodyLocation(), clothe)

    chr:addBlood(BloodBodyPartType.Torso_Upper, false, false, false)
    chr:addBlood(BloodBodyPartType.Torso_Upper, false, false, false)
    chr:addBlood(BloodBodyPartType.Torso_Upper, false, false, false)
    chr:addDirt(BloodBodyPartType.Hand_L, 5, false)
    chr:addDirt(BloodBodyPartType.Hand_R, 5, false)
    chr:addDirt(BloodBodyPartType.ForeArm_L, 5, false)
    chr:addDirt(BloodBodyPartType.ForeArm_R, 5, false)

    Events.OnGameStart.Add(function()
      -- Plumbed rig
      local barrels = PFDebugRig.build(8349, 7184, 0, true)
      for i, barrel in ipairs(barrels) do
        barrel:getFluidContainer():addFluid(Fluid.TaintedWater, 7.5 * i)
      end

      -- Unplumbed control rig
      local controlBarrels = PFDebugRig.build(8354, 7184, 0, false)
      local mixedBarrel = controlBarrels[1]
      if mixedBarrel then
        local mixedBarrelFC = mixedBarrel:getFluidContainer()
        mixedBarrelFC:addFluid(Fluid.TaintedWater, 10)
        mixedBarrelFC:addFluid(Fluid.Water, 5)
        mixedBarrelFC:addFluid(Fluid.TaintedWater, 10)
        mixedBarrelFC:addFluid(Fluid.CarbonatedWater, 20)
        mixedBarrelFC:addFluid(Fluid.Beer, 10)
        mixedBarrelFC:addFluid(Fluid.Bleach, 10)
      end

      -- Plumbed washer rig
      local washerBarrels = PFDebugRig.build(8359, 7184, 0, true, "washer")
      PFDebugRig.powerGenerator(8359, 7184, 0)
      for i, barrel in ipairs(washerBarrels) do
        barrel:getFluidContainer():addFluid(Fluid.TaintedWater, 7.5 * i)
      end
    end)
  end,
}
