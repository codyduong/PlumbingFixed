--- Single creation point for the mod's PZAPI.ModOptions page. Regular options live
--- here; debug-only options attach to the same instance behind their own gate
--- (PFTestRigMenu adds the spawn-test-rig tickbox when debug is enabled).
--- @class PFModOptions
PFModOptions = {}

PFModOptions.options = PZAPI.ModOptions:create("PlumbingFixed", "Plumbing Fixed")

--- Whether or not to show the matrix at all
PFModOptions.showMatrix = PFModOptions.options:addTickBox(
  "showMatrix",
  getText("IGUI_PFShowMatrixAxis"),
  true,
  getText("IGUI_PFShowMatrixAxisTooltip")
)

PFModOptions.showMatrix.onChange = function(_, bool)
  if PFModOptions.matrixAxisXPrimary ~= nil then
    PFModOptions.matrixAxisXPrimary:setEnabled(bool)
  end
  if PFModOptions.poolBarPosition ~= nil then
    PFModOptions.poolBarPosition:setEnabled(bool)
  end
end

--- Transpose toggle for the connected-barrels 3x3 grid (PFConnectedMatrixPanel):
--- unchecked (default) each row shares a world Y coordinate (columns vary X); checked
--- transposes.
PFModOptions.matrixAxisXPrimary = PFModOptions.options:addTickBox(
  "matrixAxisXPrimary",
  getText("IGUI_PFMatrixAxisOption"),
  false,
  getText("IGUI_PFMatrixAxisTooltip")
)

--- Position of the pooled-total bar around the 3x3 grid. getValue() is the 1-based item
--- index in insertion order: 1 = left, 2 = right (default), 3 = top, 4 = bottom —
--- PFConnectedMatrixPanel.POS_* mirror these.
PFModOptions.poolBarPosition = PFModOptions.options:addComboBox(
  "poolBarPosition",
  getText("IGUI_PFPoolBarPositionOption"),
  getText("IGUI_PFPoolBarPositionTooltip")
)
PFModOptions.poolBarPosition:addItem("IGUI_PFPoolBarLeft", false)
PFModOptions.poolBarPosition:addItem("IGUI_PFPoolBarRight", true)
PFModOptions.poolBarPosition:addItem("IGUI_PFPoolBarTop", false)
PFModOptions.poolBarPosition:addItem("IGUI_PFPoolBarBottom", false)
