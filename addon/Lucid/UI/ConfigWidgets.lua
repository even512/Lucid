-- Eigene, schlichte Widgets fuer das Konfig-Fenster (B4). Keine Fremd-Bibliotheken, keine geschuetzten Templates.
-- Alles hier sind ungeschuetzte, eigene Frames; Blizzard-Templates nur, wo sie ungeschuetzt und seit Langem stabil
-- sind (UIPanelButtonTemplate, UIPanelCloseButton) - jeweils per pcall mit eigenem Ersatz.
--
-- Dropdowns: in Retail 12.x / Forever das neue Menue-System (MenuUtil + WowStyle1DropdownTemplate, kein
-- UIDropDownMenu => kein Taint der alten Dropdown-Liste), per Existenzpruefung; sonst eine eigene einfache Liste.
--
-- Sicherheit: dynamischer Text (Profilnamen, Fehlerdetails, Eingaben) geht nur ueber Widgets.Plain in FontStrings,
-- Tooltips und Menues: "|" wird verdoppelt, damit keine Escape-Codes (|c, |T, |H ...) wirken.
local _, ns = ...

local W = {}
ns.Widgets = W

-- Farben: ruhig, dunkel, ein kuehler Akzent (Lucid-Blau wie im Chat-Praefix)
W.COLORS = {
    bg = { 0.035, 0.04, 0.055, 0.94 },
    panel = { 0.07, 0.08, 0.105, 0.9 },
    line = { 0.62, 0.85, 1, 0.22 },
    accent = { 0.62, 0.85, 1 },
    text = { 0.92, 0.93, 0.95 },
    muted = { 0.6, 0.63, 0.68 },
    disabled = { 0.42, 0.44, 0.47 },
    warn = { 1, 0.6, 0.45 },
    ok = { 0.55, 0.88, 0.62 },
    select = { 0.62, 0.85, 1, 0.14 },
}
local C = W.COLORS

--- Text fuer FontString/Tooltip/Menue ohne wirksame Escape-Codes
function W.Plain(s)
    return (tostring(s == nil and "" or s):gsub("|", "||"))
end

local function color(fs, c)
    if fs and fs.SetTextColor then fs:SetTextColor(c[1], c[2], c[3]) end
end
W.Color = color

function W.Fill(frame, c, layer)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND")
    t:SetAllPoints(frame)
    t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
    return t
end

--- feiner Rahmen (1 px) aus vier Linien
function W.Border(frame, c)
    c = c or C.line
    local function line(p1, p2, horiz)
        local t = frame:CreateTexture(nil, "BORDER")
        t:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
        t:SetPoint(p1)
        t:SetPoint(p2)
        if horiz then t:SetHeight(1) else t:SetWidth(1) end
        return t
    end
    line("TOPLEFT", "TOPRIGHT", true)
    line("BOTTOMLEFT", "BOTTOMRIGHT", true)
    line("TOPLEFT", "BOTTOMLEFT", false)
    line("TOPRIGHT", "BOTTOMRIGHT", false)
end

--- FontString mit Schrift (Font-Objekt-Name) und Farbe
function W.Text(parent, font, c, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    local obj = _G[font or "GameFontHighlight"] or _G.GameFontHighlight
    if obj then fs:SetFontObject(obj) end
    if fs.SetJustifyH then fs:SetJustifyH("LEFT") end
    color(fs, c or C.text)
    return fs
end

-- Tooltip ------------------------------------------------------------------------------------------
--- Tooltip an ein Widget haengen. fn() -> titel, text (beide bereits als Plain-Text oder Locale-Text)
function W.Tooltip(widget, fn)
    widget.tooltipFn = fn
    if widget.lucidTooltipHooked then return end
    widget.lucidTooltipHooked = true
    widget:HookScript("OnEnter", function(self)
        local tip = GameTooltip
        if not (tip and self.tooltipFn) then return end
        local title, text = self.tooltipFn(self)
        if not title then return end
        tip:SetOwner(self, "ANCHOR_RIGHT")
        tip:SetText(title, 1, 1, 1)
        if text then tip:AddLine(text, nil, nil, nil, true) end
        tip:Show()
    end)
    widget:HookScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)
end

