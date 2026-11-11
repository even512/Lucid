-- Testfenster des Plaketten-Stils (/lucid nameplates style panel): Knoepfe fuer Stil an/aus/Vorschau, Rang-Test,
-- Zauber-Test, Diagnose und Haken fuer alle Bausteine und Unteroptionen. Reines Entwickler-/Testfenster; jede Aktion ist
-- eine Funktion aus ns.NameplateStyle.Actions (dieselben wie im Slash-Befehl, spaeter im Reiter mit Live-Vorschau).
-- Verschiebbar, ESC schliesst (UISpecialFrames), die Position bleibt fuer die Sitzung (das Fenster wird nur versteckt).
--
-- Sicherheit: nur eigene, ungeschuetzte Frames; Profilwerte gehen ueber Nameplates.SetMany (geprueft wie beim Import).
local _, ns = ...
local L = ns.L

local Panel = {}
ns.StylePanel = Panel

Panel.FRAME_NAME = "LucidStylePanel"
local WIDTH, HEIGHT = 640, 560
local BTN_W, BTN_H, GAP = 112, 22, 6

-- Rang-Test: Schluessel aus NameplateStyle.RANK_PREVIEW (Reihenfolge = Knoepfe), "off" beendet
Panel.RANK_KEYS = { "normal", "elite", "rare", "rareelite", "boss", "eliteboss", "quest", "loot", "slay", "interact", "off" }
-- Zauber-Test: Sekunden, nicht unterbrechbar
Panel.CASTS = { { key = "cast3", sec = 3 }, { key = "cast3nokick", sec = 3, nokick = true }, { key = "cast8", sec = 8 } }
-- Haken: Bausteine (STYLE_PARTS) und Unteroptionen (Pfad relativ zu nameplates.style)
Panel.SUB_OPTIONS = { "frame.living", "frame.capsule", "frame.inset", "frame.meniscus", "frame.glass", "font.veil",
    "barOnDemand.target", "levelRank.onlyDiff", "castThread.showName" }

local frame

local function label(key) return L["NP_PANEL_" .. key] or key end

--- Wert eines Pfads ("frame" = Baustein an, "frame.glass" = Unteroption) aus den Stil-Einstellungen
local function valueAt(style, path)
    local part, sub = path:match("^([^%.]+)%.?(.*)$")
    local p = type(style) == "table" and style[part]
    if type(p) ~= "table" then return false end
    if sub == "" then return p.enabled == true end
    return p[sub] == true
end
Panel.ValueAt = valueAt

local function setPressed(b, on)
    b.active = on and true or false
    if on then pcall(b.LockHighlight, b) else pcall(b.UnlockHighlight, b) end
    if b.mark then b.mark:SetShown(on) end
end

--- Anzeige an den aktuellen Zustand angleichen (gedrueckte Knoepfe, Haken)
function Panel.Refresh()
    if not (frame and frame:IsShown()) then return end
    local Style = ns.NameplateStyle
    local st = Style and Style.Actions and Style.Actions.State()
    if not st then return end
    setPressed(frame.buttons.on, st.enabled)
    setPressed(frame.buttons.off, not st.enabled)
    setPressed(frame.buttons.test, st.test)
    for _, k in ipairs(Panel.RANK_KEYS) do
        setPressed(frame.buttons["rank_" .. k], (k == "off" and st.rank == nil) or st.rank == k)
    end
    for _, cdef in ipairs(Panel.CASTS) do setPressed(frame.buttons[cdef.key], false) end
    setPressed(frame.buttons.caststop, not st.cast)
    setPressed(frame.buttons.fartest, ns.QuestFar and ns.QuestFar.TestKind() ~= nil)
    for path, cb in pairs(frame.checks) do cb:SetValue(valueAt(st.style, path)) end
end

local function action(fn)
    return function()
        fn()
        Panel.Refresh()
    end
end

