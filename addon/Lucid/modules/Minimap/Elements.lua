-- Minimap: Elemente (B6, M6). Je Element eine Sichtbarkeit: always (wie Blizzard, nichts angefasst) | hover (blendet
-- weich ein, solange die Maus ueber der Minimap oder dem Element steht) | off (versteckt). Elemente: Standortname (zone),
-- Uhr (clock), Kalender (calendar), Post (mail), Tracking, Instanz-Schwierigkeit (difficulty), Expansion-Knopf (expansion),
-- Addon-Fach (compartment), Zoom-Knoepfe (zoom; in Cleanup.lua) und Addon-Knoepfe am Rand (buttons, LibDBIcon: nur
-- Sichtbarkeit, keine Neuanordnung).
-- Technik:
--  - off = SetParent an den gemeinsamen versteckten Frame (Cleanup.HiddenParent) + Hook gegen Zurueckhaengen, wie bei
--    den Blizzard-Teilen der eckigen Form.
--  - hover = Alpha, weich nachgefuehrt von einem eigenen OnUpdate (nur solange ein Element hover ist); die Karte
--    (Minimap:IsMouseOver) oder das Element selbst loest aus, sodass auch ein unsichtbares Element erreichbar bleibt.
--    Setzt Blizzard das Alpha zurueck, fuehrt der naechste Takt es nach.
--  - Standortname und Uhr mit Lage oben/unten (nur bei eckiger Form): Lucids eigener Text im Rahmen (Frame.lua), Blizzards
--    Element wird dafuer versteckt; die Sichtbarkeit gilt dann fuer Lucids Text.
--  - Nichts im Kampf (die Anwendung wartet in MM.Apply bis Kampfende), nichts an geschuetzten Frames, Edit-Mode-Frames
--    nur lesen. Bei Standardwerten (alles always, Lage blizzard) ruft Lucid nichts an diesen Elementen auf.
local _, ns = ...
local MM, Compat, L = ns.Minimap, ns.Compat, ns.L
local Cleanup = MM.Cleanup

local E = {}
MM.Elements = E

local driver                 -- OnUpdate-Frame fuer das weiche Ein-/Ausblenden (nur bei Bedarf aktiv)
E.FADE_IN, E.FADE_OUT = 0.15, 0.45 -- Sekunden von 0 auf 1 bzw. zurueck

local function child(parent, key) return type(parent) == "table" and parent[key] or nil end
local function minimap() return type(_G.Minimap) == "table" and _G.Minimap or nil end

