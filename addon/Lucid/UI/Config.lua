-- Konfig-Fenster (Spec 3.5, B4): eigenes, ungeschuetztes Fenster mit Reitern. /lucid ohne Argument oeffnet bzw.
-- schliesst es, ESC schliesst es (UISpecialFrames), verschiebbar, Position im DB (LucidDB.configPos).
--
-- Reiter melden sich per Config.RegisterPage an (UI/ConfigHide.lua, ConfigChat.lua, ConfigProfiles.lua) und werden
-- beim ersten Oeffnen gebaut (kein Aufwand beim Login). Alle Aenderungen laufen ueber die Modul-APIs (Elements.Set,
-- Presets.Apply, Glass.Set, Store.*) und wirken sofort (Live-Vorschau). "Zustand simulieren" setzt einen Override
-- im State (State.SetOverride), der echte Zustand bleibt unberuehrt; beim Schliessen endet die Simulation.
--
-- Taint/Kampf: das Fenster darf im Kampf offen sein und bedient werden. Es fasst selbst keine Blizzard-Frames an;
-- Maus-Aenderungen an Blizzard-Frames laufen ausschliesslich ueber die Kampfsperre des Faders.
local _, ns = ...
local State, Store = ns.State, ns.Store
local W = ns.Widgets
local L = ns.L
local C = W.COLORS

local Config = {}
ns.Config = Config

Config.FRAME_NAME = "LucidConfigFrame"
Config.WIDTH, Config.HEIGHT = 800, 620
Config.pages, Config.pageOrder = {}, {}

local frame

