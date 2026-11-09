-- State: boolesche Zustaende (Spec 3.1), ereignisgetrieben. Kein Dauer-Polling ausser
--  - Mouseover: Ticker (~10 Hz) nur, solange Elemente dafuer angemeldet sind (WatchMouseover, IsCursorOver)
--  - Fliegen: es gibt kein Event fuer Abheben/Landen; leichter Ticker nur, solange beritten/Reiseform/Flugroute.
--  - Drinnen/Schwimmen: IsIndoors/IsSwimming aendern sich ohne (verlaessliches) Ereignis. Ein gemeinsamer Ticker (0,5 s) laeuft nur,
--    solange ein Abnehmer den Zustand braucht: State.Need (Kamera-Regeln, mit Abmeldung) oder eine Abfrage per State.Get
--    (Bedingungen anderer Module, bleibt bis zum Neuladen). State.GetQuiet fragt, ohne den Ticker anzufordern.
-- Nicht verfuegbare Zustaende (API fehlt, Secret Value) gelten als "nicht erfuellt"; IsAvailable nennt den Grund.
-- Ausnahme "debuffed" (Debuff auf dir): sind die Auren gerade Secret (Kampf, Encounter, M+, PvP), bleibt der letzte lesbare
-- Wert stehen (im Kampf blendet ohnehin "Kampf" ein); nach Kampfende (PLAYER_REGEN_ENABLED) wird neu gelesen.
-- "debuffed" wird erst gelesen, wenn ein Abnehmer danach fragt (State.Get/GetQuiet/GetReal oder State.Need, bleibt dann bis
-- zum Neuladen aktiv); UNIT_AURA ist per RegisterUnitEvent nur fuer "player" angemeldet (Rueckfall: normales Event + Filter).
-- Aenderungen gehen an Callbacks: fn(name, value, elementId) (elementId nur bei "mouseover").
local _, ns = ...
local Compat = ns.Compat

local State = {}
ns.State = State

State.NAMES = {
    "combat", "target", "focus", "mouseover", "resting", "city", "group", "raid", "instance",
    "mounted", "flying", "casting", "afk", "typing", "hurt", "power", "npc", "indoors", "swimming", "debuffed",
}
State.KNOWN = {}
for _, n in ipairs(State.NAMES) do State.KNOWN[n] = true end

State.MOUSEOVER_INTERVAL = 0.1
State.FLIGHT_INTERVAL = 0.25
State.POLL_INTERVAL = 0.5
State.POLLED = { indoors = true, swimming = true }
State.ON_DEMAND = { debuffed = true } -- ereignisgetrieben, aber erst gelesen, wenn ein Abnehmer den Zustand braucht

-- Hauptstaedte (uiMapID). "city" = Ruhezone innerhalb einer dieser Karten (inkl. Unterkarten).
State.CAPITALS = {
    [84] = true,   -- Sturmwind
    [85] = true,   -- Orgrimmar
    [86] = true,   -- Orgrimmar, Kluft der Schatten
    [87] = true,   -- Eisenschmiede
    [88] = true,   -- Donnerfels
    [89] = true,   -- Darnassus
    [90] = true,   -- Unterstadt
    [103] = true,  -- Die Exodar
    [110] = true,  -- Silbermond
    [111] = true,  -- Shattrath
    [125] = true,  -- Dalaran (Nordend)
    [627] = true,  -- Dalaran (Verheerte Inseln)
    [1161] = true, -- Boralus
    [1165] = true, -- Dazar'alor
    [1670] = true, -- Oribos
    [2112] = true, -- Valdrakken
    [2339] = true, -- Dornogal
    [622] = true,  -- Sturmschild (Ashran)
    [624] = true,  -- Kriegsspeer (Ashran)
    [393] = true,  -- Schrein der Sieben Sterne
    [394] = true,  -- Schrein der Zwei Monde
    [2393] = true, -- Silbermond (Midnight)
}
State.MAX_EXTRA_CAPITALS = 32

--- zusaetzliche Hauptstaedte aus der Config (LucidDB.extraCapitals = { uiMapID, ... }) uebernehmen.
--- Nur positive ganze Zahlen, hoechstens MAX_EXTRA_CAPITALS; alles andere wird ignoriert.
function State.LoadExtraCapitals(list)
    if type(list) ~= "table" then return 0 end
    local n = 0
    for _, id in ipairs(list) do
        if n >= State.MAX_EXTRA_CAPITALS then break end
        if type(id) == "number" and id > 0 and id % 1 == 0 and id < 2 ^ 31 then
            State.CAPITALS[id] = true
            n = n + 1
        end
    end
    return n
