-- Zone: Zonentext (B5). Datenmodell (Z1: Profil-Abschnitt "zone", Standardwerte, Pruefung fuer Import und
-- Aendern), Entscheidungslogik (Z2) und Slash-Befehl /lucid zone (Z3). Die Karte zeichnet Card.lua.
--
-- Profil-Abschnitt "zone" (additiv, Schema bleibt 1; fehlende Felder bekommen die Standardwerte):
--   enabled (bool, Standard aus), minGap (0-600 s, Standard 0 wie Blizzard), pos = { point, x, y },
--   zone / subzone / discovery je { on, font, size, fadeIn, hold, fadeOut },
--   glow / band (0-100 %, Standard 50 = Werkswert, 0 = aus; Nachtrag 03.11.): Staerke von Glanz und Lichtband,
--   ornament (Schluessel aus Zone.ORNAMENTS, Standard "swirl"), ornScale (50-200 %, Standard 100) und ornDelay
--   (0-2 s nach Kartenstart, Standard 0,2), ornFade (0,2-2 s, Standard 0,6): Verzierung.
--   autoOrnament (bool, Standard an): die grosse Karte waehlt das Zonen-Motiv der Zone (ZoneMotifs.lua); "ornament" gilt
--   dann fuer Zonen ohne Motiv und als fester Stil bei aus. ornament = "none" schaltet die Verzierung immer ab.
-- Schriften sind nur Schluessel aus einer festen Liste; ein Pfad steht nie im Profil.
local _, ns = ...
local Store = ns.Store

local Zone = {}
ns.Zone = Zone

