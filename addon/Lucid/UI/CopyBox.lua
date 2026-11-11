-- Kopierfenster: Probe-/Debug-Ausgaben aus dem Chat sind in WoW nicht kopierbar. ns.CopyBox.Capture(titel, fn, ...) fuehrt
-- fn aus, schreibt alles mit, was ueber ns.Print ausgegeben wird (der Chat bleibt unveraendert), und zeigt den Text danach
-- in einem verschiebbaren Fenster: mehrzeiliges Feld, Text vorausgewaehlt (Strg+A, Strg+C), Esc schliesst.
--
-- Zentral angeschlossen in Core.lua (Slash-Verteiler): ns.CopyBox.Wants(rest) entscheidet anhand des Unterbefehls
-- (probe, debug, style debug), ob eine Ausgabe mitgeschrieben wird - neue Probe-/Debug-Unterbefehle brauchen nichts weiter.
--
-- Sicherheit: nur eigene, ungeschuetzte Frames; das Fenster nimmt keine Eingaben an (Tastatur-Eingaben werden verworfen);
-- der Text wird nie als Befehl ausgefuehrt.
local _, ns = ...
local L = ns.L

local CopyBox = {}
ns.CopyBox = CopyBox

CopyBox.FRAME_NAME = "LucidCopyBox"
local WIDTH, HEIGHT = 640, 440

local frame
local currentText = ""
local setting = false

--- Farbcodes (|cAARRGGBB ... |r) entfernen, "||" zu "|" zurueck. "||" wird vorab geschuetzt, damit "||r" kein Farbende ist.
function CopyBox.Clean(msg)
    local s = tostring(msg == nil and "" or msg)
    s = s:gsub("||", "\1")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", "")
    s = s:gsub("|r", "")
    s = s:gsub("\1", "|")
    return s
end

--- Wird fuer diese Befehlszeile (Rest nach dem Hauptbefehl, z. B. "probe style") mitgeschrieben?
function CopyBox.Wants(rest)
    local a, b = tostring(rest or ""):lower():match("^%s*(%S*)%s*(%S*)")
    return a == "probe" or a == "debug" or (a == "style" and b == "debug")
end

local function header()
    local stamp = type(date) == "function" and date("%Y-%m-%d %H:%M:%S") or "?"
    return L.COPY_HEADER:format(tostring(ns.version), tostring(ns.Compat and ns.Compat.flavor or "?"),
        tostring(ns.Compat and ns.Compat.interface or "?"), stamp)
end

local function build()
    local W = ns.Widgets
    local C = W.COLORS
    local f = CreateFrame("Frame", CopyBox.FRAME_NAME, UIParent)
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER", 0, 30)
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

    f.title = W.Text(f, "GameFontNormal", C.accent)
    f.title:SetPoint("TOPLEFT", 14, -12)
    f.title:SetPoint("RIGHT", f, "RIGHT", -40, 0)
    f.title:SetWordWrap(false)

    local ok, close = pcall(CreateFrame, "Button", nil, f, "UIPanelCloseButton")
    if not ok or not close then close = W.Button(f, "X", 24) end
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() f:Hide() end)

    f.area = W.TextArea(f, WIDTH - 28, HEIGHT - 92, 0)
    f.area:SetPoint("TOPLEFT", 14, -38)
    local edit = f.area.edit
    f.edit = edit
    -- nur zum Kopieren: Eingaben werden verworfen, der Text bleibt markiert (Setzen durch uns ist userInput == false)
    edit:SetScript("OnTextChanged", function(self, userInput)
        if setting or not userInput then return end
        if self:GetText() ~= currentText then
            setting = true
            self:SetText(currentText)
            setting = false
            self:HighlightText()
        end
    end)
    edit:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)

    f.hint = W.Text(f, "GameFontHighlightSmall", C.muted)
    f.hint:SetPoint("BOTTOMLEFT", 14, 16)
    f.hint:SetText(L.COPY_HINT)

    f.closeBtn = W.Button(f, L.COPY_CLOSE, 110, function() f:Hide() end)
    f.closeBtn:SetPoint("BOTTOMRIGHT", -14, 12)

    -- ESC schliesst das Fenster (Liste des Clients)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, CopyBox.FRAME_NAME) end
    f:Hide()
    return f
end

--- Text im Fenster zeigen (Fenster wird beim ersten Mal erzeugt), markiert und fokussiert.
function CopyBox.Show(title, text)
    if not frame then
        local ok, f = pcall(build)
        if not ok then return false end
        frame = f
        CopyBox.frame = f
    end
    currentText = text
    frame.title:SetText(ns.Widgets.Plain(L.COPY_TITLE:format(title)))
    setting = true
    frame.edit:SetText(text)
    setting = false
    if frame.area.scroll and frame.area.scroll.SetVerticalScroll then frame.area.scroll:SetVerticalScroll(0) end
    frame:Show()
    frame.edit:SetFocus()
    frame.edit:HighlightText()
    -- manche Clients setzen die Auswahl erst nach dem Anzeigen: einen Tick spaeter noch einmal
    if type(C_Timer) == "table" and C_Timer.After then
        C_Timer.After(0, function()
            if frame:IsShown() and currentText == text then frame.edit:HighlightText() end
        end)
    end
    return true
end

--- fn(...) ausfuehren, ns.Print-Ausgaben mitschreiben und im Kopierfenster zeigen. Fehler in fn landen im Text.
--- Der Mitschreiber wird immer zurueckgesetzt (auch bei Fehlern); verschachtelte Aufrufe stellen den vorherigen wieder her.
function CopyBox.Capture(title, fn, ...)
    local lines = { header() }
    local previous = ns.printSink
    ns.printSink = function(msg) lines[#lines + 1] = CopyBox.Clean(msg) end
    local ok, err = pcall(fn, ...)
    ns.printSink = previous
    if not ok then lines[#lines + 1] = CopyBox.Clean(L.COPY_ERROR:format(tostring(err))) end
    CopyBox.Show(title, table.concat(lines, "\n"))
    if not ok then ns.Print(L.COPY_ERROR, (tostring(err):gsub("|", "||"))) end
end
