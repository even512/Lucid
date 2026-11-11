-- Minimap: Zonen-Ornament (Delta Minimap-Ornament, Gestalt Runde 4). Ein dezentes Gold-Ornament oben
-- und rechts um die Karte, je Zone wechselnd (Motive wie die Zonenkarte), mit einem Ring um die Sonne (GameTimeFrame).
-- Nur bei Form rect 4:3, Schalter minimap.ornament an und freigegebenem Motiv (Daten in OrnamentData.lua, erzeugt von
-- scripts/gen-minimap-ornament.mjs); sonst wird nichts gezeigt.
-- Aufbau: EIN Container-Frame als Kind der Minimap (folgt ihrer Skala, blendet mit ihr aus/ein, Maus aus; ornamentTop: s. u.). Seine Mitte ist
-- der Fixpunkt = die Sonnenmitte; alle Stuecke (Leiste oben, Spalte rechts, Ring) liegen relativ dazu genau wie im
-- Referenzbild, jedes als eigene, ungedrehte Textur. Massstab K = Breite des sichtbaren Kartenrechtecks x ornamentSize:
-- die Groesse skaliert alles um die Sonnenmitte, ornamentOffsetX/Y verschieben alles gemeinsam (positiv = rechts/oben),
-- ornamentAlpha ist die Deckkraft. Alle Motive sind im Konverter auf dieselbe Geometrie gebracht (Vorbild dwarf), damit
-- eine Reglereinstellung fuer alle passt.
-- Fixpunkt, in dieser Reihenfolge: (1) das Tag/Nacht-Symbol (Forever: namenloser Frame, Kind von MinimapCluster.MinimapContainer,
-- 42 x 42, mit einer Region, deren Atlas "UI-HUD-Minimap-...Cycle..." heisst; seine Mitte ist die Ringmitte), ohne Abstandsschwelle;
-- (2) die Mitte von GameTimeFrame, wenn sichtbar und plausibel (hoechstens SUN_TOLERANCE Ringradien von der Standardlage entfernt;
-- sonst ist es nicht die gezeichnete Sonne); (3) die Standardlage aus der Referenz relativ zur oberen rechten Ecke des
-- Kartenrechtecks. Die Wahl wird im Takt (0,5 s) nachgeprueft, solange das Ornament sichtbar ist.
-- Ebene: Container-Ebene = Ebene des Rahmens + 1 (Texturen OVERLAY): das Ornament liegt ueber Karte und Bronze-Rahmen; Frame.SetLevel
-- zieht es bei jedem Anwenden nach (Reihenfolge der Listener egal). Unter der Sonne (GameTimeFrame), solange diese hoeher liegt.
-- Schalter ornamentTop: das Ornament liegt sicher ueber Sonne/Mond: Strata des Containers = die hoehere von Minimap und
-- Tag/Nacht-Symbol (sonst GameTimeFrame), Ebene mindestens dessen Ebene + 2 (nur gelesen). Dazu verlaesst der Container die
-- Minimap: als Kind der Minimap zaehlte seine Ebene im Client nicht gegen das Symbol (Forever: Ornament LOW/6 lag sichtbar
-- unter dem Symbol LOW/5 in MinimapContainer). Neuer Elternframe = MinimapCluster (Geschwister von MinimapContainer), sonst
-- UIParent, jeweils nur, wenn weder er noch ein Vorfahr seine Kinder flach zeichnet (GetFlattensRenderLayers). Anker und Masse
-- bleiben; die Skala wird auf die der Minimap umgerechnet (SetScale = Minimap-EffectiveScale / Eltern-EffectiveScale), damit das
-- Ornament pixelgleich sitzt. Sichtbarkeit und Alpha spiegeln die Minimap (IsVisible, GetEffectiveAlpha; Hooks auf Minimap
-- Show/Hide/SetShown/SetAlpha und MinimapCluster SetAlpha, dazu der Takt als Netz; fremde Frames nur gelesen).
-- Aus: alles wie bisher (Kind der Minimap, Skala 1, Strata wie die Minimap). Bewusst nur fuer ornamentTop (Standard an): der Standardweg
-- funktioniert im Client, ein Elternwechsel dort setzte ohne Not das Layering gegen den Bronze-Rahmen aufs Spiel.
-- Motivwahl wie die Zonenkarte: ZoneMotifs.byName (Zonen-/Subzonenname) vor O.MapOverride (nur Minimap) vor ZoneMotifs.byMap[uiMapID]; neu bei
-- Zonenwechsel. Nur eigene Frames werden beschrieben; Tag/Nacht-Symbol und GameTimeFrame werden nur gelesen (als Anker).
local ADDON_NAME, ns = ...
local MM, Compat, L = ns.Minimap, ns.Compat, ns.L

local O = {}
MM.Ornament = O

O.SUN_TOLERANCE = 1 -- Ringradien (bei 100 %), nur fuer GameTimeFrame
O.MIN_ALPHA = 0.05  -- effektives Alpha, ab dem etwas als sichtbar gilt
local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"
local frame
local tex = {}             -- key (top | side | ring) -> Textur
local lastActive, lastCfg = false, nil
local strataSet = false -- Strata des Containers wurde ausdruecklich gesetzt (ornamentTop)
local anchorTarget = nil -- Frame, an dem der Container haengt (nil = Standardlage an der Kartenecke)
local driver               -- eigener Takt-Frame ohne Eltern: laeuft auch, wenn der Container (ornamentTop) ausgeblendet ist
local hooked = false       -- Hooks auf Minimap/MinimapCluster gesetzt (einmalig)
local state = { shown = false, reason = "off" }

