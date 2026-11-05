-- Discovery: Entdeckungsliste je Charakter (B5, Z2) und ihre Befuellung durch Abtastung der Weltkarte (Z4).
--
-- Schluessel: Zonenebene ueber die Karten-ID (zones[uiMapID]), Subzonenebene ueber den Gebietsnamen
-- (areas[name], ohne Zonenpraefix; namensgleiche Subzonen anderer Zonen gelten als bekannt).
-- Datensatz: Store.GetDiscovered() = { seeded, zones, areas }; Obergrenze Store.DISCOVERED_MAX Eintraege,
-- bei Erreichen wird nichts mehr eingetragen (und nichts geloescht).
local _, ns = ...
local Store, Compat = ns.Store, ns.Compat
local L = ns.L

local Discovery = {}
ns.Discovery = Discovery

local limitWarned = false

local function entry() return Store.db and Store.GetDiscovered() or nil end

local function validKey(kind, key)
    if kind == "zone" then return Store.ValidMapId(key) end
    if kind == "area" then return Store.ValidAreaName(key) end
    return false
end

--- true, wenn der Schluessel schon eingetragen ist (ungueltige Schluessel gelten als unbekannt)
function Discovery.IsKnown(kind, key)
    local e = entry()
    if not e or not validKey(kind, key) then return false end
    local t = kind == "zone" and e.zones or e.areas
    return t[key] == true
end

--- Eintragen. Liefert "new" (neu eingetragen), "known", "full" (Obergrenze erreicht, nichts eingetragen)
--- oder "invalid" (Schluessel/Charakter ungueltig). Prueft vor jedem Eintrag die Obergrenze.
function Discovery.Mark(kind, key)
    local e = entry()
    if not e or not validKey(kind, key) then return "invalid" end
    local t = kind == "zone" and e.zones or e.areas
    if t[key] == true then return "known" end
    if Store.DiscoveredCount(e) >= Store.DISCOVERED_MAX then
        if not limitWarned then
            limitWarned = true
            ns.Print(L.ZONE_LIMIT_REACHED, Store.DISCOVERED_MAX)
        end
        return "full"
    end
    t[key] = true
    return "new"
end

--- true, wenn die Liste befuellt ist und gerade keine Abtastung laeuft (waehrenddessen kein Untertitel)
function Discovery.IsSeeded()
    local e = entry()
    return e ~= nil and e.seeded == true and not Discovery.IsScanning()
end

function Discovery.SetSeeded(v)
    local e = entry()
    if e then e.seeded = v == true end
end

--- Anzahl der Eintraege des aktuellen Charakters
function Discovery.Count()
    return Store.DiscoveredCount(entry())
end

-- Zonenkarte -------------------------------------------------------------------------------------
local MAXTYPE = { zone = 3, dungeon = 4, orphan = 6 } -- Enum.UIMapType (Rueckfall, falls Enum fehlt)
local function mapType(name)
    local e = Enum and Enum.UIMapType
    return (type(e) == "table" and e[name]) or MAXTYPE[name:lower()]
end

--- uiMapID der Zonenkarte des Spielers: von C_Map.GetBestMapForUnit ueber parentMapID hoch bis zum ersten
--- Zone-Eintrag (Dungeon-/Orphan-Karte oder fehlender Elternteil => eigene ID). nil, wenn nicht bestimmbar
--- (API fehlt, nil, Secret, Fehler).
function Discovery.CurrentZoneMapId()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetMapInfo) then return nil end
    local ok, id = pcall(C_Map.GetBestMapForUnit, "player")
    id = ok and Compat.Num(id) or nil
    if not id or not Store.ValidMapId(id) then return nil end
    local zoneT, dungeonT, orphanT = mapType("Zone"), mapType("Dungeon"), mapType("Orphan")
    for _ = 1, 12 do
        local okInfo, info = pcall(C_Map.GetMapInfo, id)
        if not okInfo or type(info) ~= "table" or Compat.IsSecret(info) then return nil end
        local mt = Compat.Num(info.mapType)
        if mt and (mt == zoneT or mt == dungeonT or mt == orphanT) then return id end
        local parent = Compat.Num(info.parentMapID)
        if not parent or parent <= 0 then return id end
        id = parent
    end
    return nil
