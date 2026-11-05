-- Minimap: Rahmen und N-Markierung (B6, M3). Nur bei eckiger Form (square/rect); bei "round" ist alles Blizzard.
-- Aufbau: ein Frame als Kind von Minimap (er blendet mit der Minimap aus und wird mit Minimap:Hide() versteckt, die
-- Maus laeuft durch: EnableMouse(false), der Mausrad-Zoom bleibt nativ). Darin acht Texturen nach dem Neun-Teile-Prinzip:
-- vier Ecken in fester Groesse, vier gleichfoermige Kantenstreifen gedehnt (Daten aus Frames.lua, erzeugt von
-- scripts/gen-minimap-media.mjs). Die Stufe (Eckgroesse in Pixeln) wird nach physischen Pixeln gewaehlt wie bei der
-- Zonenkarte (B5): kleinste Stufe, die nicht hochskaliert wird.
-- Staerke: borderSize 50-200 % skaliert Ecken und Kanten gemeinsam und ist unabhaengig von der Kartengroesse
-- (minimap.scale): der Frame hebt die Skala der Minimap wieder auf (SetScale(1 / Minimap-Skala)).
-- Lage: das Rahmenband liegt aussen am sichtbaren Rechteck (bei rect: Maske, nicht der quadratische Frame), mit leichter
-- Ueberlappung nach innen; Ecken ragen mit ihrem Ueberstand ueber das Band hinaus. Nur eigene Frames werden beschrieben.
-- Die N-Markierung ("N" oben mittig) steht nur bei eckiger Form und ausgeschalteter Kartendrehung.
-- M6: Standortname und Uhr als Lucids eigener Text im Rahmen (Lage oben/unten, Schriftgroesse, Bronze-Ton), wenn die
-- Elemente-Einstellung zonePos/clockPos nicht "blizzard" ist; Blizzards Element versteckt dann Elements.lua.
local ADDON_NAME, ns = ...
local MM, Compat, L = ns.Minimap, ns.Compat, ns.L

local Frame = {}
MM.Frame = Frame

local frame, north, border
local pieces, mids = {}, {} -- TL TR BL BR top bottom left right -> Textur; Mittelschmuck der Kanten (aus ns.FrameBorder)
local hookedScale = setmetatable({}, { __mode = "k" })
local texts = {}        -- zone, clock -> FontString (Lucids eigener Text im Rahmen)
local TEXT_POS = { zone = "zonePos", clock = "clockPos", coords = "coordsPos" }
local TEXT_ORDER = { "zone", "clock", "coords" }
local BRONZE, PLAIN = { 0.86, 0.66, 0.38 }, { 1, 0.82, 0.3 }
local lastActive, lastCfg = false, nil
local state = { shown = false }

local function minimap()
    local m = _G.Minimap
    if type(m) == "table" and type(m.GetScale) == "function" then return m end
    return nil
end

--- Der Rahmen liegt auf der Ebene der Karte selbst (Kinder liegen ueber ihrem Elternframe): alle anderen Kinder der Minimap
--- (Addon-Knoepfe mit Ebene 8, Post, Tracking ...) liegen darueber. Wird bei jedem Anwenden erneuert.
function Frame.SetLevel(m)
    if not (frame and frame.SetFrameLevel and m.GetFrameLevel) then return end
    local okL, lvl = pcall(m.GetFrameLevel, m)
    lvl = okL and Compat.Num(lvl) or nil
    if lvl then pcall(frame.SetFrameLevel, frame, lvl) end
end