--- Reiter anmelden. def = { label = Locale-Schluessel, build = function(page), refresh = function(page) }
function Config.RegisterPage(id, def)
    assert(type(id) == "string" and not Config.pages[id], "Lucid: Reiter fehlt oder doppelt: " .. tostring(id))
    def.id = id
    Config.pages[id] = def
    Config.pageOrder[#Config.pageOrder + 1] = id
end

-- Position --------------------------------------------------------------------------------------------
local POINTS = {
    CENTER = true, TOP = true, BOTTOM = true, LEFT = true, RIGHT = true,
    TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true,
}
local function finite(v) return type(v) == "number" and v == v and v > -10000 and v < 10000 end

local function savePosition()
    local db = Store.db
    if not (db and frame and frame.GetPoint) then return end
    local point, _, relPoint, x, y = frame:GetPoint(1)
    if POINTS[point] and POINTS[relPoint] and finite(x) and finite(y) then
        db.configPos = { point = point, relPoint = relPoint, x = x, y = y }
    end
end

local function restorePosition()
    frame:ClearAllPoints()
    local p = Store.db and Store.db.configPos
    if type(p) == "table" and POINTS[p.point] and POINTS[p.relPoint] and finite(p.x) and finite(p.y) then
        frame:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    end
end
Config.RestorePosition = function() if frame then restorePosition() end end

-- Bestaetigung (eigenes Overlay statt StaticPopup: kein Eintrag in globale Blizzard-Tabellen) -------------
local function buildConfirm()
    local o = CreateFrame("Frame", nil, frame)
    o:SetAllPoints(frame)
    o:SetFrameLevel((frame:GetFrameLevel() or 1) + 50)
    o:EnableMouse(true) -- Klicks erreichen das Fenster darunter nicht
    W.Fill(o, { 0, 0, 0, 0.6 })
    local box = CreateFrame("Frame", nil, o)
    box:SetSize(420, 150)
    box:SetPoint("CENTER")
    W.Fill(box, C.bg)
    W.Border(box, { C.accent[1], C.accent[2], C.accent[3], 0.5 })
    o.text = W.Text(box, "GameFontHighlight")
    o.text:SetPoint("TOPLEFT", 18, -18)
    o.text:SetPoint("TOPRIGHT", -18, -18)
    if o.text.SetJustifyH then o.text:SetJustifyH("CENTER") end
    if o.text.SetWordWrap then o.text:SetWordWrap(true) end
    o.yes = W.Button(box, L.UI_CONFIRM_YES, 130, function()
        local fn = o.onYes
        o.onYes = nil
        o:Hide()
        if fn then fn() end
    end)
    o.yes:SetPoint("BOTTOMRIGHT", box, "BOTTOM", -6, 16)
    o.no = W.Button(box, L.UI_CONFIRM_NO, 130, function()
        o.onYes = nil
        o:Hide()
    end)
    o.no:SetPoint("BOTTOMLEFT", box, "BOTTOM", 6, 16)
    o:Hide()
    return o
end

--- Rueckfrage im Fenster. text muss bereits Plain sein (Nutzerdaten ueber Widgets.Plain). onYes laeuft nur bei "Ja".
function Config.Confirm(text, yesLabel, onYes)
    if not frame then return end
    local o = Config.confirm
    o.text:SetText(text)
    o.yes:SetText(yesLabel or L.UI_CONFIRM_YES)
    o.onYes = onYes
    o:Show()
end

-- Simulation -----------------------------------------------------------------------------------------
Config.SIM_NONE = "none"

--- Zustand simulieren (State-Name) oder beenden (nil/"none"). Liefert true bei Erfolg.
function Config.SetSimulation(name)
    if name == Config.SIM_NONE then name = nil end
    if name ~= nil then
        if not State.KNOWN[name] or name == "mouseover" then return false end
        if not (State.IsAvailable(name) or Config.IsCurveDriven(name)) then return false end
    end
    if Config.simulating and Config.simulating ~= name then State.SetOverride(Config.simulating, false) end
    Config.simulating = name
    if name then State.SetOverride(name, true) end
    Config.UpdateSimulation()
    return true
end

--- true, wenn der Zustand nicht lesbar ist, im Fader (Ausblenden) aber ueber den Kurvenmodus wirkt ("hurt" als Secret)
function Config.IsCurveDriven(name)
    return ns.Fader ~= nil and ns.Fader.IsCurveDriven(name) == true
end

--- Grund, warum ein Zustand nicht verfuegbar ist (nil = verfuegbar). fader: Sicht des Faders (Ausblenden,
--- Simulation) => ein Zustand im Kurvenmodus gilt als verfuegbar; andere Abnehmer (Namensplaketten, Kamera) nicht.
local function stateReason(name, fader)
    local ok, reason = State.IsAvailable(name)
    if ok or (fader and Config.IsCurveDriven(name)) then return nil end
    return reason == "secret" and L.STATE_UNAVAILABLE_SECRET or L.STATE_UNAVAILABLE_API
end
Config.StateReason = stateReason

--- Hinweis fuer einen Zustand im Kurvenmodus (Tooltip), sonst nil
function Config.StateNote(name)
    return Config.IsCurveDriven(name) and L.STATE_CURVE_NOTE or nil
end

--- Auswahl-Optionen fuer Zustaende (ohne die in skip). Nicht verfuegbare sind gesperrt, mit Grund (Akzeptanz 10).
--- fader: Sicht des Faders (Zustand im Kurvenmodus waehlbar, mit Hinweis im Tooltip)
function Config.StateOptions(skip, includeMouseover, fader)
    local out = {}
    for _, name in ipairs(State.NAMES) do
        if (includeMouseover or name ~= "mouseover") and not (skip and skip[name]) then
            local reason = stateReason(name, fader)
            out[#out + 1] = {
                value = name,
                text = reason and (L["STATE_" .. name] .. " " .. L.UI_STATE_UNAVAILABLE_SUFFIX) or L["STATE_" .. name],
                disabled = reason ~= nil, tooltip = reason or (fader and Config.StateNote(name)) or nil,
            }
        end
    end
    return out
end

function Config.UpdateSimulation()
    if not frame then return end
    local opts = { { value = Config.SIM_NONE, text = L.UI_SIM_NONE } }
    for _, o in ipairs(Config.StateOptions(nil, false, true)) do opts[#opts + 1] = o end
    frame.sim:SetOptions(opts)
    frame.sim:SetValue(Config.simulating or Config.SIM_NONE)
    if Config.simulating then
        frame.simNote:SetText(L.UI_SIM_ACTIVE:format(L["STATE_" .. Config.simulating]))
        frame.simNote:Show()
    else
        frame.simNote:Hide()
    end
end

-- Reiter -------------------------------------------------------------------------------------------
function Config.SelectTab(id)
    if not frame or not Config.pages[id] then return false end
    Config.current = id
    for pid, def in pairs(Config.pages) do
        local on = pid == id
        def.tab:SetSelected(on)
        W.Color(def.tab.label, on and C.accent or C.muted)
        if on then def.page:Show() else def.page:Hide() end
    end
    Config.Refresh()
    return true
end

--- aktuellen Reiter (bzw. alle mit all = true) aus dem Profil neu zeichnen
function Config.Refresh(all)
    if not frame then return end
    frame.profileNote:SetText(L.UI_PROFILE_NOTE:format(W.Plain(Store.GetActiveName())))
    for id, def in pairs(Config.pages) do
        if (all or id == Config.current) and def.refresh then
            xpcall(def.refresh, geterrorhandler(), def.page)
        end
    end
end

-- Aufbau ---------------------------------------------------------------------------------------------
local function build()
    frame = CreateFrame("Frame", Config.FRAME_NAME, UIParent)
    Config.frame = frame
    frame:SetSize(Config.WIDTH, Config.HEIGHT)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
    end)
    W.Fill(frame, C.bg)
    W.Border(frame, { C.accent[1], C.accent[2], C.accent[3], 0.35 })

    -- Kopf: Name, Leitidee, Profil, Simulation, Schliessen
    local title = W.Text(frame, "GameFontNormalLarge", C.accent)
    title:SetPoint("TOPLEFT", 20, -16)
    title:SetText("Lucid")
    local tagline = W.Text(frame, "GameFontHighlightSmall", C.muted)
    tagline:SetPoint("LEFT", title, "RIGHT", 10, -1)
    tagline:SetText(L.UI_TAGLINE)
    frame.profileNote = W.Text(frame, "GameFontHighlightSmall", C.muted)
    frame.profileNote:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)

    local ok, close = pcall(CreateFrame, "Button", nil, frame, "UIPanelCloseButton")
    if not ok or not close then
        close = W.Button(frame, "X", 24)
    end
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() Config.Close() end)
    frame.close = close

    local simLabel = W.Text(frame, "GameFontNormalSmall", C.muted)
    simLabel:SetText(L.UI_SIM_LABEL)
    frame.sim = W.Dropdown(frame, 190, function(v) Config.SetSimulation(v) end)
    frame.sim:SetPoint("TOPRIGHT", -40, -18)
    simLabel:SetPoint("RIGHT", frame.sim, "LEFT", -8, 0)
    W.Tooltip(frame.sim, function() return L.UI_SIM_LABEL, L.UI_SIM_TOOLTIP end)
    frame.simNote = W.Text(frame, "GameFontNormalSmall", C.warn)
    frame.simNote:SetPoint("TOPRIGHT", frame.sim, "BOTTOMRIGHT", 0, -4)
    frame.simNote:Hide()

    -- Reiterleiste
    local x = 16
    local n = #Config.pageOrder
    local tabW = math.min(130, math.floor((Config.WIDTH - 32 - (n - 1) * 4) / n))
    for _, id in ipairs(Config.pageOrder) do
        local def = Config.pages[id]
        local tab = W.FlatButton(frame, tabW, 26, "GameFontNormal")
        tab:SetPoint("TOPLEFT", x, -64)
        tab.label:SetText(L[def.label])
        if tab.label.SetJustifyH then tab.label:SetJustifyH("CENTER") end
        tab:SetScript("OnClick", function() Config.SelectTab(id) end)
        def.tab = tab
        x = x + tabW + 4
    end
    local rule = frame:CreateTexture(nil, "ARTWORK")
    rule:SetColorTexture(C.line[1], C.line[2], C.line[3], C.line[4])
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", 12, -91)
    rule:SetPoint("TOPRIGHT", -12, -91)

    -- Seiten
    for _, id in ipairs(Config.pageOrder) do
        local def = Config.pages[id]
        local page = CreateFrame("Frame", nil, frame)
        page:SetPoint("TOPLEFT", 16, -100)
        page:SetPoint("BOTTOMRIGHT", -16, 16)
        page:Hide()
        def.page = page
        def.build(page)
    end

    Config.confirm = buildConfirm()

    -- Schliessen beendet die Simulation und offene Rueckfragen
    frame:SetScript("OnHide", function()
        Config.SetSimulation(nil)
        if Config.confirm then Config.confirm.onYes = nil; Config.confirm:Hide() end
    end)
    frame:SetScript("OnShow", function()
        Config.UpdateSimulation()
        Config.Refresh()
    end)

    -- ESC schliesst das Fenster (Liste des Clients, nur ein Eintrag mit unserem Namen)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, Config.FRAME_NAME) end

    restorePosition()
    frame:Hide()
    Config.SelectTab(Config.pageOrder[1])