Zone.TRIGGERS = { "zone", "subzone", "discovery" }
Zone.FONT_KEYS = { "client", "frizqt", "morpheus", "arialn", "skurri", "cinzel", "cormorant", "marcellus" }
Zone.POINTS = { "TOP", "TOPLEFT", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOM", "BOTTOMLEFT", "BOTTOMRIGHT" }
Zone.LIMITS = {
    minGap = { 0, 600 },
    pos = { -4000, 4000 },
    size = { 10, 96 },
    fadeIn = { 0.1, 5 },
    hold = { 0.5, 15 },
    fadeOut = { 0.1, 6 },
    strength = { 0, 100 }, -- glow / band in %
    ornScale = { 50, 200 }, -- Verzierungsgroesse in %
    ornDelay = { 0, 2 }, -- Einsatz der Verzierung in s
    ornFade = { 0.2, 2 }, -- Einblenden der Verzierung in s
}
-- eingebaute Stile + Vorlagen-Stile aus Ornaments.lua (erzeugt aus docs/ornament-src/recipes.json) + schlicht/keine
-- Reihenfolge: swirl, filigree, bisherige Vorlagen, Zonen-Motive (O.motif), simple, none
Zone.ORNAMENTS = { "swirl", "filigree" }
do
    local O = ns.ZoneOrnaments or {}
    local motif = O.motif or {}
    for _, name in ipairs(O.order or {}) do
        if not motif[name] then Zone.ORNAMENTS[#Zone.ORNAMENTS + 1] = name end
    end
    for _, name in ipairs(O.order or {}) do
        if motif[name] then Zone.ORNAMENTS[#Zone.ORNAMENTS + 1] = name end
    end
end
Zone.ORNAMENTS[#Zone.ORNAMENTS + 1] = "simple"
Zone.ORNAMENTS[#Zone.ORNAMENTS + 1] = "none"
-- entfernte Stile (Welle B5-3): gespeicherte Profile mit diesen Werten fallen still auf den Standard zurueck, statt
-- dass der ganze Zonen-Abschnitt verworfen wird
Zone.REMOVED_ORNAMENTS = { celtic = true, artdeco = true, branches = true, wings = true, dragon = true, norse = true,
    flames = true, arabesque = true, frost = true, artnouveau = true }
Zone.STRENGTH_KEYS = { "glow", "band" }

local function set(list)
    local s = {}
    for _, k in ipairs(list) do s[k] = true end
    return s
end
local FONT_SET, POINT_SET, ORNAMENT_SET = set(Zone.FONT_KEYS), set(Zone.POINTS), set(Zone.ORNAMENTS)

local function trigger(font, size, fadeIn, hold, fadeOut)
    return { on = true, font = font, size = size, fadeIn = fadeIn, hold = hold, fadeOut = fadeOut }
end

--- Standardwerte (frische Kopie bei jedem Aufruf)
function Zone.Defaults()
    return {
        enabled = false,
        minGap = 0, -- wie Blizzard: ZoneText_OnEvent kennt keine Sperrzeit (Nachtrag 03.11.)
        pos = { point = "TOP", x = 0, y = -140 },
        zone = trigger("cinzel", 44, 1.5, 2.8, 1.8),
        subzone = trigger("cinzel", 22, 0.5, 1.6, 0.8),
        discovery = trigger("cormorant", 18, 1.4, 3.8, 2.2),
        glow = 50,
        band = 50,
        ornament = "swirl",
        autoOrnament = true,
        ornScale = 100,
        ornDelay = 0.2,
        ornFade = 0.6,
    }
end

local function isNum(v, range) return type(v) == "number" and v == v and v >= range[1] and v <= range[2] end

local TRIGGER_NUMS = { "size", "fadeIn", "hold", "fadeOut" }

-- Teilabschnitt pruefen: unbekannte Felder fallen weg, fehlende bekommen den Standard,
-- falsche Typen/Grenzen => nil, Feldname.
local function validateTrigger(v, default)
    if type(v) ~= "table" then return nil, "type" end
    local out = {}
    for k, x in pairs(v) do
        if k == "on" then
            if type(x) ~= "boolean" then return nil, k end
        elseif k == "font" then
            if type(x) ~= "string" or not FONT_SET[x] then return nil, k end
        elseif k == "size" or k == "fadeIn" or k == "hold" or k == "fadeOut" then
            if not isNum(x, Zone.LIMITS[k]) then return nil, k end
        else
            x = nil
        end
        if x ~= nil then out[k] = x end
    end
    if out.on == nil then out.on = default.on end
    if out.font == nil then out.font = default.font end
    for _, k in ipairs(TRIGGER_NUMS) do
        if out[k] == nil then out[k] = default[k] end
    end
    return out
end

local function validatePos(v, default)
    if type(v) ~= "table" then return nil, "type" end
    local out = {}
    for k, x in pairs(v) do
        if k == "point" then
            if type(x) ~= "string" or not POINT_SET[x] then return nil, k end
        elseif k == "x" or k == "y" then
            if not isNum(x, Zone.LIMITS.pos) then return nil, k end
        else
            x = nil
        end
        if x ~= nil then out[k] = x end
    end
    for _, k in ipairs({ "point", "x", "y" }) do
        if out[k] == nil then out[k] = default[k] end
    end
    return out
end

--- Profil-Abschnitt "zone" pruefen (Import und Aendern). Liefert eine vollstaendige bereinigte Kopie
--- oder nil, Detail.
function Zone.Validate(v)
    if type(v) ~= "table" then return nil, "type" end
    local def = Zone.Defaults()
    local out = {}
    for k, x in pairs(v) do
        if k == "enabled" then
            if type(x) ~= "boolean" then return nil, k end
            out.enabled = x
        elseif k == "minGap" then
            if not isNum(x, Zone.LIMITS.minGap) then return nil, k end
            out.minGap = x
        elseif k == "glow" or k == "band" then
            -- Staerke: Zahl Pflicht, Bereich wird auf 0-100 geklemmt und auf ganze Prozent gerundet
            if type(x) ~= "number" or x ~= x then return nil, k end
            local r = Zone.LIMITS.strength
            out[k] = math.floor(math.min(r[2], math.max(r[1], x)) + 0.5)
        elseif k == "ornament" then
            -- entfernte Stile fallen auf den Standard; ein Name, der heute wieder ein Stil ist (Motiv "frost"), bleibt gueltig
            if type(x) == "string" and Zone.REMOVED_ORNAMENTS[x] and not ORNAMENT_SET[x] then x = def.ornament end
            if type(x) ~= "string" or not ORNAMENT_SET[x] then return nil, k end
            out.ornament = x
        elseif k == "autoOrnament" then
            -- kein bool => Standard (an); additives Feld, alte Profile ohne Feld bekommen ebenfalls den Standard
            if type(x) == "boolean" then out.autoOrnament = x end
        elseif k == "ornScale" then
            -- wie die Staerken: Zahl Pflicht, auf 50-200 geklemmt und gerundet
            if type(x) ~= "number" or x ~= x then return nil, k end
            local r = Zone.LIMITS.ornScale
            out.ornScale = math.floor(math.min(r[2], math.max(r[1], x)) + 0.5)
        elseif k == "ornDelay" or k == "ornFade" then
            -- Zahl Pflicht, auf die Grenzen geklemmt und auf 0,1 s gerundet
            if type(x) ~= "number" or x ~= x then return nil, k end
            local r = Zone.LIMITS[k]
            out[k] = math.floor(math.min(r[2], math.max(r[1], x)) * 10 + 0.5) / 10
        elseif k == "pos" then
            local p, d = validatePos(x, def.pos)
            if not p then return nil, "pos." .. tostring(d) end
            out.pos = p
        elseif k == "zone" or k == "subzone" or k == "discovery" then
            local t, d = validateTrigger(x, def[k])
            if not t then return nil, k .. "." .. tostring(d) end
            out[k] = t
        end -- unbekannte Felder fallen weg
    end
    if out.enabled == nil then out.enabled = def.enabled end
    if out.minGap == nil then out.minGap = def.minGap end
    if out.pos == nil then out.pos = def.pos end
    for _, k in ipairs({ "glow", "band", "ornament", "autoOrnament", "ornScale", "ornDelay", "ornFade" }) do
        if out[k] == nil then out[k] = def[k] end
    end
    for _, k in ipairs(Zone.TRIGGERS) do
        if out[k] == nil then out[k] = def[k] end
    end
    return out
end

Store.RegisterSection("zone", {
    default = Zone.Defaults,
    validate = Zone.Validate,
})

-- Standardwerte-Stand der gespeicherten Profile (LucidDB.zoneDefaults). Stand 2 (03.11.): minGap 60 -> 0 und
-- Einblenden der Zonenkarte 1,2 -> 1,5 s. Umgestellt wird je Wert nur, wenn er exakt dem alten Standard entspricht
-- (bewusst gewaehlte Werte bleiben), und nur einmal: danach steht der Stand fest, auch ein spaeter wieder auf 60
-- gestellter Regler bleibt 60. Importierte Profile werden nicht umgestellt.
Zone.DEFAULTS_REV = 2

--- gespeicherte Profile einmalig auf die neuen Standardwerte heben (bei ADDON_LOADED nach Store.Init)
function Zone.MigrateDefaults(db)
    if type(db) ~= "table" or type(db.profiles) ~= "table" then return end
    local rev = tonumber(db.zoneDefaults) or 1
    if rev >= Zone.DEFAULTS_REV then return end
    for _, p in pairs(db.profiles) do
        local z = type(p) == "table" and p.zone
        if type(z) == "table" then
            if z.minGap == 60 then z.minGap = 0 end
            if type(z.zone) == "table" and z.zone.fadeIn == 1.2 then z.zone.fadeIn = 1.5 end
        end
    end
    db.zoneDefaults = Zone.DEFAULTS_REV
end

-- Store.lua meldet sich vorher an (Ladereihenfolge der .toc) und hat Store.db dann schon vorbereitet
ns.On("ADDON_LOADED", function(_, name)
    if name ~= ns.name or not Store.db then return end
    Zone.MigrateDefaults(Store.db)
end)

--- wirksame Einstellungen des aktiven Profils (immer gueltig; ungueltiger Bestand => Standardwerte)
function Zone.GetConfig()
    local stored
    if Store.db then
        local p = Store.GetActive()
        stored = p and p.zone
    end
    return (type(stored) == "table" and Zone.Validate(stored)) or Zone.Defaults()
end

-- =================================================================================================
-- Z2: Entscheidungslogik (ohne Frames). Verhalten 1:1 wie Blizzards ZoneText_OnEvent:
-- Eingaenge sind nur ZONE_CHANGED_NEW_AREA / ZONE_CHANGED / ZONE_CHANGED_INDOORS; Ladebildschirm- und
-- PLAYER_ENTERING_WORLD-Ereignisse verschieben bzw. pflegen nur Zustand und loesen nie selbst etwas aus.
-- Die Karte zeichnet Card.lua (Z3) ueber Zone.Present/Zone.Stop; Zone.shown merkt die letzten 20 Karten.
-- =================================================================================================
local Compat = ns.Compat
local L = ns.L

Zone.DEBOUNCE = 0.3          -- Sammel-Verzoegerung in Sekunden
Zone.LOADING_GUARD = 15      -- Waechter: loading wird nach so vielen Sekunden ohne ...DISABLED zurueckgesetzt
Zone.NAME_MAX = 80           -- Bytes je Zonen-/Gebietsname in einer Karte
Zone.DIAG_MAX = 20
local GAPS_MAX = 1000
local ZONE_EVENTS = { "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS" }

local modEnabled = false     -- Modul aktiv (PLAYER_LOGIN bis Abschalten)
local loading = false
local loadingGen = 0
local debounceGen = 0
local pending = false        -- Zonen-Ereignis gesammelt, noch nicht ausgewertet
local pendingNewArea = false
local pendingLost = false    -- Blizzard hat ein Zonen-Ereignis moeglicherweise verpasst (Instanzeintritt)
local lastZone = ""          -- Sitzungszustand wie Blizzards zoneText
local lastInstance = nil     -- zuletzt gelesener Instanzstatus (true/false/nil)
local applied = nil          -- nil | "suppressed" | "restored": Zustand der Blizzard-Events
local failureReported = false
local current = nil          -- { sig, endsAt } der laufenden Karte
local gaps = {}              -- Mindestabstand: Schluessel -> GetTime()
local gapCount = 0
local diag = {}

Zone.shown = {}              -- zuletzt gestartete Karten (Tests/Diagnose); Card.lua haengt sich an Zone.Present

--- Fremdtext fuer FontString:SetText entschaerfen: Steuerzeichen raus, auf NAME_MAX Bytes (UTF-8-sicher)
--- kuerzen, "|" verdoppeln. Fuer Chat/Print/Tooltip ist dasselbe Verdoppeln noetig (Zone.Esc).
function Zone.Clean(s)
    s = s:gsub("%c", "")
    local n = Zone.NAME_MAX
    if #s > n then
        while n > 0 do
            local b = s:byte(n + 1)
            if b and b >= 128 and b <= 191 then n = n - 1 else break end
        end
        s = s:sub(1, n)
    end
    return (s:gsub("|", "||"))
end

--- beliebigen Text fuer Chat/Print/Tooltip: "|" verdoppeln
function Zone.Esc(s)
    return (tostring(s):gsub("|", "||"))
end

local function record(event)
    diag[#diag + 1] = { t = GetTime(), ev = event, inst = lastInstance }
    if #diag > Zone.DIAG_MAX then table.remove(diag, 1) end
end

--- Diagnose-Ringpuffer (letzte 20 Ereignisse) als fertige Chat-Zeilen; enthaelt nur feste Texte und Zahlen
function Zone.DiagLines()
    local out = {}
    for _, d in ipairs(diag) do
        local inst = d.inst == true and "instance" or (d.inst == false and "outside" or "?")
        out[#out + 1] = L.ZONE_DIAG_LINE:format(("%.2f"):format(d.t), Zone.Esc(d.ev), inst)
    end
    return out
end

-- Blizzards Zonentext abmelden / wieder anmelden --------------------------------------------------
local function blizzardFrame()
    local f = _G.ZoneTextFrame
    return type(f) == "table" and f or nil
end

local function readInstance()
    if type(IsInInstance) ~= "function" then return nil end
    local ok, v = pcall(IsInInstance)
    if not ok or Compat.IsSecret(v) then return nil end
    return v == true
end

local function eachEvent(f, method)
    local failed = false
    for _, ev in ipairs(ZONE_EVENTS) do
        if type(f[method]) ~= "function" or not pcall(f[method], f, ev) then failed = true end
    end
    return not failed
end

--- Entscheidung SOFORT (nicht entprellt): Instanz oder Modul aus => Blizzards Events angemeldet, sonst abgemeldet.
--- Unlesbarer Instanzstatus => Zustand unveraendert. Liefert inInstance (true/false/nil) und flipped
--- (true, wenn der Status gerade von "draussen" auf "Instanz" gekippt ist).
function Zone.SyncSuppression()
    local cfg = Zone.GetConfig()
    local inst = readInstance()
    local flipped = false
    if inst == nil then
        inst = lastInstance
    else
        flipped = lastInstance == false and inst == true
        lastInstance = inst
    end
    local suppress = modEnabled and cfg.enabled and inst ~= true
    local f = blizzardFrame()
    if suppress then
        local firstTime = applied ~= "suppressed"
        local ok = f ~= nil and eachEvent(f, "UnregisterEvent")
        if f and firstTime and type(f.Hide) == "function" then pcall(f.Hide, f) end
        applied = "suppressed"
        if not ok and not failureReported then
            failureReported = true
            ns.Print(L.ZONE_SUPPRESS_FAILED)
        end
    elseif applied == "suppressed" then
        if f then eachEvent(f, "RegisterEvent") end
        applied = "restored"
    end
    return inst, flipped
end

-- Mindestabstand ----------------------------------------------------------------------------------
local function gapOk(key, now, minGap)
    local t = gaps[key]
    return minGap <= 0 or t == nil or now - t >= minGap
end

local function stamp(key, now)
    if gaps[key] == nil then
        if gapCount >= GAPS_MAX then gaps, gapCount = {}, 0 end
        gapCount = gapCount + 1
    end
    gaps[key] = now
end

-- Karte beenden / zeigen --------------------------------------------------------------------------
--- laufende Karte sofort beenden (Card.lua ueberschreibt das)
function Zone.Stop() end

--- Karte zeigen (Card.lua ueberschreibt das); bis dahin: nur merken. upgrade = true: gleiche Zeilen wie die
--- laufende Karte, nur der Entdeckungs-Untertitel kommt hinzu.
function Zone.Present(card)
    Zone.shown[#Zone.shown + 1] = card
    if #Zone.shown > 20 then table.remove(Zone.shown, 1) end
end

local function stopCard()
    current = nil
    Zone.Stop()
end

local function running()
    return current ~= nil and GetTime() < current.endsAt
end

--- Signatur der Zeilen einer Karte (ohne Untertitel): gleiche Signatur = gleicher Inhalt
function Zone.CardSig(card)
    return card.kind .. "\n" .. card.lines[1].text .. "\n" .. (card.lines[2] and card.lines[2].text or "")
end

--- uiMapID der Zonenkarte des Spielers fuer die Motiv-Wahl (nil: nicht bestimmbar, Instanz, Fehler, Secret)
function Zone.CurrentMapId()
    if not (ns.Discovery and ns.Discovery.CurrentZoneMapId) then return nil end
    local ok, id = pcall(ns.Discovery.CurrentZoneMapId)
    if not ok then return nil end
    return Compat.Num(id)
end

local function present(card)
    local t = Zone.GetConfig()[card.trigger]
    if card.kind == "big" and card.mapID == nil then card.mapID = Zone.CurrentMapId() end
    local sig = Zone.CardSig(card)
    if running() and current.sig == sig then
        -- gleiche Zeilen wie die laufende Karte: ignorieren. Bringt die neue Karte aber den Entdeckungs-Untertitel
        -- mit (die Entdeckung ist schon eingetragen und kaeme nie wieder), wird er der laufenden Karte nachgereicht.
        if not card.subtitle or current.subtitle then return false end
        current.subtitle = card.subtitle
        current.endsAt = math.max(current.endsAt, GetTime() + t.fadeIn + t.hold + t.fadeOut)
        Zone.Present(card, true)
        return true
    end
    current = { sig = sig, subtitle = card.subtitle, endsAt = GetTime() + t.fadeIn + t.hold + t.fadeOut }
    Zone.Present(card)
    return true
end

local function readText(fn)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn)
    if not ok or Compat.IsSecret(v) or type(v) ~= "string" then return nil end
    return v
end

local function toastActive()
    local t = _G.EventToastManagerFrame
    if type(t) ~= "table" or type(t.IsCurrentlyToasting) ~= "function" then return false end
    local ok, v = pcall(t.IsCurrentlyToasting, t)
    return ok and not Compat.IsSecret(v) and v == true
end

local function frameShown(name)
    local f = _G[name]
    return type(f) == "table" and Compat.QueryBool(f, "IsShown") == true
end

-- Karten bilden -----------------------------------------------------------------------------------
local function line(text, trigger) return { text = Zone.Clean(text), trigger = trigger } end

--- Auswertung eines Zonenzustands nach Blizzards Regel. snap = { zone, sub, newArea, now }; nutzt und
--- veraendert Sitzungszustand (lastZone) und die Entdeckungsliste, setzt aber keine Zeitstempel.
--- Liefert die Karte oder nil. Karte: { kind = "big"|"small", lines = { {text, trigger}, ... },
--- subtitle = Text|nil, trigger = "zone"|"subzone"|"discovery" (bestimmt die Zeiten: Entdeckung > Zone > Subzone),
--- ornament = bool, stamps = { Abstands-Schluessel } }
function Zone.Decide(cfg, snap)
    local zone, sub, now = snap.zone, snap.sub, snap.now
    local zoneChanged = (zone ~= lastZone) or snap.newArea == true
    lastZone = zone
    if sub == "" and not zoneChanged then sub = zone end

    -- Entdeckung (die Liste wird immer gepflegt, auch bei ausgeschaltetem Ausloeser)
    local zoneNew, subNew = false, false
    if zoneChanged then
        local id = ns.Discovery.CurrentZoneMapId()
        if id then zoneNew = ns.Discovery.Mark("zone", id) == "new" end
    end
    if sub ~= "" then subNew = ns.Discovery.Mark("area", sub) == "new" end
    local disc = cfg.discovery.on and ns.Discovery.IsSeeded()

    local wantZone = zoneChanged and cfg.zone.on
    local wantSub = sub ~= "" and (sub ~= zone or (not zoneChanged and not running())) and cfg.subzone.on
    local zKey, sKey = "Z|" .. zone, "S|" .. zone .. "|" .. sub
    local keepZone = wantZone and (gapOk(zKey, now, cfg.minGap) or (zoneNew and disc))
    local keepSub = wantSub and (gapOk(sKey, now, cfg.minGap) or (subNew and disc))
    if not keepZone and not keepSub then return nil end

    local card = { lines = {}, stamps = {} }
    if keepZone then
        card.kind, card.ornament = "big", true
        card.lines[1] = line(zone, "zone")
        card.stamps[#card.stamps + 1] = zKey
        if keepSub then
            card.lines[2] = line(sub, "subzone")
            card.stamps[#card.stamps + 1] = sKey
        end
    else
        card.kind, card.ornament = "small", false
        card.lines[1] = line(sub, "subzone")
        card.stamps[1] = sKey
    end
    if disc and ((keepZone and zoneNew) or (keepSub and subNew)) then
        card.subtitle = L.ZONE_DISCOVERED
        card.trigger = "discovery"
    else
        card.trigger = keepZone and "zone" or "subzone"
    end
    return card
end

--- Auswertung nach der Sammel-Verzoegerung
local function evaluate()
    if not (modEnabled and Zone.GetConfig().enabled) then pending = false return end
    if loading then return end -- bleibt gesammelt, laeuft nach LOADING_SCREEN_DISABLED
    local newArea, lost = pendingNewArea, pendingLost
    pending, pendingNewArea, pendingLost = false, false, false
    local cfg = Zone.GetConfig()
    local inst = Zone.SyncSuppression()
    local now = GetTime()
    if inst == true then
        lastZone = ""
        if lost and not frameShown("ZoneTextFrame") and not frameShown("SubZoneTextFrame") and cfg.zone.on then
            -- Sicherungs-Rueckfall: Blizzard hat das Ereignis beim Instanzeintritt verpasst => einmalig Lucids grosse Karte
            local zone = readText(GetZoneText)
            if zone and zone ~= "" then
                present({ kind = "big", ornament = true, trigger = "zone", lines = { line(zone, "zone") },
                    stamps = {}, fallback = true })
            end
        end
        return
    end
    if toastActive() then return end
    local zone, sub = readText(GetZoneText), readText(GetSubZoneText)
    if not zone or not sub or zone == "" then return end
    local card = Zone.Decide(cfg, { zone = zone, sub = sub, newArea = newArea, now = now })
    if card and present(card) then
        for _, key in ipairs(card.stamps) do stamp(key, now) end
    end
end

local function schedule()
    debounceGen = debounceGen + 1
    local mine = debounceGen
    C_Timer.After(Zone.DEBOUNCE, function()
        if mine == debounceGen then evaluate() end
    end)
end

local function onZoneEvent(event)
    local _, flipped = Zone.SyncSuppression()
    record(event)
    if not (modEnabled and Zone.GetConfig().enabled) then return end
    pending = true
    if event == "ZONE_CHANGED_NEW_AREA" then pendingNewArea = true end
    if flipped then pendingLost = true end
    if not loading then schedule() end
end

local function onLoadingStart(event)
    Zone.SyncSuppression()
    record(event)
    loading = true
    loadingGen = loadingGen + 1
    local mine = loadingGen
    if modEnabled then stopCard() end -- Bildschirm ist verdeckt: Karte sofort beenden, ohne Ausblenden
    C_Timer.After(Zone.LOADING_GUARD, function()
        if mine == loadingGen and loading then
            loading = false
            if pending then schedule() end
        end
    end)
end

local function onLoadingEnd(event)
    Zone.SyncSuppression()
    record(event)
    loading = false
    loadingGen = loadingGen + 1
    if pending then schedule() end
end

--- true, solange Lucids Zonentext wirkt (Modul an und im aktiven Profil eingeschaltet)
function Zone.IsActive()
    return modEnabled and Zone.GetConfig().enabled == true
end

--- true, solange ein Ladebildschirm offen ist (inkl. 15-s-Waechter); fuer die Pause der Abtastung (Discovery.lua)
function Zone.IsLoading() return loading end

--- Profil/Modulzustand anwenden: Unterdrueckung neu bestimmen; bei Abschalten Karte und Sammlung beenden.
--- Die Entdeckungs-Befuellung (Discovery.lua) startet bzw. endet mit.
function Zone.Apply()
    Zone.SyncSuppression()
    local active = Zone.IsActive()
    if not active then
        stopCard()
        pending, pendingNewArea, pendingLost = false, false, false
        debounceGen = debounceGen + 1
    end
    if ns.Discovery and ns.Discovery.OnApply then ns.Discovery.OnApply(active) end
end

--- Ein-/Ausschalten im aktiven Profil und sofort anwenden. Liefert true oder nil, Fehlercode.
function Zone.SetEnabled(on)
    if type(on) ~= "boolean" then return nil, "ZONE_VALUE_INVALID" end
    local p = Store.GetActive()
    local z = Zone.GetConfig() -- frische, gueltige Kopie
    z.enabled = on
    p.zone = z
    Zone.Apply()
    return true
end

--- Zustand fuer Tests/Diagnose
function Zone.State()
    return { loading = loading, pending = pending, lastZone = lastZone, applied = applied,
        instance = lastInstance, running = running() }
end

ns.RegisterModule("zone", {
    OnEnable = function()
        modEnabled = true
        Zone.Apply()
    end,
    OnDisable = function()
        modEnabled = false
        Zone.Apply()
    end,
})

for _, ev in ipairs(ZONE_EVENTS) do
    Compat.TryOn(ev, onZoneEvent)
end
Compat.TryOn("PLAYER_ENTERING_WORLD", function(e)
    Zone.SyncSuppression()
    record(e)
end)
Compat.TryOn("LOADING_SCREEN_ENABLED", onLoadingStart)
Compat.TryOn("LOADING_SCREEN_DISABLED", onLoadingEnd)
Store.RegisterCallback(function()
    stopCard()
    Zone.Apply()
end)

-- Slash-Befehl /lucid zone ------------------------------------------------------------------------
-- Unterbefehle tragen sich in Zone.commands ein (Card.lua: test; Discovery.lua: seed; Move.lua: move). Fremdtext in der Ausgabe
-- immer ueber Zone.Esc.
Zone.commands = {}

local function num(v) return ("%g"):format(v) end

Zone.commands[""] = function()
    local cfg = Zone.GetConfig()
    ns.Print(L.ZONE_STATUS, cfg.enabled and L.ZONE_ON or L.ZONE_OFF, num(cfg.minGap),
        applied == "suppressed" and L.ZONE_BLIZZARD_SUPPRESSED or L.ZONE_BLIZZARD_ACTIVE,
        tostring(ns.Discovery.Count()))
    local lines = Zone.DiagLines()
    if #lines == 0 then
        ns.Print(L.ZONE_DIAG_EMPTY)
    else
        ns.Print(L.ZONE_DIAG_HEADER)
        for _, l in ipairs(lines) do ns.Print(l) end
    end
end

--- Verzierung passt sich der Zone an: /lucid zone auto [on|off] (ohne Argument: Zustand)
function Zone.SetAutoOrnament(on)
    if type(on) ~= "boolean" then return nil, "ZONE_VALUE_INVALID" end
    local p = Store.GetActive()
    if not p then return nil, "ZONE_VALUE_INVALID" end
    local z = Zone.GetConfig() -- frische, gueltige Kopie
    z.autoOrnament = on
    p.zone = z
    return true
end

Zone.commands.auto = function(arg)
    arg = (arg or ""):lower()
    if arg == "" then
        ns.Print(L.ZONE_AUTO_STATUS, Zone.GetConfig().autoOrnament and L.ZONE_ON or L.ZONE_OFF)
        return
    end
    if arg ~= "on" and arg ~= "off" then
        ns.Print(L.ZONE_ONOFF_INVALID, Zone.Esc(arg))
        return
    end
    if Zone.SetAutoOrnament(arg == "on") then
        ns.Print(arg == "on" and L.ZONE_AUTO_ENABLED or L.ZONE_AUTO_DISABLED)
        if ns.Config and ns.Config.Refresh then pcall(ns.Config.Refresh) end
    end
end

Zone.commands.on = function()
    if Zone.SetEnabled(true) then ns.Print(L.ZONE_ENABLED) end
end

Zone.commands.off = function()
    if Zone.SetEnabled(false) then ns.Print(L.ZONE_DISABLED) end
end

ns.commands.zone = function(rest)
    local sub, arg = (rest or ""):match("^%s*(%S*)%s*(.-)%s*$")
    sub = sub:lower()
    local fn = Zone.commands[sub]
    if fn then
        fn(arg)
    else
        ns.Print(L.ZONE_UNKNOWN, Zone.Esc(sub))
        ns.Print(L.HELP_ZONE)
    end
end
ns.AddHelp("HELP_ZONE")
ns.AddHelp("HELP_ZONE_AUTO")