local function ensureFrame(m)
    if frame then return true end
    local ok, f = pcall(CreateFrame, "Frame", nil, m)
    if not ok or type(f) ~= "table" then return false end
    frame = f
    pcall(f.EnableMouse, f, false)
    -- Aendert sich die Skala der Minimap oder ihres Behaelters (Bearbeitungsmodus "Groesse", fremde Addons), wird die
    -- Stufe neu gewaehlt. Nur lesende Hooks (hooksecurefunc), nichts wird an Blizzard-Frames geschrieben.
    local container = type(_G.MinimapCluster) == "table" and _G.MinimapCluster.MinimapContainer or nil
    for _, obj in ipairs({ m, container }) do
        if type(obj) == "table" and type(obj.SetScale) == "function" and not hookedScale[obj] then
            hookedScale[obj] = true
            hooksecurefunc(obj, "SetScale", function() Frame.Refresh() end)
        end
    end
    Frame.SetLevel(m)
    border = ns.FrameBorder.New(f)
    pieces, mids = border.pieces, border.mids
    for key in pairs(TEXT_POS) do
        local t = f:CreateFontString(nil, "OVERLAY")
        if t.SetJustifyH then t:SetJustifyH("CENTER") end
        texts[key] = t
    end
    local fs = f:CreateFontString(nil, "OVERLAY")
    local okF = fs.SetFont and pcall(fs.SetFont, fs, _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    if not okF and fs.SetFontObject and _G.GameFontNormal then pcall(fs.SetFontObject, fs, _G.GameFontNormal) end
    if fs.SetTextColor then fs:SetTextColor(1, 0.82, 0.3) end
    fs:SetText("N")
    north = fs
    return true
end

local function layoutBorder(m, cfg, u, W, H, l, t, r, b)
    local res = border:Layout(m, { style = cfg.border, borderSize = cfg.borderSize, u = u, W = W, H = H, l = l, t = t, r = r, b = b })
    if not res then return false end
    state.mids = res.mids
    state.style, state.level, state.k, state.cornerPx = res.style, res.level, res.k, res.cornerPx
    return true
end

local function rotating()
    if type(GetCVar) ~= "function" then return false end
    local ok, v = pcall(GetCVar, "rotateMinimap")
    return ok and Compat.IsSecret(v) == false and v == "1"
end

-- Texte -------------------------------------------------------------------------------------------
local function cleanText(v)
    if type(v) ~= "string" or Compat.IsSecret(v) then return "" end
    -- Zone.Clean: Steuerzeichen raus, UTF-8-sicher kuerzen, erst danach | verdoppeln (ein Escape-Paar wird nie zerschnitten)
    local z = ns.Zone
    if z and z.Clean then return z.Clean(v) end
    local s = (v:gsub("%c", "")):sub(1, 80)
    return (s:gsub("|", "||"))
end

local function zoneString()
    local fn = _G.GetMinimapZoneText or _G.GetZoneText
    if type(fn) ~= "function" then return "" end
    local ok, v = pcall(fn)
    return ok and cleanText(v) or ""
end

local function clockString()
    if type(_G.GameTime_GetTime) == "function" then
        local ok, v = pcall(_G.GameTime_GetTime, false)
        if ok and type(v) == "string" and not Compat.IsSecret(v) then return cleanText(v) end
    end
    return date and date("%H:%M") or ""
end

-- Spielerkoordinaten wie Blizzards PlayerCoords: Prozent der Zonenkarte, eine Nachkommastelle; ohne Position (Instanz): "--"
local function coordsString()
    local C = _G.C_Map
    if type(C) ~= "table" or type(C.GetBestMapForUnit) ~= "function" or type(C.GetPlayerMapPosition) ~= "function" then return "" end
    local ok, mapId = pcall(C.GetBestMapForUnit, "player")
    mapId = ok and Compat.Num(mapId) or nil
    if not mapId then return "--" end
    local ok2, pos = pcall(C.GetPlayerMapPosition, mapId, "player")
    if not ok2 or type(pos) ~= "table" or type(pos.GetXY) ~= "function" then return "--" end
    local ok3, x, y = pcall(pos.GetXY, pos)
    x, y = ok3 and Compat.Num(x) or nil, ok3 and Compat.Num(y) or nil
    if not x or not y then return "--" end
    return ("%.1f, %.1f"):format(x * 100, y * 100)
end

local TEXT_STRING = { zone = zoneString, clock = clockString, coords = coordsString }

--- Texte aktualisieren (Zonenwechsel, Uhr und Koordinaten im Takt)
function Frame.UpdateTexts()
    for key, fs in pairs(texts) do
        if fs:IsShown() then fs:SetText(TEXT_STRING[key]()) end
    end
end

local clockElapsed = 0
local function clockTick(_, dt)
    clockElapsed = clockElapsed + dt
    if clockElapsed < 0.5 then return end
    clockElapsed = 0
    for _, key in ipairs({ "clock", "coords" }) do
        local fs = texts[key]
        if fs and fs:IsShown() then fs:SetText(TEXT_STRING[key]()) end
    end
end

local function wantsText(active, el, key)
    return active and type(el) == "table" and el[TEXT_POS[key]] ~= "blizzard" and el[key] ~= "off"
end

local function layoutTexts(m, u, cfg, l, t, r, b, W, showN)
    local el = cfg.elements
    local bronze = el.bronze and BRONZE or PLAIN
    local size = el.fontSize
    -- welche Texte sind an? je Kante gezaehlt (oben/unten): Standortname mittig, Uhr rechts, Koordinaten links, sobald
    -- mehrere auf derselben Kante stehen
    local on, perEdge = {}, { top = 0, bottom = 0 }
    for _, key in ipairs(TEXT_ORDER) do
        on[key] = wantsText(true, el, key)
        if on[key] then perEdge[el[TEXT_POS[key]]] = perEdge[el[TEXT_POS[key]]] + 1 end
    end
    local running = false
    for _, key in ipairs(TEXT_ORDER) do
        local fs = texts[key]
        if not on[key] then
            fs:Hide()
        else
            local okF = fs.SetFont and pcall(fs.SetFont, fs, _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "OUTLINE")
            if not okF and fs.SetFontObject and _G.GameFontNormal then pcall(fs.SetFontObject, fs, _G.GameFontNormal) end
            if fs.SetTextColor then fs:SetTextColor(bronze[1], bronze[2], bronze[3]) end
            local edge = el[TEXT_POS[key]]
            local top = edge == "top"
            local point = top and "TOP" or "BOTTOM"
            local y = top and (-(u * t) - 4 - (showN and (size + 2) or 0)) or (u * b + 4)
            local x = (u * (l - r)) / 2
            local shared = perEdge[edge] > 1
            if shared and key == "clock" then
                point = top and "TOPRIGHT" or "BOTTOMRIGHT"
                x = -(u * r) - 6
            elseif shared and key == "coords" then
                point = top and "TOPLEFT" or "BOTTOMLEFT"
                x = u * l + 6
            end
            fs:SetWidth(math.max(40, W * (shared and 0.34 or 0.8)))
            fs:ClearAllPoints()
            fs:SetPoint(point, m, point, x, y)
            fs:Show()
            if key ~= "zone" then running = true end
        end
    end
    Frame.UpdateTexts()
    frame:SetScript("OnUpdate", running and clockTick or nil)
end

--- Textobjekt (zone | clock | coords) oder nil, solange noch nicht angelegt (fuer Elements.lua und Tests)
function Frame.Text(key) return texts[key] end

--- Rahmen und N-Markierung anwenden. active = eckige Form; cfg = wirksame Minimap-Einstellungen.
function Frame.Apply(active, cfg)
    lastActive, lastCfg = active, cfg or lastCfg
    cfg = lastCfg
    local wantBorder = active and cfg and cfg.border ~= "none"
    local wantNorth = active and cfg and cfg.northMarker
    local wantText = false
    if active and cfg then
        for _, key in ipairs(TEXT_ORDER) do wantText = wantText or wantsText(true, cfg.elements, key) end
    end
    local m = minimap()
    if not m or not (wantBorder or wantNorth or wantText) then
        if frame then
            frame:Hide()
            for _, fs in pairs(texts) do fs:Hide() end
            frame:SetScript("OnUpdate", nil)
            state.shown = false
        end
        return
    end
    if not ensureFrame(m) then return end
    local okS, u = pcall(m.GetScale, m)
    u = okS and Compat.Num(u) or 1
    if u <= 0 then u = 1 end
    pcall(frame.SetScale, frame, 1 / u) -- Rahmenstaerke unabhaengig von der Kartengroesse
    Frame.SetLevel(m)
    local size = MM.FrameSize(m)
    local l, t, r, b = MM.Insets(cfg, size)
    local W, H = u * (size - l - r), u * (size - t - b)
    local shownBorder = wantBorder and layoutBorder(m, cfg, u, W, H, l, t, r, b)
    if not shownBorder then
        for _, tex in pairs(pieces) do tex:Hide() end
        for _, tex in pairs(mids) do tex:Hide() end
        state.mids = false
        state.style, state.level, state.k, state.cornerPx = nil, nil, nil, nil
    end
    local showN = wantNorth and not rotating()
    if showN then
        north:ClearAllPoints()
        north:SetPoint("TOP", m, "TOP", 0, -(u * t) - 3)
        north:Show()
    else
        north:Hide()
    end
    state.north = showN and true or false
    layoutTexts(m, u, cfg, l, t, r, b, W, showN)
    frame:Show()
    state.shown = true
end

--- Zustand fuer Tests/Diagnose
function Frame.State()
    return { shown = state.shown, mids = state.mids, style = state.style, level = state.level, k = state.k, cornerPx = state.cornerPx,
        north = state.north }
end

--- Teile fuer Tests: Textur-Tabelle und Frame
function Frame.Parts() return frame, pieces, north, mids end

MM.OnApply(Frame.Apply)

--- erneut zeichnen (Bildschirmgroesse/UI-Skala, Kartendrehung): nur eigene Frames, auch im Kampf erlaubt
--- erneut zeichnen (Stufe/Anordnung neu bestimmen); Skalierungs-Hooks laufen auch waehrend Lucids eigenem Anwenden
local refreshing = false
function Frame.Refresh()
    if refreshing or not (lastCfg and state.shown) then return end
    refreshing = true
    local ok, err = pcall(Frame.Apply, lastActive, lastCfg)
    refreshing = false
    if not ok then geterrorhandler()(err) end
end
local refresh = Frame.Refresh
for _, ev in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA", "PLAYER_ENTERING_WORLD" }) do
    Compat.TryOn(ev, function() if state.shown then Frame.UpdateTexts() end end)
end
Compat.TryOn("UI_SCALE_CHANGED", refresh)
Compat.TryOn("DISPLAY_SIZE_CHANGED", refresh)
Compat.TryOn("CVAR_UPDATE", function(_, name)
    if name == "rotateMinimap" then refresh() end
end)

--- Diagnosezeilen: Rahmen
function MM.FrameLines()
    local cfg = MM.GetConfig()
    local yn = cfg.northMarker and L.MINIMAP_YES or L.MINIMAP_NO
    if state.shown and state.style then
        local label = L["MINIMAP_BORDER_" .. state.style]
        return { L.MINIMAP_DEBUG_BORDER:format(label, tostring(cfg.borderSize), tostring(state.level), state.cornerPx or 0,
            state.k or 0, yn) }
    end
    local reason = cfg.shape == "round" and L.MINIMAP_REASON_ROUND
        or (cfg.border == "none" and L.MINIMAP_REASON_NONE or L.MINIMAP_REASON_STYLE)
    return { L.MINIMAP_DEBUG_BORDER_OFF:format(reason) }
end
