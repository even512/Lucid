-- Move: Verschiebemodus fuer den Zonentext (B5 Z5). /lucid zone move (spaeter Knopf im Reiter "Zonentext").
--
-- Ablauf: Konfig-Fenster aus, laufende Karte stoppt, ein ziehbarer Rahmen (Groesse der grossen Karte, gestrichelter
-- Rand, Beschriftung, Beispieltext) erscheint an der aktuellen Position, dazu eine feste Leiste
-- "Speichern | Zuruecksetzen | Abbrechen". ESC = Abbrechen. Waehrend des Modus zeigt Lucid keine echte Karte.
-- Speichern rechnet die Rahmenposition (GetCenter/GetTop relativ zu UIParent, skalierungskorrekt) in pos = TOP/x/y um,
-- klemmt sie auf den Bildschirm und die Grenzen von Zone.Validate und schreibt sie ins aktive Profil.
-- Sicherheit/Kampf: nur eigene, ungeschuetzte Frames (kein Blizzard-Frame) - der Modus funktioniert auch im Kampf.
local ADDON_NAME, ns = ...
local Zone, Compat, Store = ns.Zone, ns.Compat, ns.Store
local Card = ns.ZoneCard
local L = ns.L

local Move = {}
ns.ZoneMove = Move

Move.FRAME_NAME = "LucidZoneMove"
Move.BAR_NAME = "LucidZoneMoveBar"
Move.WIDTH = 480              -- Breite des Verschieberahmens (grosse Karte)
Move.PAD = 14                 -- Hoehe = Zonenschriftgroesse + 2 x PAD
Move.DASH, Move.GAP = 8, 6    -- gestrichelter Rand

local active = false
local reopenConfig = false
local frame, bar

-- reine Funktionen --------------------------------------------------------------------------------

local function round(v) return math.floor(v + 0.5) end

local function limit(v)
    local lo, hi = Zone.LIMITS.pos[1], Zone.LIMITS.pos[2]
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

--- Position (TOP-Anker relativ zu UIParent) auf den Bildschirm klemmen: w, h = Rahmengroesse, pw, ph = Bildschirmgroesse
--- (alles in UIParent-Einheiten). Liefert x, y (ganzzahlig, innerhalb der Validate-Grenzen). Ist der Rahmen groesser
--- als der Bildschirm, wird er mittig bzw. oben ausgerichtet.
function Move.Clamp(x, y, w, h, pw, ph)
    local maxX = (pw > w) and (pw - w) / 2 or 0
    local minY = (ph > h) and -(ph - h) or 0
    if x < -maxX then x = -maxX elseif x > maxX then x = maxX end
    if y < minY then y = minY elseif y > 0 then y = 0 end
    return limit(round(x)), limit(round(y))
end

--- aus Mitte/Oberkante des Rahmens (in seinen Einheiten) und Skalen die TOP-Position relativ zu UIParent
function Move.ComputePos(cx, top, fs, pcx, ptop, ps)
    return (cx * fs - pcx * ps) / ps, (top * fs - ptop * ps) / ps
end

local function num(v)
    local ok, n = pcall(Compat.Num, v)
    return ok and n or nil
end

-- Position im Profil -------------------------------------------------------------------------------

--- Position ins aktive Profil schreiben (geprueft ueber Zone.Validate). Liefert true oder nil.
local function writePos(pos)
    local z = Zone.GetConfig()
    z.pos = { point = pos.point, x = pos.x, y = pos.y }
    local valid = Zone.Validate(z)
    if not valid then return nil end
    local p = Store.GetActive()
    if not p then return nil end
    p.zone = valid
    return true
end

local function defaultPos() return Zone.Defaults().pos end

local function placeFrame(pos)
    frame:ClearAllPoints()
    frame:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
end

-- Frames -------------------------------------------------------------------------------------------