-- Knoepfe ------------------------------------------------------------------------------------------
--- Standard-Knopf (UIPanelButtonTemplate, ungeschuetzt), sonst eigener Knopf
function W.Button(parent, text, width, onClick)
    local ok, b = pcall(CreateFrame, "Button", nil, parent, "UIPanelButtonTemplate")
    if not ok or not b then
        b = CreateFrame("Button", nil, parent)
        W.Fill(b, C.panel)
        W.Border(b)
        local fs = W.Text(b, "GameFontHighlight")
        fs:SetPoint("CENTER")
        b.SetText = function(self, t) fs:SetText(t) end
        b.GetText = function() return fs:GetText() end
    end
    b:SetSize(width or 110, 22)
    b:SetText(text or "")
    if onClick then b:SetScript("OnClick", function(self) onClick(self) end) end
    return b
end

--- flacher Text-Knopf (Reiter, Listeneintraege) mit Auswahl-Hintergrund
function W.FlatButton(parent, width, height, font)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, height)
    b.sel = W.Fill(b, C.select, "BACKGROUND")
    b.sel:Hide()
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    hl:SetColorTexture(1, 1, 1, 0.06)
    b.label = W.Text(b, font or "GameFontHighlight")
    b.label:SetPoint("LEFT", 6, 0)
    b.label:SetPoint("RIGHT", -4, 0)
    b.SetSelected = function(self, on)
        if on then self.sel:Show() else self.sel:Hide() end
        self.selected = on and true or false
    end
    return b
end

-- Haken ----------------------------------------------------------------------------------------------
--- Haken mit Beschriftung. onChange(checked) nur bei Nutzer-Klick; SetValue setzt still.
function W.Check(parent, label, onChange)
    local cb = CreateFrame("CheckButton", nil, parent)
    cb:SetSize(22, 22)
    cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    cb:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    cb:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
    cb.label = W.Text(cb, "GameFontHighlight")
    cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cb.label:SetText(label or "")
    cb:SetScript("OnClick", function(self)
        if onChange then onChange(self:GetChecked() and true or false) end
    end)
    cb.SetValue = function(self, v) self:SetChecked(v and true or false) end
    cb.SetActive = function(self, on)
        if on then self:Enable() else self:Disable() end
        color(self.label, on and C.text or C.disabled)
    end
    return cb
end

-- Schieberegler --------------------------------------------------------------------------------------
local function round(v, step)
    if not step or step <= 0 then return v end
    local r = math.floor(v / step + 0.5) * step
    -- Gleitkomma-Rest (0.15000000000000002) entfernen
    return tonumber(("%.4f"):format(r))
end
W.Round = round

--- Schieberegler mit Beschriftung und Wertanzeige. fmt(v) -> Anzeige. onChange(v) nur bei Nutzer-Aenderung.
function W.Slider(parent, label, min, max, step, width, fmt, onChange)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(width or 220, 40)
    box.title = W.Text(box, "GameFontNormalSmall", C.muted)
    box.title:SetPoint("TOPLEFT", 0, 0)
    box.title:SetText(label or "")
    box.value = W.Text(box, "GameFontHighlightSmall")
    box.value:SetPoint("TOPRIGHT", 0, 0)
    if box.value.SetJustifyH then box.value:SetJustifyH("RIGHT") end

    local s = CreateFrame("Slider", nil, box)
    s:SetOrientation("HORIZONTAL")
    s:SetHeight(16)
    s:SetPoint("TOPLEFT", 0, -16)
    s:SetPoint("TOPRIGHT", 0, -16)
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetColorTexture(1, 1, 1, 0.12)
    track:SetHeight(4)
    track:SetPoint("LEFT")
    track:SetPoint("RIGHT")
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    if s.SetObeyStepCount then s:SetObeyStepCount(true) end
    if s.EnableMouseWheel then s:EnableMouseWheel(true) end
    box.slider, box.step, box.fmt = s, step, fmt or function(v) return ("%g"):format(v) end

    local quiet = false
    s:SetScript("OnValueChanged", function(_, v)
        v = round(v, step)
        box.value:SetText(box.fmt(v))
        if quiet or box.current == v then return end
        box.current = v
        if onChange then onChange(v) end
    end)
    s:SetScript("OnMouseWheel", function(self, delta)
        if self.IsEnabled and not self:IsEnabled() then return end
        local lo, hi = self:GetMinMaxValues()
        local v = round((box.current or lo) + delta * step, step)
        if v < lo then v = lo elseif v > hi then v = hi end
        self:SetValue(v)
    end)

    --- Wert setzen ohne onChange
    box.SetValue = function(self, v)
        v = round(v, step)
        quiet = true
        self.current = v
        s:SetValue(v)
        quiet = false
        self.value:SetText(self.fmt(v))
    end
    box.GetValue = function(self) return self.current end
    box.SetActive = function(self, on)
        if on then s:Enable() else s:Disable() end
        color(self.title, on and C.muted or C.disabled)
        color(self.value, on and C.text or C.disabled)
    end
    return box