end

--- true, wenn die Obergrenze erreicht ist (nichts wird mehr eingetragen)
function Discovery.IsFull()
    local e = entry()
    return e ~= nil and Store.DiscoveredCount(e) >= Store.DISCOVERED_MAX
end

--- nur fuer Tests
function Discovery._ResetWarning() limitWarned = false end

-- =================================================================================================
-- Z4: Befuellung durch Abtastung der Weltkarte.
-- Alle Zonenkarten unter der Kosmos-Karte (946, ersatzweise Weltkarte 947) werden in einem Raster von
-- GRID x GRID Positionen mit C_MapExplorationInfo.GetExploredAreaIDsAtPosition abgefragt; jeder Treffer traegt
-- areas[C_Map.GetAreaInfo(id)] ein, eine Karte mit mindestens einem Treffer auch zones[uiMapID]. Die Arbeit laeuft
-- in Zeitscheiben (hoechstens BUDGET API-Aufrufe je Frame) und pausiert bei Kampf, Ladebildschirm und Instanz.
-- Rueckfall (API fehlt, keine Zonenkarte lesbar oder 0 Treffer in allen Karten): aktuelle Zonenkarte + aktuelle
-- Subzone gelten als bekannt. Ergebnis immer: seeded = true. Waehrend die Abtastung laeuft, gibt es keinen Untertitel
-- (IsSeeded = false). Abbruch durch /reload ist harmlos: nur die Eintraege sind persistent, beim naechsten Start
-- beginnt sie von vorn.
-- =================================================================================================
Discovery.GRID = 24          -- Rasterpunkte je Achse
Discovery.BUDGET = 300       -- hoechstens so viele API-Aufrufe je Frame
Discovery.START_DELAY = 3    -- s nach PLAYER_ENTERING_WORLD bzw. Einschalten
Discovery.PAUSE_POLL = 0.5   -- s, Pruefabstand waehrend einer Pause
Discovery.COSMIC_MAP, Discovery.WORLD_MAP = 946, 947
local MAX_IDS_PER_POINT = 32 -- Schutz gegen unplausible Rueckgaben

local scan = nil             -- laufende Abtastung (nur im Speicher) oder nil
local scanFrame = nil
local startGen = 0           -- verzoegerte Starts: nur der juengste zaehlt
Discovery.calls = 0          -- API-Aufrufe der laufenden/letzten Abtastung (Tests/Diagnose)
Discovery.maxCallsPerFrame = 0

function Discovery.IsScanning() return scan ~= nil end

local function apisPresent()
    return type(C_Map) == "table" and type(C_Map.GetMapChildrenInfo) == "function"
        and type(C_Map.GetAreaInfo) == "function"
        and type(C_MapExplorationInfo) == "table"
        and type(C_MapExplorationInfo.GetExploredAreaIDsAtPosition) == "function"
        and type(CreateVector2D) == "function"
end

local function readText(fn)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn)
    if not ok or Compat.IsSecret(v) or type(v) ~= "string" then return nil end
    return v
end

local function inInstance()
    if type(IsInInstance) ~= "function" then return false end
    local ok, v = pcall(IsInInstance)
    return ok and not Compat.IsSecret(v) and v == true
end

local function inCombat()
    if scan and scan.combat then return true end
    if type(InCombatLockdown) ~= "function" then return false end
    local ok, v = pcall(InCombatLockdown)
    return ok and not Compat.IsSecret(v) and v == true
end

--- Grund einer Pause ("combat" | "loading" | "instance") oder nil
local function pauseReason()
    if inCombat() then return "combat" end
    local z = ns.Zone
    if z and z.IsLoading and z.IsLoading() then return "loading" end
    if inInstance() then return "instance" end
    return nil
end

