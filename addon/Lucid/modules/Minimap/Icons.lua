-- Minimap: Addon-Symbole auf den Rand der eckigen Minimap (B6). LibDBIcon und viele Addons mit eigenem Code legen ihr
-- Symbol auf einen Kreis um die Karte (LibDBIcon nach GetMinimapShape auch auf das quadratische Frame, bei rect also in die
-- Luft ueber/neben dem sichtbaren Rechteck). Lucid projiziert alle erkannten Addon-Knoepfe (Erkennung wie das Element
-- "buttons": LibDBIcon10_* und generische Button-Kinder von Minimap/MinimapCluster/MinimapBackdrop), die mit
-- SetPoint("CENTER", Minimap, "CENTER", x, y) an der Minimap haengen, bei square/rect selbst auf den Rand des sichtbaren
-- Rechtecks, im gleichen Winkel und mit dem Abstand, den das Addon waehlt (Kreisradius minus Kartenhaelfte, LibDBIcon 5,
-- Ink & Embers 10; Punkte auf dem Quadrat gelten als 5):
--  - ein hooksecurefunc auf SetPoint des Knopfes zieht jede Aktualisierung (Ziehen, Refresh) nach (eigenes Flag gegen Rekursion);
--  - ein Addon, das beim Ziehen jeden Frame neu setzt (OnUpdate), kostet nur eine Winkelrechnung je Aufruf;
--  - bei Rueckkehr zu "round" werden die Knoepfe im selben Winkel wieder auf den Kreis (Radius Kartenhaelfte + Abstand) gelegt;
--  - nichts im Kampf (Nachholen bei PLAYER_REGEN_ENABLED), nur nicht geschuetzte Frames, spaet entstehende Knoepfe
--    werden nach ADDON_LOADED/Login (entprellt) erfasst.
-- Knoepfe mit anderem Anker (nicht CENTER an der Minimap) bleiben, wo ihr Addon sie hinsetzt.
local _, ns = ...
local MM, Compat = ns.Minimap, ns.Compat

local Icons = {}
MM.Icons = Icons

Icons.RADIUS = 5 -- LibDBIcon: Abstand der Mitte des Knopfes zum Kartenrand

local own = false
local dirty = false
local lastActive, lastCfg = false, nil
local seen = setmetatable({}, { __mode = "k" })     -- Knopf -> true (bekannt und gehookt)
local moved = setmetatable({}, { __mode = "k" })    -- Knopf -> true (von Lucid projiziert)
Icons.hookCount = 0

local function minimap() return type(_G.Minimap) == "table" and _G.Minimap or nil end
local function atan2(y, x) return math.atan2 and math.atan2(y, x) or math.atan(y, x) end

--- Punkt auf dem Rechteck (halbe Breite hw, halbe Hoehe hh) im Winkel a (Bogenmass)
function Icons.RectPoint(a, hw, hh)
    local dx, dy = math.cos(a), math.sin(a)
    local tx = math.abs(dx) > 1e-9 and hw / math.abs(dx) or math.huge
    local ty = math.abs(dy) > 1e-9 and hh / math.abs(dy) or math.huge
    local t = math.min(tx, ty)
    return dx * t, dy * t
end

--- Zielpunkt eines Knopfes im Winkel a: eckig = auf dem sichtbaren Rechteck, rund = auf dem Kreis
Icons.PAD_MAX = 12 -- groesserer Abstand gilt als Punkt auf dem Quadrat (LibDBIcon mit SQUARE), nicht als Kreis

--- Abstand eines Addon-Punkts (x, y) zum Kartenrand: Kreisradius minus Kartenhaelfte; Punkte auf der Quadratkante oder weit
--- ausserhalb des Kreises gelten als Standard (5)
function Icons.PadOf(x, y, size)
    local half = size / 2
    if math.abs(math.max(math.abs(x), math.abs(y)) - (half + Icons.RADIUS)) < 0.6 then return Icons.RADIUS end
    local pad = math.sqrt(x * x + y * y) - half
    if pad < 0 or pad > Icons.PAD_MAX then return Icons.RADIUS end
    return pad
end

local function target(a, active, cfg, m, pad)
    local size = MM.FrameSize(m)
    pad = pad or Icons.RADIUS
    if not active then
        local r = size / 2 + pad
        return math.cos(a) * r, math.sin(a) * r
    end
    local l, t, r, b = MM.Insets(cfg, size)
    local hw = (size - l - r) / 2 + pad
    local hh = (size - t - b) / 2 + pad
    return Icons.RectPoint(a, hw, hh)
end

--- Mittelpunkt (relativ zur Minimap-Mitte) fuer einen Knopf im Winkel a (Bogenmass) im aktuellen Zustand: bei eckiger
--- Form auf dem sichtbaren Rechteck, sonst auf dem Kreis; Abstand pad (Standard 5). Fuer Lucids eigenen Knopf (Button.lua).
function Icons.PointAt(a, pad)
    local m = minimap()
    if not m then return nil end
    return target(a, lastActive, lastCfg, m, pad)
