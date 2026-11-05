-- Minimap: Lucids eigener Minimap-Knopf (B9-Nachtrag), ohne Bibliothek.
--  - Linksklick: Lucid-Fenster oeffnen/schliessen (wie /lucid). Rechtsklick: kleines Kontextmenue (MenuUtil) mit
--    Preset, Kamera-Voreinstellung, Kartenmodus und Zonentext; jeder Eintrag ruft die vorhandene Funktion bzw. den
--    vorhandenen Slash-Befehl auf (nichts doppelt). Ohne MenuUtil oeffnet der Rechtsklick das Fenster.
--  - Ziehen: der Knopf folgt dem Mauswinkel um die Minimap; bei eckiger Form (square/rect) liegt er wie die fremden
--    Addon-Symbole auf dem Rand des sichtbaren Rechtecks (Icons.PointAt), sonst auf dem Kreis. Der Winkel (Grad) steht im
--    Minimap-Abschnitt des Profils (buttonAngle); "button" (Standard an) blendet den Knopf ein/aus (/lucid minimap button).
--  - Der Knopf ist ein Kind der Minimap: Lucids Ausblenden (Alpha/Minimap:Hide) nimmt ihn mit. Sein Name beginnt mit
--    "Lucid", dadurch zaehlt er nicht als fremdes Addon-Symbol (Icons.lua fasst ihn nicht an), folgt aber der Sichtbarkeit
--    "Addon-Knoepfe" der Minimap-Elemente (Elements.lua: aus = versteckt, hover = bei Maus ueber der Karte); "button"
--    (Minimap-Knopf zeigen) bleibt zusaetzliche Bedingung.
--  - Nur ein ungeschuetzter Frame, keine geschuetzten Aktionen; im Kampf erlaubt ist, was /lucid dort auch darf.
local ADDON_NAME, ns = ...
local MM, Compat, Store, L = ns.Minimap, ns.Compat, ns.Store, ns.L

local Button = {}
MM.Button = Button

Button.NAME = "LucidMinimapButton"
Button.SIZE = 31
Button.ICON = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\icon"
Button.DEFAULT_ANGLE = 225

local frame
local function minimap() return type(_G.Minimap) == "table" and _G.Minimap or nil end
local function atan2(y, x) return math.atan2 and math.atan2(y, x) or math.atan(y, x) end

-- Lage ----------------------------------------------------------------------------------------------
--- Mittelpunkt des Knopfes (relativ zur Minimap-Mitte) fuer einen Winkel in Grad; nil ohne Minimap
function Button.Offset(deg)
    local icons = MM.Icons
    if not (icons and icons.PointAt) then return nil end
    return icons.PointAt(math.rad(deg))
end

function Button.Place(deg)
    local m = minimap()
    if not (frame and m) then return false end
    local x, y = Button.Offset(deg or MM.GetConfig().buttonAngle)
    if not x then return false end
    pcall(frame.ClearAllPoints, frame)
    pcall(frame.SetPoint, frame, "CENTER", m, "CENTER", x, y)
    return true
end

--- Winkel (Grad, 0-360) aus Mauslage (Bildschirmpixel) und Kartenmitte; nil bei unlesbaren Werten
function Button.AngleFrom(dx, dy)
    dx, dy = Compat.Num(dx), Compat.Num(dy)
    if not dx or not dy or (dx == 0 and dy == 0) then return nil end
    return math.deg(atan2(dy, dx)) % 360
end

-- Aktionen ------------------------------------------------------------------------------------------
function Button.ToggleWindow()
    local C = ns.Config
    if C and C.Toggle then C.Toggle() end
end

local function refreshConfig()
    local C = ns.Config
    if C and C.IsShown and C.IsShown() and C.Refresh then C.Refresh() end
end

--- wirksames Alpha des Knopfes (Produkt ueber die Eltern); unlesbar = 1. Bei Immersion bliebe der Knopf sonst unsichtbar
--- klick- und hoverbar: Klicks und Tooltip ruhen, solange die Minimap praktisch unsichtbar ist (der Mausbereich bleibt
--- unveraendert, damit Lucids Einblenden per Mouseover der Karte nicht gestoert wird).
Button.MIN_ALPHA = 0.05
function Button.EffectiveAlpha()
    local a, f, n = 1, frame, 0
    while type(f) == "table" and n < 8 do
        if type(f.GetAlpha) == "function" then
            local ok, v = pcall(f.GetAlpha, f)
            v = ok and Compat.Num(v) or nil
            if v then a = a * v end
        end
        f = type(f.GetParent) == "function" and f:GetParent() or nil
        n = n + 1
    end
    return a
