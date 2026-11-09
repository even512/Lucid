-- Element-Katalog (Spec 3.3): Aktionsleisten, Einheitenfenster, Minimap & Sonstiges.
--
-- Jedes Katalog-Element hat eine id und eine Namensliste mit Fallbacks. Ein Eintrag der Liste ist eine
-- Alternative: ein Frame-Name oder eine Liste von Namen, die zusammen das Element bilden. Die erste
-- Alternative, von der mindestens ein Frame existiert, gewinnt. Frames, die das Spiel erst spaet erzeugt
-- (Load-on-Demand, nach dem Login), werden bei ADDON_LOADED/PLAYER_ENTERING_WORLD nachtraeglich aufgeloest.
-- Was nach dem ersten PLAYER_ENTERING_WORLD fehlt, gilt als "in diesem Client nicht vorhanden" (geloggt,
-- abfragbar ueber GetStatus/List); taucht es spaeter doch auf, wird es noch angemeldet.
--
-- Beim Fader angemeldet ist ein Element nur, solange es im aktiven Profil eingeschaltet ist: ausgeschaltete
-- Elemente fasst Lucid gar nicht an (Standard nach Erstinstallation = alles aus). Lucid aendert an
-- Blizzard-Frames nur Alpha (und bei "Klicks durchlassen" ausserhalb des Kampfs die Maus), nie Show/Hide,
-- Position, Groesse oder Parent. Einzige Ausnahme: die (ungeschuetzte) Minimap wird bei Alpha 0 ganz versteckt
-- (MinimapExtras), weil die Engine Spielerpfeil und Questgebiete unabhaengig vom Alpha zeichnet.
--
-- Optionale Elemente (optional = true): Fremd-Addons (Questie, Gruppe "addons") und Blizzard-Teile, die nicht jeder Client
-- hat (Cooldown-Manager). Fehlen sie, gibt es keine Chat-Meldung, nur den Hinweis im Reiter ("<Addon> fehlt", mit addon =
-- Ordnername); Nachsuche bei ADDON_LOADED, alle 5 s (bis 24x) und beim Oeffnen des Reiters. Mehrfach-Elemente (multi = true,
-- genau eine Alternative): das Addon erzeugt Instanzen nachtraeglich (Details-Fenster 2+, VuhDo-Panels erst bei Bedarf). Ein
-- schon gefundenes Mehrfach-Element nimmt neu erschienene Frames seiner Liste nachtraeglich auf (Resolve/ResolveOptional,
-- zusaetzlich bei GROUP_ROSTER_UPDATE); angemeldet werden sie per Fader.AddFrames (nur Alpha, Maus nur ausserhalb des Kampfs).
-- Fremd-Frames fasst Lucid genauso an wie Blizzard-Frames: nur Alpha (und bei "Klicks durchlassen" ausserhalb des Kampfs die
-- Maus), nie Show/Hide/Position. Presets setzen die Gruppe "addons" nicht (siehe Presets.lua).
local _, ns = ...
local Fader, Store, Compat = ns.Fader, ns.Store, ns.Compat
local L = ns.L

local Elements = {}
ns.Elements = Elements

-- Standardwerte eines Elements ohne eigene Einstellung: aus; wird es eingeschaltet, verhaelt es sich wie
-- in "Immersion" (unsichtbar, Kampf/Ziel/Maus darueber blenden ein).
Elements.DEFAULTS = {
    enabled = false, baseAlpha = 0, fadeIn = 0.3, fadeOut = 0.8, delay = 2, clickThrough = true,
    conditions = { { state = "combat", alpha = 1 }, { state = "target", alpha = 1 }, { state = "mouseover", alpha = 1 } },
}

Elements.GROUPS = { "bars", "units", "misc", "addons" }