local function minimap()
    local m = _G.Minimap
    if type(m) == "table" and type(m.GetScale) == "function" then return m end
    return nil
end

local function data()
    local d = ns.MinimapOrnamentData
    return type(d) == "table" and type(d.motifs) == "table" and d or nil
end

local function call(obj, name, ...)
    if type(obj) ~= "table" or type(obj[name]) ~= "function" then return nil end
    local ok, a, b, c, d = pcall(obj[name], obj, ...)
    if not ok then return nil end
    return a, b, c, d
end

--- Mitte und Groesse eines Frames in Bildschirmpixeln (GetCenter x GetEffectiveScale) oder nil
function O.ScreenCenter(f)
    local x, y = call(f, "GetCenter")
    local e = Compat.Num(call(f, "GetEffectiveScale")) or 1
    x, y = Compat.Num(x), Compat.Num(y)
    if not x or not y then return nil end
    return x * e, y * e, e
end

--- sichtbar: IsVisible und effektives Alpha > MIN_ALPHA (ohne GetEffectiveAlpha: eigenes Alpha)
local function seen(f)
    if call(f, "IsVisible") ~= true then return false end
    local a = Compat.Num(call(f, "GetEffectiveAlpha")) or Compat.Num(call(f, "GetAlpha")) or 1
    return a > O.MIN_ALPHA
end

local function atlasOf(r)
    local a = call(r, "GetAtlas")
    if type(a) == "string" and not Compat.IsSecret(a) then return a end
    return nil
end

--- Atlasname des Tag/Nacht-Symbols: "UI-HUD-Minimap-..." mit "Cycle" (Frame-Cycle, DayCycle, NightCycle)
local function isCycleAtlas(a)
    return type(a) == "string" and a:find("^UI%-HUD%-Minimap%-") ~= nil and a:find("Cycle", 1, true) ~= nil
end

--- Hat der Frame eine Region (oder .Background) mit Cycle-Atlas?
local function hasCycleRegion(f)
    if type(f) ~= "table" then return false end
    local ok, bg = pcall(function() return f.Background end)
    if ok and type(bg) == "table" and isCycleAtlas(atlasOf(bg)) then return true end
    if type(f.GetRegions) == "function" then
        local regs = { pcall(f.GetRegions, f) }
        if regs[1] then
            for i = 2, #regs do
                if type(regs[i]) == "table" and isCycleAtlas(atlasOf(regs[i])) then return true end
            end
        end
    end
    return false
end

local cache = setmetatable({}, { __mode = "v" }) -- schwach: frame (Tag/Nacht-Symbol), parent

local function cycleParents()
    local cl = _G.MinimapCluster
    local mc = type(cl) == "table" and cl.MinimapContainer or nil
    return { mc, _G.Minimap, cl }
end

--- Tag/Nacht-Symbol suchen (Kinder von MinimapContainer, Minimap, MinimapCluster); nur sichtbare Treffer, sonst nil.
--- Der Fund wird gecacht und neu gesucht, wenn er unsichtbar wird, den Elternframe wechselt oder den Atlas verliert.
function O.CycleFrame()
    local c = cache.frame
    if c and seen(c) and call(c, "GetParent") == cache.parent and hasCycleRegion(c) then return c end
    cache.frame, cache.parent = nil, nil
    local done = {}
    for _, parent in ipairs(cycleParents()) do
        if type(parent) == "table" and type(parent.GetChildren) == "function" then
            local kids = { pcall(parent.GetChildren, parent) }
            if kids[1] then
                for i = 2, #kids do
                    local k = kids[i]
                    if type(k) == "table" and not done[k] and k ~= frame then
                        done[k] = true
                        if hasCycleRegion(k) and seen(k) then
                            cache.frame, cache.parent = k, call(k, "GetParent")
                            return k
                        end
                    end
                end
            end
        end
    end
    return nil
end

--- GameTimeFrame, solange er sichtbar ist (Alpha > MIN_ALPHA); sonst nil
function O.GameTime()
    local g = _G.GameTimeFrame
    if seen(g) then return g end
    return nil
end

--- Sonne/Mond als Fixpunkt: Tag/Nacht-Symbol ("cycle"), sonst GameTimeFrame ("sun"), sonst nil
function O.Sun()
    local c = O.CycleFrame()
    if c then return c, "cycle" end
    local g = O.GameTime()
    if g then return g, "sun" end
    return nil
end

local function text(fn)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn)
    if ok and type(v) == "string" and not Compat.IsSecret(v) and v ~= "" then return v end
    return nil
end

--- aktuelle Zone: uiMapID (Zonenebene wie die Zonenkarte), Zonenname, Subzonenname
function O.CurrentZone()
    local id
    if ns.Zone and ns.Zone.CurrentMapId then id = ns.Zone.CurrentMapId() end
    return id, text(_G.GetZoneText), text(_G.GetSubZoneText)
end

--- Nur fuer die Minimap: eigene Motive, die die Zonenkarte (ZoneMotifs) nicht kennt.
--- Greift nur, wenn das Motiv freigegebene Daten hat, sonst gilt ZoneMotifs.
O.MapOverride = {
    [1448] = "legion", [77] = "legion",   -- Teufelswald: Brennende Legion (Zonenkarte: fel)
}

