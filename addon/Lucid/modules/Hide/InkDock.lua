-- Ink-&-Embers-Zettel am Quest-Tracker (Mitlaeufer): Ink & Embers kann seinen To-do-Zettel (Frame EveNChronicleTodoDock, auf
-- UIParent, bewusst NICHT am Tracker geankert) unter/ueber den Quest-Tracker andocken. Blendet Lucid den Tracker aus, soll der
-- Zettel mit ihm ein- und ausblenden, als waere er Teil davon.
--  - Ziel: dieselbe Rangfolge wie Ink & Embers (nur lesend): Kaliels Tracker, Questie_BaseFrame, Blizzards Tracker; das erste
--    sichtbare (IsVisible) gewinnt, sonst das zuletzt gesehene. Questie => Element questietracker, Blizzard => Element tracker,
--    Kaliel ist kein Lucid-Element => Lucid tut nichts. Ein Frame gehoert nie zwei Elementen: der Zettel folgt hoechstens einem.
--  - Der Zettel uebernimmt das Alpha des Elements (Elements ON_ALPHA => InkDock.OnAlpha); sein Ausgangs-Alpha wird gemerkt und
--    beim Zielwechsel, Abschalten des Elements oder Lucids zurueckgesetzt. Fremde Alpha-Aenderungen werden korrigiert (Hook + Abgleich).
--  - Mouseover ueber dem Zettel zaehlt fuer das Tracker-Element (Elements.AddMouseFrame): Hover blendet Tracker samt Zettel ein.
--  - "Klicks durchlassen" wie beim Tracker-Element: bei Alpha 0 (und eingeschaltetem Haken) Maus am Zettel und seinen Kindern
--    aus, nie im Kampf (InCombatLockdown => pending, PLAYER_REGEN_ENABLED zieht nach), nie im Bearbeitungsmodus.
--  - Ink & Embers erzeugt den Zettel spaet/erst bei aktivierter Option und baut ihn nicht neu auf (Show/Hide desselben Frames, das
--    Alpha bleibt): gesucht wird bei Laden von Ink & Embers/PLAYER_ENTERING_WORLD, beim Oeffnen des Reiters und per begrenzter
--    Nachsuche; fehlt er, gibt es keine Meldung. Ist er da, gleicht ein leichter Abgleich (alle 0,5 s) Zielwechsel und Alpha ab.
--  Lucid aendert am Zettel nur Alpha und Maus, nie Show/Hide/Position/Parent. Zustandsabfragen ueber Compat (Secret Values).
local _, ns = ...
local Fader, State, Compat, Elements = ns.Fader, ns.State, ns.Compat, ns.Elements

local InkDock = {}
ns.InkDock = InkDock

InkDock.FRAME = "EveNChronicleTodoDock"
-- Reihenfolge wie Ink & Embers (TodoDock.lua, Dock.TARGETS); element = Lucid-Katalog-id (nil = kein Lucid-Element)
InkDock.TARGETS = {
    { kind = "kaliel", name = "!KalielsTrackerFrame" },
    { kind = "kaliel", name = "KT_ObjectiveTrackerFrame" },
    { kind = "questie", name = "Questie_BaseFrame", element = "questietracker" },
    { kind = "blizzard", name = "ObjectiveTrackerFrame", element = "tracker" },
    { kind = "blizzard", name = "WatchFrame", element = "tracker" },
    { kind = "blizzard", name = "QuestWatchFrame", element = "tracker" },
}
InkDock.POLL = 0.5          -- Abgleich (Ziel, Alpha, Maus) in Sekunden, solange der Zettel existiert
InkDock.SEARCH_FAST = 24    -- Nachsuchen im Abstand von 5 s ...
InkDock.SEARCH_SLOW = 40    -- ... danach im Abstand von 30 s (Laden von Ink & Embers / Reiter oeffnen beginnt von vorn)
local EPS = 0.001

local enabled = false
local follow            -- { frame, id, orig, alpha, mouseOff = {frame -> Zustand}, mouseIsOff, mousePending }
local lastName          -- zuletzt gewaehltes Ziel (wenn keines sichtbar ist)
local applying = false  -- eigenes SetAlpha laeuft (Hook bleibt still)
local hooked = {}       -- frame -> true (SetAlpha-Hook; Hooks lassen sich nicht entfernen)
local hookedShow = {}   -- frame -> true (OnShow-Hook)
local ticker
local tries, queued = 0, false
local orphans = {}      -- Maus-Zustaende abgegebener Zettel, die erst nach dem Kampf zurueck duerfen

local function lockdown() return InCombatLockdown and InCombatLockdown() end