local function dashes(f, w, h, color)
    f.dashPool, f.dashUsed = f.dashPool or {}, 0
    for _, t in ipairs(f.dashPool) do t:Hide() end -- Pool wiederverwenden, bei jeder Groessenaenderung neu legen
    local function seg(horizontal, offset, len, fixed)
        f.dashUsed = f.dashUsed + 1
        local t = f.dashPool[f.dashUsed]
        if not t then
            t = f:CreateTexture(nil, "BORDER")
            f.dashPool[f.dashUsed] = t
        end
        t:Show()
        t:ClearAllPoints()
        t:SetColorTexture(color[1], color[2], color[3], color[4])
        if horizontal then
            t:SetSize(len, 1)
            t:SetPoint("TOPLEFT", f, "TOPLEFT", offset, fixed)
        else
            t:SetSize(1, len)
            t:SetPoint("TOPLEFT", f, "TOPLEFT", fixed, -offset)
        end
    end
    local step = Move.DASH + Move.GAP
    local x = 0
    while x < w do
        local len = math.min(Move.DASH, w - x)
        seg(true, x, len, 0)
        seg(true, x, len, -(h - 1))
        x = x + step
    end
    local y = 0
    while y < h do
        local len = math.min(Move.DASH, h - y)
        seg(false, y, len, 0)
        seg(false, y, len, w - 1)
        y = y + step
    end
end

local function buildFrame()
    local cfg = Zone.GetConfig()
    local h = cfg.zone.size + 2 * Move.PAD
    local f = CreateFrame("Frame", Move.FRAME_NAME, UIParent)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetSize(Move.WIDTH, h)
    f:Hide()
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(0.05, 0.05, 0.07, 0.55)
    bg:SetAllPoints(f)
    f.label = f:CreateFontString(nil, "OVERLAY")
    f.label:SetFontObject(_G.GameFontNormal)
    f.label:SetTextColor(0.86, 0.72, 0.45)
    f.label:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -3)
    f.sample = f:CreateFontString(nil, "OVERLAY")
    f.sample:SetJustifyH("CENTER")
    f.sample:SetShadowColor(0, 0, 0, 0.8)
    f.sample:SetShadowOffset(2, -2)
    f.sample:SetTextColor(1, 0.93, 0.76)
    f.sample:SetPoint("CENTER", f, "CENTER", 0, -4)
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    f:SetScript("OnHide", function() if active then Move.Cancel() end end) -- ESC (UISpecialFrames) oder fremdes Hide
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, Move.FRAME_NAME)
    end
    return f
end

local function button(parent, x, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(100, 24)
    b:SetPoint("BOTTOM", parent, "BOTTOM", x, 8)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(0.16, 0.14, 0.10, 0.95)
    bg:SetAllPoints(b)
    b.text = b:CreateFontString(nil, "OVERLAY")
    b.text:SetFontObject(_G.GameFontNormal)
    b.text:SetPoint("CENTER", b, "CENTER", 0, 0)
    b:SetScript("OnClick", onClick)
    return b
end

local function buildBar()
    local b = CreateFrame("Frame", Move.BAR_NAME, UIParent)
    b:SetFrameStrata("DIALOG")
    b:SetFrameLevel(10)
    b:SetSize(340, 64)
    b:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 180)
    b:EnableMouse(true)
    b:Hide()
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(0.05, 0.05, 0.07, 0.9)
    bg:SetAllPoints(b)
    b.hint = b:CreateFontString(nil, "OVERLAY")
    b.hint:SetFontObject(_G.GameFontNormal)
    b.hint:SetPoint("TOP", b, "TOP", 0, -8)
    b.save = button(b, -108, function() Move.Save() end)
    b.reset = button(b, 0, function() Move.ResetFrame() end)
    b.cancel = button(b, 108, function() Move.Cancel() end)
    return b
end

local function refreshTexts()
    local cfg = Zone.GetConfig()
    local h = cfg.zone.size + 2 * Move.PAD
    frame:SetSize(Move.WIDTH, h)
    dashes(frame, Move.WIDTH, h, { 0.80, 0.66, 0.38, 0.9 })
    frame.label:SetText(L.ZONE_MOVE_LABEL)
    Card.ApplyFont(frame.sample, cfg.zone.font, cfg.zone.size)
    frame.sample:SetText(Zone.Clean(L.ZONE_SAMPLE_ZONE))
    bar.hint:SetText(L.ZONE_MOVE_HINT)
    bar.save.text:SetText(L.ZONE_MOVE_SAVE)
    bar.reset.text:SetText(L.ZONE_MOVE_RESET)
    bar.cancel.text:SetText(L.ZONE_MOVE_CANCEL)
