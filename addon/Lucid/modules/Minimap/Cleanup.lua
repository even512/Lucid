-- Minimap: Blizzard-Teile bei eckiger Form (B6, M2). Bei square/rect verschwinden der runde Rand, die Kompass-Textur und
-- die Zoom-Knoepfe; Mail, Tracking, Kalender, Uhr, Instanz-Schwierigkeit und Expansion-Knopf bleiben sichtbar und
-- werden an den neuen Rand gelegt. Bei "round" ist alles wieder Blizzard.
-- Technik (Recherche 4a/4b):
--  - Verstecken = SetParent an einen versteckten Frame (+ Hook auf SetParent, falls Blizzard zurueckhaengt). Der
--    Mausrad-Zoom bleibt: Blizzard ruft Minimap.ZoomIn:Click(), das auch an versteckten Knoepfen wirkt.
--  - MinimapBackdrop wird nie versteckt (der Expansion-Knopf ist sein Kind). Jedes Teil ist nil-sicher: fehlt es im
--    Client (BorderTop, DielFrame, spaet geladene Uhr ...), wird es uebersprungen.
--  - Anordnung: ClearAllPoints/SetPoint der Knoepfe relativ zur Minimap (Rechteck: um den Einzug der Maske nach innen
--    versetzt); Blizzards Originalpunkte werden gemerkt und beim Rueckweg wiederhergestellt. Ein Hook auf SetPoint
--    stellt Lucids Platz nach einem Blizzard-Layout wieder her.
--  - Nie MinimapCluster/MinimapContainer anfassen (Bearbeitungsmodus); nichts im Kampf (Nachholen bei PLAYER_REGEN_ENABLED).
local _, ns = ...
local MM, Compat, L = ns.Minimap, ns.Compat, ns.L

local Cleanup = {}
MM.Cleanup = Cleanup

local function minimap() return type(_G.Minimap) == "table" and _G.Minimap or nil end
local function child(parent, key)
    return type(parent) == "table" and parent[key] or nil
end

--- Teile, die bei eckiger Form versteckt werden (nil-sicher aufgeloest)
Cleanup.HIDE = {
    { id = "MinimapCompassTexture", get = function() return _G.MinimapCompassTexture end,
        fallback = function() return _G.MinimapBackdrop end },
    { id = "MinimapCompassTextureUnderlay", get = function() return _G.MinimapCompassTextureUnderlay end,
        fallback = function() return _G.MinimapBackdrop end },
    { id = "ZoomIn", get = function() return child(minimap(), "ZoomIn") end, fallback = minimap, zoom = true },
    { id = "ZoomOut", get = function() return child(minimap(), "ZoomOut") end, fallback = minimap, zoom = true },
    { id = "ZoomHitArea", get = function() return child(minimap(), "ZoomHitArea") end, fallback = minimap, zoom = true },
    -- aeltere/andere Clients: globale Zoom-Knoepfe
    { id = "MinimapZoomIn", get = function() return _G.MinimapZoomIn end, fallback = minimap, zoom = true },
    { id = "MinimapZoomOut", get = function() return _G.MinimapZoomOut end, fallback = minimap, zoom = true },
}

--- Knoepfe, die sichtbar bleiben: Ankerpunkt am Knopf (point), an der Minimap (rel), Versatz (x, y) von der Ecke bzw. Kante
--- des sichtbaren Rechtecks nach aussen. Werte sind Startwerte fuer den Handtest im Client.
Cleanup.PLACE = {
    { id = "Tracking", get = function() return child(_G.MinimapCluster, "Tracking") end,
        point = "TOPLEFT", rel = "TOPLEFT", x = -2, y = 2 },
    { id = "GameTimeFrame", get = function() return _G.GameTimeFrame end,
        point = "TOPRIGHT", rel = "TOPRIGHT", x = 2, y = 2 },
    { id = "InstanceDifficulty", get = function() return child(_G.MinimapCluster, "InstanceDifficulty") end,
        point = "TOPRIGHT", rel = "TOPRIGHT", x = -4, y = -24 },
    { id = "IndicatorFrame", get = function() return child(_G.MinimapCluster, "IndicatorFrame") end,
        point = "BOTTOMRIGHT", rel = "BOTTOMRIGHT", x = 2, y = -2 },
    { id = "ExpansionLandingPageMinimapButton", get = function() return _G.ExpansionLandingPageMinimapButton end,
        point = "BOTTOMLEFT", rel = "BOTTOMLEFT", x = -2, y = -2 },
    { id = "TimeManagerClockButton", get = function() return _G.TimeManagerClockButton end,
        point = "TOP", rel = "BOTTOM", x = 0, y = -2 },
}

