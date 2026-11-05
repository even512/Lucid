-- Kamera (B8): Katalog der verwalteten Kamera-CVars. Der Treiber (Existenz-Pruefung, Sicherung, Wiederherstellung,
-- CVAR_UPDATE) ist der gemeinsame aus CVarDriver.lua, Daten liegen in LucidDB.camera.
--
-- Grundwerte   normale camera*-CVars (Account-weit gespeichert => Restore-Pflicht, damit andere Charaktere unberuehrt bleiben)
-- Action Cam   test_camera*-CVars (lokal in Config.wtf; Blizzard zeigt beim Setzen ggf. die Experimental-Warnung)
-- abhaengig    CameraKeepCharacterCentered / CameraReduceUnexpectedMovement ("Bewegungsuebelkeit") stimmen Schulterversatz
--              und dynamische Neigung nieder; Lucid setzt sie nur, solange Action Cam gebraucht wird (Camera.lua)
local _, ns = ...

local BASE = {
    "cameraDistanceMaxZoomFactor", "cameraZoomSpeed", "cameraYawMoveSpeed", "cameraPitchMoveSpeed", "cameraSmoothStyle",
    "cameraTerrainTilt", "cameraIndirectVisibility", "cameraWaterCollision", "cameraFov",
}
local ACTION = {
    "test_cameraOverShoulder", "test_cameraDynamicPitch", "test_cameraDynamicPitchBaseFovPad",
    "test_cameraDynamicPitchBaseFovPadFlying", "test_cameraDynamicPitchBaseFovPadDownScale",
    "test_cameraDynamicPitchSmartPivotCutoffDist",
    "test_cameraHeadMovementStrength", "test_cameraHeadMovementStandingStrength", "test_cameraHeadMovementMovingStrength",
    "test_cameraHeadMovementRangeScale", "test_cameraHeadMovementDampRate", "test_cameraHeadMovementDeadZone",
    "test_cameraHeadMovementFirstPersonDampRate",
    "test_cameraTargetFocusEnemyEnable", "test_cameraTargetFocusEnemyStrengthYaw", "test_cameraTargetFocusEnemyStrengthPitch",
    "test_cameraTargetFocusInteractEnable", "test_cameraTargetFocusInteractStrengthYaw", "test_cameraTargetFocusInteractStrengthPitch",
}
local COMFORT = { "CameraKeepCharacterCentered", "CameraReduceUnexpectedMovement" }

local catalog = {}
for _, list in ipairs({ BASE, ACTION, COMFORT }) do
    for _, n in ipairs(list) do catalog[#catalog + 1] = n end
end

local CVars = ns.CVarDriver.New("camera", catalog)
CVars.BASE, CVars.ACTION, CVars.COMFORT = BASE, ACTION, COMFORT
CVars.KEEP_CENTERED, CVars.REDUCE_MOVEMENT = COMFORT[1], COMFORT[2]
ns.CameraCVars = CVars

--- true fuer die test_*-CVars (Action Cam, Experimental-Warnung)
function CVars.IsExperimental(name) return type(name) == "string" and name:sub(1, 5) == "test_" end
