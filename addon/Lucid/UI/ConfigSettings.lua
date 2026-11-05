-- Eintrag "Lucid" im Blizzard-Optionsmenue (Settings-API, Retail 10.0+ / Forever 12.1): eine Canvas-Seite mit
-- kurzer Beschreibung und dem Knopf "Oeffnen", der das eigene Konfig-Fenster zeigt. Nur per Existenzpruefung und
-- pcall; gibt es die API nicht, bleibt /lucid der Weg ins Fenster. Das Optionsmenue selbst wird nicht angefasst
-- (kein Schliessen/Umbau aus Addon-Code); das Lucid-Fenster liegt in einer hoeheren Ebene darueber.
local _, ns = ...
local Config, W = ns.Config, ns.Widgets
local L = ns.L
local C = W.COLORS

local SettingsLink = {}
Config.Settings = SettingsLink

local function available()
    return type(Settings) == "table" and type(Settings.RegisterCanvasLayoutCategory) == "function"
        and type(Settings.RegisterAddOnCategory) == "function"
end

function SettingsLink.Register()
    if SettingsLink.category or not available() then return SettingsLink.category ~= nil end
    local panel = CreateFrame("Frame")
    panel.name = "Lucid"
    local title = W.Text(panel, "GameFontNormalLarge", C.accent)
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Lucid")
    local desc = W.Text(panel, "GameFontHighlight", C.text)
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
    desc:SetWidth(560)
    desc:SetText(L.UI_SETTINGS_DESC)
    local open = W.Button(panel, L.UI_SETTINGS_OPEN, 160, function() Config.Open() end)
    open:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)
    panel.open = open
    SettingsLink.panel = panel

    local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, "Lucid")
    if not ok or not category then return false end
    if not pcall(Settings.RegisterAddOnCategory, category) then return false end
    SettingsLink.category = category
    return true
end

ns.On("ADDON_LOADED", function(_, name)
    if name ~= ns.name then return end
    xpcall(SettingsLink.Register, geterrorhandler())
end)