end

local function canCall(obj, name) return type(obj) == "table" and type(obj[name]) == "function" end

--- Addon-Knoepfe: dieselbe Erkennung wie das Element "buttons" (Elements.lua)
local function iconButtons()
    local E = MM.Elements
    return (E and E.AddonButtons and E.AddonButtons()) or {}
end

local padOf = setmetatable({}, { __mode = "k" }) -- Knopf -> Abstand zum Kartenrand, den das Addon gewaehlt hat

local function place(btn, x, y, m)
    own = true
    pcall(btn.ClearAllPoints, btn)
    pcall(btn.SetPoint, btn, "CENTER", m, "CENTER", x, y)
    own = false
end

--- aktueller Winkel eines Knopfes aus seinem Punkt (CENTER relativ zur Minimap); nil, wenn nicht lesbar
local function angleOf(btn, m)
    if not canCall(btn, "GetPoint") then return nil end
    local ok, point, rel, _, x, y = pcall(btn.GetPoint, btn, 1)
    if not ok or point ~= "CENTER" or rel ~= m then return nil end
    x, y = Compat.Num(x), Compat.Num(y)
    if not x or not y or (x == 0 and y == 0) then return nil end
    return atan2(y, x)
end

--- Punkt (CENTER an der Minimap) eines Knopfes: x, y oder nil
local function offsetOf(btn, m)
    if not canCall(btn, "GetPoint") then return nil end
    local ok, point, rel, _, x, y = pcall(btn.GetPoint, btn, 1)
    if not ok or point ~= "CENTER" or rel ~= m then return nil end
    x, y = Compat.Num(x), Compat.Num(y)
    if not x or not y or (x == 0 and y == 0) then return nil end
    return x, y
end

local function hookButton(btn, m)
    if seen[btn] or not canCall(btn, "SetPoint") then return end
    seen[btn] = true
    Icons.hookCount = Icons.hookCount + 1
    hooksecurefunc(btn, "SetPoint", function(_, point, rel, _, x, y)
        if own or not lastActive or point ~= "CENTER" or rel ~= m then return end
        x, y = Compat.Num(x), Compat.Num(y)
        if not x or not y or (x == 0 and y == 0) then return end
        if MM.InCombat() then dirty = true return end
        padOf[btn] = Icons.PadOf(x, y, MM.FrameSize(m)) -- der Punkt kommt vom Addon selbst
        local px, py = target(atan2(y, x), true, lastCfg, m, padOf[btn])
        moved[btn] = true
        place(btn, px, py, m)
    end)
end

--- Knoepfe auf den Rand legen (eckig) bzw. auf den Kreis zurueck (rund)
function Icons.Apply(active, cfg)
    lastActive, lastCfg = active, cfg or lastCfg
    dirty = false
    local m = minimap()
    if not m then return end
    if active then
        for _, btn in ipairs(iconButtons()) do
            hookButton(btn, m)
            local a = angleOf(btn, m)
            if a then
                if not moved[btn] then -- noch der Punkt des Addons: Abstand daraus lernen
                    local x, y = offsetOf(btn, m)
                    padOf[btn] = Icons.PadOf(x, y, MM.FrameSize(m))
                end
                moved[btn] = true
                local px, py = target(a, true, lastCfg, m, padOf[btn])
                place(btn, px, py, m)
            end
        end
    else
        for btn in pairs(moved) do
            local a = angleOf(btn, m)
            if a then
                local px, py = target(a, false, lastCfg, m, padOf[btn])
                place(btn, px, py, m)
            end
            moved[btn] = nil
        end
    end
end

MM.OnApply(Icons.Apply)

Compat.TryOn("PLAYER_REGEN_ENABLED", function()
    if dirty and lastCfg then Icons.Apply(lastActive, lastCfg) end
end)

-- spaet entstehende Knoepfe (LibDBIcon legt sie beim Laden der Addons an): ein gemeinsamer entprellter Timer
local latePending = false
local function late()
    latePending = false
    if lastActive and lastCfg and not MM.InCombat() then Icons.Apply(lastActive, lastCfg) end
end
local function scheduleLate()
    if latePending or not lastActive or not (C_Timer and C_Timer.After) then return end
    latePending = true
    C_Timer.After(1, late)
end
Compat.TryOn("ADDON_LOADED", scheduleLate)
Compat.TryOn("PLAYER_ENTERING_WORLD", scheduleLate)

--- Zustand fuer Tests
function Icons.State()
    local n = 0
    for _ in pairs(moved) do n = n + 1 end
    return { moved = n, dirty = dirty, latePending = latePending }
end