end

function Config.IsShown() return frame ~= nil and frame:IsShown() == true end

function Config.Open(tab)
    if not frame then build() end
    if tab then Config.SelectTab(tab) end
    frame:Show()
    if frame.Raise then frame:Raise() end
end

function Config.Close()
    if frame then frame:Hide() end
end

function Config.Toggle()
    if Config.IsShown() then Config.Close() else Config.Open() end
end

-- Aenderungen von aussen (Profilwechsel, Import, Reset, Slash-Befehle) ins offene Fenster uebernehmen
Store.RegisterCallback(function()
    if Config.IsShown() then Config.Refresh(true) end
end)

-- Verfuegbarkeit der Zustaende aendert sich (z. B. Secret im Kampf): Auswahl/Markierungen nachziehen, gedrosselt
local availPending = false
State.RegisterCallback(function(name)
    -- simulierter Zustand wird nicht verfuegbar (z. B. Secret im Kampf): Simulation sofort beenden
    -- (Ausnahme Kurvenmodus: "hurt" bleibt im Fader wirksam, die Simulation laeuft weiter)
    if name ~= "mouseover" and name == Config.simulating and not State.IsAvailable(name) and not Config.IsCurveDriven(name) then
        Config.SetSimulation(nil)
    end
    if name == "mouseover" or availPending or not Config.IsShown() then return end
    availPending = true
    local function run()
        availPending = false
        if not Config.IsShown() then return end
        Config.UpdateSimulation()
        for _, def in pairs(Config.pages) do
            if def.availability then xpcall(def.availability, geterrorhandler(), def.page) end
        end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.2, run) else run() end
end)

-- Slash: /lucid ohne Argument oeffnet/schliesst das Fenster; alle anderen Befehle bleiben wie gehabt -------
do
    local orig = SlashCmdList.LUCID
    SlashCmdList.LUCID = function(msg)
        if type(msg) ~= "string" or msg:match("^%s*$") then
            Config.Toggle()
        else
            orig(msg)
        end
    end
    ns.commands.config = function() Config.Toggle() end
    ns.AddHelp("HELP_CONFIG")
end