local function dockFrame()
    local f = rawget(_G, InkDock.FRAME)
    if type(f) == "table" and type(f.SetAlpha) == "function" and type(f.GetAlpha) == "function" then return f end
    return nil
end

-- Ziel -----------------------------------------------------------------------------------------------
local function visible(f)
    local v
    if type(f.IsVisible) == "function" then v = Compat.QueryBool(f, "IsVisible") else v = Compat.QueryBool(f, "IsShown") end
    return v == true
end

--- Tracker, an dem Ink & Embers den Zettel gerade andockt: { kind, name, frame, element } oder nil (nur lesend)
function InkDock.Target()
    local found = {}
    for _, c in ipairs(InkDock.TARGETS) do
        local f = rawget(_G, c.name)
        if type(f) == "table" then found[#found + 1] = { kind = c.kind, name = c.name, frame = f, element = c.element } end
    end
    local pick
    for _, t in ipairs(found) do
        if visible(t.frame) then pick = t break end
    end
    -- keiner sichtbar (keine Quests, Tracker aus): beim zuletzt gesehenen bleiben, sonst der erste der Rangfolge
    if not pick and lastName then
        for _, t in ipairs(found) do
            if t.name == lastName then pick = t break end
        end
    end
    pick = pick or found[1]
    if pick then lastName = pick.name end
    return pick
end

-- Alpha ------------------------------------------------------------------------------------------------
local function setAlpha(f, a)
    applying = true
    local ok, err = pcall(f.SetAlpha, f, a)
    applying = false
    if not ok then geterrorhandler()(err) end
end

local function onSetAlpha(f, a)
    if applying or not follow or follow.frame ~= f then return end
    if Compat.IsSecret(a) or type(a) ~= "number" or math.abs(a - follow.alpha) > EPS then setAlpha(f, follow.alpha) end
end

-- Maus ---------------------------------------------------------------------------------------------------
-- Zettel und Kind-Frames (Kopf, Knopf, Zeilen), nur lesend und nur ausserhalb des Lockdowns; verbotene Frames bleiben unberuehrt
local function mouseTargets(root)
    local out, seen = {}, {}
    local function add(f, depth)
        if type(f) ~= "table" or seen[f] or #out >= Fader.MOUSE_MAX then return end
        seen[f] = true
        if f.IsForbidden and Compat.QueryBool(f, "IsForbidden") ~= false then return end
        out[#out + 1] = f
        if depth < Fader.MOUSE_DEPTH and f.GetChildren then
            local ok, kids = pcall(function() return { f:GetChildren() } end)
            if ok then
                for i = 1, #kids do add(kids[i], depth + 1) end
            end
        end
    end
    add(root, 0)
    return out
end

local function wantMouseOff()
    if not follow or follow.alpha > EPS or Fader.IsEditMode() or State.Get("combat") then return false end
    local cfg = Elements.GetConfig(follow.id)
    return cfg ~= nil and cfg.clickThrough
end

local function restoreList(list)
    local firstErr
    for f, st in pairs(list) do
        list[f] = nil
        local ok, err = pcall(Fader.RestoreMouse, f, st)
        if not ok then firstErr = firstErr or err end
    end
    if firstErr then geterrorhandler()(firstErr) end
end

-- force: Maus unbedingt wieder an (Kampfbeginn). Kein EnableMouse im Kampf (pending, Kampfende zieht nach).
local function updateMouse(force)
    local fl = follow
    if not fl then return end
    local want = not force and wantMouseOff() and true or false
    if not want and not fl.mouseIsOff then
        fl.mousePending = false
        return
    end
    if lockdown() then
        fl.mousePending = true
        return
    end
    fl.mousePending = false
    local firstErr
    if want then
        -- Maus schon aus: nur neu durchsuchen, wenn der Zettel neue Kind-Frames (Zeilen) bekommen hat (billige Zaehlung)
        local kids = fl.frame.GetChildren and select("#", fl.frame:GetChildren()) or 0
        if fl.mouseIsOff and kids == fl.kids then return end
        fl.kids = kids
        -- bereits abgeschaltete Frames haben IsMouseEnabled false und werden nicht doppelt gemerkt
        for _, f in ipairs(mouseTargets(fl.frame)) do
            if f.EnableMouse and Compat.QueryBool(f, "IsMouseEnabled") == true then
                local st = Fader.MouseState(f)
                if st then
                    local ok, err = pcall(f.EnableMouse, f, false)
                    if ok then fl.mouseOff[f] = st else firstErr = firstErr or err end
                end
            end
        end
    else
        restoreList(fl.mouseOff)
    end
    fl.mouseIsOff = want
    if not want then fl.kids = nil end
    if firstErr then geterrorhandler()(firstErr) end
end

-- Mitlaeufer an-/abmelden --------------------------------------------------------------------------------
local function release()
    local fl = follow
    if not fl then return end
    follow = nil
    Elements.RemoveMouseFrame(fl.id, fl.frame)
    setAlpha(fl.frame, fl.orig)
    if next(fl.mouseOff) then
        if lockdown() then
            orphans[#orphans + 1] = fl.mouseOff
        else
            restoreList(fl.mouseOff)
        end
    end
end

local function apply(a)
    follow.alpha = a
    setAlpha(follow.frame, a)
    updateMouse()
end

local function take(f, id)
    local ok, a0 = pcall(f.GetAlpha, f)
    a0 = ok and Compat.Num(a0) or nil -- Secret/unlesbar: Ausgangswert 1
    follow = {
        frame = f, id = id, orig = (a0 and a0 >= 0 and a0 <= 1) and a0 or 1, alpha = 1, mouseOff = {}, mouseIsOff = false,
    }
    if not hooked[f] and hooksecurefunc and pcall(hooksecurefunc, f, "SetAlpha", onSetAlpha) then hooked[f] = true end
    follow.listed = Elements.AddMouseFrame(id, f)
    apply(Fader.GetAlpha(id) or 1)
end

--- Alpha-Weitergabe des Elements (Elements ON_ALPHA): id = Katalog-id, a = gesetzter Wert
function InkDock.OnAlpha(id, a)
    if follow and follow.id == id and type(a) == "number" and a == a then apply(a) end
end

-- Abgleich ---------------------------------------------------------------------------------------------
local scheduleSearch

local function stopTicker()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
end

local function poll()
    local ok, err = pcall(InkDock.Sync)
    if not ok then geterrorhandler()(err) end
end

--- Ziel, Alpha und Maus abgleichen (Ereignisse, Poll, Elemente an-/abgemeldet)
function InkDock.Sync()
    if not enabled then
        release()
        stopTicker()
        return
    end
    local f = dockFrame()
    if not f then
        release()
        stopTicker()
        scheduleSearch()
        return
    end
    if not hookedShow[f] and type(f.HookScript) == "function" then
        -- Ink & Embers zeigt/versteckt denselben Frame: beim Zeigen sofort abgleichen
        if pcall(f.HookScript, f, "OnShow", poll) then hookedShow[f] = true end
    end
    local t = InkDock.Target()
    local id = t and t.element
    if id and not Elements.IsActive(id) then id = nil end
    if follow and (follow.frame ~= f or follow.id ~= id) then release() end
    if id and not follow then take(f, id) end
    if follow then
        if not follow.listed then follow.listed = Elements.AddMouseFrame(follow.id, f) end -- Mouseover-Liste nachziehen
        local ok, a = pcall(f.GetAlpha, f)
        a = ok and Compat.Num(a) or nil -- Secret/unlesbar: gilt als fremder Wert
        if not a or math.abs(a - follow.alpha) > EPS then setAlpha(f, follow.alpha) end
        updateMouse()
    end
    if not ticker and C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(InkDock.POLL, poll) end
end

-- Der Zettel entsteht ggf. erst lange nach dem Login (Option in Ink & Embers): begrenzte Nachsuche
function scheduleSearch()
    local max = InkDock.SEARCH_FAST + InkDock.SEARCH_SLOW
    if queued or tries >= max or not (C_Timer and C_Timer.After) then return end
    queued = true
    tries = tries + 1
    C_Timer.After(tries <= InkDock.SEARCH_FAST and 5 or 30, function()
        queued = false
        if enabled then poll() end
    end)
end

--- billige Nachsuche (Reiter geoeffnet, Ink & Embers geladen): Suche beginnt von vorn, falls der Zettel noch fehlt
function InkDock.Poke()
    if not enabled then return end
    tries = 0
    poll()
end

--- id des Elements, dem der Zettel gerade folgt, oder nil (Diagnose/Tests)
function InkDock.Following() return follow and follow.id or nil end

ns.RegisterModule("hide-inkdock", {
    OnEnable = function()
        enabled = true
        InkDock.Sync()
    end,
    OnDisable = function()
        enabled = false
        InkDock.Sync()
    end,
})

ns.On("ADDON_LOADED", function(_, name)
    if type(name) == "string" and not Compat.IsSecret(name) and name:find("^InkAndEmbers") then InkDock.Poke() end
end)
ns.On("PLAYER_ENTERING_WORLD", function() InkDock.Poke() end)

ns.On("PLAYER_REGEN_DISABLED", function()
    if lockdown() then return end
    updateMouse(true)
end)

ns.On("PLAYER_REGEN_ENABLED", function()
    local list = orphans
    orphans = {}
    for _, mouseOff in ipairs(list) do restoreList(mouseOff) end
    updateMouse()
end)
