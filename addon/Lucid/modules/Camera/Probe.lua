-- Kamera (B8/K0): Diagnose-Probe /lucid camera probe. Beantwortet im Client, was die Recherche offen liess:
-- Existenz, Wert, Standard, secure/gesperrt und Speicherort jeder Kamera-CVar, Grenzen (Min/Max), ob die Zoom-Funktionen
-- da sind, ob die Experimental-Warnung beim Schreiben von test_*-CVars erscheint.
-- Rein lesend; nur der Min/Max-Test schreibt - ausserhalb des Kampfs, je CVar kurz mit -1000 und 1000, jeder Wert wird
-- zurueckgelesen und der Originalwert sofort wiederhergestellt (auch bei Fehlern), mit Absturzsicherung (Guard).
-- Die Bewegungsuebelkeit-CVars werden nur gelesen, nie getestet. CameraZoomIn/Out werden nicht aufgerufen.
local _, ns = ...
local CVars, Camera = ns.CameraCVars, ns.Camera
local L = ns.L

-- zusaetzlich (nur lesen). Sichtfeld und die Feinwerte der Kopfbewegung stehen im Katalog und werden daher mitgetestet; hier
-- stehen Namensvarianten, von denen die Recherche nicht weiss, welche der Client wirklich hat.
local EXTRA = {
    "cameraSmoothTrackingStyle", "cameraYawSmoothSpeed", "cameraPitchSmoothSpeed", "cameraSavedDistance",
    "cameraSavedPitch", "ActionCombatCameraEnable", "ShakeStrengthCamera",
    "test_cameraHeadMovementStandingDampRate", "test_cameraHeadMovementMovingDampRate",
}
local TEST_LOW, TEST_HIGH = -1000, 1000
local EVENT = "EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED"

local function esc(s) return (tostring(s):gsub("|", "||")) end
local function yn(b) return b and L.CAM_YES or L.CAM_NO end
local function where(info)
    if info.character then return L.CAM_PROBE_CHARACTER end
    if info.account then return L.CAM_PROBE_ACCOUNT end
    return L.CAM_PROBE_LOCAL
end

local function probeLine(name)
    local info = CVars.Info(name)
    if not info.exists then
        ns.Print(L.CAM_PROBE_MISSING, name)
        return
    end
    ns.Print(L.CAM_PROBE_LINE, name, esc(info.value), esc(info.default or "-"), yn(info.secure), yn(info.locked),
        yn(info.readOnly), where(info))
end

local function isFn(path) return ns.Compat.HasAPI(path) end

--- Min/Max-Test fuer eine CVar. Liefert Tabellenzeile oder nil (uebersprungen).
local function testOne(name)
    local info = CVars.Info(name)
    if not info.exists or info.readOnly then return nil end
    local original = info.value
    local release = CVars.Guard(name) -- Absturz mitten im Test: der Login stellt den Originalwert wieder her
    local lo, hi
    local ok, err = pcall(function()
        CVars.ProbeWrite(name, TEST_LOW)
        lo = CVars.Get(name) or "?"
        CVars.ProbeWrite(name, TEST_HIGH)
        hi = CVars.Get(name) or "?"
    end)
    local okRestore, restored = pcall(CVars.ProbeWrite, name, original) -- immer sofort zurueck
    restored = okRestore and restored
    if restored and release then release() end
    return { name = name, original = original, lo = lo or "?", hi = hi or "?", restored = restored, err = (not ok) and err or nil }
end

local function rangeTest()
    if InCombatLockdown() then
        ns.Print(L.CAM_PROBE_RANGE_COMBAT)
        return
    end
    local count = 0
    local function onPopup() count = count + 1 end
    local listening = pcall(ns.On, EVENT, onPopup)
    ns.Print(L.CAM_PROBE_RANGE_HEAD, TEST_LOW, TEST_HIGH)
    for _, name in ipairs(CVars.CATALOG) do
        local isComfort = (name == CVars.KEEP_CENTERED or name == CVars.REDUCE_MOVEMENT)
        if not isComfort then
            local r = testOne(name)
            if r then
                ns.Print(L.CAM_PROBE_RANGE_LINE, name, esc(r.original), esc(r.lo), esc(r.hi),
                    r.restored and L.CAM_PROBE_RESTORED or L.CAM_PROBE_RESTORE_FAILED)
                if r.err then ns.Print(L.CAM_PROBE_ERROR, esc(r.err)) end
            end
        end
    end
    if listening then pcall(ns.Off, EVENT, onPopup) end
    ns.Print(listening and L.CAM_PROBE_POPUP_COUNT or L.CAM_PROBE_POPUP_UNKNOWN, count)
end

Camera.sub.probe = function()
    ns.Print(L.CAM_PROBE_HEAD, ns.Compat.flavor, ns.Compat.interface, yn(InCombatLockdown()))
    for _, name in ipairs(CVars.CATALOG) do probeLine(name) end
    for _, name in ipairs(EXTRA) do probeLine(name) end
    local zoom = "-"
    if isFn("GetCameraZoom") then
        local ok, v = pcall(GetCameraZoom)
        if ok and not ns.Compat.IsSecret(v) and v ~= nil then zoom = ("%.2f"):format(tonumber(v) or 0) end
    end
    ns.Print(L.CAM_PROBE_ZOOM, yn(isFn("CameraZoomIn")), yn(isFn("CameraZoomOut")), yn(isFn("GetCameraZoom")), zoom)
    local gameEvent = type(GameEvent) == "table" and type(GameEvent.UnregisterInternalEvent) == "function"
    local uiParent = type(UIParent) == "table" and type(UIParent.UnregisterEvent) == "function"
    ns.Print(L.CAM_PROBE_POPUP_API, yn(gameEvent), yn(uiParent))
    local fovLo, fovHi, fromClient = Camera.FovRange()
    local fovDefault = "-"
    if isFn("GetCameraFOVDefaults") then
        local ok, a = pcall(GetCameraFOVDefaults)
        a = ok and ns.Compat.Num(a) or nil
        if a then fovDefault = ("%g"):format(a) end
    end
    ns.Print(fromClient and L.CAM_PROBE_FOV or L.CAM_PROBE_FOV_FALLBACK, fovDefault, fovLo, fovHi)
    local conflicts = Camera.Conflicts()
    ns.Print(L.CAM_PROBE_ADDONS, #conflicts > 0 and table.concat(conflicts, ", ") or L.CAM_NONE)
    rangeTest()
end

ns.AddHelp("HELP_CAMERA_PROBE")