-- Namensliste je Nummer 1..n (mehrere Muster: { "A%d", "B%d" } => A1, B1, A2, B2, ...)
local function numbered(patterns, n)
    local out = {}
    for i = 1, n do
        for _, p in ipairs(patterns) do out[#out + 1] = p:format(i) end
    end
    return out
end

-- Cooldown-Manager (Blizzard_CooldownViewer): Blizzard zeigt/versteckt die Viewer selbst und setzt ihr Alpha ueber die
-- Deckkraft-Einstellung des Bearbeitungsmodus (UpdateSystemSettingOpacity) => verify.
local CD_VERIFY = { methods = { "Show", "SetShown", "UpdateShownState", "UpdateSystemSettingOpacity" } }

-- Katalog. Namen: zuerst Retail 12.x / Forever (12.1-Basis), dann aeltere Schreibweisen als Fallback.
-- noReapply: fuer Frames, die ihr Alpha selbst blenden (derzeit keiner bekannt, Handtest beobachtet das).
-- verify: Blizzard aendert das Alpha dieser Frames auch ohne SetAlpha (Leisten-Update bei XP-/Ruf-Gewinn, neue
-- Leiste, Layout) => Ist-Alpha regelmaessig und nach den genannten Events/Methoden gegen das Soll pruefen.
Elements.CATALOG = {
    -- Aktionsleisten (Nummern wie im Bearbeitungsmodus: 2 = unten links, 3 = unten rechts, 4 = rechts, 5 = links)
    { id = "mainbar", group = "bars", names = { "MainActionBar", "MainMenuBar" } },
    { id = "bar2", group = "bars", names = { "MultiBarBottomLeft" } },
    { id = "bar3", group = "bars", names = { "MultiBarBottomRight" } },
    { id = "bar4", group = "bars", names = { "MultiBarRight" } },
    { id = "bar5", group = "bars", names = { "MultiBarLeft" } },
    { id = "bar6", group = "bars", names = { "MultiBar5" } },
    { id = "bar7", group = "bars", names = { "MultiBar6" } },
    { id = "bar8", group = "bars", names = { "MultiBar7" } },
    { id = "stancebar", group = "bars", names = { "StanceBar", "StanceBarFrame" } },
    { id = "petbar", group = "bars", names = { "PetActionBar", "PetActionBarFrame" } },
    { id = "possessbar", group = "bars", names = { "PossessActionBar", "PossessBarFrame" } },
    { id = "micromenu", group = "bars", names = { "MicroMenuContainer", "MicroMenu", "MicroButtonAndBagsBar" } },
    { id = "bags", group = "bars", names = { "BagsBar", "MicroButtonAndBagsBar" } },
    -- Cooldown-Manager (Retail/Forever; optional: fehlt er, ist die Zeile ausgegraut, ohne Chat-Meldung)
    { id = "cdessential", group = "bars", names = { "EssentialCooldownViewer" }, optional = true, verify = CD_VERIFY },
    { id = "cdutility", group = "bars", names = { "UtilityCooldownViewer" }, optional = true, verify = CD_VERIFY },
    { id = "cdbufficons", group = "bars", names = { "BuffIconCooldownViewer" }, optional = true, verify = CD_VERIFY },
    { id = "cdbuffbars", group = "bars", names = { "BuffBarCooldownViewer" }, optional = true, verify = CD_VERIFY },
    -- Einheitenfenster (Ziel des Ziels gehoert zum Ziel, Ziel des Fokus zum Fokus)
    { id = "player", group = "units", names = { "PlayerFrame" } },
    { id = "target", group = "units", names = { { "TargetFrame", "TargetFrameToT" } } },
    { id = "focus", group = "units", names = { { "FocusFrame", "FocusFrameToT" } } },
    { id = "pet", group = "units", names = { "PetFrame" } },
    -- Minimap & Sonstiges
    { id = "minimap", group = "misc", names = { { "MinimapCluster", "Minimap" } } },
    { id = "tracker", group = "misc", names = { "ObjectiveTrackerFrame", "WatchFrame" } },
    -- Questies eigener Tracker (optional: nur mit geladenem Questie; Frame Questie_BaseFrame, Questie legt ihn ggf. spaet an
    -- und blendet ihn teils selbst => verify). Fehlt er, gibt es keine Chat-Meldung (optional), nur den Hinweis im Reiter.
    -- Lucid aendert nur Alpha und Maus, nie Show/Hide/Position (Questie zeigt/versteckt den Frame selbst).
    { id = "questietracker", group = "misc", names = { "Questie_BaseFrame" }, optional = true, addon = "Questie",
        verify = { methods = { "Show", "SetShown" } } },
    { id = "buffs", group = "misc", names = { "BuffFrame" } },
    { id = "debuffs", group = "misc", names = { "DebuffFrame" } },
    { id = "statusbars", group = "misc", names = {
        { "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" },
        "StatusTrackingBarManager",
        { "MainMenuExpBar", "ReputationWatchBar" },
    }, verify = {
        events = {
            "PLAYER_XP_UPDATE", "UPDATE_EXHAUSTION", "PLAYER_LEVEL_UP", "UPDATE_FACTION", "HONOR_XP_UPDATE",
            "ARTIFACT_XP_UPDATE", "AZERITE_ITEM_EXPERIENCE_CHANGED", "MAJOR_FACTION_RENOWN_LEVEL_CHANGED",
            "PLAYER_UPDATE_RESTING", "UPDATE_EXPANSION_LEVEL",
        },
        -- Methoden der Container bzw. des Managers (12.x/aeltere Namen; fehlende werden uebergangen)
        methods = { "Show", "SetShown", "Layout", "UpdateShownState", "SetShownBar", "UpdateBarsShown", "UpdateBarVisibility" },
        globals = { "StatusTrackingBarManager" },
    } },
    -- Fremd-Addons (Gruppe "addons", alle optional, Standard aus, von Presets unberuehrt). verify, wo das Addon Alpha/Show
    -- selbst setzt: RestedXP (Show/SetShown, Pfeil und Leisten SetAlpha), Details (Interaktions-/Kontext-Alpha), VuhDo
    -- (Panel-Alpha je Gruppe). VuhDo, Cell und HealBot sind geschuetzte Frames: nur SetAlpha, Maus nur ausserhalb des Kampfs.
    { id = "rxpguide", group = "addons", names = { { "RXPFrame", "RXPItemFrame", "RXPTargetFrame" } }, optional = true,
        addon = "RXPGuides", multi = true, verify = { methods = { "Show", "SetShown" } } },
    { id = "rxparrow", group = "addons", names = { "RXPG_ARROW" }, optional = true, addon = "RXPGuides",
        verify = { methods = { "Show", "SetShown" } } },
    -- Details: je Fenster Basis-Frame + Zeilen-Frame (Geschwister, nicht Kind), Fenster 1..10, auch spaeter erzeugte
    { id = "details", group = "addons", names = { numbered({ "DetailsBaseFrame%d", "DetailsRowFrame%d" }, 10) },
        optional = true, addon = "Details", multi = true, verify = { methods = { "Show", "SetShown" } } },
    -- VuhDo: Panels Vd1..Vd10, erst bei Bedarf erzeugt
    { id = "vuhdo", group = "addons", names = { numbered({ "Vd%d" }, 10) }, optional = true, addon = "VuhDo", multi = true,
        verify = { methods = { "Show", "SetShown" } } },
    { id = "grid2", group = "addons", names = { "Grid2LayoutFrame" }, optional = true, addon = "Grid2" },
    { id = "cell", group = "addons", names = { "CellMainFrame" }, optional = true, addon = "Cell" },
    { id = "healbot", group = "addons", names = { numbered({ "f%d_HealBot_Action" }, 10) }, optional = true,
        addon = "HealBot", multi = true },
}

Elements.BY_ID = {}
for i, entry in ipairs(Elements.CATALOG) do
    entry.order = i
    Elements.BY_ID[entry.id] = entry
end

-- Laufzeitstand je Element: status "pending" (noch nicht gesucht/geladen) | "found" | "missing"
local recs = {}       -- id -> { entry, status, frames, names, registered }
local claimed = {}    -- frame -> Element-id (ein Frame gehoert hoechstens einem Element)
local enabled = false -- Modul aktiv (nach PLAYER_LOGIN)
local checked = false -- erstes PLAYER_ENTERING_WORLD vorbei: Fehlendes gilt als nicht vorhanden
Elements.log = {}     -- Meldungen der Aufloesung (Diagnose)

for _, entry in ipairs(Elements.CATALOG) do
    recs[entry.id] = { entry = entry, status = "pending", registered = false }
end

local function log(fmt, ...)
    local entries = Elements.log
    if #entries >= 200 then table.remove(entries, 1) end
    entries[#entries + 1] = fmt:format(...)
end

-- Aufloesung -----------------------------------------------------------------------------------------
local function lookup(name)
    local f = _G[name]
    if type(f) == "table" and type(f.SetAlpha) == "function" and type(f.GetAlpha) == "function" then return f end
    return nil
end

local function isDescendant(f, of)
    local p = f.GetParent and f:GetParent()
    for _ = 1, 32 do
        if p == nil then return false end
        if p == of then return true end
        p = p.GetParent and p:GetParent()
    end
    return false
end

-- Frames einer Alternative: vorhandene, nicht von einem anderen Element belegte Frames; Kinder eines
-- anderen Frames derselben Alternative fallen weg (Alpha vererbt sich, sonst wuerde es doppelt wirken).
local function resolveAlternative(id, alt)
    local list = type(alt) == "table" and alt or { alt }
    local found, names = {}, {}
    for _, name in ipairs(list) do
        local f = lookup(name)
        if f and (claimed[f] == nil or claimed[f] == id) then
            found[#found + 1] = f
            names[#names + 1] = name
        end
    end
    local frames, used = {}, {}
    for i, f in ipairs(found) do
        local nested = false
        for j, g in ipairs(found) do
            if i ~= j and isDescendant(f, g) then nested = true break end
        end
        if not nested then
            frames[#frames + 1] = f
            used[#used + 1] = names[i]
        end
    end
    return frames, used
end

local function resolve(rec)
    for _, alt in ipairs(rec.entry.names) do
        local frames, used = resolveAlternative(rec.entry.id, alt)
        if #frames > 0 then return frames, used end
    end
    return nil
end

-- Mehrfach-Element um neu erschienene Frames seiner Liste erweitern (siehe Kopf). Liefert true, wenn Frames hinzukamen.
-- Ist das Element angemeldet, bekommt der Fader sie per AddFrames (dazu die verify-Hooks).
local hookVerify -- unten definiert
local function growMulti(rec)
    local id = rec.entry.id
    local frames, used = resolveAlternative(id, rec.entry.names[1])
    local have = {}
    for _, f in ipairs(rec.frames) do have[f] = true end
    local new = {}
    for i, f in ipairs(frames) do
        if not have[f] then
            new[#new + 1] = f
            rec.frames[#rec.frames + 1] = f
            rec.names[#rec.names + 1] = used[i]
            claimed[f] = id
            log("%s: %s (nachgemeldet)", id, used[i])
        end
    end
    if #new == 0 then return false end
    if rec.registered then
        Fader.AddFrames(id, new)
        local v = rec.entry.verify
        if v then
            for _, f in ipairs(new) do hookVerify(f, id, v.methods or {}) end
        end
    end
    return true
end

-- Einstellungen ------------------------------------------------------------------------------------
--- wirksame Einstellungen (Profil > Katalog-Standard > Fader-Standard)
function Elements.GetConfig(id)
    if not Elements.BY_ID[id] then return nil end
    return Fader.GetConfig(id, Elements.DEFAULTS)
end

function Elements.IsEnabled(id)
    local cfg = Elements.GetConfig(id)
    return cfg ~= nil and cfg.enabled
end

-- naechstes Element, in dessen Frame dieses Element steckt (z. B. PetFrame im PlayerFrame), oder nil
local function findParent(rec)
    local id = rec.entry.id
    local f = rec.frames and rec.frames[1]
    local p = f and f.GetParent and f:GetParent()
    for _ = 1, 32 do
        if p == nil then return nil end
        local c = claimed[p]
        if c ~= nil and c ~= id then return c end
        p = p.GetParent and p:GetParent()
    end
    return nil
end

-- Zusatz je Element nach jedem gesetzten Alpha (Fader opts.onAlpha)
-- Tracker/Questie-Tracker: ein angedockter Ink-&-Embers-Zettel blendet mit (modules/Hide/InkDock.lua)
local function followDock(id)
    return function(a) if ns.InkDock then ns.InkDock.OnAlpha(id, a) end end
end
local ON_ALPHA = {
    minimap = function(a) if ns.MinimapExtras then ns.MinimapExtras.Update(a) end end,
    tracker = followDock("tracker"),
    questietracker = followDock("questietracker"),
}

-- Elemente, deren Mouseover-Liste weitere Frames aufnehmen darf (angedockter Zettel, InkDock): eigene Liste je Element,
-- anfangs die Element-Frames; der Fader haelt den Verweis, spaeter hinzugefuegte Frames zaehlen sofort mit.
local MOUSE_EXTRA = { tracker = true, questietracker = true }
local function mouseList(rec)
    if not MOUSE_EXTRA[rec.entry.id] or not rec.frames then return nil end
    if not rec.mouseFrames then
        rec.mouseFrames = {}
        for i, f in ipairs(rec.frames) do rec.mouseFrames[i] = f end
    end
    return rec.mouseFrames
end

--- weiteren Frame zur Mouseover-Erkennung des Elements hinzufuegen (nur tracker/questietracker). true bei Erfolg.
function Elements.AddMouseFrame(id, f)
    local list = recs[id] and mouseList(recs[id])
    if not list or type(f) ~= "table" then return false end
    for _, g in ipairs(list) do
        if g == f then return true end
    end
    list[#list + 1] = f
    return true
end

--- Frame wieder aus der Mouseover-Erkennung nehmen (die Element-Frames selbst bleiben)
function Elements.RemoveMouseFrame(id, f)
    local rec = recs[id]
    local list = rec and rec.mouseFrames
    if not list then return end
    for _, g in ipairs(rec.frames or {}) do
        if g == f then return end
    end
    for i = #list, 1, -1 do
        if list[i] == f then table.remove(list, i) end
    end
end

-- Pruef-Ausloeser (Katalog: verify): nach Events/Methoden sofort und einen Frame spaeter pruefen (Blizzards eigene
-- Handler laufen ggf. erst nach dem von Lucid). Hooks einmal je Frame/Methode, nur Nachher-Hooks (hooksecurefunc).
local verifyHooked = {}  -- table -> { methode = true }
local verifyEvents = {}  -- "event|id" -> true
local verifyQueued = {}  -- id -> true: Pruefung im naechsten Frame geplant

local function verifyNow(id)
    local rec = recs[id]
    if rec and rec.registered then Fader.Verify(id) end
end

local function verifySoon(id)
    verifyNow(id)
    if verifyQueued[id] or not (C_Timer and C_Timer.After) then return end
    verifyQueued[id] = true
    C_Timer.After(0, function()
        verifyQueued[id] = nil
        verifyNow(id)
    end)
end

function hookVerify(t, id, methods)
    if type(t) ~= "table" or not hooksecurefunc then return end
    local done = verifyHooked[t] or {}
    verifyHooked[t] = done
    for _, m in ipairs(methods) do
        if not done[m] and type(t[m]) == "function" then
            if pcall(hooksecurefunc, t, m, function() verifySoon(id) end) then done[m] = true end
        end
    end
    if not done.OnShow and type(t.HookScript) == "function" then
        if pcall(t.HookScript, t, "OnShow", function() verifySoon(id) end) then done.OnShow = true end
    end
end

local function setupVerify(rec)
    local v = rec.entry.verify
    if not v then return end
    local id = rec.entry.id
    for _, f in ipairs(rec.frames) do hookVerify(f, id, v.methods or {}) end
    for _, name in ipairs(v.globals or {}) do
        local g = _G[name]
        if type(g) == "table" and not claimed[g] then hookVerify(g, id, v.methods or {}) end
    end
    for _, e in ipairs(v.events or {}) do
        if not verifyEvents[e .. "|" .. id] then
            verifyEvents[e .. "|" .. id] = true
            Compat.TryOn(e, function() verifySoon(id) end)
        end
    end
end

-- Fader-Anmeldung an den Profilstand angleichen
local function sync(rec)
    if not rec.frames then return end
    local id = rec.entry.id
    local want = enabled and Elements.IsEnabled(id)
    if want and not rec.registered then
        local ok = xpcall(function()
            Fader.Register(id, rec.frames, Elements.DEFAULTS, {
                noReapply = rec.entry.noReapply == true,
                -- Klicks durchlassen mit Kind-Frames nur, wo die Knoepfe die Maus tragen (Leisten, Mikromenue,
                -- Taschen) und bei Minimap/Tracker/Buffs (Minimap, Tracker-Bloecke, Aura-Knoepfe sind Kinder).
                -- Einheitenfenster: nur der Haupt-Frame (Secure-Unit-Button). Ihr Inneres (Lebens-/Ressourcenleisten,
                -- Auren, Zauberleiste, PowerBarAlt) liefert in 12.x Secret Values und wird von Blizzard wiederverwendet;
                -- EnableMouse am Haupt-Frame ist ausserhalb des Kampfs erlaubt und wird vor dem Lockdown zurueckgesetzt.
                mouseChildren = rec.entry.group ~= "units",
                -- Frames eines anderen Elements (PetFrame im PlayerFrame) fasst "Klicks durchlassen" nie an
                mouseExclude = function(frame)
                    local c = claimed[frame]
                    return c ~= nil and c ~= id
                end,
                parent = rec.parent, -- Alpha-Ausgleich fuer verschachtelte Elemente (Fader: outAlpha)
                onAlpha = ON_ALPHA[id], -- z. B. Minimap: bei Alpha 0 ganz verstecken (Pfeil/Questgebiete)
                mouseFrames = mouseList(rec), -- Tracker: angedockter Zettel zaehlt fuer "Maus darueber"
                verify = rec.entry.verify ~= nil, -- regelmaessig Ist- gegen Soll-Alpha pruefen
            })
        end, geterrorhandler())
        rec.registered = ok
        if ok then xpcall(setupVerify, geterrorhandler(), rec) end
    elseif not want and rec.registered then
        rec.registered = false
        Fader.Unregister(id)
    elseif rec.registered then
        Fader.Refresh(id)
    end
    -- Zettel an-/abmelden (Element ein/aus, Einstellung); gekapselt: ein Fehler darf SyncAll nicht abbrechen
    if MOUSE_EXTRA[id] and ns.InkDock then
        local ok, err = pcall(ns.InkDock.Sync)
        if not ok then geterrorhandler()(err) end
    end
end

--- alle Elemente an das aktive Profil angleichen (nach Preset, Profilwechsel, Aenderung)
function Elements.SyncAll()
    for _, entry in ipairs(Elements.CATALOG) do sync(recs[entry.id]) end
end

--- noch nicht gefundene Elemente erneut suchen (z. B. nach ADDON_LOADED eines Blizzard-Moduls)
function Elements.Resolve()
    local fresh = {}
    for _, entry in ipairs(Elements.CATALOG) do
        local rec = recs[entry.id]
        if not rec.frames then
            local frames, used = resolve(rec)
            if frames then
                local was = rec.status
                rec.frames, rec.names, rec.status = frames, used, "found"
                for _, f in ipairs(frames) do claimed[f] = entry.id end
                log("%s: %s%s", entry.id, table.concat(used, ", "), was == "missing" and " (spaet)" or "")
                fresh[rec] = true
            end
        elseif entry.multi then
            growMulti(rec)
        end
    end
    -- Verschachtelung bestimmen, bevor angemeldet wird (ein spaet gefundenes Element kann Eltern eines anderen
    -- sein); aendert sie sich bei einem schon angemeldeten Element, wird es mit dem neuen Eltern neu angemeldet.
    for _, entry in ipairs(Elements.CATALOG) do
        local rec = recs[entry.id]
        if rec.frames then
            local parent = findParent(rec)
            if parent ~= rec.parent then
                rec.parent = parent
                if rec.registered then
                    rec.registered = false
                    Fader.Unregister(entry.id)
                    fresh[rec] = true
                end
            end
        end
    end
    for _, entry in ipairs(Elements.CATALOG) do
        if fresh[recs[entry.id]] then sync(recs[entry.id]) end
    end
end

-- Optionale Elemente (Fremd-Addons wie Questie) entstehen ggf. erst lange nach dem Login: bis zu 24 Nachsuchen im Abstand von
-- 5 s, dazu eine billige Nachsuche beim Oeffnen/Aktualisieren des Reiters (Elements.List) und bei ADDON_LOADED.
local function optionalPending()
    for _, entry in ipairs(Elements.CATALOG) do
        if entry.optional and not recs[entry.id].frames then return true end
    end
    return false
end

local optionalTries, optionalQueued = 0, false
local function scheduleOptional()
    if optionalQueued or optionalTries >= 24 or not optionalPending() then return end
    if not (C_Timer and C_Timer.After) then return end
    optionalQueued = true
    optionalTries = optionalTries + 1
    C_Timer.After(5, function()
        optionalQueued = false
        if enabled then Elements.Resolve() end
        scheduleOptional()
    end)
end

--- Optionale Elemente nachsuchen, falls ihr Frame inzwischen existiert (nil-Pruefung, billig)
--- Mehrfach-Elemente: auch, wenn ein noch keinem Element gehoerender Frame ihrer Liste erschienen ist.
function Elements.ResolveOptional()
    if not enabled then return end
    for _, entry in ipairs(Elements.CATALOG) do
        local rec = recs[entry.id]
        if entry.optional and not rec.frames then
            for _, alt in ipairs(entry.names) do
                local list = type(alt) == "table" and alt or { alt }
                for _, name in ipairs(list) do
                    if lookup(name) then return Elements.Resolve() end
                end
            end
        elseif entry.multi and rec.frames then
            for _, name in ipairs(entry.names[1]) do
                local f = lookup(name)
                if f and claimed[f] == nil then return Elements.Resolve() end
            end
        end
    end
end

-- nach dem ersten Ladebildschirm: was fehlt, gibt es in diesem Client nicht (Meldung einmal im Chat)
local function markMissing()
    local missing = {}
    for _, entry in ipairs(Elements.CATALOG) do
        local rec = recs[entry.id]
        local tried = {}
        for _, alt in ipairs(entry.names) do
            tried[#tried + 1] = type(alt) == "table" and table.concat(alt, "+") or alt
        end
        if rec.status == "pending" and entry.optional then
            rec.status = "missing" -- optionale Elemente (Fremd-Addon): still, ohne Chat-Meldung; Nachsuche bleibt aktiv
            log("%s: nicht vorhanden (optional, gesucht: %s)", entry.id, table.concat(tried, " / "))
        elseif rec.status == "pending" then
            rec.status = "missing"
            missing[#missing + 1] = entry.id
            log("%s: nicht vorhanden (gesucht: %s)", entry.id, table.concat(tried, " / "))
        end
    end
    if #missing > 0 then ns.Print(L.ELEMENTS_MISSING, #missing, table.concat(missing, ", ")) end
end

-- Abfrage-API (fuer /lucid status und das Konfig-Fenster) -----------------------------------------
--- "pending" | "found" | "missing" oder nil fuer unbekannte id
function Elements.GetStatus(id)
    local rec = recs[id]
    return rec and rec.status
end

--- true, wenn das Element in diesem Client vorhanden ist (false auch, solange noch nicht gesucht)
function Elements.IsAvailable(id) return Elements.GetStatus(id) == "found" end

--- true, wenn Lucid das Element gerade steuert (eingeschaltet und gefunden)
function Elements.IsActive(id)
    local rec = recs[id]
    return rec ~= nil and rec.registered
end

--- true, wenn das genannte Addon geladen ist (nil-sicher; ohne Namen: true)
function Elements.AddonLoaded(name)
    if name == nil then return true end
    local fn = (_G.C_AddOns and _G.C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
    if type(fn) ~= "function" then return false end
    local ok, res = pcall(fn, name)
    return ok and Compat.Bool(res) == true
end

--- Katalog mit Laufzeitstand, in Katalog-Reihenfolge:
--- { id, group, status, enabled, active, parent = Eltern-Element-id|nil, frames = { Frame-Name, ... } }
function Elements.List()
    Elements.ResolveOptional()
    if ns.InkDock then ns.InkDock.Poke() end -- Ink-&-Embers-Zettel nachsuchen (billig)
    local out = {}
    for _, entry in ipairs(Elements.CATALOG) do
        local rec = recs[entry.id]
        local names = {}
        for i, n in ipairs(rec.names or {}) do names[i] = n end
        out[#out + 1] = {
            id = entry.id, group = entry.group, status = rec.status,
            enabled = Elements.IsEnabled(entry.id), active = rec.registered, parent = rec.parent, frames = names,
            optional = entry.optional == true, addon = entry.addon, addonLoaded = Elements.AddonLoaded(entry.addon),
        }
    end
    return out
end

function Elements.Label(id) return L["ELEMENT_" .. id] end

-- Aendern ------------------------------------------------------------------------------------------
local function activeElements()
    local p = Store.GetActive()
    if type(p.elements) ~= "table" then p.elements = {} end
    return p.elements
end

--- eine Einstellung eines Elements im aktiven Profil setzen (geprueft wie beim Import) und sofort anwenden.
--- Liefert true oder nil, Code ("ELEMENT_UNKNOWN" | "ELEMENT_VALUE_INVALID").
function Elements.Set(id, key, value)
    if not Elements.BY_ID[id] then return nil, "ELEMENT_UNKNOWN" end
    local list = activeElements()
    local candidate = Store.DeepCopy(type(list[id]) == "table" and list[id] or {})
    candidate[key] = Store.DeepCopy(value)
    local clean = Fader.ValidateElements({ [id] = candidate })
    if not clean or clean[id][key] == nil then return nil, "ELEMENT_VALUE_INVALID" end
    list[id] = clean[id]
    sync(recs[id])
    return true
end

--- Element ein-/ausschalten; ohne Wert umschalten. Liefert den neuen Zustand oder nil, Code.
function Elements.SetEnabled(id, on)
    if not Elements.BY_ID[id] then return nil, "ELEMENT_UNKNOWN" end
    if on == nil then on = not Elements.IsEnabled(id) end
    local ok, code = Elements.Set(id, "enabled", on and true or false)
    if not ok then return nil, code end
    return on and true or false
end

--- Zeitwert (fadeIn | fadeOut | delay) fuer ALLE Katalog-Elemente des aktiven Profils setzen, auch fuer ausgeschaltete.
--- Der Wert wird vorab mit der Element-Validierung geprueft; bei Fehler wird nichts geaendert. Einzelwerte bleiben
--- danach einzeln aenderbar. Liefert Anzahl der Elemente und den gesetzten (ggf. auf den Bereich geklemmten) Wert
--- oder nil, Code ("ELEMENT_VALUE_INVALID").
Elements.TIME_KEYS = { fadeIn = true, fadeOut = true, delay = true }
function Elements.SetAllTimes(key, value)
    if not Elements.TIME_KEYS[key] or type(value) ~= "number" or value ~= value then return nil, "ELEMENT_VALUE_INVALID" end
    local probe = Fader.ValidateElements({ probe = { [key] = value } })
    if not probe or probe.probe[key] == nil then return nil, "ELEMENT_VALUE_INVALID" end
    local n = 0
    for _, entry in ipairs(Elements.CATALOG) do
        local ok = Elements.Set(entry.id, key, probe.probe[key])
        if ok then n = n + 1 end
    end
    return n, probe.probe[key]
end

-- Modul + Ereignisse ------------------------------------------------------------------------------
ns.RegisterModule("hide", {
    OnEnable = function()
        enabled = true
        Elements.Resolve()
        Elements.SyncAll()
    end,
    OnDisable = function()
        enabled = false
        Elements.SyncAll() -- meldet alles ab: Alpha und Maus zurueck
    end,
})

-- spaet erzeugte Frames (Blizzard-Module laden nach)
ns.On("ADDON_LOADED", function(_, name)
    if enabled then
        Elements.Resolve()
        -- ein optionales Fremd-Addon ist geladen: Nachsuche neu starten (es legt seine Frames ggf. erst spaeter an)
        for _, entry in ipairs(Elements.CATALOG) do
            if entry.addon ~= nil and entry.addon == name then optionalTries = 0 break end
        end
        scheduleOptional()
    end
end)

ns.On("PLAYER_ENTERING_WORLD", function()
    if not enabled then return end
    Elements.Resolve()
    if not checked then
        checked = true
        markMissing()
    end
    scheduleOptional()
end)

-- Gruppenwechsel: Heil-Addons erzeugen Panels erst jetzt (VuhDo), neue Instanzen nachmelden (billig). Manche Addons legen
-- ihre Frames erst nach dem Event (bzw. nach Kampfende) an: einmal verzoegert nachsuchen (entprellt), nur wenn ein
-- Mehrfach-Element gerade angemeldet ist.
Elements.MULTI_DELAY = 2
local multiQueued = false
local function multiActive()
    for _, entry in ipairs(Elements.CATALOG) do
        if entry.multi and recs[entry.id].registered then return true end
    end
    return false
end
local function resolveMultiLater()
    if multiQueued or not enabled or not multiActive() or not (C_Timer and C_Timer.After) then return end
    multiQueued = true
    C_Timer.After(Elements.MULTI_DELAY, function()
        multiQueued = false
        Elements.ResolveOptional()
    end)
end
Compat.TryOn("GROUP_ROSTER_UPDATE", function()
    Elements.ResolveOptional()
    resolveMultiLater()
end)
Compat.TryOn("PLAYER_REGEN_ENABLED", resolveMultiLater)

-- Profilwechsel/-import/-reset: Fader hat angemeldete Elemente schon aufgefrischt; hier an-/abmelden
Store.RegisterCallback(function()
    if enabled then Elements.SyncAll() end
end)

-- Slash: /lucid toggle <element>, /lucid status --------------------------------------------------
-- Eingaben nur als Katalog-id verwenden; fremder Text wird vor der Ausgabe entschaerft ("|" verdoppelt).
local function safe(s) return (tostring(s):gsub("|", "||")) end

local function idList()
    local ids = {}
    for _, entry in ipairs(Elements.CATALOG) do ids[#ids + 1] = entry.id end
    return table.concat(ids, ", ")
end

ns.commands.toggle = function(rest)
    local id = (rest or ""):lower():match("^%s*(%S*)")
    if id == "" or not Elements.BY_ID[id] then
        if id ~= "" then ns.Print(L.ELEMENT_UNKNOWN, safe(id)) end
        ns.Print(L.ELEMENT_LIST, idList())
        return
    end
    local on, code = Elements.SetEnabled(id)
    if on == nil then
        ns.Print(L[code or "ELEMENT_VALUE_INVALID"], safe(id))
        return
    end
    ns.Print(on and L.ELEMENT_TOGGLED_ON or L.ELEMENT_TOGGLED_OFF, Elements.Label(id))
    if Elements.GetStatus(id) == "missing" then ns.Print(L.ELEMENT_NOT_IN_CLIENT, Elements.Label(id)) end
end

ns.commands.status = function()
    ns.Print(L.STATUS_HEADER, safe(Store.GetActiveName()))
    for _, e in ipairs(Elements.List()) do
        local word
        if e.status == "missing" then word = L.STATUS_MISSING
        elseif e.status == "pending" then word = L.STATUS_PENDING
        elseif e.active then word = L.STATUS_ON
        elseif e.enabled then word = L.STATUS_FAILED -- gefunden, aber Anmeldung fehlgeschlagen (Fehler gemeldet)
        else word = L.STATUS_OFF end
        ns.Print(L.STATUS_LINE, e.id, Elements.Label(e.id), word)
    end
end

--- /lucid delay <sek>: Verzoegerung fuer alle Elemente
ns.commands.delay = function(rest)
    local arg = (rest or ""):match("^%s*(%S+)%s*$")
    local v = arg and tonumber((arg:gsub(",", ".")))
    local n, applied
    if v then n, applied = Elements.SetAllTimes("delay", v) end
    if not n then
        ns.Print(L.DELAY_INVALID, safe((arg or ""):gsub("%c", ""):sub(1, 20)), Fader.MAX_TIME)
        return
    end
    ns.Print(L.DELAY_ALL_SET, n, ("%g"):format(applied))
end

ns.AddHelp("HELP_TOGGLE")
ns.AddHelp("HELP_DELAY")
ns.AddHelp("HELP_STATUS")