end

-- Modus --------------------------------------------------------------------------------------------

function Move.IsActive() return active end

local function finish()
    active = false
    if frame then
        frame:StopMovingOrSizing()
        frame:Hide()
    end
    if bar then bar:Hide() end
    if reopenConfig and ns.Config then ns.Config.Open() end
    reopenConfig = false
end

--- Verschiebemodus starten. Liefert true; laeuft er schon, passiert nichts (false).
function Move.Start()
    if active then return false end
    if ns.Config and ns.Config.IsShown() then
        reopenConfig = true
        ns.Config.Close()
    end
    Zone.Stop() -- laufende echte Karte beenden
    frame = frame or buildFrame()
    bar = bar or buildBar()
    refreshTexts()
    placeFrame(Zone.GetConfig().pos)
    active = true
    frame:Show()
    bar:Show()
    return true
end

--- Rahmenposition lesen und als TOP/x/y (geklemmt) liefern, sonst nil
local function readPos()
    local cx, top = num(frame:GetCenter()), num(frame:GetTop())
    local pcx, ptop = num(UIParent:GetCenter()), num(UIParent:GetTop())
    if not (cx and top and pcx and ptop) then return nil end
    local fs, ps = num(frame:GetEffectiveScale()) or 1, num(UIParent:GetEffectiveScale()) or 1
    if ps <= 0 or fs <= 0 then return nil end
    local x, y = Move.ComputePos(cx, top, fs, pcx, ptop, ps)
    local k = fs / ps
    local pw, ph = num(UIParent:GetWidth()) or 0, num(UIParent:GetHeight()) or 0
    local fw, fh = (num(frame:GetWidth()) or Move.WIDTH) * k, (num(frame:GetHeight()) or 0) * k
    x, y = Move.Clamp(x, y, fw, fh, pw, ph)
    return { point = "TOP", x = x, y = y }
end

--- speichern und Modus beenden. Liefert true; scheitert das Lesen/Schreiben, bleibt der Modus offen (false).
function Move.Save()
    if not active then return false end
    frame:StopMovingOrSizing()
    local pos = readPos()
    if not (pos and writePos(pos)) then
        ns.Print(L.ZONE_MOVE_FAILED)
        return false
    end
    finish()
    ns.Print(L.ZONE_MOVE_SAVED)
    return true
end

--- abbrechen: nichts wird veraendert
function Move.Cancel()
    if not active then return false end
    finish()
    ns.Print(L.ZONE_MOVE_CANCELLED)
    return true
end

--- Rahmen auf die Standardposition setzen (gespeichert wird erst mit "Speichern")
function Move.ResetFrame()
    if not active then return false end
    frame:StopMovingOrSizing()
    placeFrame(defaultPos())
    return true
end

--- gespeicherte Position auf den Standard (TOP 0/-140) zuruecksetzen (Reiter/Befehl)
function Move.ResetPosition()
    local d = defaultPos()
    if not writePos({ point = d.point, x = d.x, y = d.y }) then return false end
    if active then placeFrame(d) end
    return true
end

-- Anbindung ---------------------------------------------------------------------------------------
-- Waehrend des Modus erscheint keine echte Karte.
do
    local present = Zone.Present
    function Zone.Present(card, upgrade)
        if active then return end
        return present(card, upgrade)
    end
    -- Modul ausgeschaltet => Modus beenden (ns.modules.zone.enabled ist da schon false)
    local apply = Zone.Apply
    function Zone.Apply()
        apply()
        local mod = ns.modules and ns.modules.zone
        if active and not (mod and mod.enabled) then Move.Cancel() end
    end
end
-- Profilwechsel/Import/Reset: der Modus gilt dem alten Profil => abbrechen
Store.RegisterCallback(function() if active then Move.Cancel() end end)

Zone.commands.move = function(arg)
    if (arg or ""):lower() == "reset" then
        if Move.ResetPosition() then ns.Print(L.ZONE_POS_RESET) end
        return
    end
    Move.Start()
end
ns.AddHelp("HELP_ZONE_MOVE")