--- Motiv zu Zone (rein): Name aus ZoneMotifs.byName (Zone, dann Subzone), dann Minimap-Override, dann ZoneMotifs.byMap[mapID]; sonst nil
function O.MotifFor(mapID, zone, sub)
    local M = ns.ZoneMotifs or {}
    if type(M.byName) == "table" then
        for _, n in ipairs({ zone or false, sub or false }) do
            if type(n) == "string" and M.byName[n] then return M.byName[n] end
        end
    end
    if type(mapID) ~= "number" or mapID ~= mapID then return nil end
    local o = O.MapOverride[mapID]
    local d = o and data()
    if d and type(d.motifs) == "table" and type(d.motifs[o]) == "table" then return o end
    if type(M.byMap) ~= "table" then return nil end
    return M.byMap[mapID]
end

--- Welches Motiv gilt (rein, ohne Frames)? Liefert Motiv oder nil, Grund:
---   "off" (Schalter aus/Modul aus), "shape" (nicht rect 4:3), "nomotif" (Zone ohne Motiv), "notapproved" (keine Daten)
function O.Wanted(active, cfg, mapID, zone, sub)
    if not (active and type(cfg) == "table" and cfg.ornament) then return nil, "off" end
    if cfg.shape ~= "rect" or cfg.rectRatio ~= "4:3" then return nil, "shape" end
    local motif = O.MotifFor(mapID, zone, sub)
    if not motif then return nil, "nomotif" end
    local d = data()
    if not (d and type(d.motifs[motif]) == "table") then return nil, "notapproved", motif end
    return motif, "ok"
end

local tick = 0
local function onUpdate(_, dt)
    tick = tick + dt
    if tick < 0.5 then return end
    tick = 0
    O.CheckAnchor()
end

local function ensureFrame(m)
    if frame then return true end
    local ok, f = pcall(CreateFrame, "Frame", nil, m)
    if not ok or type(f) ~= "table" then return false end
    frame = f
    pcall(f.EnableMouse, f, false)
    f:SetSize(1, 1)
    local okD, d = pcall(CreateFrame, "Frame", nil, nil)
    if okD and type(d) == "table" then
        driver = d
        d:SetScript("OnUpdate", onUpdate)
    else
        f:SetScript("OnUpdate", onUpdate) -- Notweg: Takt am Container
    end
    return true
end

local function isTop() return type(lastCfg) == "table" and lastCfg.ornamentTop == true end

--- Zeichnet f oder einer seiner Vorfahren seine Kinder flach (GetFlattensRenderLayers)? Unbekannt zaehlt als nein.
local function flattens(f)
    local n = 0
    while type(f) == "table" and n < 20 do
        if call(f, "GetFlattensRenderLayers") == true then return true end
        f = call(f, "GetParent")
        n = n + 1
    end
    return false
end

--- Elternframe fuer ornamentTop: MinimapCluster, sonst UIParent (der erste, der nicht flach zeichnet); nil = keiner
function O.OuterParent()
    for _, p in ipairs({ _G.MinimapCluster, _G.UIParent }) do
        if type(p) == "table" and type(p.GetEffectiveScale) == "function" and not flattens(p) then return p end
    end
    return nil
end

--- gewuenschter Elternframe des Containers je Modus (aus: Minimap; an: OuterParent, sonst Minimap)
local function wantedParent(m)
    if isTop() then return O.OuterParent() or m end
    return m
end

--- Elternframe nachziehen (nur der eigene Container wird umgehaengt); liefert den Elternframe danach
local function reparent(m)
    local p = wantedParent(m)
    if call(frame, "GetParent") ~= p then pcall(frame.SetParent, frame, p) end
    return call(frame, "GetParent") or m
end

--- Ausserhalb der Minimap (ornamentTop): Skala, Alpha und Sichtbarkeit der Minimap spiegeln (an fremden Frames nur gelesen).
--- Skala = Minimap-EffectiveScale / Eltern-EffectiveScale (pixelgleich), Alpha = Deckkraft x Minimap-Alpha / Eltern-Alpha.
--- In der Minimap: Skala 1, Alpha = Deckkraft (der Rest wird geerbt).
function O.Sync()
    if not (frame and lastCfg and state.shown) then return end
    local m = minimap()
    if not m then return end
    local alpha = (Compat.Num(lastCfg.ornamentAlpha) or 100) / 100
    local p = call(frame, "GetParent")
    if p == m or type(p) ~= "table" then
        if call(frame, "GetScale") ~= 1 then pcall(frame.SetScale, frame, 1) end
        pcall(frame.SetAlpha, frame, alpha)
        return
    end
    local me = Compat.Num(call(m, "GetEffectiveScale")) or 1
    local pe = Compat.Num(call(p, "GetEffectiveScale")) or 1
    if me > 0 and pe > 0 then
        local sc = me / pe
        local cur = Compat.Num(call(frame, "GetScale"))
        if not cur or math.abs(cur - sc) > 1e-6 then pcall(frame.SetScale, frame, sc) end
    end
    local ma = Compat.Num(call(m, "GetEffectiveAlpha")) or Compat.Num(call(m, "GetAlpha")) or 1
    local pa = Compat.Num(call(p, "GetEffectiveAlpha")) or 1
    local a = pa > 0 and alpha * ma / pa or 0
    if a > 1 then a = 1 elseif a < 0 then a = 0 end
    pcall(frame.SetAlpha, frame, a)
    if call(m, "IsVisible") == true then frame:Show() else frame:Hide() end
