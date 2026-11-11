-- Plaketten (B7/N3): weiches Ein-/Ausblenden einzelner Plaketten ueber nameplate.UnitFrame:SetAlpha.
--
-- Zusammenspiel mit der CVar-Ebene (CVars.lua / Nameplates.lua): die CVars entscheiden, ob eine Plakette ueberhaupt
-- existiert, das Alpha gestaltet den Uebergang. Wird eine Gruppe unsichtbar, bleibt ihre CVar noch die Dauer des
-- Ausblendens an (Nameplates.lua, "hold"); neue Plaketten blenden ein. Mit keepTarget bleibt die Plakette des Ziels
-- sichtbar, waehrend alle anderen ihrer Gruppe ausblenden.
--
-- Taint: nur Lesen und SetAlpha auf dem UnitFrame (kein geschuetzter Aufruf), hooksecurefunc als Nachher-Hook, keine
-- Felder auf Blizzard-Frames (Zustand liegt in einer Schwachschluessel-Tabelle), keine Blizzard-Methode ersetzt.
-- Befreundete Plaketten in Instanzen sind "forbidden" und fuer Addons unerreichbar: sie werden uebersprungen
-- (dort wirken nur die CVars). Ein einziges Mini-OnUpdate treibt alle Uebergaenge und ruht, wenn nichts zu tun ist.
local _, ns = ...
local Compat = ns.Compat

local Plates = {}
ns.Plates = Plates

local tracked = setmetatable({}, { __mode = "k" }) -- UnitFrame -> { cur, target, group }
local byUnit = {}                                  -- unit-Token -> UnitFrame (Pool-Reset beim Entfernen)
local mode = nil                                   -- nil = aus; sonst { vis = {enemies,friends}, keep = {enemies,friends}, duration }
local driver                                       -- Frame mit OnUpdate
local running = false

local listeners = {} -- fn(uf, targetAlpha|nil, unit|nil): Quest-Fernsicht (QuestFar.lua) und Stil-Treiber (Style.lua)

local function notify(uf, target, unit)
    for _, fn in ipairs(listeners) do pcall(fn, uf, target, unit) end
end

local function call(fn, ...)
    local ok, v = pcall(fn, ...)
    if not ok or Compat.IsSecret(v) then return nil end
    return v
end

--- UnitFrame der Plakette zu einem Einheiten-Token, oder nil (fehlt/forbidden)
local function unitFrameOf(unit)
    if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return nil end
    local plate = call(C_NamePlate.GetNamePlateForUnit, unit)
    if type(plate) ~= "table" then return nil end
    if Compat.QueryBool(plate, "IsForbidden") == true then return nil end
    local uf = plate.UnitFrame
    if type(uf) ~= "table" or type(uf.SetAlpha) ~= "function" then return nil end
    if Compat.QueryBool(uf, "IsForbidden") == true then return nil end
    return uf
end

--- "enemies" | "friends" | nil (nicht lesbar)
local function groupOf(unit)
    if not UnitCanAttack then return nil end
    local v = call(UnitCanAttack, "player", unit)
    if v == nil then return nil end
    return v and "enemies" or "friends"
end
Plates.GroupOf = groupOf

local function isTarget(unit)
    if not UnitIsUnit then return false end
    return Compat.Bool(call(UnitIsUnit, unit, "target"))
end

local function setAlpha(uf, a)
    pcall(uf.SetAlpha, uf, a)
end

local function targetAlpha(unit, group)
    if not mode or not group then return 1 end
    if mode.vis[group] then return 1 end
    if mode.keep and mode.keep[group] and isTarget(unit) then return 1 end
    return 0
end

-- Uebergaenge ------------------------------------------------------------------------------------
local function ensureDriver()
    if driver then return end
    driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function(_, dt)
        local step = (mode and mode.duration > 0) and (dt / mode.duration) or 1
        local busy = false
        for uf, st in pairs(tracked) do
            if st.cur ~= st.target then
                if st.cur < st.target then
                    st.cur = math.min(st.target, st.cur + step)
                else
                    st.cur = math.max(st.target, st.cur - step)
                end
                setAlpha(uf, st.cur)
                if st.cur ~= st.target then busy = true end
            end
        end
        if not busy then
            running = false
            driver:Hide()
        end
    end)
    driver:Hide()
end

local function wake()
    ensureDriver()
    if not running then
        running = true
        driver:Show()
    end
end

local function retarget(uf, st)
    st.target = targetAlpha(st.unit, st.group)
    notify(uf, st.target, st.unit)
    if st.cur ~= st.target and mode.duration <= 0 then
        st.cur = st.target -- Dauer 0: sofort
        setAlpha(uf, st.cur)
    elseif st.cur ~= st.target then
        wake()
    end