end
local function seeable() return Button.EffectiveAlpha() >= Button.MIN_ALPHA end

--- Eintraege des Kontextmenues in root (MenuUtil-Wurzel). Jeder Aufruf geht an bestehende Funktionen.
function Button.BuildMenu(root)
    if type(root.CreateTitle) == "function" then root:CreateTitle(L.MMBTN_TITLE) end
    local Presets = ns.Presets
    if Presets and Presets.ORDER then
        local sub = root:CreateButton(L.MMBTN_MENU_PRESET)
        for _, key in ipairs(Presets.ORDER) do
            sub:CreateButton(L["PRESET_" .. key], function()
                ns.commands.preset(key)
                refreshConfig()
            end)
        end
    end
    local Camera = ns.Camera
    if Camera and Camera.PRESET_ORDER and Camera.ApplyPreset then
        local sub = root:CreateButton(L.MMBTN_MENU_CAMERA)
        for _, id in ipairs(Camera.PRESET_ORDER) do
            sub:CreateButton(L["UI_CAM_PRESET_" .. id], function()
                ns.commands.camera("preset " .. id) -- vorhandener Befehl: Anwenden, Sperr-Hinweis, Meldung
                refreshConfig()
            end)
        end
    end
    local Map = ns.Map
    if Map and Map.GetConfig and ns.commands.map then
        root:CreateCheckbox(L.MMBTN_MENU_MAP, function() return Map.GetConfig().enabled == true end, function()
            ns.commands.map(Map.GetConfig().enabled and "off" or "on")
            refreshConfig()
        end)
    end
    local Zone = ns.Zone
    if Zone and Zone.GetConfig and ns.commands.zone then
        root:CreateCheckbox(L.MMBTN_MENU_ZONE, function() return Zone.GetConfig().enabled == true end, function()
            ns.commands.zone(Zone.GetConfig().enabled and "off" or "on")
            refreshConfig()
        end)
    end
end

function Button.OpenMenu()
    local owner = frame
    if type(_G.MenuUtil) == "table" and type(_G.MenuUtil.CreateContextMenu) == "function" and owner then
        local ok, err = pcall(_G.MenuUtil.CreateContextMenu, owner, function(_, root) Button.BuildMenu(root) end)
        if ok then return true end
        geterrorhandler()(err)
    end
    -- Rueckfall (kein Menue-System): das Lucid-Fenster
    local C = ns.Config
    if C and C.Open then C.Open() end
    return false
end

-- Knopf ---------------------------------------------------------------------------------------------
local function tooltip(self)
    local tip = _G.GameTooltip
    if not tip or not seeable() then return end
    tip:SetOwner(self, "ANCHOR_LEFT")
    tip:SetText(L.MMBTN_TITLE, 1, 0.82, 0)
    tip:AddLine(L.MMBTN_TIP_LEFT, 0.8, 0.8, 0.8)
    tip:AddLine(L.MMBTN_TIP_RIGHT, 0.8, 0.8, 0.8)
    tip:AddLine(L.MMBTN_TIP_DRAG, 0.8, 0.8, 0.8)
    tip:Show()
end

local function hideTip()
    if _G.GameTooltip and _G.GameTooltip.Hide then _G.GameTooltip:Hide() end
end

--- laufender Zug: Winkel aus der Mausposition, Knopf mitfuehren (nichts wird gespeichert)
local function dragTick()
    local m = minimap()
    if not m or type(m.GetCenter) ~= "function" or type(_G.GetCursorPosition) ~= "function" then return end
    local mx, my = m:GetCenter()
    local cx, cy = _G.GetCursorPosition()
    local s = type(m.GetEffectiveScale) == "function" and Compat.Num(m:GetEffectiveScale()) or 1
    mx, my, cx, cy = Compat.Num(mx), Compat.Num(my), Compat.Num(cx), Compat.Num(cy)
    if not (mx and my and cx and cy and s and s > 0) then return end
    local a = Button.AngleFrom(cx / s - mx, cy / s - my)
    if a then
        Button.dragAngle = a
        Button.Place(a)
    end
