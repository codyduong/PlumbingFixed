-- PlumbingFixed ephemeral testhost sandbox: mirrors the SP DebugPlumbing scenario's
-- setSandbox so MP testing happens under the same conditions (no zombies, water never
-- shuts off, no fire spread).
SandboxVars = {
    VERSION = 6,
    Zombies = 5, -- population: None
    WaterShutModifier = -1,
    ElecShutModifier = -1,
    FireSpread = false,
    Helicopter = 1,
    VehicleEasyUse = true,
}