end

local function syncSafe()
    local ok, err = pcall(O.Sync)
    if not ok then geterrorhandler()(err) end
end

--- Hooks (einmalig, erst wenn ornamentTop den Container aus der Minimap nimmt): Minimap Show/Hide/SetShown/SetAlpha,
--- MinimapCluster SetAlpha. Nachher-Hooks, aendern nichts an den fremden Frames.
local function hookMinimap(m)
    if hooked or type(hooksecurefunc) ~= "function" then return end
    hooked = true
    for _, name in ipairs({ "Show", "Hide", "SetShown", "SetAlpha" }) do
        if type(m[name]) == "function" then pcall(hooksecurefunc, m, name, syncSafe) end
    end
    local cl = _G.MinimapCluster
    if type(cl) == "table" and type(cl.SetAlpha) == "function" then pcall(hooksecurefunc, cl, "SetAlpha", syncSafe) end
end

local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }

local function strataOf(f)
    local s = call(f, "GetFrameStrata")
    if type(s) == "string" and not Compat.IsSecret(s) and STRATA[s] then return s end
    return nil
end

--- Ebene: mindestens eine ueber dem Rahmen (Frame.lua, Kind der Minimap auf deren Ebene) und der Karte, damit das Ornament
--- den Rahmen ueberdeckt, wo es ihn kreuzt. Blizzards Tag/Nacht-Symbol (sonst GameTimeFrame) wird nur gelesen: liegt es hoeher,
--- bleibt das Ornament darunter (Sonne ueber dem Ring); liegt es nicht hoeher, hat der Rahmen Vorrang (State.sunBelow, Probe).
--- ornamentTop: mindestens dessen Strata, Ebene mindestens dessen Ebene + 2.
function O.SetLevel(m)
    m = m or minimap()
    if not (frame and m and frame.SetFrameLevel and m.GetFrameLevel) then return end
    local base = Compat.Num(call(m, "GetFrameLevel"))
    if not base then return end
    local bf = MM.Frame and MM.Frame.Parts and MM.Frame.Parts() or nil
    local bl = Compat.Num(call(bf, "GetFrameLevel"))
    if bl and bl > base then base = bl end
    local want = base + 1
    local g = O.CycleFrame() or _G.GameTimeFrame
    local gl = Compat.Num(call(g, "GetFrameLevel"))
    local gs = strataOf(g)
    local ms = strataOf(m)
    local top = isTop()
    local strata -- nil = nicht gesetzt (erbt von der Minimap)
    if top then
        if gl and gl + 2 > want then want = gl + 2 end
        strata = ms
        if gs and (not ms or STRATA[gs] > STRATA[ms]) then strata = gs end
    elseif strataSet and ms then
        strata = ms -- zurueck auf die Strata der Minimap
    end
    if strata and frame.SetFrameStrata then
        pcall(frame.SetFrameStrata, frame, strata)
        strataSet = top
    end
    local own = strataOf(frame) or ms
    if gl and gs and own and own ~= gs then
        state.sunBelow = STRATA[own] > STRATA[gs]
    else
        state.sunBelow = gl ~= nil and gl <= want
    end
    state.top = top
    pcall(frame.SetFrameLevel, frame, want)
end
local setLevel = O.SetLevel

local function hideAll(reason, motif)
    if frame then frame:Hide() end
    state = { shown = false, reason = reason, motif = motif }
end

--- Geometrie (rein aus Minimap und Konfig): W = Breite des sichtbaren Rechtecks, Einzuege, Standardlage der Sonne
--- (Versatz ab Minimap-TOPRIGHT in Minimap-Einheiten) und in Bildschirmpixeln (nil, solange die Minimap kein Rechteck hat)
local function geometry(m, cfg, D)
    local size = MM.FrameSize(m)
    local l, t, r = MM.Insets(cfg, size)
    local W = size - l - r
    local dx, dy = -r + D.sunX * W, -t - D.sunY * W
    local sx, sy
    local left, bottom, w, h = call(m, "GetRect")
    left, bottom, w, h = Compat.Num(left), Compat.Num(bottom), Compat.Num(w), Compat.Num(h)
    local e = Compat.Num(call(m, "GetEffectiveScale")) or 1
    if left and bottom and w and h then sx, sy = (left + w + dx) * e, (bottom + h + dy) * e end
    return W, dx, dy, sx, sy, e
end

--- Fixpunkt waehlen: "cycle" (Tag/Nacht-Symbol, ohne Schwelle), "sun" (GameTimeFrame plausibel) oder "default"; dazu
--- Abstand Symbol <-> Standardlage in Ringradien (nil, wenn unbekannt) und der Ankerframe
function O.ChooseAnchor(m, cfg, D)
    local W, dx, dy, sx, sy, e = geometry(m, cfg, D)
    local sun, kind = O.Sun()
    if not sun then return "default", nil, W, dx, dy end
    local x, y = O.ScreenCenter(sun)
    if not x then return "default", nil, W, dx, dy end
    if kind == "cycle" then
        local d = sx and math.sqrt((x - sx) ^ 2 + (y - sy) ^ 2) / (D.ringR * W * e) or nil
        return "cycle", d, W, dx, dy, sun
    end
    if not sx then return "sun", nil, W, dx, dy, sun end -- Minimap ohne Rechteck: der Sonne vertrauen
    local dist = math.sqrt((x - sx) ^ 2 + (y - sy) ^ 2) / (D.ringR * W * e)
    if dist <= O.SUN_TOLERANCE then return "sun", dist, W, dx, dy, sun end
    return "far", dist, W, dx, dy