end

-- Eingabefelder ------------------------------------------------------------------------------------
--- einzeiliges Eingabefeld mit eigenem Hintergrund
function W.Input(parent, width, maxLetters)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(width or 180, 22)
    e:SetAutoFocus(false)
    e:SetFontObject(_G.ChatFontNormal or _G.GameFontHighlight)
    e:SetTextInsets(6, 6, 0, 0)
    e:SetMaxLetters(maxLetters or 64)
    W.Fill(e, { 0, 0, 0, 0.55 })
    W.Border(e)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return e
end

--- mehrzeiliges Eingabefeld in einer Rollflaeche (Export/Import). Liefert den Rahmen; .edit ist die EditBox.
function W.TextArea(parent, width, height, maxLetters)
    local box = CreateFrame("Frame", nil, parent)
    box:SetSize(width, height)
    W.Fill(box, { 0, 0, 0, 0.55 })
    W.Border(box)
    local scroll = CreateFrame("ScrollFrame", nil, box)
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -6, 6)
    local e = CreateFrame("EditBox", nil, scroll)
    e:SetMultiLine(true)
    e:SetAutoFocus(false)
    e:SetFontObject(_G.ChatFontSmall or _G.ChatFontNormal or _G.GameFontHighlightSmall)
    e:SetWidth(width - 12)
    e:SetMaxLetters(maxLetters or 0)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(e)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = self.GetVerticalScrollRange and self:GetVerticalScrollRange() or 0
        local v = (self:GetVerticalScroll() or 0) - delta * 20
        if v < 0 then v = 0 elseif v > range then v = range end
        self:SetVerticalScroll(v)
    end)
    -- Cursor im sichtbaren Bereich halten (Blizzard-Helfer, falls vorhanden)
    e:SetScript("OnCursorChanged", function(self, x, y, w, h)
        if type(ScrollingEdit_OnCursorChanged) == "function" then ScrollingEdit_OnCursorChanged(self, x, y, w, h) end
    end)
    -- Klick irgendwo in die Flaeche setzt den Fokus
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() e:SetFocus() end)
    box.edit, box.scroll = e, scroll
    return box
end

-- Dropdown -------------------------------------------------------------------------------------------
-- Optionen: { { value = <Wert>, text = <Plain-Text>, disabled = bool, tooltip = <Text>|nil }, ... }
-- onSelect(value) nur bei Auswahl durch den Nutzer (Menue/Liste oder dd:Select). SetValue setzt still.

local function menuSystem()
    return type(MenuUtil) == "table" and type(MenuUtil.CreateContextMenu) == "function"
end

local function optionText(dd, value)
    for _, o in ipairs(dd.options) do
        if o.value == value then return o.text end
    end
    return dd.placeholder or ""
end

