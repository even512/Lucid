-- Karte (B9/W1): Lucid-Kartenmodus fuer Blizzards WorldMapFrame (Weg A). Profil-Abschnitt "map" (additiv, Schema bleibt 1):
--   enabled (Standard aus = es wird nichts angefasst), hideHeader (Kopfzeile/NavBar aus), hideEdges (Blizzards Rahmen aus),
--   questLog (hide | toggle | show: Questliste weg / per kleinem Knopf ausklappbar / unveraendert),
--   border (Stil aus Minimap/Frames.lua oder "none"), borderSize (50-200 %), scale (50-200 %), alpha (20-100 %),
--   placement (auto | lucid | external: wer Position/Skala besitzt; auto = Lucid, mit Open Map ueber dessen Einstellungen (mirrorOpenMap);
--     external = Option "Open Map ueberlassen"; auto faellt auf external zurueck, wenn Open Maps Einstellungen nicht erreichbar sind),
--   pos (nil | { point, relPoint, x, y }: gemerkte Lage nach dem Ziehen am Rahmen),
--   takeKey (W3: Taste der Blizzard-Karte, meist M, oeffnet die Lucid-Karte; die grosse Ansicht liegt auf Umschalt+Taste),
--   runFade (W3: beim Laufen auf runAlpha abblenden, im Stehen/mit Maus darueber volle Deckkraft; ersetzt Blizzards mapFade).
-- Groesse: "scale" ist die einzige Groessen-Einstellung; der Regler im Reiter und das Ziehen an den vier Eck-Griffen schreiben beide
--   dorthin (Ziehen skaliert um die gegenueberliegende Ecke, Seitenverhaeltnis bleibt; nicht im Kampf, nicht bei Open Map).
-- Kein eigener Schliessen-Knopf: die Karte schliesst die Taste (M) bzw. ESC; Blizzards Questpanel-Knopf bleibt verborgen,
--   umgeschaltet wird nur ueber Lucids eigenen Knopf; Blizzards Kartenrand-Knoepfe (overlayFrames) stehen ohne Ueberlappung in einer Reihe.
-- Technik (Mapster-Muster, keine Eingriffe in Pins/Data-Provider/Panel-Tabellen):
--  - Der Inhalt (ScrollContainer samt allen Pins, Open Maps zusammengesetzte Karte, Zoom und Ziehen) bleibt unberuehrt;
--    Lucid aendert nur die Huelle: Position/Skala/Deckkraft des WorldMapFrame, Hide/Show der nicht geschuetzten Kinder
--    BorderFrame/NavBar/QuestMapFrame, Klickflaeche (SetHitRectInsets) und einen eigenen Rahmen als Kind des WorldMapFrame.
--  - Nur im Fenstermodus (nicht maximiert). Nichts im Kampf: Aenderungen warten auf PLAYER_REGEN_ENABLED.
--  - Ruecksprung (Modul/Option aus, Maximieren): Skala, Deckkraft, Lage, Klickflaeche, Sichtbarkeit exakt wie vorgefunden,
--    (ohne UpdateUIPanelPositions aus Addon-Code: Taint-Pfad; Blizzard legt beim naechsten Oeffnen selbst aus).
--  - Open Map besitzt Fensterlage und -skala selbst (Titelleiste, Ecken, eigene Hooks auf SetPoint/SetScale): bei placement
--    "auto" und geladenem Open Map fasst Lucid Lage und Skala nicht an (kein Zieh-Rahmen), Rahmen/Deckkraft/Ausblenden bleiben.
local ADDON_NAME, ns = ...
local Store, Compat, L = ns.Store, ns.Compat, ns.L

local Map = {}
ns.Map = Map
Map.sub = {} -- Unterbefehle von /lucid map (Probe.lua traegt "probe" ein)

