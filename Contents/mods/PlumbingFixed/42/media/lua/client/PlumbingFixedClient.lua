require("PlumbingFixed/TimedActions/PFTakeWaterAction")
require("PlumbingFixed/TimedActions/PFWashClothing")
require("PlumbingFixed/TimedActions/PFCleanBandage")
require("PlumbingFixed/TimedActions/PFWashYourself")

-- The B42.19 fixture water menu is built natively in Java
-- (zombie/iso/ISWorldObjectContextMenuLogic). It scans the same 3x3 grid above the
-- fixture we do and binds each option (Drink/Fill/Wash/CleanBandage) to the Lua
-- handlers by name, which construct the timed actions we override above. So the mod
-- needs no client menu override -- it only has to load those overrides on the client.

-- DebugLog.setLogSeverity(DebugType.Mod, LogSeverity.All)
DebugLog.log(DebugType.Mod, "PlumbingFixed - initialized on client")