end

local function place(m, cfg, D)
    local anchor, dist, W, dx, dy, sun = O.ChooseAnchor(m, cfg, D)
    local K = W * cfg.ornamentSize / 100
    local ox, oy = cfg.ornamentOffsetX, cfg.ornamentOffsetY
    frame:ClearAllPoints()
    if anchor == "sun" or anchor == "cycle" then
        frame:SetPoint("CENTER", sun, "CENTER", ox, oy)
    else
        frame:SetPoint("CENTER", m, "TOPRIGHT", dx + ox, dy + oy)
    end
    for _, p in ipairs(D.pieces) do
        local t = tex[p.key]
        t:SetSize(p.w * K, p.h * K)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", frame, "CENTER", p.x * K, -p.y * K)
    end
    state.anchor, state.dist, state.W, state.K, state.ox, state.oy = anchor, dist, W, K, ox, oy
    anchorTarget = sun -- Ankerframe; nicht in state (Tests serialisieren ihn)
end

--- Ornament anwenden. active = eckige Form; cfg = wirksame Minimap-Einstellungen.
function O.Apply(active, cfg)
    lastActive, lastCfg = active, cfg or lastCfg
    cfg = lastCfg
    local mapID, zone, sub = O.CurrentZone()
    local motif, reason, named = O.Wanted(active, cfg, mapID, zone, sub)
    local m = minimap()
    if not motif or not m then return hideAll(m and reason or "nomap", named) end
    if not ensureFrame(m) then return hideAll("frame") end
    local D = data().motifs[motif]
    local used = {}
    for _, p in ipairs(D.pieces) do
        local t = tex[p.key]
        if not t then
            t = frame:CreateTexture(nil, "OVERLAY")
            tex[p.key] = t
        end
        if t:SetTexture(MEDIA .. p.file) == false then return hideAll("texture", motif) end
        t:SetTexCoord(p.r.x / p.tw, (p.r.x + p.r.w) / p.tw, p.r.y / p.th, (p.r.y + p.r.h) / p.th)
        t:Show()
        used[p.key] = true
    end
    for key, t in pairs(tex) do
        if not used[key] then t:Hide() end
    end
    state = { shown = true, reason = "ok", motif = motif }
    if reparent(m) ~= m then hookMinimap(m) end
    setLevel(m)
    place(m, cfg, D)
    frame:SetAlpha(cfg.ornamentAlpha / 100)
    frame:Show()
    O.Sync() -- ausserhalb der Minimap: Skala, Alpha und Sichtbarkeit wie die Minimap
end

--- Fixpunkt nachpruefen (Takt): setzt nur neu, wenn sich die Wahl Sonne/Standardlage geaendert hat
function O.CheckAnchor()
    if not (state.shown and lastCfg and frame) then return end
    local m = minimap()
    local D = m and data() and data().motifs[state.motif]
    if not D then return end
    local anchor, _, _, _, _, target = O.ChooseAnchor(m, lastCfg, D)
    if anchor ~= state.anchor or target ~= anchorTarget then place(m, lastCfg, D) end
    if reparent(m) ~= m then hookMinimap(m) end -- z. B. ein Vorfahr zeichnet spaeter flach
    setLevel(m) -- Blizzard kann Strata/Ebene des Symbols spaeter aendern; auch sein Auftauchen/Verschwinden zaehlt
    O.Sync() -- Netz zu den Hooks (Skala, Alpha, Sichtbarkeit der Minimap)
end

--- Zustand fuer Tests/Diagnose
function O.State()
    local s = {}
    for k, v in pairs(state) do s[k] = v end
    return s
end

--- Teile fuer Tests: Container, Texturen je Stueck, Takt-Frame
function O.Parts() return frame, tex, driver end

MM.OnApply(O.Apply)

--- erneut anwenden (Zonenwechsel): nur eigene Frames, auch im Kampf erlaubt
function O.Refresh()
    if lastCfg == nil then return end
    local ok, err = pcall(O.Apply, lastActive, lastCfg)
    if not ok then geterrorhandler()(err) end
end
for _, ev in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
    Compat.TryOn(ev, function() O.Refresh() end)
end

-- Slash /lucid minimap ornament on|off|probe ------------------------------------------------------
local REASON = { off = "MINIMAP_ORN_R_OFF", shape = "MINIMAP_ORN_R_SHAPE", nomotif = "MINIMAP_ORN_R_NOMOTIF",
    notapproved = "MINIMAP_ORN_R_NOTAPPROVED", texture = "MINIMAP_ORN_R_TEXTURE", nomap = "MINIMAP_ORN_R_NOMAP",
    frame = "MINIMAP_ORN_R_NOMAP", ok = "MINIMAP_ORN_R_OK" }
local ANCHOR = { cycle = "MINIMAP_ORN_ANCHOR_CYCLE", sun = "MINIMAP_ORN_ANCHOR_SUN", default = "MINIMAP_ORN_ANCHOR_DEFAULT", far = "MINIMAP_ORN_ANCHOR_FAR" }

local function clean(s) return (tostring(s or "-"):gsub("[%c|]", "")):sub(1, 60) end
local function f1(v) return ("%.1f"):format(tonumber(v) or 0) end
local function xy(x, y) return (x and y) and (f1(x) .. ", " .. f1(y)) or "-" end