-- eigene, einfache Liste (Ersatz, wenn es das neue Menue-System nicht gibt)
local LIST_ROWS = 12
local function buildList(dd)
    local list = CreateFrame("Frame", nil, dd)
    list:SetFrameStrata("FULLSCREEN_DIALOG")
    list:SetPoint("TOPLEFT", dd, "BOTTOMLEFT", 0, -2)
    list:SetWidth(dd.width)
    list:EnableMouse(true)
    list:EnableMouseWheel(true)
    W.Fill(list, { 0.05, 0.06, 0.08, 0.98 })
    W.Border(list)
    list.rows, list.offset = {}, 0
    for i = 1, LIST_ROWS do
        local b = W.FlatButton(list, dd.width - 4, 18, "GameFontHighlightSmall")
        b:SetPoint("TOPLEFT", 2, -2 - (i - 1) * 18)
        b:SetScript("OnClick", function(self)
            if self.option and not self.option.disabled then
                list:Hide()
                dd:Select(self.option.value)
            end
        end)
        W.Tooltip(b, function(self)
            local o = self.option
            if o and o.tooltip then return o.text, o.tooltip end
        end)
        list.rows[i] = b
    end
    list:SetScript("OnMouseWheel", function(self, delta)
        local max = math.max(0, #dd.options - LIST_ROWS)
        self.offset = math.min(max, math.max(0, self.offset - delta))
        dd:RenderList()
    end)
    list:Hide()
    return list
end

function W.Dropdown(parent, width, onSelect, placeholder)
    local dd
    if menuSystem() then
        local ok, b = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
        if ok and b and type(b.SetupMenu) == "function" then
            dd = b
            dd.usesMenu = true
        end
    end
    if not dd then
        dd = CreateFrame("Button", nil, parent)
        W.Fill(dd, { 0, 0, 0, 0.55 })
        W.Border(dd)
        dd.text = W.Text(dd, "GameFontHighlightSmall")
        dd.text:SetPoint("LEFT", 6, 0)
        dd.text:SetPoint("RIGHT", -18, 0)
        dd.arrow = W.Text(dd, "GameFontHighlightSmall", C.accent)
        dd.arrow:SetPoint("RIGHT", -6, 0)
        dd.arrow:SetText("v")
        dd:SetScript("OnClick", function(self)
            if not self.list then self.list = buildList(self) end
            if self.list:IsShown() then self.list:Hide() else self.list.offset = 0; self:RenderList(); self.list:Show() end
        end)
        dd:SetScript("OnHide", function(self) if self.list then self.list:Hide() end end)
    end
    dd.width, dd.options, dd.placeholder = width or 180, {}, placeholder
    dd:SetSize(dd.width, 22)

    function dd:RenderList()
        local list = self.list
        if not list then return end
        local n = math.min(LIST_ROWS, #self.options)
        list:SetHeight(n * 18 + 4)
        for i, b in ipairs(list.rows) do
            local o = self.options[i + list.offset]
            b.option = o
            if o and i <= n then
                b.label:SetText(o.text)
                color(b.label, o.disabled and C.disabled or C.text)
                b:SetSelected(o.value == self.value)
                b:Show()
            else
                b:Hide()
            end
        end
    end

    function dd:Refresh()
        if self.usesMenu then
            -- Knopftext = gewaehlte Radio-Option (das Menue-System liest isSelected beim Neuaufbau),
            -- ohne Auswahl der Platzhalter
            if self.placeholder and type(self.SetDefaultText) == "function" then pcall(self.SetDefaultText, self, self.placeholder) end
            if type(self.GenerateMenu) == "function" then pcall(self.GenerateMenu, self) end
        else
            self.text:SetText(optionText(self, self.value))
            if self.list and self.list:IsShown() then self:RenderList() end
        end
    end

    function dd:SetOptions(options)
        self.options = options or {}
        if self.usesMenu then
            self:SetupMenu(function(_, root)
                -- lange Listen (Verzierungs-Stile samt Zonen-Motiven): Menue scrollt statt ueber den Bildschirm zu ragen
                if #self.options > 16 and type(root.SetScrollMode) == "function" then pcall(root.SetScrollMode, root, 16 * 20) end
                for _, o in ipairs(self.options) do
                    local value = o.value
                    local desc = root:CreateRadio(o.text,
                        function() return self.value == value end,
                        function()
                            self:Select(value)
                            return _G.MenuResponse and _G.MenuResponse.Close or nil
                        end, value)
                    if desc then
                        if o.disabled and type(desc.SetEnabled) == "function" then desc:SetEnabled(false) end
                        if o.tooltip and type(desc.SetTooltip) == "function" then
                            desc:SetTooltip(function(tip)
                                tip:SetText(o.text, 1, 1, 1)
                                tip:AddLine(o.tooltip, nil, nil, nil, true)
                            end)
                        end
                    end
                end
            end)
        end
        self:Refresh()
    end

    function dd:SetValue(v)
        self.value = v
        self:Refresh()
    end

    function dd:GetValue() return self.value end

    --- Auswahl wie durch den Nutzer: gesperrte oder unbekannte Optionen werden abgewiesen (false)
    function dd:Select(v)
        for _, o in ipairs(self.options) do
            if o.value == v then
                if o.disabled then return false end
                self.value = v
                self:Refresh()
                if onSelect then onSelect(v) end
                return true
            end
        end
        return false
    end

    function dd:GetOptions() return self.options end

    function dd:SetActive(on)
        if on then self:Enable() else self:Disable() end
    end
    return dd
end

-- Abschnitts-Ueberschrift mit feiner Linie
function W.Header(parent, text, width)
    local fs = W.Text(parent, "GameFontNormal", C.accent)
    fs:SetText(text)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(C.line[1], C.line[2], C.line[3], C.line[4])
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -3)
    line:SetWidth(width or 200)
    fs.line = line
    return fs
end