local function build()
    local W = ns.Widgets
    local C = W.COLORS
    local Actions = ns.NameplateStyle.Actions
    local f = CreateFrame("Frame", Panel.FRAME_NAME, UIParent)
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER", 0, 40)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    W.Fill(f, C.bg)
    W.Border(f, { C.accent[1], C.accent[2], C.accent[3], 0.35 })
    f.buttons, f.checks = {}, {}

    f.title = W.Text(f, "GameFontNormal", C.accent)
    f.title:SetPoint("TOPLEFT", 14, -12)
    f.title:SetText(L.NP_PANEL_TITLE)
    local ok, close = pcall(CreateFrame, "Button", nil, f, "UIPanelCloseButton")
    if not ok or not close then close = W.Button(f, "X", 24) end
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() f:Hide() end)

    -- linke Spalte: Knopf-Gruppen (je drei Knoepfe pro Zeile)
    local y = -40
    local function header(text, x, width)
        local h = W.Header(f, text, width)
        h:SetPoint("TOPLEFT", x, y)
        y = y - 22
    end
    local function buttons(defs)
        for i, d in ipairs(defs) do
            local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
            local b = W.Button(f, label(d.label), BTN_W, action(d.fn))
            b:SetPoint("TOPLEFT", 14 + col * (BTN_W + GAP), y - row * (BTN_H + 4))
            f.buttons[d.key] = b
        end
        y = y - (math.floor((#defs - 1) / 3) + 1) * (BTN_H + 4) - 10
    end
    local leftW = 3 * BTN_W + 2 * GAP

    header(L.NP_PANEL_H_STYLE, 14, leftW)
    buttons({
        { key = "on", label = "ON", fn = function() Actions.SetEnabled(true) end },
        { key = "off", label = "OFF", fn = function() Actions.SetEnabled(false) end },
        { key = "test", label = "TEST", fn = function() Actions.Test() end },
    })
    header(L.NP_PANEL_H_RANK, 14, leftW)
    local rankDefs = {}
    for _, k in ipairs(Panel.RANK_KEYS) do
        rankDefs[#rankDefs + 1] = { key = "rank_" .. k, label = "RANK_" .. k:upper(), fn = function() Actions.Rank(k) end }
    end
    buttons(rankDefs)
    header(L.NP_PANEL_H_CAST, 14, leftW)
    local castDefs = {}
    for _, cdef in ipairs(Panel.CASTS) do
        castDefs[#castDefs + 1] = { key = cdef.key, label = cdef.key:upper(),
            fn = function() Actions.Cast(cdef.sec, nil, cdef.nokick == true) end }
    end
    castDefs[#castDefs + 1] = { key = "caststop", label = "CASTSTOP", fn = function() Actions.CastStop() end }
    buttons(castDefs)
    header(L.NP_PANEL_H_DIAG, 14, leftW)
    buttons({
        { key = "debug", label = "DEBUG", fn = function() Actions.Debug() end },
        { key = "trace", label = "TRACE", fn = function() Actions.Trace() end },
        { key = "fartest", label = "FARTEST", fn = function()
            ns.QuestFar.SetTest(ns.QuestFar.TestKind() and "off" or "mix")
        end },
    })

    -- rechte Spalte: Haken fuer Bausteine und Unteroptionen (wirken sofort)
    local x = 14 + leftW + 24
    y = -40
    header(L.NP_PANEL_H_PARTS, x, WIDTH - x - 14)
    local function check(path, indent)
        local cb = W.Check(f, label("P_" .. path:gsub("%.", "_")), function(on)
            Actions.SetPart(path:find("%.") and path or (path .. ".enabled"), on)
            Panel.Refresh()
        end)
        cb:SetPoint("TOPLEFT", x + (indent and 16 or 0), y)
        f.checks[path] = cb
        y = y - 20
    end
    local subsOf = {}
    for _, sp in ipairs(Panel.SUB_OPTIONS) do
        local part = sp:match("^([^%.]+)")
        subsOf[part] = subsOf[part] or {}
        table.insert(subsOf[part], sp)
    end
    for _, part in ipairs(ns.Nameplates.STYLE_PARTS) do
        check(part)
        for _, sp in ipairs(subsOf[part] or {}) do check(sp, true) end
    end

    f.hint = W.Text(f, "GameFontHighlightSmall", C.muted)
    f.hint:SetPoint("BOTTOMLEFT", 14, 14)
    f.hint:SetPoint("RIGHT", f, "RIGHT", -14, 0)
    f.hint:SetJustifyH("LEFT")
    f.hint:SetText(L.NP_PANEL_HINT)

    f:SetScript("OnShow", function() Panel.Refresh() end)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, Panel.FRAME_NAME) end
    f:Hide()
    return f
end

--- Fenster oeffnen/schliessen (beim ersten Mal erzeugt). Liefert true, wenn es danach sichtbar ist.
function Panel.Toggle()
    if not frame then
        local ok, f = pcall(build)
        if not ok then
            ns.Print(L.COPY_ERROR, (tostring(f):gsub("|", "||")))
            return false
        end
        frame = f
        Panel.frame = f
    end
    if frame:IsShown() then frame:Hide() else frame:Show() end
    Panel.Refresh()
    return frame:IsShown()
end

-- Profil geaendert (auch ueber Slash/Reiter): Haken und Knoepfe nachziehen
ns.Store.RegisterCallback(function() Panel.Refresh() end)