end

-- Ressourcen, deren Ruhewert 0 ist (Wut, Runenmacht, Astralmacht, Mahlstrom, Wahnsinn, Zorn, Schmerz):
-- "power" heisst dort "nicht leer", sonst "nicht voll".
State.POWER_REST_EMPTY = { [1] = true, [6] = true, [8] = true, [11] = true, [13] = true, [17] = true, [18] = true }

-- "debuffed": schaedliche Effekte, die nicht zaehlen (fest, nicht konfigurierbar; nur per Quelle belegte IDs):
-- 26013 Deserteur, 15007 Wiederbelebungsschwaeche, 57723 Erschoepfung. Ist die spellId Secret, zaehlt der Eintrag.
State.DEBUFF_IGNORE = { [26013] = true, [15007] = true, [57723] = true }
State.DEBUFF_MAX_INDEX = 40 -- Rueckfall GetDebuffDataByIndex: so viele Plaetze werden hoechstens gelesen

-- Gestaltwandel, in denen geflogen werden kann (Reisegestalt, Fluggestalt)
local FLIGHT_FORMS = { [3] = true, [27] = true, [29] = true }

local values = {}    -- name -> bool
local unavail = {}   -- name -> Grund ("api" | "secret"), solange nicht verfuegbar
local callbacks = {}
local silent = false