end

local function track(unit, fresh)
    local uf = unitFrameOf(unit)
    if not uf then return end
    local st = tracked[uf]
    if not st then
        st = { cur = 1, unit = unit }
        tracked[uf] = st
    end
    st.unit, st.group = unit, groupOf(unit)
    byUnit[unit] = uf
    st.target = targetAlpha(unit, st.group)
    notify(uf, st.target, unit)
    -- neue Plaketten blenden ein (Frames werden gepoolt: der Startwert gilt fuer die neue Einheit)
    if fresh and mode and mode.duration > 0 and st.target == 1 then st.cur = 0 elseif fresh then st.cur = st.target end
    setAlpha(uf, st.cur)
    if st.cur ~= st.target then wake() end
end

local function untrack(unit)
    local uf = byUnit[unit] or unitFrameOf(unit)
    byUnit[unit] = nil
    if uf and tracked[uf] then
        tracked[uf] = nil
        notify(uf, nil, nil)
        setAlpha(uf, 1) -- Pool-Reset: der Frame wird fuer eine andere Einheit wiederverwendet
    end
end

--- Alle sichtbaren Plaketten erfassen (beim Einschalten des weichen Modus)
local function scan()
    if not (C_NamePlate and C_NamePlate.GetNamePlates) then return end
    local plates = call(C_NamePlate.GetNamePlates)
    if type(plates) ~= "table" then return end
    for _, plate in ipairs(plates) do
        local unit = type(plate) == "table" and plate.namePlateUnitToken
        if type(unit) == "string" then track(unit, false) end
    end
end

--- Alles auf Alpha 1 zurueck und nichts mehr verfolgen
function Plates.Reset()
    mode = nil
    for uf in pairs(tracked) do
        setAlpha(uf, 1)
        tracked[uf] = nil
        notify(uf, nil, nil)
    end
    byUnit = {}
    running = false
    if driver then driver:Hide() end
end

--- Modus setzen (spec = { vis = {enemies, friends}, keep = {enemies, friends}, duration }) oder nil fuer "aus".
--- Verfolgte Plaketten bekommen ihr neues Ziel-Alpha und blenden dorthin ueber.
function Plates.Update(spec)
    if not spec then
        if mode or next(tracked) then Plates.Reset() end
        return
    end
    local first = mode == nil
    mode = spec
    if first then scan() end
    for uf, st in pairs(tracked) do retarget(uf, st) end
end

function Plates.IsActive() return mode ~= nil end

--- Ziel-Alpha einer verfolgten Plakette (0 = nach B7 unsichtbar, 1 = sichtbar) oder nil (nicht verfolgt)
function Plates.TargetAlpha(uf)
    local st = tracked[uf]
    return st and st.target or nil
end

--- Zuhoerer fuer Sichtbarkeitswechsel anmelden (einmalig je Funktion)
function Plates.AddListener(fn)
    for _, f in ipairs(listeners) do if f == fn then return end end
    listeners[#listeners + 1] = fn
end

--- true, wenn Lucid die Plakette (UnitFrame) gerade ganz ausgeblendet haelt (Alpha 0 und Ziel 0, also auch nicht im Einblenden)
function Plates.IsHidden(uf)
    local st = tracked[uf]
    return st ~= nil and st.cur == 0 and st.target == 0
end

--- aktuelles Lucid-Alpha einer verfolgten Plakette (UnitFrame) oder nil (nicht verfolgt); fuer die Klick-Probe
function Plates.CurrentAlpha(uf)
    local st = tracked[uf]
    return st and st.cur or nil
end

--- Diagnose: Anzahl verfolgter Plaketten, davon gerade im Uebergang
function Plates.Counts()
    local n, moving = 0, 0
    for _, st in pairs(tracked) do
        n = n + 1
        if st.cur ~= st.target then moving = moving + 1 end
    end
    return n, moving
end

-- Ereignisse ----------------------------------------------------------------------------------------
Compat.TryOn("NAME_PLATE_UNIT_ADDED", function(_, unit)
    if mode and type(unit) == "string" then track(unit, true) end
end)
Compat.TryOn("NAME_PLATE_UNIT_REMOVED", function(_, unit)
    if type(unit) == "string" then untrack(unit) end
end)

-- Blizzard richtet eine Plakette ein: Nachher-Hook, danach Lucids Alpha erneut setzen (nur Hook, keine Ersetzung)
if hooksecurefunc and type(NamePlateDriverFrame) == "table" and type(NamePlateDriverFrame.OnNamePlateAdded) == "function" then
    pcall(hooksecurefunc, NamePlateDriverFrame, "OnNamePlateAdded", function(_, unit)
        if mode and type(unit) == "string" then track(unit, false) end
    end)
end