end

--- Zug beenden: OnUpdate weg, zuletzt gelesenen Winkel speichern (nur wenn ein Zug lief)
function Button.EndDrag()
    if not frame then return end
    frame:SetScript("OnUpdate", nil)
    local a = Button.dragAngle
    Button.dragAngle = nil
    if a then MM.Set({ buttonAngle = a }, true) end
    Button.Place()
end

function Button.Create()
    if frame then return frame end
    local m = minimap()
    if not m then return nil end
    local ok, f = pcall(CreateFrame, "Button", Button.NAME, m)
    if not ok or type(f) ~= "table" then return nil end
    frame = f
    f:SetSize(Button.SIZE, Button.SIZE)
    f:SetFrameStrata("MEDIUM")
    f:SetFrameLevel(8)
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    f:RegisterForDrag("LeftButton")
    local overlay = f:CreateTexture(nil, "OVERLAY")
    overlay:SetSize(53, 53)
    overlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    overlay:SetPoint("TOPLEFT", 0, 0)
    local back = f:CreateTexture(nil, "BACKGROUND")
    back:SetSize(20, 20)
    back:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    back:SetPoint("TOPLEFT", 7, -5)
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetTexture(Button.ICON)
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    icon:SetPoint("TOPLEFT", 7, -6)
    f:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    f.icon, f.overlay = icon, overlay
    f:SetScript("OnClick", function(_, button)
        hideTip()
        if not seeable() then return end
        if button == "RightButton" then Button.OpenMenu() else Button.ToggleWindow() end
    end)
    f:SetScript("OnEnter", tooltip)
    f:SetScript("OnLeave", hideTip)
    f:SetScript("OnDragStart", function(self)
        hideTip()
        Button.dragAngle = nil
        self:SetScript("OnUpdate", dragTick)
    end)
    f:SetScript("OnDragStop", function() Button.EndDrag() end)
    -- Minimap (oder Knopf) mitten im Zug versteckt: kein OnDragStop => Zug hier sauber beenden, letzten Winkel speichern
    f:SetScript("OnHide", function() Button.EndDrag() end)
    return f
end

--- Zustand aus dem Profil uebernehmen: anlegen, zeigen/verstecken, platzieren. Ein laufender Zug bleibt unberuehrt.
function Button.Refresh()
    local cfg = MM.GetConfig()
    if cfg.button and not frame then
        Button.Create()
        -- der Knopf folgt der Sichtbarkeit "Addon-Knoepfe" (Elements.lua): nach dem Entstehen nachziehen
        if frame and MM.Elements and MM.Elements.Reapply then MM.Elements.Reapply() end
    end
    if not frame then return end
    if cfg.button then
        if not Button.dragAngle then Button.Place(cfg.buttonAngle) end
        frame:Show()
    else
        frame:SetScript("OnUpdate", nil)
        Button.dragAngle = nil
        frame:Hide()
    end
end

--- Zustand fuer Tests/Diagnose
function Button.Frame() return frame end

MM.OnApply(function() Button.Refresh() end)
Store.RegisterCallback(function() Button.Refresh() end)
Compat.TryOn("PLAYER_ENTERING_WORLD", function() Button.Refresh() end)

-- Slash: /lucid minimap button [on|off] -- ohne Angabe umschalten ---------------------------------
MM.commands.button = function(arg)
    local a = (arg or ""):lower()
    local want
    if a == "" then want = not MM.GetConfig().button
    elseif a == "on" or a == "an" then want = true
    elseif a == "off" or a == "aus" then want = false
    else
        ns.Print(L.MINIMAP_ONOFF_INVALID, (a:gsub("[%c|]", "")):sub(1, 20))
        return
    end
    if not MM.Set({ button = want }, true) then return end
    ns.Print(want and L.MMBTN_SHOWN or L.MMBTN_HIDDEN)
    local C = ns.Config
    if C and C.IsShown and C.IsShown() and C.Refresh then C.Refresh() end
end
ns.AddHelp("HELP_MINIMAP_BUTTON")