function State.RegisterCallback(fn) callbacks[#callbacks + 1] = fn end
function State.UnregisterCallback(fn)
    for i = #callbacks, 1, -1 do if callbacks[i] == fn then table.remove(callbacks, i) end end
end

local function notify(name, value, id)
    if silent then return end
    local list = { unpack(callbacks) }
    for _, fn in ipairs(list) do xpcall(function() fn(name, value, id) end, geterrorhandler()) end
end

-- Simulation (B4, Konfig-Fenster "Zustand simulieren"): ein Override macht einen Zustand fuer alle Abnehmer
-- erfuellt, ohne den echten Wert anzufassen (values/unavail bleiben, GetReal liefert weiter die Wahrheit).
-- Nicht fuer "mouseover" (je Element). Das Fenster nimmt alle Overrides beim Schliessen zurueck.
local overrides = {}  -- name -> true

local demanded = {}   -- name -> true: Zustand aus ON_DEMAND wird gebraucht (siehe demand)
local evaluate
local function demand(name)
    if State.ON_DEMAND[name] and not demanded[name] then
        demanded[name] = true
        if values[name] == nil then values[name] = false end -- Startwert "aus" ist keine Aenderung (kein Callback)
        evaluate(name) -- frischer Startwert
    end
end

--- true, wenn der Zustand erfuellt ist. Unbekannte oder nicht verfuegbare Zustaende: false.
function State.Get(name, id)
    if name == "mouseover" then return id ~= nil and State.mouse[id] == true end
    if State.POLLED[name] then State.Touch(name) end -- erst die Abfrage durch einen Abnehmer startet den Ticker
    demand(name)
    if overrides[name] then return true end
    if unavail[name] then return false end
    return values[name] == true
end

-- wie Get, ohne Ticker-Start (interne Meldungen an Abnehmer)
local function peek(name)
    if overrides[name] then return true end
    if unavail[name] then return false end
    return values[name] == true
end
--- wie Get, fordert aber keinen Ticker an (fuer Abnehmer, die ihren Bedarf mit State.Need melden)
function State.GetQuiet(name)
    demand(name) -- kein Ticker, nur der erste Lesevorgang
    return peek(name)
end

--- true, wenn ein bedarfsabhaengiger Zustand (ON_DEMAND) gelesen wird (Diagnose/Tests)
function State.IsDemanded(name) return demanded[name] == true end

--- echter Zustand ohne Simulation
function State.GetReal(name, id)
    if name == "mouseover" then return State.Get(name, id) end
    if State.POLLED[name] then State.Touch(name) end
    demand(name)
    if unavail[name] then return false end
    return values[name] == true
end

--- true oder false, Grund ("api" | "secret")
function State.IsAvailable(name)
    if not State.KNOWN[name] then return false, "api" end
    demand(name) -- ON_DEMAND: Verfuegbarkeit zeigt erst der erste Lesevorgang
    if unavail[name] then return false, unavail[name] end
    return true
end

-- Wert setzen: v = true/false, oder nil + Grund fuer "nicht verfuegbar"
local function set(name, v, reason)
    local oldV, oldR = values[name], unavail[name]
    if v == nil then
        values[name], unavail[name] = false, reason or "api"
    else
        values[name], unavail[name] = (v and true or false), nil
    end
    if oldV ~= values[name] or oldR ~= unavail[name] then notify(name, peek(name)) end
end

--- Zustand simulieren (on = true) oder Simulation beenden (on = false/nil). Liefert true bei Erfolg.
function State.SetOverride(name, on)
    if not State.KNOWN[name] or name == "mouseover" then return false end
    on = on and true or nil
    if overrides[name] == on then return true end
    overrides[name] = on
    notify(name, peek(name))
    return true
end

function State.GetOverride(name) return overrides[name] == true end

--- alle Simulationen beenden
function State.ClearOverrides()
    local names = {}
    for name in pairs(overrides) do names[#names + 1] = name end
    for _, name in ipairs(names) do State.SetOverride(name, false) end
end

-- Zustands-Definitionen ---------------------------------------------------------------------------
local npcOpen = {}      -- offene NPC-Fenster: Art -> true
local typingBoxes = {}  -- Chat-Eingabefelder mit Fokus
local editBoxes = {}

local NPC_OPEN = {
    GOSSIP_SHOW = "gossip", MERCHANT_SHOW = "merchant", TRAINER_SHOW = "trainer",
    BANKFRAME_OPENED = "bank", TAXIMAP_OPENED = "taxi",
    QUEST_GREETING = "quest", QUEST_DETAIL = "quest", QUEST_PROGRESS = "quest", QUEST_COMPLETE = "quest",
}
local NPC_CLOSE = {
    GOSSIP_CLOSED = "gossip", MERCHANT_CLOSED = "merchant", TRAINER_CLOSED = "trainer",
    BANKFRAME_CLOSED = "bank", TAXIMAP_CLOSED = "taxi", QUEST_FINISHED = "quest",
}

local B = Compat.Bool -- Wahrheitswert eines API-Ergebnisses, Secret Value => false (kein Wahrheitstest darauf)

local function isCapital()
    local id = Compat.Num(C_Map.GetBestMapForUnit("player"))
    for _ = 1, 8 do
        if not id or id == 0 then return false end
        if State.CAPITALS[id] then return true end
        local info = C_Map.GetMapInfo(id)
        id = type(info) == "table" and Compat.Num(info.parentMapID) or nil
    end
    return false
end

local function ratioState(kind)
    local cur, max, ptype = Compat.PlayerValues(kind)
    if cur == nil then return nil, max end -- max traegt hier den Grund
    if max <= 0 then return false end
    if kind == "power" and State.POWER_REST_EMPTY[ptype] then return cur > 0 end
    return cur < max
end

local REGEN = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }

-- Debuff auf dir --------------------------------------------------------------------------------------
-- Jeder Zugriff auf Aura-Daten laeuft in pcall (RequiresUnitAuraAccess: bei Einschraenkung Fehler statt nil); Secret
-- Values werden nur mit Compat.IsSecret geprueft, nie verglichen. Die Nutzlast von UNIT_AURA wird nicht ausgewertet.
local lastDebuffed = false

-- true, wenn der Index laut C_Secrets gerade Secret waere (oder die Abfrage selbst nicht eindeutig ist)
local function auraIndexSecret(index)
    local CS = C_Secrets
    if type(CS) ~= "table" or type(CS.ShouldUnitAuraIndexBeSecret) ~= "function" then return false end
    local ok, v = pcall(CS.ShouldUnitAuraIndexBeSecret, "player", index, "HARMFUL")
    if not ok or Compat.IsSecret(v) then return true end
    return v == true
end

-- zaehlt dieser Eintrag (AuraData) als Debuff? Ausnahmeliste nur bei lesbarer spellId; Secret/unlesbar => zaehlt
local function auraCounts(a)
    if Compat.IsSecret(a) then return true end
    if type(a) ~= "table" then return false end
    local ok, sid = pcall(function() return a.spellId end)
    if not ok or Compat.IsSecret(sid) or type(sid) ~= "number" then return true end
    return not State.DEBUFF_IGNORE[sid]
end

-- true/false, oder nil + Grund ("api": keine Aura-API; "secret": gerade nicht lesbar)
local function readDebuffs()
    local UA = C_UnitAuras
    local list = type(UA) == "table" and type(UA.GetUnitAuras) == "function"
    local byIndex = type(UA) == "table" and type(UA.GetDebuffDataByIndex) == "function"
    if not (list or byIndex) then return nil, "api" end
    if auraIndexSecret(1) then return nil, "secret" end
    if list then
        local ok, auras = pcall(UA.GetUnitAuras, "player", "HARMFUL")
        if not ok or Compat.IsSecret(auras) then return nil, "secret" end
        if type(auras) == "table" then
            local okL, found = pcall(function()
                for _, a in ipairs(auras) do
                    if auraCounts(a) then return true end
                end
                return false
            end)
            if not okL then return nil, "secret" end
            return found
        end
        if not byIndex then return nil, "secret" end
    end
    for i = 1, State.DEBUFF_MAX_INDEX do
        local ok, a = pcall(UA.GetDebuffDataByIndex, "player", i)
        if not ok then return nil, "secret" end
        if Compat.IsSecret(a) then return true end -- es gibt einen Eintrag, nur sein Inhalt ist gesperrt
        if a == nil then return false end
        if auraCounts(a) then return true end
    end
    return false
end

local defs = {
    combat = {
        api = { "UnitAffectingCombat" }, events = REGEN,
        read = function(event)
            -- Events zuerst: der Kampfstatus der API kann beim Event noch nachhinken
            if event == "PLAYER_REGEN_DISABLED" then return true end
            if event == "PLAYER_REGEN_ENABLED" then return false end
            return B(UnitAffectingCombat("player")) or (InCombatLockdown and B(InCombatLockdown())) or false
        end,
    },
    target = { api = { "UnitExists" }, events = { "PLAYER_TARGET_CHANGED" }, read = function() return UnitExists("target") end },
    focus = { api = { "UnitExists" }, events = { "PLAYER_FOCUS_CHANGED" }, read = function() return UnitExists("focus") end },
    resting = { api = { "IsResting" }, events = { "PLAYER_UPDATE_RESTING" }, read = function() return IsResting() end },
    city = {
        api = { "IsResting", "C_Map.GetBestMapForUnit", "C_Map.GetMapInfo" },
        events = { "PLAYER_UPDATE_RESTING", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" },
        read = function()
            local resting = IsResting()
            if Compat.IsSecret(resting) then return nil, "secret" end
            return B(resting) and isCapital()
        end,
    },
    group = { api = { "IsInGroup" }, events = { "GROUP_ROSTER_UPDATE" }, read = function() return IsInGroup() end },
    raid = { api = { "IsInRaid" }, events = { "GROUP_ROSTER_UPDATE" }, read = function() return IsInRaid() end },
    instance = {
        api = { "IsInInstance" }, events = { "ZONE_CHANGED_NEW_AREA" },
        read = function() return (IsInInstance()) end,
    },
    mounted = { api = { "IsMounted" }, events = { "PLAYER_MOUNT_DISPLAY_CHANGED" }, read = function() return IsMounted() end },
    flying = {
        api = { "IsFlying" },
        events = { "PLAYER_MOUNT_DISPLAY_CHANGED", "UPDATE_SHAPESHIFT_FORM", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED" },
        read = function()
            local fl = IsFlying()
            if Compat.IsSecret(fl) then return nil, "secret" end
            if B(fl) then return true end
            -- Dracthyr-Gleiten (Retail ab 10.0): eigene API, nicht ueber IsFlying
            if C_PlayerInfo and C_PlayerInfo.GetGlidingInfo then
                local gliding = C_PlayerInfo.GetGlidingInfo()
                if B(gliding) then return true end
            end
            return false
        end,
    },
    casting = {
        api = { "UnitCastingInfo", "UnitChannelInfo" },
        events = {
            "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
            "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP",
            "UNIT_SPELLCAST_EMPOWER_START", "UNIT_SPELLCAST_EMPOWER_STOP",
        },
        -- Ein Secret-Rueckgabewert heisst "es gibt einen Zauber" (nur der Inhalt ist gesperrt);
        -- Secret zuerst pruefen, nie vergleichen oder als Wahrheitswert testen.
        read = function()
            for _, fn in ipairs({ UnitCastingInfo, UnitChannelInfo }) do
                local spell = fn("player")
                if Compat.IsSecret(spell) or spell ~= nil then return true end
            end
            return false
        end,
    },
    afk = { api = { "UnitIsAFK" }, events = { "PLAYER_FLAGS_CHANGED" }, read = function() return UnitIsAFK("player") end },
    typing = { api = {}, events = {}, read = function() return next(typingBoxes) ~= nil end },
    hurt = {
        api = {}, events = { "UNIT_HEALTH", "UNIT_MAXHEALTH", REGEN[1], REGEN[2] },
        read = function() return ratioState("health") end,
    },
    power = {
        api = {}, events = { "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER", REGEN[1], REGEN[2] },
        read = function() return ratioState("power") end,
    },
    -- Drinnen (Gebaeude, Hoehle): Blizzards IsIndoors. Das Ereignis kommt beim Wechsel der Unterzone drinnen; Zonen-/Ladewechsel
    -- fangen ZONE_CHANGED* und der Gesamtabgleich bei PLAYER_ENTERING_WORLD ab.
    indoors = {
        api = { "IsIndoors" }, events = { "ZONE_CHANGED_INDOORS", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA" },
        read = function()
            local v = IsIndoors() -- liefert je Client true/false oder 1/nil
            if Compat.IsSecret(v) then return nil, "secret" end
            return B(v)
        end,
    },
    -- Schwimmen: an der Oberflaeche oder unter Wasser. IsSubmerged gibt es nicht ueberall (optional). Die MIRROR_TIMER-Ereignisse
    -- (Atemanzeige) melden das Untertauchen sofort; den Rest holt der Ticker (State.Need/Touch).
    swimming = {
        api = { "IsSwimming" }, events = { "MIRROR_TIMER_START", "MIRROR_TIMER_STOP", "MIRROR_TIMER_PAUSE", "PLAYER_MOUNT_DISPLAY_CHANGED" },
        read = function()
            local sw = IsSwimming()
            if Compat.IsSecret(sw) then return nil, "secret" end
            if B(sw) then return true end
            if type(IsSubmerged) == "function" then
                local sub = IsSubmerged()
                if Compat.IsSecret(sub) then return nil, "secret" end
                return B(sub)
            end
            return false
        end,
    },
    -- Debuff auf dir (siehe readDebuffs): Secret => letzten Wert halten, keine API => nicht verfuegbar
    debuffed = {
        api = {}, events = { "UNIT_AURA", REGEN[2] },
        read = function()
            local v, reason = readDebuffs()
            if v == nil then
                if reason == "secret" then return lastDebuffed end
                return nil, reason
            end
            lastDebuffed = v and true or false
            return lastDebuffed
        end,
    },
    npc = {
        api = {}, events = {},
        read = function(event)
            if NPC_OPEN[event] then npcOpen[NPC_OPEN[event]] = true end
            if NPC_CLOSE[event] then npcOpen[NPC_CLOSE[event]] = nil end
            return next(npcOpen) ~= nil
        end,
    },
}
for e in pairs(NPC_OPEN) do defs.npc.events[#defs.npc.events + 1] = e end
for e in pairs(NPC_CLOSE) do defs.npc.events[#defs.npc.events + 1] = e end
table.sort(defs.npc.events)

-- Events, deren erstes Argument die Einheit ist (nur "player" zaehlt)
local UNIT_ARG = {
    UNIT_HEALTH = true, UNIT_MAXHEALTH = true, UNIT_POWER_UPDATE = true, UNIT_MAXPOWER = true,
    UNIT_DISPLAYPOWER = true, PLAYER_FLAGS_CHANGED = true, UNIT_AURA = true,
    UNIT_SPELLCAST_START = true, UNIT_SPELLCAST_STOP = true, UNIT_SPELLCAST_FAILED = true,
    UNIT_SPELLCAST_INTERRUPTED = true, UNIT_SPELLCAST_CHANNEL_START = true, UNIT_SPELLCAST_CHANNEL_STOP = true,
    UNIT_SPELLCAST_EMPOWER_START = true, UNIT_SPELLCAST_EMPOWER_STOP = true,
}

-- Fliegen: Ticker nur bei Anlass ------------------------------------------------------------------
local flightTicker

-- Dracthyr koennen jederzeit gleiten: kein Event fuer den Start, daher Ticker, solange Gleiten moeglich ist
local function canGlide()
    if not (C_PlayerInfo and C_PlayerInfo.GetGlidingInfo) then return false end
    local _, can = C_PlayerInfo.GetGlidingInfo()
    return not Compat.IsSecret(can) and can == true
end
local function updateFlightTicker()
    if unavail.flying == "api" or not (C_Timer and C_Timer.NewTicker) then return end
    local need = (IsMounted and B(IsMounted())) or (UnitOnTaxi and B(UnitOnTaxi("player")))
        or (GetShapeshiftFormID and FLIGHT_FORMS[Compat.Num(GetShapeshiftFormID()) or 0])
        or canGlide()
    if need and not flightTicker then
        flightTicker = C_Timer.NewTicker(State.FLIGHT_INTERVAL, function() evaluate("flying") end)
    elseif not need and flightTicker then
        flightTicker:Cancel()
        flightTicker = nil
    end
end
function State.IsFlightTickerActive() return flightTicker ~= nil end

-- Drinnen/Schwimmen: Ticker nur bei Bedarf. Bedarf = Need-Eintraege (mit Abmeldung) oder eine Abfrage per Get (bleibt).
local pollTicker
local needs = {}  -- name -> { owner = true }
local touched = {} -- name -> true: von einem Abnehmer ohne Need abgefragt

local function polled(name)
    if unavail[name] == "api" then return false end
    return touched[name] == true or (needs[name] ~= nil and next(needs[name]) ~= nil)
end

local function updatePoll()
    local any = false
    for name in pairs(State.POLLED) do if polled(name) then any = true end end
    if any and not pollTicker and C_Timer and C_Timer.NewTicker then
        pollTicker = C_Timer.NewTicker(State.POLL_INTERVAL, function()
            for name in pairs(State.POLLED) do if polled(name) then evaluate(name) end end
        end)
    elseif not any and pollTicker then
        pollTicker:Cancel()
        pollTicker = nil
    end
end

--- Abnehmer meldet Bedarf (on = true) bzw. gibt ihn zurueck (on = false/nil); gilt nur fuer indoors/swimming
function State.Need(name, owner, on)
    if on and State.ON_DEMAND[name] then demand(name) end
    if not State.POLLED[name] then return end
    needs[name] = needs[name] or {}
    local was = polled(name)
    needs[name][owner] = on and true or nil
    if on and not was then evaluate(name) end -- frischer Startwert
    updatePoll()
end

--- erste Abfrage per Get: Ticker anfordern (bleibt) und sofort lesen
function State.Touch(name)
    if touched[name] then return end
    touched[name] = true
    updatePoll()
    evaluate(name)
end

function State.IsPolling(name) return pollTicker ~= nil and polled(name) end
function State.IsSwimTickerActive() return State.IsPolling("swimming") end

function evaluate(name, event, ...)
    local def = defs[name]
    if State.ON_DEMAND[name] and not demanded[name] then return end
    if unavail[name] == "api" and def.static then return end
    local ok, v, reason = xpcall(def.read, geterrorhandler(), event, ...)
    if not ok then return end
    -- Secret Value als Ergebnis (Retail 12.x): nicht verfuegbar statt Wahrheitstest in set()
    if Compat.IsSecret(v) then v, reason = nil, "secret" end
    set(name, v, reason)
    if name == "flying" then updateFlightTicker() end
end

-- Anmeldung: fehlende API oder kein einziges bekanntes Event => Zustand dauerhaft nicht verfuegbar ----
local eventStates = {} -- event -> { name... }

local function dispatch(event, ...)
    if UNIT_ARG[event] then
        local unit = ...
        if Compat.IsSecret(unit) or unit ~= "player" then return end
    end
    for _, name in ipairs(eventStates[event]) do evaluate(name, event, ...) end
end

-- Einheiten-Events, die nur fuer "player" gebraucht werden: eigener Frame mit RegisterUnitEvent (der Client filtert)
local UNIT_ONLY_PLAYER = { UNIT_AURA = true }
local unitFrame

local function registerEvent(event, name)
    if eventStates[event] then
        table.insert(eventStates[event], name)
        return true
    end
    eventStates[event] = { name }
    if UNIT_ONLY_PLAYER[event] and CreateFrame then
        unitFrame = unitFrame or CreateFrame("Frame")
        if type(unitFrame.RegisterUnitEvent) == "function"
            and pcall(unitFrame.RegisterUnitEvent, unitFrame, event, "player") then
            unitFrame:SetScript("OnEvent", function(_, e, ...) dispatch(e, ...) end) -- dispatch filtert zusaetzlich
            return true
        end
    end
    if Compat.TryOn(event, dispatch) then return true end
    eventStates[event] = nil
    return false
end

for _, name in ipairs(State.NAMES) do
    local def = defs[name]
    if def then
        local ok = true
        for _, path in ipairs(def.api) do
            if not Compat.HasAPI(path) then ok = false end
        end
        if ok and #def.events > 0 then
            local any = false
            for _, e in ipairs(def.events) do
                if registerEvent(e, name) then any = true end
            end
            ok = any
        end
        if not ok then
            def.static = true
            values[name], unavail[name] = false, "api"
        end
    end
end

-- Chat-Eingabe: Fokus der Eingabefelder (HookScript, keine geschuetzten Skripte)
do
    local function gained(box) typingBoxes[box] = true; evaluate("typing") end
    local function lost(box) typingBoxes[box] = nil; evaluate("typing") end
    local watched = {}

    --- weiteres Chat-Eingabefeld beobachten (z. B. eines spaeter erzeugten, temporaeren Chat-Fensters).
    --- Liefert true, wenn es neu angemeldet wurde.
    function State.WatchEditBox(box)
        if type(box) ~= "table" or not box.HookScript or watched[box] then return false end
        watched[box] = true
        box:HookScript("OnEditFocusGained", gained)
        box:HookScript("OnEditFocusLost", lost)
        box:HookScript("OnHide", lost)
        editBoxes[#editBoxes + 1] = box
        if defs.typing.static then -- erstes Eingabefeld ueberhaupt: Zustand wird verfuegbar
            defs.typing.static = nil
            evaluate("typing")
        end
        return true
    end

    for i = 1, (NUM_CHAT_WINDOWS or 10) do State.WatchEditBox(_G["ChatFrame" .. i .. "EditBox"]) end
    if #editBoxes == 0 then defs.typing.static = true; unavail.typing = "api" end
end

-- Mouseover je Element -----------------------------------------------------------------------------
-- Erkennung je Frame (Hotfix B2): Cursor geometrisch gegen das Frame-Rechteck (GetCursorPosition/GetRect/
-- GetEffectiveScale) ODER Region:IsMouseOver (Fallback: MouseIsOver). Die Geometrie haengt weder am Alpha noch
-- daran, ob die Maus des Frames an ist ("Klicks durchlassen" schaltet sie bei Alpha 0 ab). Jede Abfrage laeuft
-- ueber Compat (Secret Value => "nicht darueber"), nie als Wahrheitstest auf dem Rohwert.
State.mouse = {}       -- elementId -> bool
local watches = {}     -- elementId -> { frame... }
local mouseTicker
local mouseErrors = {} -- elementId -> true: Fehler beim Pruefen schon einmal gemeldet

local function cursorInRect(f)
    if not (GetCursorPosition and f.GetRect and f.GetEffectiveScale) then return nil end
    local ok, l, b, w, h = pcall(f.GetRect, f)
    if not ok then return nil end
    l, b, w, h = Compat.Num(l), Compat.Num(b), Compat.Num(w), Compat.Num(h)
    local okS, s = pcall(f.GetEffectiveScale, f)
    s = okS and Compat.Num(s) or nil
    local x, y = GetCursorPosition()
    x, y = Compat.Num(x), Compat.Num(y)
    if not (l and b and w and h and s and x and y) or s <= 0 then return nil end
    x, y = x / s, y / s
    return x >= l and x <= l + w and y >= b and y <= b + h
end

-- Rechtecke versteckter Frames (z. B. Minimap, die Lucid ganz versteckt): vor dem Hide gemerkt, damit Mouseover sie
-- trotzdem findet. frame -> { links, unten, breite, hoehe, scale }
local hiddenRects = setmetatable({}, { __mode = "k" })

--- Rechteck eines Frames merken, bevor er versteckt wird (nur lesbare Zahlen; sonst wird nichts gemerkt)
function State.RememberRect(f)
    if type(f) ~= "table" or not (f.GetRect and f.GetEffectiveScale) then return false end
    local ok, l, b, w, h = pcall(f.GetRect, f)
    if not ok then return false end
    l, b, w, h = Compat.Num(l), Compat.Num(b), Compat.Num(w), Compat.Num(h)
    local okS, s = pcall(f.GetEffectiveScale, f)
    s = okS and Compat.Num(s) or nil
    if not (l and b and w and h and s) or s <= 0 then return false end
    hiddenRects[f] = { l, b, w, h, s }
    return true
end

function State.ForgetRect(f)
    if type(f) == "table" then hiddenRects[f] = nil end
end

local function cursorInSaved(r)
    if not GetCursorPosition then return false end
    local x, y = GetCursorPosition()
    x, y = Compat.Num(x), Compat.Num(y)
    if not (x and y) then return false end
    x, y = x / r[5], y / r[5]
    return x >= r[1] and x <= r[1] + r[3] and y >= r[2] and y <= r[2] + r[4]
end

--- true, wenn der Cursor ueber dem (sichtbaren) Frame steht. Wirft nicht, auch nicht bei Secret Values.
--- Versteckte Frames mit gemerktem Rechteck (State.RememberRect) zaehlen geometrisch, solange ihr Eltern-Frame
--- sichtbar ist (oder es keinen gibt).
function State.IsCursorOver(f)
    if type(f) ~= "table" then return false end
    local visible = Compat.QueryBool(f, "IsVisible")
    if visible ~= true then
        local r = visible == false and hiddenRects[f]
        if not r then return false end
        local okP, p = pcall(function() return f.GetParent and f:GetParent() end)
        if not okP then return false end
        if p ~= nil and Compat.QueryBool(p, "IsVisible") ~= true then return false end
        return cursorInSaved(r)
    end
    if Compat.QueryBool(f, "IsMouseOver") == true then return true end
    if cursorInRect(f) == true then return true end
    if not f.IsMouseOver and type(MouseIsOver) == "function" then
        local ok, v = pcall(MouseIsOver, f)
        return ok and Compat.Bool(v)
    end
    return false
end

local function anyOver(frames)
    for _, f in ipairs(frames) do
        if State.IsCursorOver(f) then return true end
    end
    return false
end

local function tickMouse()
    local ids = {}
    for id in pairs(watches) do ids[#ids + 1] = id end
    for _, id in ipairs(ids) do
        local frames = watches[id]
        if frames then
            -- je Element geschuetzt: ein Fehler darf den Ticker nicht beenden (sonst ist Mouseover fuer alle tot)
            local ok, over = pcall(anyOver, frames)
            if not ok then
                if not mouseErrors[id] then
                    mouseErrors[id] = true
                    geterrorhandler()(over)
                end
                over = false
            end
            if (State.mouse[id] == true) ~= over then
                State.mouse[id] = over
                notify("mouseover", over, id)
            end
        end
    end
end

--- Mouseover fuer ein Element beobachten (frames: Frame oder Liste). Liefert false, wenn der Client es nicht kann.
function State.WatchMouseover(id, frames)
    if not (C_Timer and C_Timer.NewTicker) then return false end
    if type(frames) ~= "table" or frames.GetAlpha then frames = { frames } end
    watches[id] = frames
    -- abgebrochener Ticker (z. B. von aussen beendet) wird ersetzt
    if mouseTicker and mouseTicker.IsCancelled and mouseTicker:IsCancelled() then mouseTicker = nil end
    if not mouseTicker then mouseTicker = C_Timer.NewTicker(State.MOUSEOVER_INTERVAL, tickMouse) end
    return true
end

function State.UnwatchMouseover(id)
    if not watches[id] then return end
    watches[id] = nil
    if State.mouse[id] then
        State.mouse[id] = nil
        notify("mouseover", false, id)
    end
    State.mouse[id] = nil
    if not next(watches) and mouseTicker then
        mouseTicker:Cancel()
        mouseTicker = nil
    end
end

function State.IsMouseTickerActive() return mouseTicker ~= nil end

-- Gesamtabgleich ------------------------------------------------------------------------------------
--- alle Zustaende neu lesen; quiet = ohne Callbacks (Startwerte)
function State.Refresh(quiet)
    silent = quiet and true or false
    for _, name in ipairs(State.NAMES) do
        if defs[name] and not defs[name].static then evaluate(name) end
    end
    silent = false
    updateFlightTicker()
end

ns.On("ADDON_LOADED", function(_, name)
    if name ~= ns.name then return end
    State.LoadExtraCapitals(ns.db and ns.db.extraCapitals)
    State.Refresh(true)
end)
ns.On("PLAYER_LOGIN", function() State.Refresh() end)
ns.On("PLAYER_ENTERING_WORLD", function()
    -- Ladebildschirm schliesst alle NPC-Fenster
    for k in pairs(npcOpen) do npcOpen[k] = nil end
    State.Refresh()
end)
