-- Kamera (B8): zustandsabhaengige Kamera-Einstellungen. K1 = Profilabschnitt "camera", Grundwerte, Action Cam,
-- Barrierefreiheits-Abschaltung mit Restore, Unterdrueckung der Experimental-Warnung, Sperre bei fremden Kamera-Addons,
-- Slash /lucid camera. K2 = Regeln je Zustand (Reihenfolge, die erste erfuellte gewinnt) und Voreinstellungen.
-- Erweiterung: Zustaende "indoors"/"swimming", Schulterversatz nach Kameraabstand (Offset.lua), weitere Feinwerte.
--
-- Standard enabled=false: Lucid fasst dann keine CVar an (und stellt Reste einer frueheren Sitzung zurueck).
-- Nur Werte, die der Nutzer aktiv gesetzt hat, werden geschrieben; Werte ohne Eintrag bleiben bei Blizzard.
-- Endet ein Zustand, gilt wieder der Grundwert bzw. Blizzards Wert (Sicherung/Restore im Treiber, CVarDriver.lua).
local _, ns = ...
local Store, State, CVars = ns.Store, ns.State, ns.CameraCVars
local Compat = ns.Compat
local L = ns.L

local Camera = {}
ns.Camera = Camera
Camera.sub = {} -- Unterbefehle von /lucid camera (Probe.lua traegt "probe" ein)
local active = false -- Modul aktiv (nach PLAYER_LOGIN)

Camera.MAX_RULES = 8
Camera.ZOOM_MIN, Camera.ZOOM_MAX = 1, Compat.isRetail and 39 or 50 -- Ziel-Distanz in Yards
Camera.ZOOM_SECONDS_MIN, Camera.ZOOM_SECONDS_MAX = 0.1, 5
Camera.OFFSET_SECONDS_MIN, Camera.OFFSET_SECONDS_MAX = 0, 2
Camera.FOCUS_SECONDS_MIN, Camera.FOCUS_SECONDS_MAX = 0, 3
Camera.EXPERIMENTAL_EVENT = "EXPERIMENTAL_CVAR_CONFIRMATION_NEEDED"
Camera.FOV_VALID_MIN, Camera.FOV_VALID_MAX = 30, 150 -- grobe Pruefgrenzen (Profil/Import); wirksam gilt Camera.FovRange()
Camera.FOV_FALLBACK_MIN, Camera.FOV_FALLBACK_MAX = 50, 90 -- ohne GetCameraFOVDefaults

-- Fremde Kamera-Addons: gegen sie steuert Lucid die Kamera nicht (zwei Schreiber auf denselben CVars)
Camera.CONFLICT_ADDONS = { "DynamicCam", "ActionCamPlus", "CameraOverShoulderFix" }