Map.LIMITS = { scale = { 50, 200 }, borderSize = { 50, 200 }, alpha = { 20, 100 }, runAlpha = { 10, 100 } }
Map.BACKGROUNDS = { "BlackoutFrame", "Background", "Bg", "Inset", "NineSlice" }
Map.QUESTLOG = { "hide", "toggle", "show" }
Map.PLACEMENTS = { "auto", "lucid", "external" }
local BORDERS = {}
for _, name in ipairs((ns.MinimapFrames or {}).order or {}) do BORDERS[#BORDERS + 1] = name end
BORDERS[#BORDERS + 1] = "none"
Map.BORDERS = BORDERS

local function set(list)
    local s = {}
    for _, k in ipairs(list) do s[k] = true end
    return s
end
local QL_SET, PL_SET, BORDER_SET = set(Map.QUESTLOG), set(Map.PLACEMENTS), set(BORDERS)

function Map.Defaults()
    return { enabled = false, hideHeader = true, hideEdges = true, questLog = "toggle", border = "schmal", borderSize = 100,
        scale = 100, alpha = 100, placement = "auto", pos = false, takeKey = true, runFade = false, runAlpha = 40 }
end

local POINTS = set({ "TOPLEFT", "TOP", "TOPRIGHT", "LEFT", "CENTER", "RIGHT", "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT" })

local function validatePos(v)
    if v == false or v == nil then return false end
    if type(v) ~= "table" then return nil end
    local x, y = v.x, v.y
    if type(x) ~= "number" or type(y) ~= "number" or x ~= x or y ~= y or math.abs(x) > 20000 or math.abs(y) > 20000 then return nil end
    if type(v.point) ~= "string" or not POINTS[v.point] then return nil end
    local rp = v.relPoint
    if rp == nil then rp = v.point end
    if type(rp) ~= "string" or not POINTS[rp] then return nil end
    return { point = v.point, relPoint = rp, x = x, y = y }
end

--- Abschnitt "map" pruefen: vollstaendige bereinigte Kopie oder nil, Feldname
function Map.Validate(v)
    if type(v) ~= "table" then return nil, "type" end
    local out = {}
    for k, x in pairs(v) do
        if k == "enabled" or k == "hideHeader" or k == "hideEdges" or k == "takeKey" or k == "runFade" then
            if type(x) ~= "boolean" then return nil, k end
            out[k] = x
        elseif k == "questLog" then
            if type(x) ~= "string" or not QL_SET[x] then return nil, k end
            out[k] = x
        elseif k == "placement" then
            if type(x) ~= "string" or not PL_SET[x] then return nil, k end
            out[k] = x
        elseif k == "border" then
            if type(x) ~= "string" or not BORDER_SET[x] then return nil, k end
            out[k] = x
        elseif k == "scale" or k == "borderSize" or k == "alpha" or k == "runAlpha" then
            if type(x) ~= "number" or x ~= x then return nil, k end
            local r = Map.LIMITS[k]
            out[k] = math.floor(math.min(r[2], math.max(r[1], x)) + 0.5)
        elseif k == "pos" then
            local p = validatePos(x)
            if p == nil then return nil, k end
            out.pos = p
        end -- unbekannte Felder fallen weg
    end
    for k, d in pairs(Map.Defaults()) do
        if out[k] == nil then out[k] = d end
    end
    return out
end

Store.RegisterSection("map", { default = Map.Defaults, validate = Map.Validate })

function Map.GetConfig()
    local stored
    if Store.db then
        local p = Store.GetActive()
        stored = p and p.map
    end
    return (type(stored) == "table" and Map.Validate(stored)) or Map.Defaults()
end

-- Erkennung anderer Karten-Addons ------------------------------------------------------------------
function Map.AddonLoaded(name)
    local fn = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
    if type(fn) == "function" then
        local ok, v = pcall(fn, name)
        if ok and v then return true end
    end
    return false
end

--- Open Map geladen? Nur der Addon-Status zaehlt (ein vorhandener Ordner oder eine Global reicht nicht)
function Map.OpenMapLoaded()
    return Map.AddonLoaded("OpenMap")
end

-- Open Map haelt Lage/Skala/Groesse in OpenMapDB.worldmap (window = { point, relPoint, x, y }, windowScale, windowSize) und stellt sie ueber Hooks
-- auf SetPoint/SetScale/SetSize/SetWidth/SetHeight, OnShow, ShowUIPanel und UpdateUIPanelPositions sofort wieder her (Map/Window.lua von Open Map):
-- jede fremde Aenderung wird rueckgaengig gemacht. Lucid gewinnt dadurch, dass es seine Werte dort einspiegelt (vorher, dann stimmen Open Maps
-- Hooks mit Lucids Schreibzugriff ueberein) und beim Ruecksprung die gefundenen Werte zurueckgibt.
local function omDb()
    local db = _G.OpenMapDB
    local w = type(db) == "table" and db.worldmap or nil
    return type(w) == "table" and w or nil
end

--- besitzt ein anderes Addon Lage und Skala? Nur bei "external" (Option) -- oder wenn Open Map geladen ist, sich aber nicht einspiegeln
--- laesst (OpenMapDB.worldmap fehlt): dann wuerde es Lucids Werte sofort zuruecksetzen.
function Map.ExternalPlacement(cfg)
    if cfg.placement == "external" then return true end
    return cfg.placement == "auto" and Map.OpenMapLoaded() and omDb() == nil
end

--- Open Map gehoeren Lage/Skala nicht mehr, aber es ist geladen: Lucids Werte in dessen Einstellungen spiegeln (vor den Setzern)
local omSaved -- gefundene Werte, beim Ruecksprung zurueck
local function mirrorOpenMap(scale, pos)
    if not Map.OpenMapLoaded() then return end
    local d = omDb()
    if not d then return end
    if not omSaved then omSaved = { window = d.window, windowScale = d.windowScale, had = true } end
    d.windowScale = scale
    if pos then d.window = { pos[1], pos[2], pos[3], pos[4] } else d.window = omSaved.window end
end

local function restoreOpenMap()
    if not omSaved then return end
    local d = omDb()
    if d then d.window, d.windowScale = omSaved.window, omSaved.windowScale end
    omSaved = nil
end

-- Zustand ------------------------------------------------------------------------------------------
local modEnabled = false
local pending = false
local touched = false      -- Lucid hat die Karte veraendert (Ruecksprung noetig)
local own = false          -- eigener Schreibvorgang laeuft (Hooks still)
local hooked = false
local orig                 -- Ursprungszustand beim ersten Eingriff
local host, border, buttons, grips, qbtn, dragging, sizing
local layoutBorder, layoutGrips, arrangeOverlays, hookOverlay, ensureSideHook -- unten definiert (layoutBorder ruft sie, Ziehen ruft layoutBorder)
local bypass = false       -- grosse Ansicht (Umschalt+M): Blizzards Layout, solange diese Karte offen ist
local fadeFrame, curAlpha  -- Lauf-Fade (OnUpdate-Frame, aktueller Alpha-Wert)
local last = { engaged = false, external = false, hidden = {} }

local function wmf()
    local m = _G.WorldMapFrame
    if type(m) == "table" and type(m.SetScale) == "function" then return m end
    return nil
end

local function lockdown() return InCombatLockdown ~= nil and Compat.Bool(InCombatLockdown()) end
local function inCombat() return lockdown() or (ns.State ~= nil and ns.State.Get("combat") == true) end

local function try(obj, method, ...)
    if type(obj) ~= "table" or type(obj[method]) ~= "function" then return false end
    local ok, a, b, c, d, e = pcall(obj[method], obj, ...)
    if not ok then return false end
    return true, a, b, c, d, e
end

local function maximized(m)
    local ok, v = try(m, "IsMaximized")
    return ok and Compat.Bool(v) or false
end

local function active() return modEnabled and Map.GetConfig().enabled end

--- gewuenschte Deckkraft: Lucids Wert; mit Lauf-Fade beim Laufen (und Maus nicht ueber der Karte) runAlpha
local function movingNow()
    if type(_G.IsPlayerMoving) ~= "function" then return false end
    local ok, v = pcall(_G.IsPlayerMoving)
    return ok and Compat.IsSecret(v) == false and v == true
end
function Map.WantedAlpha(cfg)
    cfg = cfg or Map.GetConfig()
    if cfg.runFade and movingNow() then
        local m = wmf()
        local ok, over = false, false
        if m then ok, over = try(m, "IsMouseOver") end
        if not (ok and Compat.Bool(over)) then return cfg.runAlpha / 100 end
    end
    return cfg.alpha / 100
end

-- Teile des WorldMapFrame, die der Kartenmodus ausblenden darf: Schluessel -> Option
local function hideTargets(m, cfg)
    local list = {}
    if cfg.hideHeader and type(m.NavBar) == "table" then list[#list + 1] = { "NavBar", m.NavBar } end
    if cfg.hideEdges then
        if type(m.BorderFrame) == "table" then list[#list + 1] = { "BorderFrame", m.BorderFrame } end
        -- Hintergruende auf Fenstergroesse (Retail 12.x / Open Map): schwarze Flaeche und Rahmenfuellung
        for _, key in ipairs(Map.BACKGROUNDS) do
            if type(m[key]) == "table" then list[#list + 1] = { key, m[key] } end
        end
    end
    -- Blizzards Questpanel-Knopf (SidePanelToggle, ausgefahren unten rechts): immer verborgen, Umschalten macht Lucids Knopf
    if cfg.questLog ~= "show" and type(m.SidePanelToggle) == "table" then list[#list + 1] = { "SidePanelToggle", m.SidePanelToggle } end
    if cfg.questLog ~= "show" and not (cfg.questLog == "toggle" and Map.questOpen) then
        -- Questliste: Blizzards QuestMapFrame (aelter) bzw. WorldMapFrame.QuestLog (12.x, auch Open Maps Anzeige)
        local q = _G.QuestMapFrame
        if type(q) == "table" then list[#list + 1] = { "QuestMapFrame", q } end
        if type(m.QuestLog) == "table" and m.QuestLog ~= q then list[#list + 1] = { "QuestLog", m.QuestLog } end
        -- Zubehoer der Questliste (Retail 12.x): Reiter an Questliste/Karte
        for _, owner in ipairs({ { "m", m }, { "QuestMapFrame", q }, { "QuestLog", m.QuestLog } }) do
            local o = owner[2]
            if type(o) == "table" then
                for _, key in ipairs({ "QuestsTab", "MapLegendTab" }) do
                    if type(o[key]) == "table" then list[#list + 1] = { owner[1] .. "." .. key, o[key] } end
                end
            end
        end
    end
    return list
end

-- Hintergrundflaechen: Texturen auf dem WorldMapFrame selbst, auf Kopf-Platzhalter, Rahmen, Questliste und auf grossen
-- direkten Kindern (>= halbe Kartenflaeche; nicht ScrollContainer/Lucid) werden per SetAlpha(0) ausgeblendet und gemerkt
-- (Rueckweg stellt den Alpha-Wert exakt wieder her). Pins, Knoepfe und Overlay-Frames bleiben unberuehrt.
local function regionsOf(f)
    if type(f) ~= "table" or type(f.GetRegions) ~= "function" then return {} end
    local res = { pcall(f.GetRegions, f) }
    table.remove(res, 1)
    return res
end

local function frameSize(f)
    local _, w = try(f, "GetWidth")
    local _, h = try(f, "GetHeight")
    return Compat.Num(w) or 0, Compat.Num(h) or 0
end

local function sweepTargets(m)
    local out, seen = {}, {}
    local function add(f)
        for _, r in ipairs(regionsOf(f)) do
            if type(r) == "table" and not seen[r] and type(r.SetAlpha) == "function" then
                local _, ot = try(r, "GetObjectType")
                if ot ~= "FontString" then
                    seen[r] = true
                    out[#out + 1] = r
                end
            end
        end
    end
    add(m)
    -- Retail 12.x: WorldMapFrameBg (globaler Name, Textur 374155) liegt als Region am WorldMapFrame; InsetBorderTop am Rahmen
    for _, name in ipairs({ "WorldMapFrameBg" }) do
        local r = _G[name]
        if type(r) == "table" and not seen[r] and type(r.SetAlpha) == "function" then
            seen[r] = true
            out[#out + 1] = r
        end
    end
    for _, key in ipairs({ "TitleCanvasSpacerFrame", "BorderFrame", "QuestLog" }) do add(m[key]) end
    add(_G.QuestMapFrame)
    local mw, mh = frameSize(m)
    local area = mw * mh
    if type(m.GetChildren) == "function" and area > 0 then
        for _, c in ipairs({ m:GetChildren() }) do
            if type(c) == "table" and c ~= host and c ~= m.ScrollContainer and c ~= m.BorderFrame and c ~= m.QuestLog
                and c ~= _G.QuestMapFrame and c ~= m.TitleCanvasSpacerFrame then
                local w, h = frameSize(c)
                if w * h >= 0.5 * area then add(c) end
            end
        end
    end
    return out
end

local function sweep(m, on)
    orig.faded = orig.faded or {}
    local want = {}
    if on then
        for _, r in ipairs(sweepTargets(m)) do
            want[r] = true
            if orig.faded[r] == nil then
                local _, a = try(r, "GetAlpha")
                orig.faded[r] = Compat.Num(a) or 1
            end
            try(r, "SetAlpha", 0)
        end
    end
    for r, a in pairs(orig.faded) do
        if not want[r] then
            try(r, "SetAlpha", a)
            orig.faded[r] = nil
        end
    end
end

local function remember(m)
    if orig then return end
    orig = { points = {}, hidden = {} }
    local _, s = try(m, "GetScale")
    local _, a = try(m, "GetAlpha")
    orig.scale, orig.alpha = Compat.Num(s) or 1, Compat.Num(a) or 1
    local _, mv = try(m, "IsMovable")
    orig.movable = Compat.Bool(mv)
    local _, n = try(m, "GetNumPoints")
    for i = 1, tonumber(n) or 0 do
        local ok, p, rel, rp, x, y = try(m, "GetPoint", i)
        if ok then orig.points[#orig.points + 1] = { p, rel, rp, x, y } end
    end
end

-- Rahmen -----------------------------------------------------------------------------------------
local function insets(m)
    local sc = m.ScrollContainer
    local okA, ml = try(m, "GetLeft")
    local _, mt = try(m, "GetTop")
    local _, mr = try(m, "GetRight")
    local _, mb = try(m, "GetBottom")
    local _, sl = try(sc, "GetLeft")
    local _, st = try(sc, "GetTop")
    local _, sr = try(sc, "GetRight")
    local _, sb = try(sc, "GetBottom")
    ml, mt, mr, mb, sl, st, sr, sb = Compat.Num(ml), Compat.Num(mt), Compat.Num(mr), Compat.Num(mb), Compat.Num(sl), Compat.Num(st),
        Compat.Num(sr), Compat.Num(sb)
    if not (okA and ml and mt and mr and mb and sl and st and sr and sb) then return 0, 0, 0, 0 end
    -- GetLeft/GetTop ... liefern Werte in den Einheiten der jeweiligen Region: ueber die effektive Skala in Einheiten des
    -- WorldMapFrame umrechnen (Faktor 1, solange der ScrollContainer keine eigene Skala hat), dann stimmt es bei jeder Kartenskala
    local _, em = try(m, "GetEffectiveScale")
    local _, es = try(sc, "GetEffectiveScale")
    em, es = Compat.Num(em) or 1, Compat.Num(es) or 1
    if em <= 0 then em = 1 end
    local f = es / em
    sl, st, sr, sb = sl * f, st * f, sr * f, sb * f
    return math.max(0, sl - ml), math.max(0, mt - st), math.max(0, mr - sr), math.max(0, sb - mb)
end

--- Klemmung an den Bildschirmrand nur fuer die sichtbare Karte: die leere Flaeche rechts (frueher Questliste), oben (Kopfzeile) und an den
--- Raendern darf ueber den Bildschirmrand hinausragen. SetClampRectInsets(l, r, t, b) verschiebt die Kanten des Klemm-Rechtecks
--- (wie Blizzards Chat: links negativ / rechts positiv = nach aussen) -> hier nach innen auf den sichtbaren Bereich.
local function clampVisible(m, l, t, r, b)
    if not orig then return end
    if orig.clamp == nil then
        local ok, cl, cr, ct, cb = try(m, "GetClampRectInsets")
        orig.clamp = ok and { Compat.Num(cl) or 0, Compat.Num(cr) or 0, Compat.Num(ct) or 0, Compat.Num(cb) or 0 } or false
    end
    try(m, "SetClampRectInsets", l, -r, -t, b)
end

local function mapSize(m)
    local _, w = try(m, "GetWidth")
    local _, h = try(m, "GetHeight")
    return Compat.Num(w) or 0, Compat.Num(h) or 0
end

local function ensureHost(m)
    if host then return true end
    local ok, f = pcall(CreateFrame, "Frame", nil, m)
    if not ok or type(f) ~= "table" then return false end
    host = f
    pcall(f.EnableMouse, f, false)
    border = ns.FrameBorder.New(f)
    return true
end

local function levelHost(m)
    if not host then return end
    local sc = m.ScrollContainer
    local _, lvl = try(sc, "GetFrameLevel")
    lvl = Compat.Num(lvl) or Compat.Num(select(2, try(m, "GetFrameLevel"))) or 1
    pcall(host.SetFrameLevel, host, lvl + 20)
end

-- Zieh-Leisten entlang der vier Kanten (nur eigene Frames; Inhalt der Karte bleibt frei fuer Mausrad und Ziehen)
local EDGE = 12
local function ensureEdges(m)
    if buttons then return end
    buttons = {}
    for _, key in ipairs({ "top", "bottom", "left", "right" }) do
        local ok, e = pcall(CreateFrame, "Frame", nil, host)
        if ok and type(e) == "table" then
            e:EnableMouse(true)
            e:RegisterForDrag("LeftButton")
            e:SetScript("OnDragStart", function()
                if inCombat() or not wmf() then return end
                local mm = wmf()
                try(mm, "SetMovable", true)
                dragging = true
                try(mm, "StartMoving")
            end)
            e:SetScript("OnDragStop", function()
                local mm = wmf()
                if not (dragging and mm) then return end
                dragging = false
                try(mm, "StopMovingOrSizing")
                Map.SavePosition()
            end)
            buttons[key] = e
        end
    end
end

local function layoutEdges(m, cfg, u, l, t, r, b, W, H)
    if not buttons then return end
    local show = not Map.ExternalPlacement(cfg) and cfg.border ~= "none"
    for key, e in pairs(buttons) do
        if not show then
            e:Hide()
        else
            e:ClearAllPoints()
            if key == "top" then
                e:SetPoint("TOPLEFT", m, "TOPLEFT", u * l, -(u * t))
                e:SetSize(math.max(1, W), EDGE)
            elseif key == "bottom" then
                e:SetPoint("BOTTOMLEFT", m, "BOTTOMLEFT", u * l, u * b)
                e:SetSize(math.max(1, W), EDGE)
            elseif key == "left" then
                e:SetPoint("TOPLEFT", m, "TOPLEFT", u * l, -(u * t))
                e:SetSize(EDGE, math.max(1, H))
            else
                e:SetPoint("TOPRIGHT", m, "TOPRIGHT", -(u * r), -(u * t))
                e:SetSize(EDGE, math.max(1, H))
            end
            e:Show()
        end
    end
end

-- kleiner Knopf im Rahmen (Questliste ein/aus)
local BTN, GAP, GRIP, ROW_Y = 22, 4, 16, 6
local function smallButton(tip, onClick)
    local ok, b = pcall(CreateFrame, "Button", nil, host)
    if not ok or type(b) ~= "table" then return nil end
    b:SetSize(BTN, BTN)
    b:EnableMouse(true)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(b)
    bg:SetColorTexture(0.1, 0.07, 0.03, 0.85)
    local fs = b:CreateFontString(nil, "OVERLAY")
    local okF = fs.SetFont and pcall(fs.SetFont, fs, _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    if not okF and fs.SetFontObject and _G.GameFontNormal then pcall(fs.SetFontObject, fs, _G.GameFontNormal) end
    fs:SetPoint("CENTER")
    fs:SetTextColor(0.86, 0.66, 0.38)
    b.label = fs
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        if GameTooltip and GameTooltip.SetOwner then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
            GameTooltip:AddLine(tip)
            if GameTooltip.Show then GameTooltip:Show() end
        end
    end)
    b:SetScript("OnLeave", function() if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end end)
    return b
end

local function ensureQuestButton()
    if qbtn then return end
    qbtn = smallButton(L.MAP_QUESTS_TIP, function()
        Map.questOpen = not Map.questOpen
        Map.Apply()
    end)
end

--- Schliessen ueber Blizzards eigenen Knopf (BorderFrame.CloseButton), sonst ToggleWorldMap
function Map.Close()
    local m = wmf()
    if not m then return end
    local bf = m.BorderFrame
    local cb = type(bf) == "table" and bf.CloseButton or nil
    if type(cb) == "table" and type(cb.Click) == "function" and pcall(cb.Click, cb) then return end
    if type(_G.ToggleWorldMap) == "function" then pcall(_G.ToggleWorldMap) else try(m, "Hide") end
end

-- Eck-Griffe (Groesse ziehen) ---------------------------------------------------------------------------
-- Alle vier Ecken des sichtbaren Kartenbereichs. Ziehen skaliert um die gegenueberliegende Ecke (Seitenverhaeltnis bleibt):
-- Skala = Projektion der Cursor-Strecke auf die Kartendiagonale; Ergebnis geht ueber Map.Set in dieselbe Einstellung "scale"
-- wie der Regler im Reiter (ganze Prozent), samt der Lage der festen Ecke. Nichts im Kampf (der Zug bricht dort ab).
local CORNERS = {
    TL = { h = "L", v = "T", point = "TOPLEFT" },
    TR = { h = "R", v = "T", point = "TOPRIGHT" },
    BL = { h = "L", v = "B", point = "BOTTOMLEFT" },
    BR = { h = "R", v = "B", point = "BOTTOMRIGHT" },
}
Map.CORNER_KEYS = { "TL", "TR", "BL", "BR" }

local function uiScale()
    local okS, v = try(_G.UIParent, "GetEffectiveScale")
    v = okS and Compat.Num(v) or 1
    if v <= 0 then v = 1 end
    return v
end

local function cursorUI()
    if type(_G.GetCursorPosition) ~= "function" then return nil end
    local ok, x, y = pcall(_G.GetCursorPosition)
    if not ok then return nil end
    x, y = Compat.Num(x), Compat.Num(y)
    if not (x and y) then return nil end
    local es = uiScale()
    return x / es, y / es
end

local function roundScale(s)
    local r = Map.LIMITS.scale
    return math.floor(math.min(r[2], math.max(r[1], s * 100)) + 0.5)
end

-- Anker der festen Ecke bei Skala s (reine Rechnung, fasst keinen Frame an)
local function sizeTarget(sz, s)
    local f = sz.fixed
    local point = (f.v == "T" and "TOP" or "BOTTOM") .. (f.h == "L" and "LEFT" or "RIGHT")
    return point, sz.fx / s + (f.h == "L" and -sz.l or sz.r), sz.fy / s + (f.v == "T" and sz.t or -sz.b)
end

-- Skala setzen und die feste Ecke an ihrem Platz halten (ohne Profil-Schreiben; gilt waehrend des Ziehens, nie im Kampf)
local function applySize(m, sz, s)
    local point, x, y = sizeTarget(sz, s)
    own = true
    mirrorOpenMap(s, { point, "BOTTOMLEFT", x, y })
    try(m, "SetScale", s)
    try(m, "ClearAllPoints")
    try(m, "SetPoint", point, _G.UIParent, "BOTTOMLEFT", x, y)
    pcall(layoutBorder, m, sz.cfg, s, { sz.l, sz.t, sz.r, sz.b })
    own = false
end

local function stopSizing(commit)
    local sz = sizing
    if not sz then return end
    sizing = nil
    if sz.grip then sz.grip:SetScript("OnUpdate", nil) end
    local m = wmf()
    if not (commit and m and sz.s) then return end
    local pct = roundScale(sz.s)
    local point, x, y = sizeTarget(sz, pct / 100)
    -- Im Kampf wird kein Frame angefasst (WorldMapFrame, Overlay-Knoepfe): nur Wert und Lage ins Profil, Map.Set merkt vor und
    -- wendet nach PLAYER_REGEN_ENABLED an. Sonst: Lage mit der gerundeten Skala setzen, damit Profil und Fenster uebereinstimmen.
    if not inCombat() then applySize(m, sz, pct / 100) end
    Map.Set({ scale = pct, pos = { point = point, relPoint = "BOTTOMLEFT", x = x, y = y } })
    if ns.Config and ns.Config.Refresh then pcall(ns.Config.Refresh) end
end
function Map.SizeStop(commit) stopSizing(commit ~= false) end

local function sizeStep()
    local sz = sizing
    local m = wmf()
    if not (sz and m) then stopSizing(false) return end
    if inCombat() then stopSizing(true) return end -- Kampf: Zug beenden, Anwendung wartet (Map.Set merkt vor)
    local cx, cy = cursorUI()
    if not cx then return end
    local dx = sz.drag.h == "R" and (cx - sz.fx) or (sz.fx - cx)
    local dy = sz.drag.v == "B" and (sz.fy - cy) or (cy - sz.fy)
    local s = (dx * sz.W + dy * sz.H) / (sz.W * sz.W + sz.H * sz.H)
    local r = Map.LIMITS.scale
    s = math.min(r[2] / 100, math.max(r[1] / 100, s))
    if sz.s == s then return end
    sz.s = s
    applySize(m, sz, s)
end

--- Zug an einer Ecke beginnen (key: TL | TR | BL | BR). Nicht im Kampf, nicht bei fremder Lage (Open Map).
function Map.SizeStart(key, grip)
    local m = wmf()
    local drag = CORNERS[key]
    if not (m and drag and touched and not sizing) then return false end
    if inCombat() then return false end
    local cfg = Map.GetConfig()
    if Map.ExternalPlacement(cfg) then return false end
    local l, t, r, b = insets(m)
    local w, h = mapSize(m)
    local W, H = w - l - r, h - t - b
    local _, em = try(m, "GetEffectiveScale")
    em = Compat.Num(em)
    local _, left = try(m, "GetLeft")
    local _, right = try(m, "GetRight")
    local _, top = try(m, "GetTop")
    local _, bottom = try(m, "GetBottom")
    left, right, top, bottom = Compat.Num(left), Compat.Num(right), Compat.Num(top), Compat.Num(bottom)
    if not (em and left and right and top and bottom) or W <= 0 or H <= 0 then return false end
    local k = em / uiScale() -- Karteneinheiten -> Bildschirm-Einheiten
    local fixed = { h = drag.h == "L" and "R" or "L", v = drag.v == "T" and "B" or "T" }
    sizing = {
        grip = grip, drag = drag, fixed = fixed, cfg = cfg, l = l, t = t, r = r, b = b, W = W, H = H,
        fx = (fixed.h == "L" and (left + l) or (right - r)) * k,
        fy = (fixed.v == "T" and (top - t) or (bottom + b)) * k,
    }
    if grip then grip:SetScript("OnUpdate", sizeStep) end
    return true
end

local function ensureGrips()
    if grips then return end
    grips = {}
    for _, key in ipairs(Map.CORNER_KEYS) do
        local ok, g = pcall(CreateFrame, "Frame", nil, host)
        if ok and type(g) == "table" then
            g:SetSize(GRIP, GRIP)
            g:EnableMouse(true)
            g:RegisterForDrag("LeftButton")
            local c = CORNERS[key]
            -- zwei Balken in Bronze als Eck-Marke (der Winkel zeigt in die Rahmenecke)
            local bars = {}
            for i = 1, 2 do
                local tx = g:CreateTexture(nil, "OVERLAY")
                tx:SetColorTexture(0.86, 0.66, 0.38, 1)
                if i == 1 then tx:SetSize(12, 2) else tx:SetSize(2, 12) end
                tx:SetPoint(c.point, g, c.point, 0, 0)
                tx:SetAlpha(0.4)
                bars[i] = tx
            end
            g.bars = bars
            g.corner = key
            g:SetScript("OnDragStart", function(self) Map.SizeStart(key, self) end)
            g:SetScript("OnDragStop", function() stopSizing(true) end)
            g:SetScript("OnHide", function() stopSizing(false) end)
            g:SetScript("OnEnter", function(self)
                for _, tx in ipairs(self.bars) do tx:SetAlpha(1) end
                if GameTooltip and GameTooltip.SetOwner then
                    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                    GameTooltip:AddLine(L.MAP_GRIP_TIP)
                    if GameTooltip.Show then GameTooltip:Show() end
                end
            end)
            g:SetScript("OnLeave", function(self)
                for _, tx in ipairs(self.bars) do tx:SetAlpha(0.4) end
                if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
            end)
            grips[key] = g
        end
    end
end

function layoutGrips(m, cfg, u, l, t, r, b)
    if not grips then return end
    local show = not Map.ExternalPlacement(cfg)
    local _, lvl = try(host, "GetFrameLevel")
    lvl = Compat.Num(lvl) or 1
    for key, g in pairs(grips) do
        if not show then
            g:Hide()
        else
            local c = CORNERS[key]
            g:ClearAllPoints()
            g:SetPoint(c.point, m, c.point, (c.h == "L" and u * l or -(u * r)), (c.v == "B" and u * b or -(u * t)))
            pcall(g.SetFrameLevel, g, lvl + 4)
            g:Show()
        end
    end
end

-- Kartenrand-Knoepfe (WorldMapFrame.overlayFrames: Filter, Kartenpin ...) -------------------------------------
-- Blizzard verankert sie am oberen rechten Rand der Kartenflaeche; mit Lucids Knopf und Eck-Griff liegen sie uebereinander.
-- Kleine, sichtbare, oben rechts verankerte Overlay-Knoepfe werden in einer Reihe (urspruengliche Reihenfolge) links von Lucids
-- Knopf gesetzt; die Ursprungsanker merkt orig.overlay, der Ruecksprung stellt sie wieder her. Nur ausserhalb des Kampfs (Aufrufer).
-- Der Filterknopf (WorldMapTrackingOptionsButton, mit rotem Zuruecksetzen-X als Kind) wird zusaetzlich erkannt, wenn er nicht oben
-- rechts an der Kartenflaeche haengt: WoW Forever verankert ihn in der Navigationsleiste (Hinweis in Questies WorldMapButton.lua),
-- also in der von Lucid ausgeblendeten Kopfzeile -- dort schwebte er ueber dem sichtbaren Rahmen. Fremde Addons, die den Anker
-- danach neu setzen (z. B. Krowis Kartenknopf-Bibliothek), werden nachgezogen.
local OVERLAY_MAX = 64
local FILTER_SIZE = 32 -- Annahme, solange der Filterknopf noch keine Groesse meldet
local function pointsOf(f)
    local pts = {}
    for i = 1, 8 do
        local ok, p, rel, rp, x, y = try(f, "GetPoint", i)
        if not (ok and p) then break end
        pts[#pts + 1] = { p, rel, rp, x, y }
    end
    return pts
end

local function restoreOverlay(f, pts)
    try(f, "ClearAllPoints")
    for _, p in ipairs(pts) do try(f, "SetPoint", p[1], p[2], p[3], p[4], p[5]) end
end

local placed = setmetatable({}, { __mode = "k" }) -- Overlay-Knopf -> { rel, x, y }: was Lucid zuletzt gesetzt hat

--- Knopf zurueck an seinen Ursprung (Anker und Ebene) und aus der Reihe nehmen
local function releaseOverlay(f, pts)
    restoreOverlay(f, pts)
    placed[f] = nil
    local lv = orig and orig.overlayLevel and orig.overlayLevel[f]
    if lv then
        try(f, "SetFrameLevel", lv)
        orig.overlayLevel[f] = nil
    end
end

--- Filterknopf von Blizzard (Optionsmenue "Anzeigen: Questziele ...", rotes X als Kind)? Erkennung wie Krowis Bibliothek ueber die
--- Vorlage (OnLoad aus WorldMapTrackingOptionsButtonMixin), dazu der globale Name und das X-Kind.
local function isFilterButton(f)
    if f == _G.WorldMapTrackingOptionsButton then return true end
    local mix = _G.WorldMapTrackingOptionsButtonMixin
    if type(mix) == "table" and type(mix.OnLoad) == "function" and f.OnLoad == mix.OnLoad then return true end
    return type(f.ResetButton) == "table"
end

--- haengt rel in der Kopfzeile (NavBar, Rahmen, Titelplatzhalter), die Lucid ausblendet?
local function inHeader(m, rel)
    local cur = rel
    for _ = 1, 4 do
        if type(cur) ~= "table" or cur == m then return false end
        if cur == m.NavBar or cur == m.BorderFrame or cur == m.TitleCanvasSpacerFrame then return true end
        local ok, par = try(cur, "GetParent")
        cur = ok and par or nil
    end
    return false
end

local overlayHooked, placeHooked = {}, {}
function hookOverlay(f)
    if overlayHooked[f] or type(f.HookScript) ~= "function" then return end
    overlayHooked[f] = true
    local function again()
        if own or sizing or not touched then return end
        if inCombat() then pending = true return end
        Map.Relayout()
    end
    pcall(f.HookScript, f, "OnShow", again)
    pcall(f.HookScript, f, "OnHide", again)
end

--- Setzt ein anderes Addon den Anker eines von Lucid platzierten Knopfs neu, zieht Lucid die Reihe nach (im Kampf: vormerken)
local function hookPlacement(f)
    if placeHooked[f] or type(f.SetPoint) ~= "function" then return end
    placeHooked[f] = true
    pcall(hooksecurefunc, f, "SetPoint", function(self)
        if own or sizing or not touched then return end
        local want = placed[self]
        if not want then return end
        local pts = pointsOf(self)
        local p = pts[1]
        if #pts == 1 and p[1] == "TOPRIGHT" and p[2] == want.rel and math.abs((Compat.Num(p[4]) or 0) - want.x) < 0.05
            and math.abs((Compat.Num(p[5]) or 0) - want.y) < 0.05 then return end
        if inCombat() then pending = true return end
        Map.Relayout()
    end)
end

--- Kandidaten: overlayFrames in Blizzards Reihenfolge, dazu der Filterknopf, falls er dort fehlt (Kind der Karte oder der Kopfzeile)
local function overlayCandidates(m)
    local cand, seen = {}, {}
    local function add(f, i)
        if type(f) == "table" and not seen[f] then
            seen[f] = true
            cand[#cand + 1] = { f = f, i = i }
        end
    end
    if type(m.overlayFrames) == "table" then
        for i, f in ipairs(m.overlayFrames) do add(f, i) end
    end
    local n = 1000
    for _, owner in ipairs({ m, m.NavBar }) do
        if type(owner) == "table" and type(owner.GetChildren) == "function" then
            for _, c in ipairs({ owner:GetChildren() }) do
                if type(c) == "table" and c ~= host and c ~= m.ScrollContainer and isFilterButton(c) then
                    n = n + 1
                    add(c, n)
                end
            end
        end
    end
    add(_G.WorldMapTrackingOptionsButton, n + 1)
    return cand
end

function arrangeOverlays(m, u, t, r, used)
    orig.overlay = orig.overlay or {}
    local cand = overlayCandidates(m)
    local filters = {}
    for _, e in ipairs(cand) do if isFilterButton(e.f) then filters[e.f] = true end end
    local picked = {}
    for _, e in ipairs(cand) do
        local f = e.f
        if f ~= m.SidePanelToggle and f ~= host and f ~= qbtn then
            local known = orig.overlay[f]
            local okS, shown = try(f, "IsShown")
            local w, h = frameSize(f)
            local filter = filters[f] == true
            if filter and (w <= 0 or h <= 0) then w, h = FILTER_SIZE, FILTER_SIZE end
            hookOverlay(f)
            if okS and Compat.Bool(shown) and w > 0 and h > 0 and w <= OVERLAY_MAX and h <= OVERLAY_MAX then
                local pts = known or pointsOf(f)
                local p1 = pts[1]
                if p1 then
                    local pt = p1[1]
                    -- oben rechts (wie bisher); der Filterknopf mit jedem Anker; rechts in der Kopfzeile (Navigationsleiste)
                    local right = pt == "TOPRIGHT" or filter
                        or ((pt == "RIGHT" or pt == "BOTTOMRIGHT") and inHeader(m, p1[2]))
                    -- am Filterknopf haengende Teile (X) folgen ihm von selbst
                    local follows = not filter and type(p1[2]) == "table" and filters[p1[2]] == true
                    if right and not follows then
                        if not known then orig.overlay[f] = pts end
                        picked[#picked + 1] = { f = f, i = e.i, x = Compat.Num(p1[4]) or 0, w = w }
                    end
                end
            end
        end
    end
    -- Blizzards Reihenfolge von rechts nach links (kleinster Abstand zum Rand zuerst)
    table.sort(picked, function(a, c) if a.x ~= c.x then return a.x > c.x end return a.i < c.i end)
    local x = -r - used / u
    local keep = {}
    local _, hostLvl = try(host, "GetFrameLevel")
    hostLvl = Compat.Num(hostLvl) or 1
    orig.overlayLevel = orig.overlayLevel or {}
    for _, e in ipairs(picked) do
        local f = e.f
        keep[f] = true
        local _, sc = try(f, "GetScale")
        sc = Compat.Num(sc) or 1
        if sc <= 0 then sc = 1 end
        local px, py = x / sc, (-t - ROW_Y / u) / sc
        try(f, "ClearAllPoints")
        try(f, "SetPoint", "TOPRIGHT", m, "TOPRIGHT", px, py)
        placed[f] = { rel = m, x = px, y = py }
        hookPlacement(f)
        -- ueber Lucids Zieh-Leisten (Kinder des Rahmens), damit der Knopf samt X anklickbar bleibt
        local _, lv = try(f, "GetFrameLevel")
        lv = Compat.Num(lv)
        if lv and lv < hostLvl + 6 then
            if orig.overlayLevel[f] == nil then orig.overlayLevel[f] = lv end
            try(f, "SetFrameLevel", hostLvl + 6)
        end
        x = x - e.w * sc - GAP / u
    end
    for f, pts in pairs(orig.overlay) do
        if not keep[f] then
            releaseOverlay(f, pts)
            orig.overlay[f] = nil
        end
    end
end

function layoutBorder(m, cfg, u, ins)
    local l, t, r, b
    if ins then l, t, r, b = ins[1], ins[2], ins[3], ins[4] else l, t, r, b = insets(m) end
    local w, h = mapSize(m)
    local W, H = u * (w - l - r), u * (h - t - b)
    -- Questliste sichtbar (ausgefahren / immer): sie gehoert zur Klemmflaeche, sonst nur die Karte
    local listShown = cfg.questLog == "show" or (cfg.questLog == "toggle" and Map.questOpen == true)
    clampVisible(m, l, t, listShown and 0 or r, b)
    pcall(host.SetScale, host, 1 / u)
    levelHost(m)
    host:ClearAllPoints()
    host:SetAllPoints(m)
    local res
    if cfg.border ~= "none" and W > 0 and H > 0 then
        res = border:Layout(m, { style = cfg.border, borderSize = cfg.borderSize, u = u, W = W, H = H, l = l, t = t, r = r, b = b })
    end
    if not res then border:HideAll() end
    last.border = res
    ensureEdges(m)
    layoutEdges(m, cfg, u, l, t, r, b, W, H)
    ensureGrips()
    layoutGrips(m, cfg, u, l, t, r, b)
    -- Klickflaeche auf die sichtbare Karte begrenzen (leere Kopf-/Listenflaeche faengt keine Klicks)
    if cfg.hideHeader or cfg.hideEdges or cfg.questLog ~= "show" then
        try(m, "SetHitRectInsets", l, r, t, b)
    else
        try(m, "SetHitRectInsets", 0, 0, 0, 0)
    end
    -- Knoepfe oben rechts im Rahmen, eine Reihe von rechts nach links ohne Ueberlappung: Lucids Questknopf ganz rechts
    -- (Abstand zum Eck-Griff), links davon Blizzards Kartenrand-Knoepfe (Filter, Kartenpin ...)
    local used = GRIP + 4 -- belegte Breite vom rechten Rand in Host-Einheiten (Bildschirmpixel)
    if cfg.questLog == "toggle" and (_G.QuestMapFrame or m.QuestLog) then
        ensureQuestButton()
        if qbtn then
            qbtn:ClearAllPoints()
            qbtn:SetPoint("TOPRIGHT", m, "TOPRIGHT", -(u * r) - used, -(u * t) - ROW_Y)
            qbtn.label:SetText(Map.questOpen and "«" or "»")
            qbtn:Show()
            used = used + BTN + GAP
        end
    elseif qbtn then
        qbtn:Hide()
    end
    arrangeOverlays(m, u, t, r, used)
    host:Show()
end

-- Eingriff und Ruecksprung -------------------------------------------------------------------------
local function restorePlacement(m)
    if orig.scaleSet then try(m, "SetScale", orig.scale) end
    if orig.posSet and #orig.points > 0 then
        try(m, "ClearAllPoints")
        for _, p in ipairs(orig.points) do try(m, "SetPoint", p[1], p[2], p[3], p[4], p[5]) end
    end
    orig.scaleSet, orig.posSet = false, false
end

-- Open Maps Titelleiste (Streifen oben, 22 hoch, Ziehen) und die beiden Eckgriffe unten (Button, Textur "SizeGrabber") kollidieren mit Lucids
-- Griffen und liegen an den Ecken des ganzen Fensters (weit rechts, wo die Questliste war). Im Lucid-Modus mit Open Map werden sie unbedienbar
-- und unsichtbar gestellt (Maus aus, Deckkraft 0); der Ruecksprung gibt sie zurueck.
-- Open Maps Eckgriff (Map/Window.lua, Grip()): namenloser Button als Kind des WorldMapFrame, Textur UI-ChatIM-SizeGrabber (Pfad oder, wenn der
-- Client die Datei-ID liefert, deren ID), und -- unabhaengig von der Textur -- die Skript-Kombination OnMouseDown + OnMouseUp + OnUpdate + OnHide
-- bei kleiner Groesse (kein anderer Kartenrand-Knopf hat OnUpdate/OnMouseUp).
local GRAB_PATH = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"
local function isOpenMapGrip(c)
    local okN, nt = try(c, "GetNormalTexture")
    if okN and type(nt) == "table" then
        local okT, tex = try(nt, "GetTexture")
        if okT and type(tex) == "string" and tex:find("SizeGrabber", 1, true) then return true end
        if okT and type(tex) == "number" and type(_G.GetFileIDFromPath) == "function" then
            local okF, id = pcall(_G.GetFileIDFromPath, GRAB_PATH)
            if okF and id == tex then return true end
        end
    end
    if type(c.GetScript) ~= "function" then return false end
    local function has(name)
        local ok, f = pcall(c.GetScript, c, name)
        return ok and f ~= nil
    end
    local w, h = frameSize(c)
    local _, ot = try(c, "GetObjectType")
    return ot == "Button" and w > 0 and h > 0 and w <= 40 and h <= 40
        and has("OnMouseDown") and has("OnMouseUp") and has("OnUpdate") and has("OnHide")
end

local function openMapChrome(m)
    local out = {}
    if type(m.GetChildren) ~= "function" then return out end
    for _, c in ipairs({ m:GetChildren() }) do
        if type(c) == "table" and c ~= host and c ~= m.ScrollContainer and c ~= m.BorderFrame then
            local kind
            if isOpenMapGrip(c) then kind = "grip" end
            if not kind and type(c.GetScript) == "function" then
                local okD, drag = pcall(c.GetScript, c, "OnDragStart")
                local _, h = frameSize(c)
                if okD and drag and h == 22 then kind = "handle" end
            end
            if kind then out[#out + 1] = { c, kind } end
        end
    end
    return out
end

local function tameOpenMap(m, on)
    orig.omChrome = orig.omChrome or {}
    if on then
        for _, e in ipairs(openMapChrome(m)) do
            local c, kind = e[1], e[2]
            if not orig.omChrome[c] then
                local _, mouse = try(c, "IsMouseEnabled")
                local _, a = try(c, "GetAlpha")
                orig.omChrome[c] = { mouse = Compat.Bool(mouse), alpha = Compat.Num(a) or 1, kind = kind }
            end
            try(c, "EnableMouse", false)
            if kind == "grip" then try(c, "SetAlpha", 0) end
        end
    else
        for c, st in pairs(orig.omChrome) do
            try(c, "EnableMouse", st.mouse)
            if st.kind == "grip" then try(c, "SetAlpha", st.alpha) end
        end
        orig.omChrome = {}
    end
end

-- Lage und Skala schreibt Lucid nur, wenn sie ihm gehoeren (nicht bei Open Map/extern); was geschrieben wurde, merkt orig
local function placeWindow(m, cfg, external)
    if external then
        if orig.scaleSet or orig.posSet then restoreOpenMap() restorePlacement(m) end -- Besitz an ein anderes Addon abgegeben
        return
    end
    local p = cfg.pos
    mirrorOpenMap(cfg.scale / 100, p and { p.point, p.relPoint, p.x, p.y } or nil)
    try(m, "SetScale", cfg.scale / 100)
    orig.scaleSet = true
    if p then
        try(m, "ClearAllPoints")
        try(m, "SetPoint", p.point, _G.UIParent, p.relPoint, p.x, p.y)
        orig.posSet = true
    elseif orig.posSet then
        restorePlacement(m)
        try(m, "SetScale", cfg.scale / 100)
        orig.scaleSet = true
    end
end

local function revert(m)
    if not touched then return end
    own = true
    if orig then
        restoreOpenMap()
        restorePlacement(m)
        if orig.clamp then try(m, "SetClampRectInsets", orig.clamp[1], orig.clamp[2], orig.clamp[3], orig.clamp[4]) end
        try(m, "SetAlpha", orig.alpha)
        sweep(m, false)
        tameOpenMap(m, false)
        for f, pts in pairs(orig.overlay or {}) do releaseOverlay(f, pts) end
        if not orig.movable then try(m, "SetMovable", false) end
        for name, was in pairs(orig.hidden) do
            local part = orig.parts and orig.parts[name]
            if was and type(part) == "table" then try(part, "Show") end
            -- von Lucid erzwungen gezeigt, urspruenglich aber zu: wieder zu
            if not was and type(part) == "table" and orig.forced and orig.forced[name] then try(part, "Hide") end
        end
    end
    try(m, "SetHitRectInsets", 0, 0, 0, 0)
    Map.FadeStop(m)
    if host then host:Hide() end
    if border then border:HideAll() end
    stopSizing(false)
    if buttons then for _, e in pairs(buttons) do e:Hide() end end
    if grips then for _, g in pairs(grips) do g:Hide() end end
    if qbtn then qbtn:Hide() end
    own = false
    orig, touched = nil, false
    last.engaged, last.hidden = false, {}
end

local function engage(m, cfg)
    ensureSideHook(m) -- Retry, falls der Frame beim ersten Lauf fehlte
    remember(m)
    touched = true
    own = true
    local external = Map.ExternalPlacement(cfg)
    placeWindow(m, cfg, external)
    curAlpha = Map.WantedAlpha(cfg)
    try(m, "SetAlpha", curAlpha)
    Map.FadeSetup(m, cfg)
    -- zuerst wiederherstellen, was nicht mehr ausgeblendet werden soll, dann ausblenden
    local want = {}
    local targets = hideTargets(m, cfg)
    for _, tgt in ipairs(targets) do want[tgt[1]] = true end
    -- Questliste per Lucids Knopf ausgefahren: Blizzards Listen-Frames werden aktiv GEZEIGT (nicht nur "nicht mehr versteckt"). Beim ersten
    -- Oeffnen nach dem Login steht Blizzards eigener Zustand auf "zu" (QuestMapFrame versteckt, spaetere Synchronisierung versteckt ihn
    -- wieder); "was" war dann false und die Liste blieb leer, bis Blizzard sie nach mehrmaligem Oeffnen selbst zeigte. Der Ursprungszustand
    -- bleibt gemerkt (Ruecksprung), nur das Zeigen ist erzwungen.
    local forceQuest = cfg.questLog == "toggle" and Map.questOpen == true
    for name, was in pairs(orig.hidden) do
        if not want[name] then
            local part = orig.parts and orig.parts[name]
            local forced = forceQuest and (name == "QuestMapFrame" or name == "QuestLog")
            if (was or forced) and type(part) == "table" then try(part, "Show") end
            if forced then
                orig.forced = orig.forced or {}
                orig.forced[name] = true
            else
                orig.hidden[name] = nil
                if orig.forced then orig.forced[name] = nil end
            end
        end
    end
    if forceQuest then
        for _, q in ipairs({ _G.QuestMapFrame, m.QuestLog }) do
            if type(q) == "table" and not Compat.Bool(select(2, try(q, "IsShown"))) then try(q, "Show") end
        end
    end
    last.hidden = {}
    for _, tgt in ipairs(targets) do
        local name, part = tgt[1], tgt[2]
        orig.parts = orig.parts or {}
        orig.parts[name] = part
        if orig.hidden[name] == nil then
            local _, shown = try(part, "IsShown")
            orig.hidden[name] = Compat.Bool(shown)
        end
        try(part, "Hide")
        last.hidden[#last.hidden + 1] = name
    end
    sweep(m, cfg.hideEdges)
    tameOpenMap(m, Map.OpenMapLoaded() and not external)
    local okH = ensureHost(m)
    if okH then
        local _, s = try(m, "GetScale")
        local u = Compat.Num(s) or 1
        if u <= 0 then u = 1 end
        layoutBorder(m, cfg, u)
    end
    own = false
    last.engaged, last.external = true, external
end

--- Zustand anwenden. Im Kampf wartet die Aenderung bis PLAYER_REGEN_ENABLED. Ohne aktiven Modus und ohne frueheren
--- Eingriff geschieht nichts.
function Map.Apply()
    local cfg = Map.GetConfig()
    local want = active()
    if not (want or touched) then return false end
    local m = wmf()
    if not m then return false end
    if inCombat() then pending = true return false end
    pending = false
    local ok, err = pcall(function()
        if want and not bypass and not maximized(m) then engage(m, cfg) else revert(m) end
    end)
    own = false
    if not ok then geterrorhandler()(err) end
    return ok
end

--- nach Blizzards eigenem Layout (Anzeige, Zustandswechsel) erneut anwenden
local function reapply()
    if own or sizing or not (touched or active()) then return end
    Map.Apply()
end

-- Lauf-Fade ------------------------------------------------------------------------------------------
-- Blizzards Bewegungs-Fader (mapFade) wuerde gegen Lucids Alpha arbeiten: im Lucid-Modus mit Lauf-Fade nimmt Lucid die Karte
-- aus dem Fader (wie Mapster); Blizzard meldet sie bei jedem Oeffnen selbst wieder an, der Ruecksprung holt das nach.
local FADE_SPEED = 4 -- Alpha je Sekunde (weicher Uebergang)
local faderRemoved = false
function Map.FadeTick(dt)
    local m = wmf()
    if not (m and touched and active()) then return end
    if not Compat.Bool(select(2, try(m, "IsShown"))) then return end -- geschlossene Karte: nichts zu tun
    local target = Map.WantedAlpha()
    local cur = curAlpha or target
    if cur == target then return end
    local step = FADE_SPEED * (tonumber(dt) or 0)
    if cur < target then cur = math.min(target, cur + step) else cur = math.max(target, cur - step) end
    curAlpha = cur
    own = true
    try(m, "SetAlpha", cur)
    own = false
end

function Map.FadeSetup(m, cfg)
    if not cfg.runFade then
        Map.FadeStop(m)
        return
    end
    local f = _G.PlayerMovementFrameFader
    if type(f) == "table" and type(f.RemoveFrame) == "function" then
        if pcall(f.RemoveFrame, m) then faderRemoved = true end
    end
    if not fadeFrame then
        local ok, fr = pcall(CreateFrame, "Frame")
        if not ok or type(fr) ~= "table" then return end
        fadeFrame = fr
    end
    fadeFrame:SetScript("OnUpdate", function(_, dt) Map.FadeTick(dt) end)
end

function Map.FadeStop(m)
    if fadeFrame then fadeFrame:SetScript("OnUpdate", nil) end
    -- zurueck in Blizzards Fader (gleiche Parameter wie WorldMapMixin:OnShow)
    local f = _G.PlayerMovementFrameFader
    if m and faderRemoved and type(f) == "table" and type(f.AddDeferredFrame) == "function" then
        pcall(f.AddDeferredFrame, m, 0.5, 1.0, 0.5, function()
            local okC, v = pcall(GetCVarBool, "mapFade")
            local _, over = try(m, "IsMouseOver")
            return okC and v and not Compat.Bool(over)
        end)
    end
    faderRemoved = false
end

-- Tasten (W3) -------------------------------------------------------------------------------------------
-- Eigene Belegungen "Lucid-Karte" (Bindings.xml: LUCID_MAP) und "Grosse Karte" (LUCID_MAP_BIG: Blizzards Layout fuer diese
-- Oeffnung). Mit takeKey liegen sie auf der Taste der Blizzard-Karte (TOGGLEWORLDMAP, meist M) bzw. Umschalt+Taste. Was Lucid
-- ueberschreibt, steht in LucidDB.mapBindings[Belegungs-Set][Taste] = vorherige Aktion (Account- und Charakter-Set getrennt); beim Ausschalten kommt alles exakt zurueck.
local ACTION, ACTION_BIG = "LUCID_MAP", "LUCID_MAP_BIG"
_G.BINDING_HEADER_LUCID = "Lucid"
_G.BINDING_NAME_LUCID_MAP = L.MAP_BINDING
_G.BINDING_NAME_LUCID_MAP_BIG = L.MAP_BINDING_BIG
local pendingKeys = false
-- Erst nach dem ersten UPDATE_BINDINGS ist die Belegung des Spielers sicher geladen: vorher wird nichts gelesen, gesetzt oder gespeichert
-- (kommt das Ereignis nie, bleibt die Tastenuebernahme aus; die Karte selbst laeuft weiter).
local bindingsReady = false

local function bindingsAvailable()
    return type(_G.GetBindingKey) == "function" and type(_G.SetBinding) == "function" and type(_G.GetBindingAction) == "function"
end

local function saveBindings()
    if type(_G.SaveBindings) == "function" and type(_G.GetCurrentBindingSet) == "function" then
        pcall(_G.SaveBindings, _G.GetCurrentBindingSet())
    end
end

local function bound(key)
    local ok, a = pcall(_G.GetBindingAction, key, true)
    return ok and type(a) == "string" and a or ""
end

-- Belegungen gelten je Tastenbelegungs-Set (1 = Account, 2 = Charakter): mapBindings[set][taste] = vorherige Aktion
local function currentSet()
    if type(_G.GetCurrentBindingSet) == "function" then
        local ok, v = pcall(_G.GetCurrentBindingSet)
        if ok and type(v) == "number" then return v end
    end
    return 1
end

local function records()
    local rec = Store.db.mapBindings
    if type(rec) ~= "table" then rec = {} end
    -- alte flache Form (Taste -> Aktion) dem aktuellen Set zuordnen
    for k, v in pairs(rec) do
        if type(k) == "string" then
            rec[currentSet()] = rec[currentSet()] or {}
            rec[currentSet()][k] = v
            rec[k] = nil
        end
    end
    return rec
end

local function releaseKeys()
    local all = Store.db and Store.db.mapBindings
    if type(all) ~= "table" then return end
    all = records()
    local set = currentSet()
    local rec = all[set]
    if type(rec) ~= "table" then Store.db.mapBindings = next(all) and all or nil return end
    local changed = false
    for key, prev in pairs(rec) do
        local cur = bound(key)
        if cur == ACTION or cur == ACTION_BIG then -- nur zurueck, was noch Lucids ist (zwischenzeitlich umbelegte Tasten bleiben)
            local ok, res
            if type(prev) == "string" and prev ~= "" then ok, res = pcall(_G.SetBinding, key, prev) else ok, res = pcall(_G.SetBinding, key) end
            if ok and res then changed = true end
        end
    end
    all[set] = nil
    Store.db.mapBindings = next(all) and all or nil
    if changed then saveBindings() end
end

local function takeKeys()
    local all = records()
    local set = currentSet()
    local rec = all[set] or {}
    local changed = false
    local function take(key, action)
        local cur = bound(key)
        if cur ~= action then
            local ok, res = pcall(_G.SetBinding, key, action)
            if ok and res then
                changed = true
                if rec[key] == nil then rec[key] = cur end -- nur eintragen, was wirklich uebernommen wurde
            end
        end
    end
    local keys = { _G.GetBindingKey("TOGGLEWORLDMAP") }
    for key in pairs(rec) do if bound(key) == ACTION then keys[#keys + 1] = key end end
    local seen = {}
    for _, key in ipairs(keys) do
        if type(key) == "string" and key ~= "" and not seen[key] then
            seen[key] = true
            take(key, ACTION)
            if not key:find("-", 1, true) then take("SHIFT-" .. key, ACTION_BIG) end
        end
    end
    if next(rec) ~= nil then
        all[set] = rec
        Store.db.mapBindings = all
    end
    if changed then saveBindings() end
end

--- Tastenuebernahme dem Profil angleichen (nur ausserhalb des Kampfs)
function Map.SyncKeys()
    if not bindingsAvailable() or not Store.db then return end
    if not bindingsReady or inCombat() then pendingKeys = true return end
    pendingKeys = false
    local ok, err = pcall(function()
        local cfg = Map.GetConfig()
        if modEnabled and cfg.enabled and cfg.takeKey then takeKeys() else releaseKeys() end
    end)
    if not ok then geterrorhandler()(err) end
end

--- Karte per Taste: big = grosse Ansicht (Blizzards Layout). Eine offene Karte schliesst die Taste wieder.
function Map.Toggle(big)
    local m = wmf()
    local isOpen = m and Compat.Bool(select(2, try(m, "IsShown")))
    if not isOpen then bypass = big and true or false end
    local function open() return m and Compat.Bool(select(2, try(m, "IsShown"))) end
    local steps = {}
    if m then
        if isOpen then
            -- Schliessen: erst Blizzards Weg, dann Rueckfaelle, bis die Karte wirklich zu ist (Taint/fremdes Addon kann einen Weg schlucken)
            steps = {
                function() if type(_G.HideUIPanel) == "function" then _G.HideUIPanel(m) end end,
                function() if type(_G.ToggleWorldMap) == "function" then _G.ToggleWorldMap() end end,
                function() m:Hide() end,
                function() Map.Close() end,
            }
        else
            steps = {
                function() if type(_G.ToggleWorldMap) == "function" then _G.ToggleWorldMap() end end,
                function() if type(_G.ShowUIPanel) == "function" then _G.ShowUIPanel(m) end end,
                function() m:Show() end,
            }
        end
    elseif type(_G.ToggleWorldMap) == "function" then
        steps = { function() _G.ToggleWorldMap() end }
    end
    local tried = 0
    for _, step in ipairs(steps) do
        tried = tried + 1
        pcall(step)
        if not m or (open() and true or false) ~= (isOpen and true or false) then break end
    end
    Map.lastToggle = { wasOpen = isOpen and true or false, steps = tried, nowOpen = open() and true or false }
    if isOpen then bypass = false end
end
_G.LucidToggleMap = function() Map.Toggle(false) end
_G.LucidToggleMapBig = function() Map.Toggle(true) end

-- Blizzards Questpanel-Knopf sofort wieder verbergen, wenn er sich zeigt; fehlt der Frame beim ersten Lauf, beim naechsten Apply erneut
local sideHooked = false
function ensureSideHook(m)
    if sideHooked then return end
    local spt = m.SidePanelToggle
    if type(spt) ~= "table" or type(spt.HookScript) ~= "function" then return end
    sideHooked = true
    pcall(spt.HookScript, spt, "OnShow", function(self)
        if own or not touched or not active() or inCombat() then return end
        if Map.GetConfig().questLog ~= "show" then try(self, "Hide") end
    end)
end

local function ensureHooks()
    local m0 = wmf()
    if m0 then ensureSideHook(m0) end
    if hooked then return end
    local m = wmf()
    if not m then return end
    hooked = true
    if type(m.HookScript) == "function" then
        pcall(m.HookScript, m, "OnShow", reapply)
        pcall(m.HookScript, m, "OnHide", function()
            if bypass then
                bypass = false
                if touched or active() then Map.Apply() end
            end
        end)
        pcall(m.HookScript, m, "OnSizeChanged", function() if touched and not own then Map.Relayout() end end)
        local sc = m.ScrollContainer
        if type(sc) == "table" and type(sc.HookScript) == "function" then
            pcall(sc.HookScript, sc, "OnSizeChanged", function() if touched and not own then Map.Relayout() end end)
        end
    end
    for _, name in ipairs({ "SynchronizeDisplayState", "SetDisplayState", "Maximize", "Minimize", "RefreshOverlayFrames" }) do
        if type(m[name]) == "function" then pcall(hooksecurefunc, m, name, reapply) end
    end
    -- Deckkraft: Blizzards Bewegungs-Fader / fremde Addons setzen Alpha neu => Lucids Wert wiederherstellen
    if type(m.SetAlpha) == "function" then
        pcall(hooksecurefunc, m, "SetAlpha", function()
            if own or not touched or not active() then return end
            own = true
            curAlpha = Map.WantedAlpha()
            try(m, "SetAlpha", curAlpha)
            own = false
        end)
    end
    -- Blizzards Panel-Layout setzt die Lage nach: spaeter noch einmal (naechster Frame)
    for _, name in ipairs({ "UpdateUIPanelPositions", "ShowUIPanel" }) do
        if type(_G[name]) == "function" then
            pcall(hooksecurefunc, name, function(panel)
                if own or not touched then return end
                if panel ~= nil and panel ~= m then return end -- anderes Panel betroffen
                if not Compat.Bool(select(2, try(m, "IsShown"))) then return end
                if C_Timer and C_Timer.After then C_Timer.After(0, reapply) else reapply() end
            end)
        end
    end
end

--- Rahmen neu legen (Groesse geaendert), ohne den Rest anzufassen
function Map.Relayout()
    local m = wmf()
    if not (m and touched and host and not sizing and not inCombat()) then return end
    local cfg = Map.GetConfig()
    local _, s = try(m, "GetScale")
    local u = Compat.Num(s) or 1
    if u <= 0 then u = 1 end
    own = true
    local ok, err = pcall(layoutBorder, m, cfg, u)
    own = false
    if not ok then geterrorhandler()(err) end
end

--- Lage nach dem Ziehen im Profil merken
function Map.SavePosition()
    local m = wmf()
    if not m then return end
    local ok, p, rel, rp, x, y = try(m, "GetPoint", 1)
    x, y = Compat.Num(x), Compat.Num(y)
    if not (ok and p and x and y) then return end
    if rel ~= nil and rel ~= _G.UIParent then return end
    local res = Map.Set({ pos = { point = p, relPoint = rp or p, x = x, y = y } })
    return res
end

--- Aenderung am aktiven Profil (Teilmenge von map), anwenden. true | "deferred" | nil, Fehlercode
function Map.Set(changes)
    local cfg = Map.GetConfig()
    for k, v in pairs(changes) do cfg[k] = v end
    local clean = Map.Validate(cfg)
    if not clean then return nil, "invalid" end
    local p = Store.GetActive()
    if not p then return nil, "invalid" end
    p.map = clean
    Map.Apply()
    Map.SyncKeys()
    return pending and "deferred" or true
end

function Map.IsPending() return pending end

--- Zustand fuer Tests/Diagnose
function Map.State()
    return { engaged = last.engaged, external = last.external, touched = touched, pending = pending, hidden = last.hidden,
        border = last.border, questOpen = Map.questOpen == true, bypass = bypass, pendingKeys = pendingKeys, bindingsReady = bindingsReady, lastToggle = Map.lastToggle }
end
function Map.Parts() return host, border, buttons, qbtn, grips end

ns.RegisterModule("map", {
    OnEnable = function()
        modEnabled = true
        ensureHooks()
        Map.Apply()
        Map.SyncKeys()
    end,
    OnDisable = function()
        modEnabled = false
        Map.Apply() -- Ruecksprung auf Blizzards Layout
        Map.SyncKeys()
    end,
})

Compat.TryOn("PLAYER_REGEN_ENABLED", function()
    if pending then Map.Apply() end
    if pendingKeys then Map.SyncKeys() end
end)
-- Belegung geladen: Nachholen, falls vorher etwas anstand. Eigene SetBinding-Aufrufe loesen das Ereignis erneut aus; das ist
-- harmlos, weil nur bei vorgemerktem Abgleich gearbeitet wird und ein Abgleich ohne Aenderung nichts setzt und nichts speichert.
Compat.TryOn("UPDATE_BINDINGS", function()
    bindingsReady = true
    if pendingKeys then Map.SyncKeys() end
end)
Compat.TryOn("PLAYER_ENTERING_WORLD", function() if modEnabled then ensureHooks() Map.Apply() Map.SyncKeys() end end)
Compat.TryOn("UI_SCALE_CHANGED", function() if touched then Map.Relayout() end end)
Compat.TryOn("DISPLAY_SIZE_CHANGED", function() if touched then Map.Relayout() end end)
Compat.TryOn("ADDON_LOADED", function(_, name)
    if modEnabled and (name == "Blizzard_WorldMap" or name == "OpenMap") then
        ensureHooks()
        Map.Apply()
    end
end)
Store.RegisterCallback(function() if modEnabled then Map.Apply() Map.SyncKeys() end end)

-- Slash-Befehl /lucid map ---------------------------------------------------------------------------
local function enable(on)
    local res, err = Map.Set({ enabled = on })
    if not res then ns.Print(L.MAP_VALUE_INVALID, tostring(err)) return end
    ns.Print(res == "deferred" and L.MAP_DEFERRED or (on and L.MAP_ON or L.MAP_OFF))
end

ns.commands.map = function(rest)
    local sub = (rest or ""):match("^%s*(%S*)"):lower()
    if sub == "" or sub == "status" then
        local cfg = Map.GetConfig()
        ns.Print(L.MAP_STATUS, cfg.enabled and L.NP_YES or L.NP_NO, cfg.questLog, cfg.border, cfg.scale, cfg.alpha,
            Map.ExternalPlacement(cfg) and L.NP_YES or L.NP_NO)
        ns.Print(L.MAP_STATUS_KEYS, bindingsReady and L.NP_YES or L.NP_NO, pendingKeys and L.NP_YES or L.NP_NO)
    elseif sub == "on" or sub == "an" then enable(true)
    elseif sub == "off" or sub == "aus" then enable(false)
    elseif Map.sub[sub] then Map.sub[sub]()
    else ns.Print(L.MAP_UNKNOWN, (sub:gsub("[%c|]", "")):sub(1, 20)) end
end
ns.AddHelp("HELP_MAP")