local active = false
local dirty = false          -- Hook kam im Kampf: nach Kampfende nachziehen
local own = false            -- eigener SetParent/SetPoint-Aufruf laeuft (Hooks still)
local hiddenFrame
local hidden = {}            -- id -> { obj, parent (Blizzards Eltern) }
local placed = {}            -- id -> { obj, part, points = { {p, rel, relPoint, x, y}, ... } }
-- Hooks bleiben fuer die Lebenszeit des Objekts (hooksecurefunc laesst sich nicht abbauen): je Objekt und Methode
-- genau einer, egal wie oft zwischen rund und eckig gewechselt wird. Die Hooks schlagen den aktuellen Zustand nach.
local hookedParent = setmetatable({}, { __mode = "k" })
local hookedPoint = setmetatable({}, { __mode = "k" })
Cleanup.hookCount = 0
local lastCfg = MM.Defaults()

local function hiddenParent()
    if not hiddenFrame then
        hiddenFrame = CreateFrame("Frame")
        hiddenFrame:Hide()
    end
    return hiddenFrame
end

local function canCall(obj, name) return type(obj) == "table" and type(obj[name]) == "function" end

local function reparent(obj, parent)
    own = true
    local ok = pcall(obj.SetParent, obj, parent)
    own = false
    return ok
end

-- Verstecken -------------------------------------------------------------------------------------
local function hidePart(part)
    local obj = part.get()
    if not canCall(obj, "SetParent") then return end
    local st = hidden[part.id]
    if not st or st.obj ~= obj then
        local ok, p = true, nil
        if canCall(obj, "GetParent") then ok, p = pcall(obj.GetParent, obj) end
        if not (ok and p) then p = part.fallback and part.fallback() or nil end -- GetParent warf: bekannter Blizzard-Parent
        st = { obj = obj, parent = p }
        hidden[part.id] = st
    end
    if not hookedParent[obj] then
        hookedParent[obj] = true
        Cleanup.hookCount = Cleanup.hookCount + 1
        hooksecurefunc(obj, "SetParent", function(_, p)
            local cur = hidden[part.id]
            if own or p == hiddenFrame or not cur or cur.obj ~= obj then return end
            cur.parent = p -- Blizzard hat neu eingehaengt: das ist ab jetzt das Original
            if MM.InCombat() then dirty = true else reparent(obj, hiddenParent()) end
        end)
    end
    reparent(obj, hiddenParent())
end

local function restorePart(id, st)
    -- ohne bekanntes Original (GetParent warf, kein Fallback): UIParent, damit das Teil nicht versteckt bleibt
    reparent(st.obj, st.parent or _G.UIParent)
    hidden[id] = nil
end