local function addonLoaded(name)
    local fn = (C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
    if type(fn) ~= "function" then return false end
    local ok, v = pcall(fn, name)
    return ok and (v == true or v == 1)
end

--- Namen der geladenen fremden Kamera-Addons (leere Liste = keine)
function Camera.Conflicts()
    local out = {}
    for _, n in ipairs(Camera.CONFLICT_ADDONS) do
        if addonLoaded(n) then out[#out + 1] = n end
    end
    return out
end

function Camera.IsLocked() return #Camera.Conflicts() > 0 end

-- Einstellbare Werte -------------------------------------------------------------------------------
-- section: base = Grundwerte, action = Action Cam, target = Zielfokus. kind: num | bool | enum. Bereiche aus der Recherche
-- (DynamicCam-Slider); der Client klemmt selbst, Lucid lehnt Werte ausserhalb ab (Fremddatei-Input).
local MAX_ZOOM_FACTOR = Compat.isRetail and 2.6 or 3.33
local PARAM_LIST = {
    { id = "cameraDistanceMaxZoomFactor", section = "base", kind = "num", min = 1, max = MAX_ZOOM_FACTOR, step = 0.1 },
    { id = "cameraZoomSpeed", section = "base", kind = "num", min = 1, max = 50, step = 1 },
    { id = "cameraYawMoveSpeed", section = "base", kind = "num", min = 45, max = 360, step = 5 },
    { id = "cameraPitchMoveSpeed", section = "base", kind = "num", min = 22, max = 180, step = 5, hidden = true }, -- folgt Yaw/2
    { id = "cameraSmoothStyle", section = "base", kind = "enum", values = { 0, 1, 2, 4 } },
    { id = "cameraTerrainTilt", section = "base", kind = "bool" },
    { id = "cameraIndirectVisibility", section = "base", kind = "bool" },
    { id = "cameraWaterCollision", section = "base", kind = "bool" },
    { id = "cameraFov", section = "base", kind = "num", min = Camera.FOV_VALID_MIN, max = Camera.FOV_VALID_MAX, step = 1 }, -- Anzeige/Klemme: FovRange
    { id = "test_cameraOverShoulder", section = "action", kind = "num", min = -15, max = 15, step = 0.1 },
    { id = "test_cameraDynamicPitch", section = "action", kind = "bool" },
    { id = "test_cameraDynamicPitchBaseFovPad", section = "action", kind = "num", min = 0, max = 0.99, step = 0.01 },
    { id = "test_cameraDynamicPitchBaseFovPadFlying", section = "action", kind = "num", min = 0, max = 1, step = 0.01 },
    { id = "test_cameraDynamicPitchBaseFovPadDownScale", section = "action", kind = "num", min = 0, max = 1, step = 0.01 },
    { id = "test_cameraDynamicPitchSmartPivotCutoffDist", section = "action", kind = "num", min = 0, max = 40, step = 1 },
    { id = "test_cameraHeadMovementStrength", section = "head", kind = "num", min = 0, max = 2, step = 0.1 },
    { id = "test_cameraHeadMovementStandingStrength", section = "head", kind = "num", min = 0, max = 1, step = 0.05 },
    { id = "test_cameraHeadMovementMovingStrength", section = "head", kind = "num", min = 0, max = 1, step = 0.05 },
    { id = "test_cameraHeadMovementRangeScale", section = "head", kind = "num", min = 0, max = 30, step = 0.5 },
    { id = "test_cameraHeadMovementDampRate", section = "head", kind = "num", min = 0, max = 20, step = 0.5 },
    { id = "test_cameraHeadMovementDeadZone", section = "head", kind = "num", min = 0, max = 0.1, step = 0.005 },
    { id = "test_cameraHeadMovementFirstPersonDampRate", section = "head", kind = "num", min = 0, max = 40, step = 1 },
    { id = "test_cameraTargetFocusEnemyEnable", section = "target", kind = "bool" },
    { id = "test_cameraTargetFocusEnemyStrengthYaw", section = "target", kind = "num", min = 0, max = 1, step = 0.05 },
    { id = "test_cameraTargetFocusEnemyStrengthPitch", section = "target", kind = "num", min = 0, max = 1, step = 0.05 },
    { id = "test_cameraTargetFocusInteractEnable", section = "target", kind = "bool" },
    { id = "test_cameraTargetFocusInteractStrengthYaw", section = "target", kind = "num", min = 0, max = 1, step = 0.05 },
    { id = "test_cameraTargetFocusInteractStrengthPitch", section = "target", kind = "num", min = 0, max = 1, step = 0.05 },
}
Camera.PARAMS = PARAM_LIST
Camera.SECTIONS = { "base", "action", "head", "target", "zoom" }
local PARAM = {}
for _, p in ipairs(PARAM_LIST) do PARAM[p.id] = p end
Camera.PARAM = PARAM

-- Zustaende, fuer die Regeln moeglich sind (Reihenfolge = Anzeige); "mouseover" ist kein Dauerzustand
Camera.RULE_STATES = { "combat", "target", "resting", "city", "group", "raid", "instance", "mounted", "flying", "swimming", "indoors", "npc" }
local RULE_STATE = {}
for _, n in ipairs(Camera.RULE_STATES) do RULE_STATE[n] = true end

Camera.DEFAULTS = {
    enabled = false,
    suppressPopup = true, -- Blizzards Experimental-Warnung ("Deaktivieren" setzt alle test_*-CVars zurueck) unterdruecken
    autoComfort = true,   -- Bewegungsuebelkeit-Optionen abschalten, solange Action Cam gebraucht wird
    zoomSeconds = 0.6,    -- Dauer des weichen Uebergangs zu einer Ziel-Distanz
    offsetByDistance = false, -- Schulterversatz nach Kameraabstand skalieren (Offset.lua); die Filmisch-Voreinstellungen schalten ihn an
    offsetSeconds = 0.6,      -- Dauer des weichen Uebergangs des Schulterversatzes bei Regel-/Zustandswechsel (0 = sofort)
    focusSeconds = 1.5,       -- Dauer des weichen Ein-/Ausblendens des Zielfokus auf Gegner (Focus.lua, 0 = sofort)
}

-- Einstellungen -------------------------------------------------------------------------------------
local function round4(v) return tonumber(("%.4f"):format(v)) end

--- Wert einer Kamera-CVar pruefen. Liefert normalisierte Zahl oder nil.
function Camera.ValidValue(id, v)
    local p = PARAM[id]
    if not p then return nil end
    if v == true then v = 1 elseif v == false then v = 0 end
    if type(v) ~= "number" or v ~= v then return nil end
    if p.kind == "bool" then
        if v ~= 0 and v ~= 1 then return nil end
    elseif p.kind == "enum" then
        local ok = false
        for _, x in ipairs(p.values) do if x == v then ok = true end end
        if not ok then return nil end
    elseif v < p.min or v > p.max then
        return nil
    end
    return round4(v)
end

--- Ziel-Distanz pruefen (Yards)
function Camera.ValidZoom(v)
    return type(v) == "number" and v == v and v >= Camera.ZOOM_MIN and v <= Camera.ZOOM_MAX
end

--- Sichtfeld-Grenzen des Clients (GetCameraFOVDefaults liefert Standard, Min, Max; die Reihenfolge wird nicht vorausgesetzt:
--- kleinster Wert = Min, groesster = Max). Fehlt die Funktion oder liefert sie Unsinn: sichere Grenzen 50 bis 90.
--- Rueckgabe: min, max, aus dem Client (true) oder Rueckfall (false).
function Camera.FovRange()
    if type(GetCameraFOVDefaults) == "function" then
        local ok, a, b, c = pcall(GetCameraFOVDefaults)
        a, b, c = Compat.Num(a), Compat.Num(b), Compat.Num(c)
        if ok and a and b and c then
            local lo, hi = math.min(a, b, c), math.max(a, b, c)
            lo, hi = math.max(lo, Camera.FOV_VALID_MIN), math.min(hi, Camera.FOV_VALID_MAX)
            if lo < hi then return lo, hi, true end
        end
    end
    return Camera.FOV_FALLBACK_MIN, Camera.FOV_FALLBACK_MAX, false
end

local function validateCvars(v)
    if type(v) ~= "table" then return nil, "type" end
    local out = {}
    for id, x in pairs(v) do
        if type(id) == "string" and PARAM[id] then -- unbekannte CVars fallen weg
            local n = Camera.ValidValue(id, x)
            if n == nil then return nil, id end
            out[id] = n
        end
    end
    return out
end

local function validateBase(v)
    if type(v) ~= "table" then return nil, "type" end
    local out = {}
    for k, x in pairs(v) do
        if k == "cvars" then
            local c, detail = validateCvars(x)
            if not c then return nil, "cvars." .. tostring(detail) end
            out.cvars = c
        elseif k == "zoom" then
            if not Camera.ValidZoom(x) then return nil, k end
            out.zoom = round4(x)
        end
    end
    return out
end

local function validateRules(v)
    if type(v) ~= "table" then return nil, "type" end
    if #v > Camera.MAX_RULES then return nil, "count" end
    local out = {}
    for i = 1, #v do
        local r = v[i]
        if type(r) ~= "table" then return nil, tostring(i) end
        if type(r.state) ~= "string" or not RULE_STATE[r.state] then return nil, i .. ".state" end
        local c, detail = validateCvars(r.cvars == nil and {} or r.cvars)
        if not c then return nil, i .. ".cvars." .. tostring(detail) end
        local zoom = nil
        if r.zoom ~= nil then
            if not Camera.ValidZoom(r.zoom) then return nil, i .. ".zoom" end
            zoom = round4(r.zoom)
        end
        out[i] = { state = r.state, cvars = c, zoom = zoom }
    end
    return out
end

--- Profil-Abschnitt "camera" pruefen (Import und Aendern). Liefert bereinigte Kopie oder nil, Detail.
function Camera.Validate(v)
    if type(v) ~= "table" then return nil, "type" end
    local out = {}
    for k, x in pairs(v) do
        if k == "enabled" or k == "suppressPopup" or k == "autoComfort" or k == "offsetByDistance" then
            if type(x) ~= "boolean" then return nil, k end
            out[k] = x
        elseif k == "zoomSeconds" then
            if type(x) ~= "number" or x ~= x or x < Camera.ZOOM_SECONDS_MIN or x > Camera.ZOOM_SECONDS_MAX then return nil, k end
            out[k] = x
        elseif k == "offsetSeconds" then
            if type(x) ~= "number" or x ~= x or x < Camera.OFFSET_SECONDS_MIN or x > Camera.OFFSET_SECONDS_MAX then return nil, k end
            out[k] = x
        elseif k == "focusSeconds" then
            if type(x) ~= "number" or x ~= x or x < Camera.FOCUS_SECONDS_MIN or x > Camera.FOCUS_SECONDS_MAX then return nil, k end
            out[k] = x
        elseif k == "base" then
            local b, detail = validateBase(x)
            if not b then return nil, "base." .. tostring(detail) end
            out.base = b
        elseif k == "rules" then
            local r, detail = validateRules(x)
            if not r then return nil, "rules." .. tostring(detail) end
            out.rules = r
        end -- unbekannte Felder fallen weg
    end
    return out
end

Store.RegisterSection("camera", {
    default = function() return {} end,
    validate = Camera.Validate,
})

--- wirksame Einstellungen (Profil > Camera.DEFAULTS), immer gueltig
function Camera.GetConfig()
    local stored
    if Store.db then
        local p = Store.GetActive()
        stored = p and p.camera
    end
    local clean = type(stored) == "table" and Camera.Validate(stored) or {}
    local D = Camera.DEFAULTS
    local function pick(k)
        if clean[k] ~= nil then return clean[k] end
        return D[k]
    end
    return {
        enabled = pick("enabled"), suppressPopup = pick("suppressPopup"), autoComfort = pick("autoComfort"),
        zoomSeconds = pick("zoomSeconds"), offsetByDistance = pick("offsetByDistance"), offsetSeconds = pick("offsetSeconds"),
        focusSeconds = pick("focusSeconds"),
        base = { cvars = Store.DeepCopy(clean.base and clean.base.cvars or {}), zoom = clean.base and clean.base.zoom or nil },
        rules = Store.DeepCopy(clean.rules or {}),
    }
end

-- Regeln --------------------------------------------------------------------------------------------
--- Index der ersten Regel, deren Zustand gerade zutrifft (Reihenfolge der Liste), oder nil
function Camera.ActiveRule(cfg)
    cfg = cfg or Camera.GetConfig()
    for i, r in ipairs(cfg.rules) do
        if State.GetQuiet(r.state) then return i end -- der Bedarf an Ticker-Zustaenden laeuft ueber syncStateNeeds
    end
    return nil
end

-- Zustaende mit Polling (drinnen, schwimmen): Ticker nur, solange eine Regel sie braucht ----------------
local function syncStateNeeds(cfg)
    local used = {}
    if cfg then
        for _, r in ipairs(cfg.rules) do used[r.state] = true end
    end
    for name in pairs(State.POLLED) do State.Need(name, "camera", used[name]) end
end

-- Sollwerte -----------------------------------------------------------------------------------------
local paused = false -- Nutzer/Blizzard hat eine Action-Cam-CVar von aussen geaendert (z. B. Warnung "Deaktivieren")
local comfortNotified = false

local function nonzero(v) return v ~= nil and v ~= 0 end

--- Soll-Werte ohne Abstandsskalierung (der Schulterversatz ist hier der Sollwert der Regel, nicht der wirksame).
--- Zweiter Rueckgabewert: Index der wirksamen Regel (oder nil).
function Camera.DesiredStatic(cfg)
    cfg = cfg or Camera.GetConfig()
    local d = {}
    if not cfg.enabled then return d, nil end
    for id, v in pairs(cfg.base.cvars) do d[id] = v end
    local idx = Camera.ActiveRule(cfg)
    if idx then
        for id, v in pairs(cfg.rules[idx].cvars) do d[id] = v end
    end
    -- Blizzards Mausgeschwindigkeit koppelt Nicken an Drehen (Yaw/2): ohne eigenen Wert folgt Nicken dem Drehen
    if d.cameraYawMoveSpeed and d.cameraPitchMoveSpeed == nil then d.cameraPitchMoveSpeed = round4(d.cameraYawMoveSpeed / 2) end
    if d.cameraFov then -- der Client klemmt selbst; Lucid bleibt in dessen Grenzen (oder 50 bis 90 ohne Auskunft)
        local lo, hi = Camera.FovRange()
        d.cameraFov = math.max(lo, math.min(hi, d.cameraFov))
    end
    if paused then
        for id in pairs(d) do
            if CVars.IsExperimental(id) then d[id] = nil end
        end
    end
    -- Schulterversatz und dynamische Neigung greifen nicht, solange Blizzards Bewegungsuebelkeit-Optionen an sind
    if cfg.autoComfort and (nonzero(d.test_cameraOverShoulder) or d.test_cameraDynamicPitch == 1) then
        d[CVars.KEEP_CENTERED], d[CVars.REDUCE_MOVEMENT] = 0, 0
    end
    return d, idx
end

--- Abstandsskalierung auf den Schulterversatz anwenden (d wird veraendert): Sollwert x Faktor(Kameraabstand)
local function scaleOffset(cfg, d)
    local t = d.test_cameraOverShoulder
    if cfg.offsetByDistance and nonzero(t) then d.test_cameraOverShoulder = Camera.Offset.Scale(t, Camera.Offset.Distance()) end
    return d
end

--- Sollwerte der CVars (name -> Zahl) aus der Konfiguration und den aktuellen Zustaenden; der Schulterversatz ist mit
--- Option "Versatz nach Abstand" der zum aktuellen Kameraabstand passende Wert.
--- Zweiter Rueckgabewert: Index der wirksamen Regel (oder nil).
function Camera.Desired(cfg)
    cfg = cfg or Camera.GetConfig()
    local d, idx = Camera.DesiredStatic(cfg)
    return scaleOffset(cfg, d), idx
end

--- Ziel-Distanz: Regel (erste zutreffende) vor Grundwert, sonst nil
function Camera.DesiredZoom(cfg)
    cfg = cfg or Camera.GetConfig()
    if not cfg.enabled then return nil end
    local idx = Camera.ActiveRule(cfg)
    if idx and cfg.rules[idx].zoom then return cfg.rules[idx].zoom end
    return cfg.base.zoom
end

-- Experimental-Warnung ------------------------------------------------------------------------------
-- Blizzards Popup (Akzeptieren/Deaktivieren) erscheint beim Setzen von test_*-CVars; "Deaktivieren" setzt ALLE test_*-CVars
-- zurueck. Unterdruecken = Blizzards Ereignis abmelden (Technik von DynamicCam). Rueckweg: wieder anmelden, soweit der Client
-- es erlaubt; sonst gilt es bis /reload. Alles unter pcall; ohne die Schnittstelle bleibt die Warnung einfach sichtbar.
local suppressed = false
local needsReload = false

function Camera.IsPopupSuppressed() return suppressed end
function Camera.NeedsReload() return needsReload end

-- Nur ueber GameEvent (kein UIParent-Fallback: Eingriff in Blizzards Frames kann Taint ausloesen). Fehlt die Schnittstelle,
-- bleibt Blizzards Warnung einfach sichtbar. Einen Rueckweg gibt es nicht (Signatur von RegisterInternalEvent ist nicht
-- belegt, ein Handler-Pflicht-Aufruf wuerde Blizzards Routing beschaedigen): wird die Unterdrueckung beendet, bleibt sie
-- bis /reload bestehen, und Lucid sagt das im Status (needsReload).
local function setPopupSuppressed(on)
    if on and not suppressed then
        if type(GameEvent) == "table" and type(GameEvent.UnregisterInternalEvent) == "function" then
            suppressed = pcall(GameEvent.UnregisterInternalEvent, Camera.EXPERIMENTAL_EVENT)
        end
    elseif not on and suppressed then
        needsReload = true
    end
end

--- soll die Warnung gerade unterdrueckt werden? (Modul an, Profil an, Schalter an, kein fremdes Kamera-Addon)
local function wantSuppress()
    if not active then return false end
    local cfg = Camera.GetConfig()
    return cfg.enabled and cfg.suppressPopup and not Camera.IsLocked()
end

--- fruehe Unterdrueckung: schon vor dem allerersten test_*-Schreiben (Login), unabhaengig von der Apply-Reihenfolge
function Camera.EarlySuppress()
    local cfg = Camera.GetConfig()
    if cfg.enabled and cfg.suppressPopup and not Camera.IsLocked() then setPopupSuppressed(true) end
end

-- Sicherheitsnetz: erscheint Blizzards Popup trotzdem (Ereignis anders geroutet), wird es geschlossen. StaticPopup_Hide
-- loest "Deaktivieren" (ResetTestCVars) nicht aus. Der Hook (hooksecurefunc) laeuft nach Blizzards Code; geschlossen wird
-- im naechsten Frame, nie mitten in Blizzards StaticPopup_Show.
Camera.POPUP_KEY = "EXPERIMENTAL_CVAR_WARNING"
local function hidePopup()
    if wantSuppress() and type(StaticPopup_Hide) == "function" then pcall(StaticPopup_Hide, Camera.POPUP_KEY) end
end
if type(hooksecurefunc) == "function" and type(StaticPopup_Show) == "function" then
    pcall(hooksecurefunc, "StaticPopup_Show", function(which)
        if which == Camera.POPUP_KEY and wantSuppress() then
            if C_Timer and C_Timer.After then C_Timer.After(0, hidePopup) else hidePopup() end
        end
    end)
end

local function anyExperimental(desired)
    for id in pairs(desired) do
        if CVars.IsExperimental(id) then return true end
    end
    return false
end

-- Anwenden ------------------------------------------------------------------------------------------
local function restoreOwned()
    local res = {}
    for _, name in ipairs(CVars.OwnedNames()) do res[name] = CVars.RestoreOne(name) end
    return res
end

--- Sollzustand herstellen: an => Sollwerte schreiben, aus (oder Modul nicht aktiv / fremdes Kamera-Addon) => Besitz
--- zurueckstellen. Liefert Tabelle name -> Status.
function Camera.Apply()
    local cfg = Camera.GetConfig()
    if not (active and cfg.enabled) or Camera.IsLocked() then
        local res = restoreOwned()
        Camera.Zoom.Resync() -- restoreOwned kann cameraZoomSpeed mitten in einer Fahrt zurueckschreiben
        syncStateNeeds(nil)
        setPopupSuppressed(false)
        Camera.Offset.Sync(nil)
        Camera.Focus.Stop()
        Camera.Zoom.Release()
        return res
    end
    syncStateNeeds(cfg)
    local static = Camera.DesiredStatic(cfg)
    local desired = scaleOffset(cfg, Store.DeepCopy(static))
    -- Zielfokus weich fuehren (Focus.lua): waehrend eines Uebergangs gelten Enable 1 und die Zwischenstaerken statt der Sollwerte;
    -- bei Pause schreibt der Uebergang nichts (der Pause-Filter hat die Action-Cam-Werte aus static entfernt)
    local focus = nil
    if paused then Camera.Focus.Stop() else focus = Camera.Focus.Plan(static, cfg.focusSeconds) end
    if focus then
        for id, v in pairs(focus) do desired[id] = v end
    end
    if cfg.suppressPopup and anyExperimental(desired) then
        setPopupSuppressed(true)
    elseif not cfg.suppressPopup then
        setPopupSuppressed(false)
    end
    -- Schulterversatz weich fuehren: bei Wechsel des Sollwerts gleitet der Wert (Offset.lua), geschrieben wird der Zwischenwert
    local planned = Camera.Offset.Plan(static.test_cameraOverShoulder, desired.test_cameraOverShoulder, cfg.offsetByDistance, cfg.offsetSeconds)
    if desired.test_cameraOverShoulder ~= nil then desired.test_cameraOverShoulder = planned end
    local res = CVars.Apply(desired)
    Camera.Zoom.Resync() -- ein hier geschriebenes cameraZoomSpeed darf das Fahrt-Tempo nicht ueberschreiben
    Camera.Zoom.Update(Camera.DesiredZoom(cfg), cfg.zoomSeconds)
    if desired[CVars.KEEP_CENTERED] ~= nil and not comfortNotified then
        comfortNotified = true
        ns.Print(L.CAM_COMFORT_HINT)
    end
    return res
end

--- Mehrere Einstellungen im aktiven Profil setzen (changes: Pfad wie "enabled", "base.cvars" -> Wert; geprueft wie beim
--- Import, alles oder nichts) und anwenden. Liefert true oder nil, Fehlerschluessel.
function Camera.SetMany(changes)
    if changes.enabled == true and Camera.IsLocked() then return nil, "CAM_LOCKED_REFUSED" end
    local p = Store.GetActive()
    local candidate = type(p.camera) == "table" and Store.DeepCopy(p.camera) or {}
    local paths = {}
    for path in pairs(changes) do paths[#paths + 1] = path end
    table.sort(paths)
    local split = {}
    for _, path in ipairs(paths) do
        local parts = {}
        for part in path:gmatch("[^%.]+") do parts[#parts + 1] = part end
        split[path] = parts
        local node = candidate
        for i = 1, #parts - 1 do
            if type(node[parts[i]]) ~= "table" then node[parts[i]] = {} end
            node = node[parts[i]]
        end
        node[parts[#parts]] = Store.DeepCopy(changes[path])
    end
    local clean = Camera.Validate(candidate)
    if not clean then return nil, "CAM_VALUE_INVALID" end
    for _, path in ipairs(paths) do
        local chk = clean
        for _, part in ipairs(split[path]) do
            if type(chk) ~= "table" then chk = nil; break end
            chk = chk[part]
        end
        if chk == nil then return nil, "CAM_VALUE_INVALID" end
    end
    p.camera = clean
    paused = false -- eine bewusste Aenderung gilt wieder
    Camera.Apply()
    return true
end

function Camera.Set(path, value) return Camera.SetMany({ [path] = value }) end

-- Voreinstellungen (ersetzen Grundwerte und Regeln, die Schalter bleiben; die Filmisch-Stufen schalten "Versatz nach Abstand" an
-- und setzen die Zoomdauer auf 1,5 s; Classic und Wide in combat lassen die Zoomdauer, wie sie ist) --
-- Die drei Filmisch-Stufen teilen sich den Aufbau, v traegt nur die Unterschiede. Regeln in dieser Reihenfolge (erste gewinnt):
-- Gespraech, Fliegen, Reiten, Instanz, Kampf, Drinnen, Erholen. Reiten/Fliegen/Instanz/Drinnen legen den Versatz ab (die Figur soll
-- dort mittig sein), im Kampf und in Instanzen schaut die Kamera auf Gegner (Calm: nie).
local function filmic(v)
    local base = {
        test_cameraOverShoulder = v.shoulder, test_cameraDynamicPitch = 1, test_cameraDynamicPitchBaseFovPad = 0.35,
        test_cameraHeadMovementStrength = v.head, test_cameraTargetFocusInteractEnable = 1, cameraDistanceMaxZoomFactor = 2.6,
    }
    if v.range then base.test_cameraHeadMovementRangeScale = v.range end
    if v.calm then base.test_cameraTargetFocusEnemyEnable = 0 end
    local function with(cvars, extra)
        for id, x in pairs(extra or {}) do cvars[id] = x end
        return cvars
    end
    return {
        enabled = true,
        offsetByDistance = true,
        zoomSeconds = 1.5, -- Filmisch: laengerer Zoom (der allgemeine Standard bleibt 0,6 s)
        base = { cvars = base },
        rules = {
            { state = "npc", cvars = { test_cameraTargetFocusInteractStrengthYaw = 1 }, zoom = v.npcZoom },
            { state = "flying", cvars = { test_cameraOverShoulder = 0 }, zoom = 22 },
            { state = "mounted", cvars = { test_cameraOverShoulder = 0, test_cameraHeadMovementStrength = 0 }, zoom = 14 },
            { state = "instance", cvars = with({ test_cameraOverShoulder = 0 }, v.instanceEnemy), zoom = 13 },
            { state = "combat", cvars = with({}, v.combatEnemy), zoom = v.combatZoom },
            { state = "indoors", cvars = { test_cameraOverShoulder = 0 } },
            { state = "resting", cvars = { test_cameraOverShoulder = 0.8 }, zoom = 9 },
        },
    }
end

Camera.PRESET_ORDER = { "cinematic", "cinematicCalm", "cinematicDynamic", "classic", "combatwide" }
Camera.PRESETS = {
    cinematic = filmic({
        shoulder = 1.2, head = 0.5, npcZoom = 4, combatZoom = 14,
        instanceEnemy = { test_cameraTargetFocusEnemyEnable = 1 },
        combatEnemy = { test_cameraTargetFocusEnemyEnable = 1, test_cameraTargetFocusEnemyStrengthYaw = 0.4, test_cameraTargetFocusEnemyStrengthPitch = 0.2 },
    }),
    cinematicCalm = filmic({ shoulder = 0.8, head = 0, calm = true, npcZoom = 5, combatZoom = 12 }),
    cinematicDynamic = filmic({
        shoulder = 1.8, head = 1, range = 15, npcZoom = 3, combatZoom = 11,
        instanceEnemy = { test_cameraTargetFocusEnemyEnable = 1, test_cameraTargetFocusEnemyStrengthYaw = 0.6, test_cameraTargetFocusEnemyStrengthPitch = 0.4 },
        combatEnemy = { test_cameraTargetFocusEnemyEnable = 1, test_cameraTargetFocusEnemyStrengthYaw = 0.6, test_cameraTargetFocusEnemyStrengthPitch = 0.4 },
    }),
    classic = {
        enabled = true,
        base = { cvars = {
            test_cameraOverShoulder = 0, test_cameraDynamicPitch = 0, test_cameraHeadMovementStrength = 0,
            test_cameraTargetFocusEnemyEnable = 0, test_cameraTargetFocusInteractEnable = 0,
        } },
        rules = {},
    },
    combatwide = {
        enabled = true,
        base = { cvars = { cameraDistanceMaxZoomFactor = 2.6 } },
        rules = { { state = "combat", zoom = 25, cvars = { test_cameraDynamicPitch = 1, test_cameraDynamicPitchBaseFovPad = 0.3 } } },
    },
}

--- Kennung einer Voreinstellung ohne Beachtung der Gross-/Kleinschreibung (Slash), oder nil
function Camera.PresetId(id)
    if type(id) ~= "string" then return nil end
    for _, pid in ipairs(Camera.PRESET_ORDER) do
        if pid:lower() == id:lower() then return pid end
    end
    return nil
end

--- Voreinstellung uebernehmen. Liefert true oder nil, Fehlerschluessel.
function Camera.ApplyPreset(id)
    local preset = Camera.PRESETS[id]
    if not preset then return nil, "CAM_PRESET_UNKNOWN" end
    return Camera.SetMany({ enabled = preset.enabled, base = preset.base, rules = preset.rules, offsetByDistance = preset.offsetByDistance, zoomSeconds = preset.zoomSeconds })
end

-- Modul + Ereignisse ------------------------------------------------------------------------------
ns.RegisterModule("camera", {
    OnEnable = function()
        active = true
        paused, comfortNotified = false, false
        CVars.ClearFailures()
        -- Login-Pruefung: Reste einer frueheren Sitzung (Absturz, anderer Charakter, Profil jetzt aus) werden ueber den
        -- owned-Marker zurueckgestellt, wenn das Modul im aktiven Profil nicht an ist.
        local wasOwned = #CVars.OwnedNames() > 0
        Camera.EarlySuppress()
        local res = Camera.Apply()
        local cfg = Camera.GetConfig()
        if cfg.enabled and Camera.IsLocked() then
            ns.Print(L.CAM_LOCKED, table.concat(Camera.Conflicts(), ", "))
        elseif wasOwned and not cfg.enabled then
            local n = 0
            for _, st in pairs(res) do if st == "ok" then n = n + 1 end end
            if n > 0 then ns.Print(L.CAM_LOGIN_RESTORED, n) end
        end
    end,
    OnDisable = function()
        active = false
        syncStateNeeds(nil)
        Camera.Offset.Sync(nil)
        Camera.Focus.Stop()
        Camera.Zoom.Release()
        setPopupSuppressed(false)
        CVars.RestoreAll()
        Camera.Zoom.Resync()
    end,
})

Store.RegisterCallback(function()
    CVars.ClearFailures()
    paused = false
    if active then Camera.Apply() end
end)

-- Zustandswechsel: nur wenn der Zustand in einer Regel steht, werden die CVars neu berechnet
State.RegisterCallback(function(name)
    if not active then return end
    local cfg = Camera.GetConfig()
    if not cfg.enabled then return end
    for _, r in ipairs(cfg.rules) do
        if r.state == name then
            Camera.Apply()
            return
        end
    end
end)

-- Zonen-/Instanzwechsel: Blizzard setzt Kamera-Einstellungen teils zurueck, Lucid gewinnt
ns.On("PLAYER_ENTERING_WORLD", function()
    if active and Camera.GetConfig().enabled then Camera.Apply() end
end)

-- Ende der Kampfsperre: ausstehende Schreibzugriffe nachholen
ns.On("PLAYER_REGEN_ENABLED", function()
    if active then CVars.Flush() end
end)

-- Abmelden/Neuladen: Blizzard-Werte zurueck (account-weite CVars gelten fuer alle Charaktere)
ns.On("ADDON_LOADED", function(_, name)
    if name == ns.name and Store.db then
        active = true -- nur fuer die Prueflogik der fruehen Unterdrueckung; OnEnable setzt es ohnehin
        Camera.EarlySuppress()
        active = false
    end
end)

Compat.TryOn("PLAYER_LOGOUT", function()
    Camera.Offset.Sync(nil)
    Camera.Focus.Stop()
    Camera.Zoom.Logout() -- unabhaengig von active: eine laufende Fahrt darf cameraZoomSpeed nicht verstellt zuruecklassen
    if active then
        setPopupSuppressed(false)
        CVars.RestoreAll()
    end
end)

-- Fremde Aenderung an einer Action-Cam-CVar (z. B. Blizzards Warnung "Deaktivieren" oder /console): Lucid schreibt sie nicht
-- erneut (sonst Endlosschleife mit der Warnung), bis der Nutzer bewusst etwas aendert.
CVars.OnExternal = function(name, value)
    if not (active and CVars.IsExperimental(name)) or paused then return end
    local cfg = Camera.GetConfig()
    if not cfg.enabled then return end
    local want = Camera.Desired(cfg)[name]
    if want == nil or CVars.Same(value, CVars.Normalize(want)) then return end
    paused = true
    ns.Print(L.CAM_EXTERNAL_RESET)
end

--- Offset.lua fragt: darf der Ticker schreiben? (nicht, solange eine Fremdaenderung die Action Cam pausiert)
function Camera.IsPaused() return paused end

-- Slash: /lucid camera on|off|status|debug|preset|probe ------------------------------------------------
local function esc(s) return (tostring(s):gsub("|", "||")) end
local function yesNo(b) return b and L.CAM_YES or L.CAM_NO end

local function countValues(c)
    local n = 0
    for _ in pairs(c) do n = n + 1 end
    return n
end

local function pendingCount()
    local n = 0
    for _ in pairs(CVars.Pending()) do n = n + 1 end
    return n
end

local function printStatus()
    local cfg = Camera.GetConfig()
    ns.Print(L.CAM_STATUS, cfg.enabled and L.CAM_ON or L.CAM_OFF)
    if Camera.IsLocked() then ns.Print(L.CAM_LOCKED, table.concat(Camera.Conflicts(), ", ")) end
    if needsReload then ns.Print(L.CAM_NEEDS_RELOAD) end
    if not cfg.enabled then return end
    ns.Print(L.CAM_STATUS_BASE, countValues(cfg.base.cvars))
    if cfg.base.zoom then ns.Print(L.CAM_STATUS_ZOOM, cfg.base.zoom) end
    local idx = Camera.ActiveRule(cfg)
    for i, r in ipairs(cfg.rules) do
        ns.Print(L.CAM_STATUS_RULE, i, L["STATE_" .. r.state], countValues(r.cvars), idx == i and L.CAM_STATUS_ACTIVE or "")
    end
    -- Diagnose: welche Zustaende gelten jetzt, welche Regel gewinnt, was Lucid als Soll setzt
    local now, missing = {}, {}
    for _, name in ipairs(Camera.RULE_STATES) do
        local ok = State.IsAvailable(name)
        if State.GetQuiet(name) then now[#now + 1] = L["STATE_" .. name] end
        if not ok then
            for _, r in ipairs(cfg.rules) do
                if r.state == name then missing[#missing + 1] = L["STATE_" .. name]; break end
            end
        end
    end
    ns.Print(L.CAM_STATUS_STATES, #now > 0 and table.concat(now, ", ") or L.CAM_NONE)
    if #missing > 0 then ns.Print(L.CAM_STATUS_UNAVAILABLE, table.concat(missing, ", ")) end
    ns.Print(L.CAM_STATUS_WINNER, idx and ("%d. %s"):format(idx, L["STATE_" .. cfg.rules[idx].state]) or L.CAM_STATUS_WINNER_NONE)
    local static = Camera.DesiredStatic(cfg)
    local desired = Camera.Desired(cfg)
    local names = {}
    for name in pairs(desired) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        ns.Print(L.CAM_STATUS_SOLL, name, esc(CVars.Normalize(desired[name]) or "-"), esc(CVars.Get(name) or "-"))
    end
    if cfg.offsetByDistance then
        local dist = Camera.Offset.Distance()
        ns.Print(L.CAM_STATUS_OFFSET, dist and ("%.1f"):format(dist) or "-", ("%.2f"):format(Camera.Offset.Factor(dist)),
            static.test_cameraOverShoulder ~= nil and ("%g"):format(static.test_cameraOverShoulder) or "-",
            desired.test_cameraOverShoulder ~= nil and ("%g"):format(desired.test_cameraOverShoulder) or "-",
            Camera.Offset.IsRunning() and L.CAM_YES or L.CAM_NO)
    end
    if paused then ns.Print(L.CAM_STATUS_PAUSED) end
    if suppressed then ns.Print(L.CAM_STATUS_POPUP) end
    if pendingCount() > 0 then ns.Print(L.CAM_STATUS_PENDING, pendingCount()) end
end

local function printDebug()
    local cfg = Camera.GetConfig()
    local desired, idx = Camera.Desired(cfg)
    local pend = CVars.Pending()
    local owned = {}
    for _, n in ipairs(CVars.OwnedNames()) do owned[n] = true end
    ns.Print(L.CAM_DEBUG_HEAD, cfg.enabled and L.CAM_ON or L.CAM_OFF, yesNo(active), yesNo(InCombatLockdown()),
        tostring(idx or "-"), yesNo(paused), yesNo(suppressed))
    for _, name in ipairs(CVars.CATALOG) do
        local info = CVars.Info(name)
        if not info.exists then
            ns.Print(L.CAM_DEBUG_MISSING, name)
        else
            ns.Print(L.CAM_DEBUG_LINE, name, esc(info.value), esc(desired[name] ~= nil and CVars.Normalize(desired[name]) or "-"), esc(CVars.Baseline(name) or "-"),
                yesNo(info.secure), yesNo(owned[name]), esc(pend[name] or "-"), esc(CVars.LastResult(name) or "-"))
        end
    end
    local count = CVars.External()
    ns.Print(L.CAM_DEBUG_EXTERNAL, count)
    local trace = Camera.Zoom.Trace()
    if #trace > 0 then
        ns.Print(L.CAM_DEBUG_ZOOMLOG, #trace)
        for _, e in ipairs(trace) do
            local function num(v) return v ~= nil and ("%.2f"):format(v) or "-" end
            ns.Print(L.CAM_DEBUG_ZOOMLINE, e.t, e.ev, num(e.pos), num(e.dest), num(e.speed))
        end
    end
end

local function setEnabled(on)
    local ok, code = Camera.Set("enabled", on)
    if not ok then
        ns.Print(L[code or "CAM_VALUE_INVALID"], table.concat(Camera.Conflicts(), ", "))
        return
    end
    ns.Print(on and L.CAM_ENABLED or L.CAM_DISABLED)
    local cfg = Camera.GetConfig()
    if on and countValues(cfg.base.cvars) == 0 and #cfg.rules == 0 then ns.Print(L.CAM_EMPTY_HINT) end
    if pendingCount() > 0 then ns.Print(L.CAM_STATUS_PENDING, pendingCount()) end
end

ns.commands.camera = function(rest)
    local sub = (rest or ""):match("^%s*(%S*)"):lower()
    if sub == "" or sub == "status" then
        printStatus()
        if sub == "" then ns.Print(L.HELP_CAMERA) end
    elseif sub == "on" or sub == "an" then
        setEnabled(true)
    elseif sub == "off" or sub == "aus" then
        setEnabled(false)
    elseif sub == "debug" then
        printDebug()
    elseif sub == "preset" then
        local id = (rest or ""):match("^%s*%S+%s+(%S+)")
        local pid = Camera.PresetId(id)
        local ok, code = false, nil
        if pid then ok, code = Camera.ApplyPreset(pid) end
        if ok then
            ns.Print(L.CAM_PRESET_APPLIED, pid)
            printStatus()
        elseif code == "CAM_LOCKED_REFUSED" then
            ns.Print(L.CAM_LOCKED_REFUSED, table.concat(Camera.Conflicts(), ", "))
        else
            ns.Print(L.CAM_PRESET_INVALID, esc(id or ""))
        end
    elseif Camera.sub[sub] then
        Camera.sub[sub]()
    else
        ns.Print(L.CAM_UNKNOWN, (sub:gsub("|", "||")))
        ns.Print(L.HELP_CAMERA)
    end
end

ns.AddHelp("HELP_CAMERA")