-- Zonenkarten (uiMapID-Liste ohne Doppelte) unter der Kosmos- bzw. Weltkarte; nil, wenn keine lesbar
local function zoneMaps()
    local zoneT = mapType("Zone")
    for _, root in ipairs({ Discovery.COSMIC_MAP, Discovery.WORLD_MAP }) do
        local ok, list = pcall(C_Map.GetMapChildrenInfo, root, nil, true)
        if ok and type(list) == "table" and not Compat.IsSecret(list) then
            local out, seen = {}, {}
            for _, info in ipairs(list) do
                if type(info) == "table" then
                    local id, mt = Compat.Num(info.mapID), Compat.Num(info.mapType)
                    if id and mt == zoneT and Store.ValidMapId(id) and not seen[id] then
                        seen[id] = true
                        out[#out + 1] = id
                    end
                end
            end
            if #out > 0 then return out end
        end
    end
    return nil
end

local function stopFrame()
    if scanFrame then scanFrame:Hide() end
end

-- Rueckfall: aktuelle Zonenkarte und aktuelle Subzone (ohne Subzone: der Zonenname, wie Zone.Decide) gelten als bekannt
local function fallback()
    local id = Discovery.CurrentZoneMapId()
    if id then Discovery.Mark("zone", id) end
    local sub = readText(GetSubZoneText)
    if not sub or sub == "" then sub = readText(GetZoneText) end
    if sub and Store.ValidAreaName(sub) then Discovery.Mark("area", sub) end
end

local function finishScan(s, useFallback)
    scan = nil
    stopFrame()
    if useFallback then fallback() end
    Discovery.SetSeeded(true)
    if s.verbose then
        if s.noApi then ns.Print(L.ZONE_SEED_FALLBACK) end
        ns.Print(L.ZONE_SEED_DONE, Discovery.Count())
    end
end

-- Name zu einer AreaID (je Abtastung gemerkt); der API-Aufruf zaehlt ins Budget. Fehler fallen in den pcall der Karte.
local function areaName(s, id)
    local cached = s.names[id]
    if cached ~= nil then return cached or nil end
    s.used = s.used + 1
    local name = C_Map.GetAreaInfo(id)
    if Compat.IsSecret(name) or not Store.ValidAreaName(name) then name = false end
    s.names[id] = name
    return name or nil
end

-- eine Rasterposition der aktuellen Karte abfragen; liefert false, wenn die Obergrenze erreicht ist
local function probe(s, mapID, cell)
    local g = Discovery.GRID
    local x, y = (cell % g + 0.5) / g, (math.floor(cell / g) + 0.5) / g
    s.used = s.used + 1
    local ids = C_MapExplorationInfo.GetExploredAreaIDsAtPosition(mapID, CreateVector2D(x, y))
    if type(ids) ~= "table" or Compat.IsSecret(ids) then return true end
    for i = 1, math.min(#ids, MAX_IDS_PER_POINT) do
        local id = Compat.Num(ids[i])
        local name = id and areaName(s, id)
        if name then
            s.hits = s.hits + 1
            s.mapHit = true
            if Discovery.Mark("area", name) == "full" then return false end
        end
    end
    return true
end

local function nextMap(s)
    s.mapIndex, s.cell, s.mapHit = s.mapIndex + 1, 0, false
end

-- eine Zeitscheibe: hoechstens BUDGET API-Aufrufe (eine Rasterposition kann mit ihren Gebietsnamen das Budget um
-- wenige Aufrufe ueberschreiten; deshalb wird vor jeder Position geprueft, ob noch Platz fuer sie ist)
local function step()
    local s = scan
    if not s then stopFrame() return end
    s.used = 0
    local g2 = Discovery.GRID * Discovery.GRID
    while s.used < Discovery.BUDGET - MAX_IDS_PER_POINT do
        local mapID = s.maps[s.mapIndex]
        if not mapID then
            finishScan(s, s.hits == 0)
            break
        end
        local ok, more = pcall(probe, s, mapID, s.cell)
        if not ok then
            nextMap(s) -- Karte wirft: ueberspringen (bereits Eingetragenes bleibt)
        elseif more == false then
            finishScan(s, false) -- Obergrenze: anhalten, nichts loeschen
            break
        else
            s.cell = s.cell + 1
            if s.cell >= g2 then
                if s.mapHit and Discovery.Mark("zone", mapID) == "full" then
                    finishScan(s, false)
                    break
                end
                nextMap(s)
            end
        end
    end
    Discovery.calls = Discovery.calls + s.used
    if s.used > Discovery.maxCallsPerFrame then Discovery.maxCallsPerFrame = s.used end
end

local function onUpdate(_, elapsed)
    local s = scan
    if not s then stopFrame() return end
    if s.paused then
        s.wait = s.wait - (tonumber(elapsed) or 0)
        if s.wait > 0 then return end
    end
    local why = pauseReason()
    if why then
        if not s.paused and s.verbose then ns.Print(L.ZONE_SEED_PAUSED) end
        s.paused, s.wait = why, Discovery.PAUSE_POLL
        return
    end
    s.paused = nil
    step()
end

--- Abtastung (neu) starten. verbose = true: Meldungen im Chat (/lucid zone seed). Laeuft schon eine, beginnt sie
--- von vorn (nur Hinzufuegen). Ist die Obergrenze erreicht, wird nichts abgetastet. Liefert true, wenn gestartet
--- oder sofort erledigt (Rueckfall/Obergrenze).
function Discovery.StartSeed(verbose)
    startGen = startGen + 1
    scan = nil
    stopFrame()
    if not Store.db or not entry() then return false end
    local s = { verbose = verbose == true, maps = {}, mapIndex = 1, cell = 0, hits = 0, mapHit = false,
        names = {}, used = 0 }
    Discovery.calls, Discovery.maxCallsPerFrame = 0, 0
    if s.verbose then ns.Print(L.ZONE_SEED_STARTED) end
    if Discovery.IsFull() then
        if not limitWarned then
            limitWarned = true
            ns.Print(L.ZONE_LIMIT_REACHED, Store.DISCOVERED_MAX)
        end
        Discovery.SetSeeded(true)
        return true
    end
    local maps = apisPresent() and zoneMaps() or nil
    if not maps then
        s.noApi = true
        finishScan(s, true)
        return true
    end
    s.maps = maps
    scan = s
    if not scanFrame then
        scanFrame = CreateFrame("Frame")
        scanFrame:SetScript("OnUpdate", onUpdate)
    end
    scanFrame:Show()
    return true
end

--- Abtastung abbrechen (Zonentext aus); seeded bleibt, wie es ist
function Discovery.StopSeed()
    startGen = startGen + 1
    scan = nil
    stopFrame()
end

local function zoneActive()
    local z = ns.Zone
    return z ~= nil and type(z.IsActive) == "function" and z.IsActive() == true
end

--- erster Start je Charakter: nach START_DELAY s abtasten, wenn der Zonentext an und die Liste nicht befuellt ist
function Discovery.ScheduleSeed()
    if scan or not Store.db or not zoneActive() then return end
    local e = entry()
    if not e or e.seeded == true then return end
    startGen = startGen + 1
    local mine = startGen
    C_Timer.After(Discovery.START_DELAY, function()
        if mine ~= startGen or scan then return end
        local cur = entry()
        if cur and cur.seeded ~= true and zoneActive() then Discovery.StartSeed(false) end
    end)
end

--- von Zone.Apply: Zonentext an => ggf. Befuellung einplanen; aus => laufende Abtastung beenden
function Discovery.OnApply(active)
    if active then Discovery.ScheduleSeed() else Discovery.StopSeed() end
end

Compat.TryOn("PLAYER_ENTERING_WORLD", function() Discovery.ScheduleSeed() end)
Compat.TryOn("PLAYER_REGEN_DISABLED", function() if scan then scan.combat = true end end)
Compat.TryOn("PLAYER_REGEN_ENABLED", function()
    if scan then
        scan.combat = nil
        scan.wait = 0
    end
end)
Compat.TryOn("LOADING_SCREEN_DISABLED", function() if scan then scan.wait = 0 end end)

-- /lucid zone seed: Abtastung erneut (nur Hinzufuegen, keine Rueckfrage); geht auch bei ausgeschaltetem Zonentext
ns.Zone.commands.seed = function()
    Discovery.StartSeed(true)
end
ns.AddHelp("HELP_ZONE_SEED")