--- Frames aus mehreren Kandidaten (nil-sicher, ohne Doppelte)
local function frames(...)
    local out, seen = {}, {}
    for i = 1, select("#", ...) do
        local f = select(i, ...)
        if type(f) == "table" and not seen[f] then
            seen[f] = true
            out[#out + 1] = f
        end
    end
    return out
end

local function container() return child(_G.MinimapCluster, "MinimapContainer") end

-- Addon-Symbole an der Minimap (generisch): Button-Kinder von Minimap, MinimapCluster und MinimapBackdrop, die nicht zu
-- Blizzard gehoeren (Name, bekannte Blizzard-Schluessel, bekannte Elemente), plus LibDBIcon10_*.
local BLIZZARD_NAMES = { "^Minimap", "^MiniMap", "^GameTime", "^TimeManager", "^Expansion", "^Garrison", "^AddonCompartment",
    "^Lucid", "^QueueStatus", "^MinimapCluster" }
-- Karten-Pins (HereBeDragons-Pins haengt sie als Button-Kinder an die Minimap, Questie: "QuestieFrame<n>"): sie sind keine
-- Addon-Symbole und duerfen weder auf den Rand projiziert noch versteckt/ausgeblendet werden. Zusaetzlich zu den Namen
-- liest Lucid die Pin-Register der HBD-Bibliotheken (nur lesend, nil-sicher).
local PIN_NAMES = { "^QuestieFrame", "^HandyNotesPin", "^GatherMatePin", "^GatherMate_", "^HBDPin" }
local PIN_LIBS = { "HereBeDragons-Pins-2.0", "HereBeDragonsQuestie-Pins-2.0" }

--- true, wenn f ein bei HereBeDragons-Pins angemeldeter Minimap-Pin ist
local function isMapPin(f)
    local ls = _G.LibStub
    if ls == nil then return false end
    for _, lib in ipairs(PIN_LIBS) do
        local ok, pins = pcall(function() return ls:GetLibrary(lib, true) end)
        local reg = ok and type(pins) == "table" and pins.minimapPins or nil
        if type(reg) == "table" and reg[f] ~= nil then return true end
    end
    return false
end
local BLIZZARD_KEYS = { "ZoomIn", "ZoomOut", "ZoomHitArea", "Tracking", "IndicatorFrame", "InstanceDifficulty", "BorderTop",
    "ZoneTextButton", "MinimapContainer", "CraftingOrderIcon", "Backdrop", "PlayerCoords", "ExpansionLandingPageMinimapButton",
    "ZoomInButton", "ZoomOutButton" }

local function nameOf(f)
    local ok, n = pcall(function() return f:GetName() end)
    return ok and type(n) == "string" and n or nil
end

local function typeOf(f)
    local ok, t = pcall(function() return f:GetObjectType() end)
    return ok and type(t) == "string" and t or nil
end

local function childrenOf(parent)
    if type(parent) ~= "table" or type(parent.GetChildren) ~= "function" then return {} end
    local ok, kids = pcall(function() return { parent:GetChildren() } end)
    return ok and kids or {}
end

--- Frames, die Lucid selbst oder ein anderes Element besitzt (nie als Addon-Symbol behandeln)
local function knownFrames()
    local set = {}
    for _, t in ipairs(E.TARGETS) do
        if t.key ~= "buttons" then
            for _, f in ipairs(t.get()) do set[f] = true end
        end
    end
    local Frame = MM.Frame
    if Frame and Frame.Parts then
        local fr = Frame.Parts()
        if fr then set[fr] = true end
    end
    if driver then set[driver] = true end
    return set
end

function E.AddonButtons()
    local out, seen, known = {}, {}, knownFrames()
    for _, parent in ipairs(frames(minimap(), _G.MinimapCluster, _G.MinimapBackdrop)) do
        local blizz = {}
        for _, key in ipairs(BLIZZARD_KEYS) do
            local kf = child(parent, key)
            if kf then blizz[kf] = true end
        end
        for _, k in ipairs(childrenOf(parent)) do
            if not seen[k] and not known[k] and not blizz[k] and k ~= parent then
                local name, kind = nameOf(k), typeOf(k)
                local isDb = name and name:find("^LibDBIcon10_") ~= nil
                local isBlizz = false
                if name and not isDb then
                    for _, pat in ipairs(BLIZZARD_NAMES) do
                        if name:find(pat) then isBlizz = true end
                    end
                    for _, pat in ipairs(PIN_NAMES) do
                        if name:find(pat) then isBlizz = true end
                    end
                end
                if not isDb and not isBlizz and isMapPin(k) then isBlizz = true end
                if isDb or (not isBlizz and (kind == "Button" or kind == "CheckButton")) then
                    seen[k] = true
                    out[#out + 1] = k
                end
            end
        end
    end
    return out
end

--- Elemente: key (Profilfeld), get() = Liste der Frames (nil-sicher), fallback() = bekannter Blizzard-Parent
E.TARGETS = {
    -- Standortname: Text und Kasten (BorderTop) zusammen
    { key = "zone", get = function() return frames(child(_G.MinimapCluster, "ZoneTextButton"), child(_G.MinimapCluster, "BorderTop")) end,
        fallback = function() return _G.MinimapCluster end },
    { key = "clock", get = function() return frames(_G.TimeManagerClockButton) end,
        fallback = function() return _G.MinimapCluster end },
    -- Koordinaten unter der Karte: Blizzard zeichnet sie ab 12.1.5 (MinimapContainer.PlayerCoords)
    { key = "coords", get = function() return frames(child(container(), "PlayerCoords"), child(_G.MinimapCluster, "PlayerCoords")) end,
        fallback = container },
    { key = "calendar", get = function() return frames(_G.GameTimeFrame) end, fallback = function() return _G.MinimapCluster end },
    { key = "mail", get = function() return frames(child(child(_G.MinimapCluster, "IndicatorFrame"), "MailFrame")) end,
        fallback = function() return child(_G.MinimapCluster, "IndicatorFrame") end },
    { key = "tracking", get = function() return frames(child(_G.MinimapCluster, "Tracking")) end,
        fallback = function() return _G.MinimapCluster end },
    { key = "difficulty", get = function() return frames(child(_G.MinimapCluster, "InstanceDifficulty")) end,
        fallback = function() return _G.MinimapCluster end },
    { key = "expansion", get = function()
        return frames(_G.ExpansionLandingPageMinimapButton, child(_G.MinimapBackdrop, "ExpansionLandingPageMinimapButton"),
            child(_G.MinimapCluster, "ExpansionLandingPageMinimapButton"), _G.GarrisonLandingPageMinimapButton)
    end, fallback = function() return _G.MinimapBackdrop end },
    { key = "compartment", get = function() return frames(_G.AddonCompartmentFrame, child(_G.MinimapCluster, "AddonCompartmentFrame")) end,
        fallback = function() return _G.MinimapCluster end },
    -- Addon-Knoepfe: erkannte Fremd-Symbole plus Lucids eigener Minimap-Knopf (folgt derselben Sichtbarkeit; Icons.lua
    -- fasst ihn nicht an, er steht nicht in AddonButtons)
    { key = "buttons", get = function()
        local list = E.AddonButtons()
        local lb = MM.Button and MM.Button.Frame and MM.Button.Frame()
        if type(lb) == "table" then list[#list + 1] = lb end
        return list
    end, fallback = minimap },
    -- Zoom-Knoepfe: off und die eckige Form regelt Cleanup.lua; hier nur hover bei runder Form
    { key = "zoom", get = function()
        local m = minimap()
        return frames(child(m, "ZoomIn"), child(m, "ZoomOut"), _G.MinimapZoomIn, _G.MinimapZoomOut)
    end, fallback = minimap, hoverOnly = true },
}

local TEXT_KEYS = { zone = "zonePos", clock = "clockPos", coords = "coordsPos" }

local own = false            -- eigener SetParent-Aufruf laeuft (Hook still)
local dirty = false          -- Hook im Kampf: nach Kampfende nachziehen
local lastActive, lastCfg = false, nil
local items = {}             -- Frame -> { parent, off }
local hookedParent = setmetatable({}, { __mode = "k" })
local hover = {}             -- Region (Frame/FontString) -> { a = Alpha, isFrame }
E.hookCount = 0

local function canCall(obj, name) return type(obj) == "table" and type(obj[name]) == "function" end

local function reparent(obj, parent)
    own = true
    local ok = pcall(obj.SetParent, obj, parent)
    own = false
    return ok
end

local function protected(obj) return Compat.QueryBool(obj, "IsProtected") == true end

-- off ---------------------------------------------------------------------------------------------
local function setOff(f, fallback, key)
    if not canCall(f, "SetParent") or protected(f) then return end
    local st = items[f]
    if not st then
        local ok, p = true, nil
        if canCall(f, "GetParent") then ok, p = pcall(f.GetParent, f) end
        st = { parent = (ok and p) or (fallback and fallback()) or nil, key = key }
        -- schon unter dem versteckten Frame (z. B. von einem anderen Teil): das ist nicht das Original
        if st.parent == Cleanup.HiddenParent() then st.parent = fallback and fallback() or nil end
        items[f] = st
    end
    if not hookedParent[f] then
        hookedParent[f] = true
        E.hookCount = E.hookCount + 1
        hooksecurefunc(f, "SetParent", function(_, p)
            local cur = items[f]
            if own or not cur or not cur.off or p == Cleanup.HiddenParent() then return end
            cur.parent = p -- Blizzard hat neu eingehaengt: das ist ab jetzt das Original
            if MM.InCombat() then dirty = true else reparent(f, Cleanup.HiddenParent()) end
        end)
    end
    st.off = true
    reparent(f, Cleanup.HiddenParent())
end

local function restoreOff(f)
    local st = items[f]
    if not st or not st.off then return end
    st.off = false
    reparent(f, st.parent or _G.UIParent)
    items[f] = nil
end

-- hover -------------------------------------------------------------------------------------------
E.POLL = 0.25 -- Sekunden: Mauspruefung, solange alles eingeschwungen ist (der OnUpdate ruht dann)
local pollGen = 0
local hookedMap = nil

local function stopDriver()
    pollGen = pollGen + 1 -- laufende Mauspruefung verwerfen
    if driver then driver:SetScript("OnUpdate", nil) end
end

local function isHot()
    local m = minimap()
    return m ~= nil and Compat.QueryBool(m, "IsMouseOver") == true
end

local function targetOf(obj, h, hot)
    return (hot or (h.isFrame and Compat.QueryBool(obj, "IsMouseOver") == true)) and 1 or 0
end

local function currentAlpha(obj)
    local ok, cur = pcall(obj.GetAlpha, obj)
    return ok and Compat.Num(cur) or nil
end

--- true, wenn ein Element noch nicht am Ziel ist oder Blizzard sein Alpha veraendert hat
local function unsettled()
    local hot = isHot()
    for obj, h in pairs(hover) do
        if targetOf(obj, h, hot) ~= h.a then return true end
        local cur = currentAlpha(obj)
        if cur == nil or math.abs(cur - h.a) > 0.005 then return true end
    end
    return false
end

local startDriver

--- niedrige Mauspruefung: weckt den Treiber, sobald etwas zu tun ist
local function schedulePoll()
    if not (C_Timer and C_Timer.After) then return startDriver() end
    pollGen = pollGen + 1
    local mine = pollGen
    C_Timer.After(E.POLL, function()
        if mine ~= pollGen or next(hover) == nil then return end
        if unsettled() then startDriver() else schedulePoll() end
    end)
end

local function tick(_, dt)
    local hot = isHot()
    for obj, h in pairs(hover) do
        local target = targetOf(obj, h, hot)
        if target > h.a then
            h.a = math.min(target, h.a + dt / E.FADE_IN)
        elseif target < h.a then
            h.a = math.max(target, h.a - dt / E.FADE_OUT)
        end
        if not (h.isFrame and protected(obj) and MM.InCombat()) then
            local cur = currentAlpha(obj)
            if cur == nil or math.abs(cur - h.a) > 0.005 then pcall(obj.SetAlpha, obj, h.a) end
        end
    end
    if not unsettled() then -- eingeschwungen und Maus ausserhalb: OnUpdate aus, nur noch niedrige Mauspruefung
        driver:SetScript("OnUpdate", nil)
        schedulePoll()
    end
end

function startDriver()
    pollGen = pollGen + 1
    if not driver then driver = CreateFrame("Frame") end
    driver:SetScript("OnUpdate", tick)
end

--- sofort wecken, wenn die Maus die Minimap betritt/verlaesst (lesender HookScript; die Pruefung faengt den Rest)
local function hookMapEnter()
    local m = minimap()
    if not m or hookedMap == m or type(m.HookScript) ~= "function" then return end
    hookedMap = m
    for _, name in ipairs({ "OnEnter", "OnLeave" }) do
        pcall(m.HookScript, m, name, function() if next(hover) ~= nil then startDriver() end end)
    end
end

local function setHover(obj, isFrame, key)
    if not canCall(obj, "SetAlpha") then return end
    if not hover[obj] then
        hover[obj] = { a = 0, isFrame = isFrame, key = key }
        pcall(obj.SetAlpha, obj, 0)
    end
    hookMapEnter()
    startDriver()
end

local function clearHover(obj)
    if hover[obj] then
        hover[obj] = nil
        pcall(obj.SetAlpha, obj, 1)
        if next(hover) == nil then stopDriver() end
    end
end

-- Anwenden ----------------------------------------------------------------------------------------
--- Lucids eigener Text fuer zone/clock (Frame.lua) aktiv? (nur bei eckiger Form und Lage oben/unten)
local function ownText(active, el, key)
    return active and TEXT_KEYS[key] ~= nil and el[TEXT_KEYS[key]] ~= "blizzard"
end

--- Frames eines Elements: gefundene plus bereits gemerkte (ein versteckter Knopf ist kein Kind der Minimap mehr)
local function framesOf(t)
    local out, seen = {}, {}
    for _, f in ipairs(t.get()) do
        seen[f] = true
        out[#out + 1] = f
    end
    for f, st in pairs(items) do
        if st.key == t.key and not seen[f] then seen[f] = true out[#out + 1] = f end
    end
    for f, h in pairs(hover) do
        if h.key == t.key and not seen[f] then seen[f] = true out[#out + 1] = f end
    end
    return out
end

function E.Apply(active, cfg)
    lastActive, lastCfg = active, cfg or lastCfg
    cfg = lastCfg
    dirty = false
    local el = type(cfg.elements) == "table" and cfg.elements or MM.ElementDefaults()
    for _, t in ipairs(E.TARGETS) do
        local mode, lucid = el[t.key], ownText(active, el, t.key)
        if t.hoverOnly then
            -- Zoom: nur hover bei runder Form (Cleanup.lua versteckt bei off und eckiger Form)
            if mode == "hover" and not active or MM.ElementsTouched() then
                for _, f in ipairs(framesOf(t)) do
                    if mode == "hover" and not active then setHover(f, true, t.key) else clearHover(f) end
                end
            end
        -- bei Standardwerten und ohne frueheren Eingriff: kein Aufruf
        elseif mode ~= "always" or lucid or MM.ElementsTouched() then
            for _, f in ipairs(framesOf(t)) do
                if lucid or mode == "off" then
                    clearHover(f)
                    setOff(f, t.fallback, t.key)
                else
                    restoreOff(f)
                    if mode == "hover" then setHover(f, true, t.key) else clearHover(f) end
                end
            end
        end
    end
    -- Lucids eigener Text (Frame.lua): Sichtbarkeit hover => Alpha-Fuehrung
    local Frame = MM.Frame
    for key in pairs(TEXT_KEYS) do
        local fs = Frame and Frame.Text and Frame.Text(key)
        if fs then
            if ownText(active, el, key) and el[key] == "hover" then setHover(fs, false) else clearHover(fs) end
        end
    end
end

--- Elemente mit dem zuletzt angewendeten Zustand erneut anwenden (Lucids Minimap-Knopf entsteht nach dem ersten Apply)
function E.Reapply()
    if lastCfg and not MM.InCombat() then E.Apply(lastActive, lastCfg) end
end

--- Zustand fuer die Anwendung (MM.Apply laeuft auch bei Standardwerten weiter, solange Lucid etwas veraendert hat)
function MM.ElementsTouched()
    return next(items) ~= nil or next(hover) ~= nil
end

MM.OnApply(E.Apply)

-- Spaet entstehende Elemente (Uhr, Addon-Knoepfe) nachziehen; nach Kampfende erledigen, was die Hooks zurueckstellten
Compat.TryOn("PLAYER_REGEN_ENABLED", function()
    if dirty and lastCfg then E.Apply(lastActive, lastCfg) end
end)
local latePending = false
local function late()
    latePending = false
    if lastCfg and MM.ElementsCustom(lastCfg) and not MM.InCombat() then E.Apply(lastActive, lastCfg) end
end
--- ein gemeinsamer Timer fuer alle spaeten Ausloeser (Login, jedes geladene Addon): entprellt
local function scheduleLate(delay)
    if latePending or not (C_Timer and C_Timer.After) then return end
    latePending = true
    C_Timer.After(delay, late)
end
Compat.TryOn("PLAYER_ENTERING_WORLD", function() scheduleLate(1) end)
Compat.TryOn("ADDON_LOADED", function()
    if lastCfg and MM.ElementsCustom(lastCfg) then scheduleLate(1) end
end)

--- Diagnosezeilen: versteckte, hover-gefuehrte und eigene Texte, gefundene Elemente, Kinder von Minimap/MinimapCluster
function MM.ElementLines()
    local off, hov, found = {}, {}, {}
    for _, t in ipairs(E.TARGETS) do
        local fs = t.get()
        found[#found + 1] = t.key .. "=" .. #fs
        for _, f in ipairs(framesOf(t)) do
            if items[f] and items[f].off then off[#off + 1] = t.key end
            if hover[f] then hov[#hov + 1] = t.key end
        end
    end
    local own = {}
    local Frame = MM.Frame
    for key in pairs(TEXT_KEYS) do
        local fs = Frame and Frame.Text and Frame.Text(key)
        if fs and Compat.QueryBool(fs, "IsShown") == true then own[#own + 1] = key end
    end
    table.sort(own)
    local none = L.MINIMAP_NONE
    local function j(t) return #t > 0 and table.concat(t, ", ") or none end
    local lines = { L.MINIMAP_DEBUG_ELEMENTS_STATE:format(j(off), j(hov), j(own)), L.MINIMAP_DEBUG_FOUND:format(table.concat(found, " ")) }
    for _, l in ipairs(E.ChildLines()) do lines[#lines + 1] = l end
    return lines
end

local function clean(s)
    -- erst Steuerzeichen raus und UTF-8-sicher kuerzen, dann | verdoppeln (ein Escape-Paar wird nie zerschnitten)
    s = tostring(s):gsub("%c", "")
    local n = 40
    if #s > n then
        while n > 0 do
            local b = s:byte(n + 1)
            if b and b >= 128 and b <= 191 then n = n - 1 else break end
        end
        s = s:sub(1, n)
    end
    return (s:gsub("|", "||"))
end

--- Name eines Kindes: globaler Name, sonst der Schluessel im Elternobjekt (parentKey), sonst "?"
local function childLabel(parent, k)
    local name = nameOf(k)
    if name then return name end
    for key, v in pairs(parent) do
        if v == k and type(key) == "string" then return "." .. key end
    end
    return "?"
end

--- Kinder von Minimap, MinimapCluster, MinimapBackdrop und MinimapContainer: Name, Typ, sichtbar (damit echte
--- Frame-Namen des Clients melden kann)
function E.ChildLines()
    local lines = {}
    local parents = { { "Minimap", minimap() }, { "MinimapCluster", _G.MinimapCluster }, { "MinimapBackdrop", _G.MinimapBackdrop },
        { "MinimapContainer", container() } }
    for _, p in ipairs(parents) do
        local kids, parts = childrenOf(p[2]), {}
        for i, k in ipairs(kids) do
            if i > 40 then parts[#parts + 1] = "..." break end
            local shown = Compat.QueryBool(k, "IsShown")
            parts[#parts + 1] = ("%s (%s, %s)"):format(clean(childLabel(p[2], k)), clean(typeOf(k) or "?"),
                shown == nil and "?" or (shown and L.MINIMAP_YES or L.MINIMAP_NO))
        end
        if p[2] ~= nil then
            lines[#lines + 1] = #parts > 0 and L.MINIMAP_DEBUG_CHILDREN:format(p[1], table.concat(parts, "; "))
                or L.MINIMAP_DEBUG_CHILDREN_NONE:format(p[1])
        end
    end
    return lines
end

--- Zustand fuer Tests
function E.State()
    local off, hov = {}, {}
    for f, st in pairs(items) do if st.off then off[#off + 1] = f end end
    for f in pairs(hover) do hov[#hov + 1] = f end
    return { off = #off, hover = #hov, dirty = dirty, driver = driver ~= nil and driver:GetScript("OnUpdate") ~= nil,
        latePending = latePending }
end