--- Beschreibung eines Frames: Name, sichtbar, Groesse (eigene Einheiten), Mitte (Bildschirm), EffectiveScale, Alpha
local function frameLine(f, fallbackName)
    local name = call(f, "GetName")
    name = (type(name) == "string" and not Compat.IsSecret(name)) and name or fallbackName or "?"
    local x, y, e = O.ScreenCenter(f)
    return L.MINIMAP_ORN_PROBE_FRAME:format(clean(name), call(f, "IsVisible") == true and L.MINIMAP_YES or L.MINIMAP_NO,
        f1(Compat.Num(call(f, "GetWidth"))), f1(Compat.Num(call(f, "GetHeight"))), xy(x, y), ("%.3f"):format(e or 0),
        ("%.2f"):format(Compat.Num(call(f, "GetEffectiveAlpha")) or Compat.Num(call(f, "GetAlpha")) or 0))
end

--- Kandidaten fuer die gezeichnete Sonne/den Mond: benannte Kinder von MinimapCluster und Minimap mit passendem Namen
local function candidates()
    local out, seen = {}, {}
    for _, parent in ipairs({ _G.MinimapCluster, _G.Minimap }) do
        if type(parent) == "table" and type(parent.GetChildren) == "function" then
            local kids = { pcall(parent.GetChildren, parent) }
            for i = 2, #kids do
                local k = kids[i]
                local n = call(k, "GetName")
                if type(n) == "string" and not Compat.IsSecret(n) and not seen[k] and
                    (n:find("Time") or n:find("Clock") or n:find("Calendar") or n:find("Sun") or n:find("Moon") or n:find("Day")) then
                    seen[k] = true
                    out[#out + 1] = k
                end
            end
        end
    end
    return out
end

-- Suche nach der gezeichneten Sonne/dem Mond (nur lesend) -----------------------------------------
O.SCAN_RADIUS = 30   -- Bildschirmpixel um die Ringmitte
O.SCAN_ALPHA = O.MIN_ALPHA -- effektives Alpha, ab dem etwas als sichtbar gilt
O.SCAN_LINES = 15    -- hoechstens so viele Trefferzeilen
O.SCAN_FRAMES = 60000

--- Name eines Frames/einer Region (GetDebugName, sonst GetName), nie ein Secret
local function objName(o)
    for _, m in ipairs({ "GetDebugName", "GetName" }) do
        local n = call(o, m)
        if type(n) == "string" and not Compat.IsSecret(n) and n ~= "" then return n end
    end
    return "?"
end

--- Text/Zahl fuer die Ausgabe (Secret, Tabellen und nil werden zu "-")
local function shown(v)
    if v == nil or Compat.IsSecret(v) then return "-" end
    local t = type(v)
    if t == "string" or t == "number" then return (tostring(v):gsub("[%c|]", "")):sub(1, 70) end
    return "-"
end

--- Treffer fuer ein Objekt (Frame oder Region) oder nil, wenn es nicht sichtbar oder zu weit von (cx, cy) entfernt ist.
--- pScale/pAlpha: Werte des Elternobjekts als Ersatz, falls die Region sie nicht selbst liefert.
local function hitOf(o, cx, cy, pScale, pAlpha)
    local x, y = call(o, "GetCenter")
    x, y = Compat.Num(x), Compat.Num(y)
    if not x or not y then return nil end
    local e = Compat.Num(call(o, "GetEffectiveScale")) or pScale or 1
    local d = math.sqrt((x * e - cx) ^ 2 + (y * e - cy) ^ 2)
    if d > O.SCAN_RADIUS then return nil end
    local vis = call(o, "IsVisible")
    if vis == nil then vis = call(o, "IsShown") end
    if vis ~= true then return nil end
    local alpha = Compat.Num(call(o, "GetEffectiveAlpha"))
    if not alpha then alpha = (Compat.Num(call(o, "GetAlpha")) or 1) * (pAlpha or 1) end
    if alpha <= O.SCAN_ALPHA then return nil end
    local kind = call(o, "GetObjectType")
    local parent = call(o, "GetParent")
    local isTex = kind == "Texture"
    local layer, sub = call(o, "GetDrawLayer")
    local owner = call(o, "GetFrameStrata") and o or parent -- Regionen: Strata/Ebene des Elternframes
    return { name = objName(o), kind = shown(kind), parent = parent and objName(parent) or "-", d = d, alpha = alpha,
        strata = shown(call(owner, "GetFrameStrata")), level = shown(call(owner, "GetFrameLevel")),
        layer = layer and (shown(layer) .. (sub and ("/" .. shown(sub)) or "")) or "-",
        w = f1(Compat.Num(call(o, "GetWidth"))), h = f1(Compat.Num(call(o, "GetHeight"))), center = xy(x * e, y * e),
        tex = isTex and shown(call(o, "GetTexture")) or "-", atlas = isTex and shown(call(o, "GetAtlas")) or "-" }
end

--- Alle sichtbaren Frames/Regionen mit Mitte hoechstens SCAN_RADIUS px von (cx, cy): sortiert nach Abstand.
--- Liefert Trefferliste (gekuerzt auf SCAN_LINES) und die Gesamtzahl. Nur lesende Aufrufe, alles pcall-geschuetzt.
function O.Scan(cx, cy)
    local hits, seen, mine = {}, {}, {}
    if frame then mine[frame] = true end
    for _, t in pairs(tex) do mine[t] = true end
    local function add(h) if h then hits[#hits + 1] = h end end
    local function visit(f, depth)
        if seen[f] or mine[f] then return end
        seen[f] = true
        local pScale = Compat.Num(call(f, "GetEffectiveScale"))
        local pAlpha = Compat.Num(call(f, "GetEffectiveAlpha"))
        add(hitOf(f, cx, cy, nil, nil))
        if type(f.GetRegions) == "function" then
            local regs = { pcall(f.GetRegions, f) }
            if regs[1] then
                for i = 2, #regs do
                    local r = regs[i]
                    if type(r) == "table" and not seen[r] and not mine[r] then
                        seen[r] = true
                        add(hitOf(r, cx, cy, pScale, pAlpha))
                    end
                end
            end
        end
        if depth > 0 and type(f.GetChildren) == "function" then
            local kids = { pcall(f.GetChildren, f) }
            if kids[1] then
                for i = 2, #kids do
                    if type(kids[i]) == "table" then visit(kids[i], depth - 1) end
                end
            end
        end
    end
    for _, root in ipairs({ _G.Minimap, _G.MinimapCluster, _G.GameTimeFrame }) do
        if type(root) == "table" then visit(root, 2) end
    end
    local ef = _G.EnumerateFrames
    if type(ef) == "function" then
        local ok, f = pcall(ef)
        local n = 0
        while ok and type(f) == "table" and n < O.SCAN_FRAMES do
            n = n + 1
            visit(f, 0)
            ok, f = pcall(ef, f)
        end
    end
    table.sort(hits, function(a, b) return a.d < b.d end)
    local total = #hits
    for i = total, O.SCAN_LINES + 1, -1 do hits[i] = nil end
    return hits, total
end

--- Ringmitte in Bildschirmpixeln: Mitte des Containers, sonst die Standardlage (nil, wenn beides unbekannt)
local function ringCenter(m, cfg)
    if frame and call(frame, "IsShown") == true then
        local x, y = O.ScreenCenter(frame)
        if x then return x, y end
    end
    local D = data() and data().motifs[state.motif or O.MotifFor(O.CurrentZone()) or ""]
    if m and D then
        local _, _, _, sx, sy = geometry(m, cfg, D)
        if sx then return sx, sy end
    end
    return nil
end

--- Wert einer optionalen Abfrage fuer die Probe (erste vorhandene Methode; "-" = fehlt, wirft oder Secret)
local function ask(f, ...)
    for _, name in ipairs({ ... }) do
        if type(f) == "table" and type(f[name]) == "function" then
            local ok, v = pcall(f[name], f)
            if not ok or v == nil or Compat.IsSecret(v) then return "-" end
            if type(v) == "boolean" then return v and L.MINIMAP_YES or L.MINIMAP_NO end
            return clean(v)
        end
    end
    return "-"
end

--- Zeichen-Eigenschaften: flacht Kinder, Ebene/Strata fest, Strata, Level, Toplevel, Elternname (nur lesend)
local function renderLine(f, label)
    local par = call(f, "GetParent")
    return L.MINIMAP_ORN_PROBE_RENDER:format(label, ask(f, "GetFlattensRenderLayers"),
        ask(f, "IsFrameLevelFixed", "IsFixedFrameLevel"), ask(f, "IsFixedFrameStrata"), ask(f, "GetFrameStrata"),
        ask(f, "GetFrameLevel"), ask(f, "IsToplevel"), par and clean(objName(par)) or "-")
end

--- Frames fuer die Zeichen-Zeilen: Minimap, MinimapContainer, MinimapCluster, Tag/Nacht-Symbol, Ornament-Container
local function renderTargets()
    local cl = _G.MinimapCluster
    local out = {}
    local function add(f, label) if type(f) == "table" then out[#out + 1] = { f, label } end end
    add(_G.Minimap, "Minimap")
    add(type(cl) == "table" and cl.MinimapContainer or nil, "MinimapContainer")
    add(cl, "MinimapCluster")
    add(O.CycleFrame(), "Cycle")
    add(frame, "Ornament")
    return out
end

--- Diagnosezeilen (Motiv, Zone, Fixpunkt, Sonne, Container, Stuecke, Kandidaten)
function O.ProbeLines()
    local cfg = MM.GetConfig()
    local mapID, zone, sub = O.CurrentZone()
    local yn = function(b) return b and L.MINIMAP_YES or L.MINIMAP_NO end
    local s = state
    local lines = {
        L.MINIMAP_ORN_PROBE_CFG:format(yn(cfg.ornament), cfg.shape, cfg.rectRatio, tostring(cfg.ornamentSize),
            tostring(cfg.ornamentOffsetX), tostring(cfg.ornamentOffsetY), tostring(cfg.ornamentAlpha)),
        L.MINIMAP_ORN_PROBE_ZONE:format(clean(zone), clean(sub), tostring(mapID or "-")),
        L.MINIMAP_ORN_PROBE_MOTIF:format(clean(s.motif or O.MotifFor(mapID, zone, sub)), L[REASON[s.reason] or "MINIMAP_ORN_R_OFF"]),
    }
    local d = data()
    lines[#lines + 1] = L.MINIMAP_ORN_PROBE_DATA:format(d and table.concat(d.order or {}, ", ") or "-")
    local g = _G.GameTimeFrame
    lines[#lines + 1] = L.MINIMAP_ORN_PROBE_SUN:format(yn(O.GameTime() ~= nil))
    if type(g) == "table" then lines[#lines + 1] = frameLine(g, "GameTimeFrame") end
    if frame then
        lines[#lines + 1] = L.MINIMAP_ORN_PROBE_LAYER:format(clean(call(frame, "GetFrameStrata")),
            clean(call(frame, "GetFrameLevel")), yn(cfg.ornamentTop), clean(call(g, "GetFrameStrata")),
            clean(call(g, "GetFrameLevel")), yn(s.sunBelow))
    end
    local m = minimap()
    for _, r in ipairs(renderTargets()) do lines[#lines + 1] = renderLine(r[1], r[2]) end
    if s.shown and m and d then
        local D = d.motifs[s.motif]
        local _, _, _, sx, sy = geometry(m, cfg, D)
        if s.anchor == "cycle" and anchorTarget then
            local tx, ty = O.ScreenCenter(anchorTarget)
            lines[#lines + 1] = L.MINIMAP_ORN_PROBE_CYCLE:format(clean(call(anchorTarget, "GetFrameStrata")),
                clean(call(anchorTarget, "GetFrameLevel")), xy(tx, ty))
        else
            lines[#lines + 1] = L.MINIMAP_ORN_PROBE_ANCHOR:format(L[ANCHOR[s.anchor] or "MINIMAP_ORN_ANCHOR_DEFAULT"],
                s.dist and ("%.2f"):format(s.dist) or "-", xy(sx, sy))
            lines[#lines + 1] = L.MINIMAP_ORN_PROBE_NOCYCLE
        end
        local cx, cy, ce = O.ScreenCenter(frame)
        lines[#lines + 1] = L.MINIMAP_ORN_PROBE_SIZE:format(f1(s.W), f1(s.K), f1(s.ox), f1(s.oy), xy(cx, cy), ("%.3f"):format(ce or 0))
        for _, p in ipairs(D.pieces) do
            local t = tex[p.key]
            lines[#lines + 1] = L.MINIMAP_ORN_PROBE_PIECE:format(p.key, f1(t and t:GetWidth()), f1(t and t:GetHeight()),
                f1(p.x * s.K), f1(-p.y * s.K), p.file)
        end
    end
    for _, k in ipairs(candidates()) do
        if k ~= g then lines[#lines + 1] = frameLine(k) end
    end
    -- Wer macht GameTimeFrame unsichtbar? Lucids Kalender-Einstellung, eigenes Alpha, Eltern
    if type(g) == "table" then
        local el = type(cfg.elements) == "table" and cfg.elements or {}
        local par = call(g, "GetParent")
        lines[#lines + 1] = L.MINIMAP_ORN_PROBE_CAL:format(shown(el.calendar), shown(("%.2f"):format(Compat.Num(call(g, "GetAlpha")) or 0)),
            par and objName(par) or "-", shown(("%.2f"):format(Compat.Num(call(par, "GetAlpha")) or 0)),
            shown(("%.2f"):format(Compat.Num(call(par, "GetEffectiveAlpha")) or 0)))
    end
    -- Suche nach allem Sichtbaren um die Ringmitte (der gezeichnete Mond ist evtl. nicht GameTimeFrame)
    local rx, ry = ringCenter(m, cfg)
    if rx then
        local hits, total = O.Scan(rx, ry)
        lines[#lines + 1] = L.MINIMAP_ORN_PROBE_SCAN:format(xy(rx, ry), tostring(O.SCAN_RADIUS), tostring(total), tostring(O.SCAN_LINES))
        for _, h in ipairs(hits) do
            lines[#lines + 1] = L.MINIMAP_ORN_PROBE_HIT:format(h.name, h.kind, h.parent, h.strata, h.level, h.layer, h.w, h.h,
                h.center, f1(h.d), ("%.2f"):format(h.alpha), h.tex, h.atlas)
        end
    else
        lines[#lines + 1] = L.MINIMAP_ORN_PROBE_NOSCAN
    end
    return lines
end

local function word(arg)
    return ((arg or ""):match("^%s*(%S+)") or ""):lower()
end

MM.commands.ornament = function(arg)
    local v = word(arg)
    if v == "on" or v == "off" then
        local res = MM.Set({ ornament = v == "on" })
        if res == "deferred" then ns.Print(L.MINIMAP_DEFERRED) else ns.Print(v == "on" and L.MINIMAP_ORN_ON or L.MINIMAP_ORN_OFF) end
        local cfg = MM.GetConfig()
        if v == "on" and not (cfg.shape == "rect" and cfg.rectRatio == "4:3") then ns.Print(L.MINIMAP_ORN_ONLY_43) end
    elseif v == "probe" then
        local function out()
            for _, line in ipairs(O.ProbeLines()) do ns.Print(line) end
        end
        -- Kopierfenster (UI/CopyBox.lua), falls vorhanden und nicht schon vom Slash-Verteiler mitgeschrieben
        if ns.CopyBox and ns.CopyBox.Capture and not ns.printSink then
            ns.CopyBox.Capture("/lucid minimap ornament probe", out)
        else
            out()
        end
    else
        ns.Print(L.MINIMAP_ORN_INVALID, (v:gsub("[%c|]", "")):sub(1, 20))
    end
end
ns.AddHelp("HELP_MINIMAP_ORNAMENT")