-- Anordnen ---------------------------------------------------------------------------------------
local function savePoints(obj)
    local pts = {}
    if canCall(obj, "GetNumPoints") and canCall(obj, "GetPoint") then
        local okN, n = pcall(obj.GetNumPoints, obj)
        for i = 1, (okN and Compat.Num(n)) or 0 do
            local ok, p, rel, relPoint, x, y = pcall(obj.GetPoint, obj, i)
            if ok and p then pts[#pts + 1] = { p, rel, relPoint, x, y } end
        end
    end
    return pts
end

local function put(part, obj, m, l, t, r, b)
    local x, y = part.x, part.y
    if part.rel:find("LEFT") then x = x + l elseif part.rel:find("RIGHT") then x = x - r end
    if part.rel:find("TOP") then y = y - t elseif part.rel:find("BOTTOM") then y = y + b end
    own = true
    pcall(obj.ClearAllPoints, obj)
    pcall(obj.SetPoint, obj, part.point, m, part.rel, x, y)
    own = false
end

local function placePart(part, m, l, t, r, b)
    local obj = part.get()
    if not (canCall(obj, "SetPoint") and canCall(obj, "ClearAllPoints")) then return end
    local st = placed[part.id]
    if not st or st.obj ~= obj then
        st = { obj = obj, points = savePoints(obj) }
        placed[part.id] = st
    end
    st.part = part
    if not hookedPoint[obj] then
        hookedPoint[obj] = true
        Cleanup.hookCount = Cleanup.hookCount + 1
        hooksecurefunc(obj, "SetPoint", function()
            local cur = placed[part.id]
            if own or not active or not cur or cur.obj ~= obj then return end
            if MM.InCombat() then dirty = true return end
            local mm = minimap()
            if mm then put(cur.part, obj, mm, MM.Insets(lastCfg, MM.FrameSize(mm))) end
        end)
    end
    put(part, obj, m, l, t, r, b)
end

local function restorePlace(id, st)
    local obj = st.obj
    if #st.points > 0 and canCall(obj, "SetPoint") and canCall(obj, "ClearAllPoints") then
        own = true
        pcall(obj.ClearAllPoints, obj)
        for _, pt in ipairs(st.points) do pcall(obj.SetPoint, obj, pt[1], pt[2], pt[3], pt[4], pt[5]) end
        own = false
    end
    placed[id] = nil
end

--- gemeinsamer versteckter Frame (auch fuer Elements.lua)
function Cleanup.HiddenParent() return hiddenParent() end

--- eckige Form anwenden (active) bzw. alles zuruecksetzen; cfg = wirksame Minimap-Einstellungen.
--- Die Zoom-Knoepfe versteckt Lucid bei eckiger Form immer, bei runder Form nur mit Element zoom = off.
function Cleanup.Apply(isActive, cfg)
    lastCfg = cfg or lastCfg
    dirty = false
    local zoomOff = type(lastCfg.elements) == "table" and lastCfg.elements.zoom == "off"
    if isActive then
        active = true
        local m = minimap()
        if not m then return end
        for _, part in ipairs(Cleanup.HIDE) do hidePart(part) end
        local l, t, r, b = MM.Insets(lastCfg, MM.FrameSize(m))
        for _, part in ipairs(Cleanup.PLACE) do placePart(part, m, l, t, r, b) end
    elseif active or zoomOff or next(hidden) or next(placed) then
        active = false
        for id, st in pairs(hidden) do
            local keep = false
            for _, part in ipairs(Cleanup.HIDE) do
                if part.id == id and part.zoom and zoomOff then keep = true end
            end
            if not keep then restorePart(id, st) end
        end
        for id, st in pairs(placed) do restorePlace(id, st) end
        if zoomOff then
            for _, part in ipairs(Cleanup.HIDE) do
                if part.zoom then hidePart(part) end
            end
        end
    end
end

MM.OnApply(Cleanup.Apply)

--- true, solange Lucid etwas versteckt oder verschoben hat (MM.Apply laeuft dann auch bei runder Standardform weiter)
function MM.CleanupTouched() return active or next(hidden) ~= nil or next(placed) ~= nil end

-- Hooks im Kampf zurueckgestellt: nach Kampfende nachziehen
Compat.TryOn("PLAYER_REGEN_ENABLED", function()
    if dirty then Cleanup.Apply(active, lastCfg) end
end)

--- Diagnosezeilen: versteckte und angelegte Teile
function MM.CleanupLines()
    local h, p = {}, {}
    for _, part in ipairs(Cleanup.HIDE) do if hidden[part.id] then h[#h + 1] = part.id end end
    for _, part in ipairs(Cleanup.PLACE) do if placed[part.id] then p[#p + 1] = part.id end end
    local none = L.MINIMAP_NONE
    return {
        L.MINIMAP_DEBUG_HIDDEN:format(#h > 0 and table.concat(h, ", ") or none),
        L.MINIMAP_DEBUG_PLACED:format(#p > 0 and table.concat(p, ", ") or none),
    }
end

--- Zustand fuer Tests
function Cleanup.State()
    local h, p = {}, {}
    for id in pairs(hidden) do h[#h + 1] = id end
    for id in pairs(placed) do p[#p + 1] = id end
    table.sort(h)
    table.sort(p)
    return { active = active, dirty = dirty, hidden = h, placed = p }
end
