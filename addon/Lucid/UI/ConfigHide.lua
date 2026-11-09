-- Reiter "Ausblenden" (Spec 3.5): Elementliste links (gruppiert, an/aus, Markierung "nicht vorhanden" bzw.
-- Lucid-Fehler), rechts die Einstellungen des gewaehlten Elements (Basis-Alpha, Bedingungen, Blenden,
-- Verzoegerung, Klicks durchlassen) und oben "Preset uebernehmen" mit Rueckfrage. Jede Aenderung geht ueber
-- Elements.Set/SetEnabled bzw. Presets.Apply und wirkt sofort.
-- Die Liste blaettert (Mausrad und senkrechter Scrollbalken rechts daneben, synchron; der Balken erscheint nur, wenn die
-- Liste ueberlaeuft), seit die Gruppen Cooldown-Manager und Addons nicht mehr in die Hoehe passen. Zeilen-Beschriftungen
-- bleiben einzeilig (abgeschnitten statt umgebrochen).
local _, ns = ...
local Elements, Presets, Fader, Store, State = ns.Elements, ns.Presets, ns.Fader, ns.Store, ns.State
local Config, W = ns.Config, ns.Widgets
local L = ns.L
local C = W.COLORS

local Hide = {}
Config.Hide = Hide

Hide.COND_ROWS = 5   -- sichtbare Bedingungszeilen (Mausrad/Knoepfe blaettern)
local ROW_H = 16
local LIST_W = 250
local TOP = -76          -- Oberkante von Liste und Detail (darueber: Preset-Zeile und Zeile "Fuer alle Elemente")

local LIST_H = 436
local LIST_VIEW = LIST_H - 12 -- sichtbarer Bereich der Liste
local SCROLL_W = 16           -- Breite des Scrollbalkens (rechts neben der Liste, im Abstand zum Detail-Bereich)

-- Tooltip-Zusatz je Element (Hinweis auf eigene Blenden des Addons/Blizzards bzw. den Ink-&-Embers-Zettel)
local EXTRA_TIP = {
    tracker = "UI_EL_INKDOCK_TIP", questietracker = "UI_EL_INKDOCK_TIP",
    details = "UI_EL_SELFFADE_TIP", vuhdo = "UI_EL_SELFFADE_TIP", rxpguide = "UI_EL_SELFFADE_TIP",
    rxparrow = "UI_EL_SELFFADE_TIP",
    cdessential = "UI_EL_CD_TIP", cdutility = "UI_EL_CD_TIP", cdbufficons = "UI_EL_CD_TIP", cdbuffbars = "UI_EL_CD_TIP",
}

local P = { selected = nil, condOffset = 0, listOffset = 0 }
Hide.state = P

local function pct(v) return ("%d %%"):format(math.floor(v * 100 + 0.5)) end
local function sec(v) return ("%.1f s"):format(v) end

local function setStatus(page, text, c)
    page.status:SetText(text or "")
    W.Color(page.status, c or C.muted)
end

-- Fehlercode der Modul-API -> Text in Client-Sprache
local function fail(page, code, arg)
    setStatus(page, (L[code or "ELEMENT_VALUE_INVALID"]):format(W.Plain(arg or "")), C.warn)
end

-- Markierung eines Elements in der Liste: Text, Farbe, Tooltip (oder nil)
local function marker(e)
    if e.status == "missing" and e.optional and not e.addonLoaded then
        return L.UI_EL_ADDON_MISSING:format(e.addon or "?"), C.disabled, L.UI_EL_ADDON_MISSING_TIP:format(e.addon or "?")
    end
    if e.status == "missing" then return L.UI_EL_MISSING, C.disabled, L.UI_EL_MISSING_TIP end
    if e.status == "pending" then return L.UI_EL_PENDING, C.muted, L.UI_EL_PENDING_TIP end
    if e.enabled and not e.active then return L.UI_EL_ERROR, C.warn, L.UI_EL_ERROR_TIP end
    return nil
end
Hide.Marker = marker

local function entryOf(id)
    for _, e in ipairs(Elements.List()) do
        if e.id == id then return e end
    end
end

-- Liste --------------------------------------------------------------------------------------------
-- page.slots: Gruppen-Ueberschriften und Element-Zeilen in Anzeige-Reihenfolge; layoutList zeigt ab P.listOffset so viele,
-- wie in den sichtbaren Bereich passen, und versteckt den Rest (nur eigene Widgets).
-- letzter Slot, der ab Versatz off in den sichtbaren Bereich passt (Positionen nur berechnet, nichts gesetzt)
local function lastFitting(slots, off)
    local y, last = -6, off
    for i = off + 1, #slots do
        local gap = (slots[i].header and i > off + 1) and 4 or 0
        if -(y - gap - ROW_H) > LIST_VIEW then break end
        y = y - gap - ROW_H
        last = i
    end
    return last
end

-- kleinster Versatz, ab dem die Liste bis zum Ende sichtbar ist (0 = passt ganz)
local function maxListOffset(slots)
    for off = 0, #slots do
        if lastFitting(slots, off) >= #slots then return off end
    end
    return 0
end

local function layoutList(page)
    local slots = page.slots
    local maxOffset = maxListOffset(slots)
    if P.listOffset > maxOffset then P.listOffset = maxOffset end
    if P.listOffset < 0 then P.listOffset = 0 end
    local last = lastFitting(slots, P.listOffset)
    local y = -6
    for i, slot in ipairs(slots) do
        local show = i > P.listOffset and i <= last
        if show then
            y = y - ((slot.header and i > P.listOffset + 1) and 4 or 0)
            slot.widget:ClearAllPoints()
            if slot.header then
                slot.widget:SetPoint("TOPLEFT", 8, y - 3)
            else
                slot.widget:SetPoint("TOPLEFT", 4, y)
            end
            y = y - ROW_H
            slot.widget:Show()
        else
            slot.widget:Hide()
        end
    end
    page.listMore = last < #slots
    -- Scrollbalken angleichen (still: der eigene OnValueChanged-Handler blaettert nicht erneut)
    local bar = page.listBar
    if bar then
        page.listSyncing = true
        bar:SetMinMaxValues(0, maxOffset)
        bar:SetValue(P.listOffset)
        page.listSyncing = false
        if maxOffset > 0 then bar:Show(); bar:Enable() else bar:Hide(); bar:Disable() end
        local up, down = bar.ScrollUpButton, bar.ScrollDownButton
        if up and up.SetEnabled then up:SetEnabled(P.listOffset > 0) end
        if down and down.SetEnabled then down:SetEnabled(P.listOffset < maxOffset) end
    end
end
Hide.LayoutList = layoutList
Hide.MaxListOffset = function(page) return maxListOffset(page.slots) end

--- Liste blaettern (delta > 0: nach oben). Liefert true, wenn sich etwas bewegt hat.
function Hide.ScrollList(page, delta)
    local before = P.listOffset
    P.listOffset = math.max(0, math.min(maxListOffset(page.slots), P.listOffset - delta))
    layoutList(page)
    return P.listOffset ~= before
end

-- Senkrechter Scrollbalken in Blizzard-Optik (UIPanelScrollBarTemplate: Balken mit Pfeil-Knoepfen, in Retail 12.x und
-- Forever vorhanden); fehlt die Vorlage, ein schlichter senkrechter Slider. Nur eigener Frame, eigene Skripte.
local function buildScrollBar(page, list)
    local ok, bar = pcall(CreateFrame, "Slider", nil, list, "UIPanelScrollBarTemplate")
    local templated = ok and type(bar) == "table"
    if not templated then
        bar = CreateFrame("Slider", nil, list)
        bar:SetWidth(SCROLL_W)
        local track = bar:CreateTexture(nil, "BACKGROUND")
        track:SetColorTexture(1, 1, 1, 0.08)
        track:SetAllPoints(bar)
        bar:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    end
    bar:SetOrientation("VERTICAL")
    -- Vorlage: Pfeil-Knoepfe sitzen ueber/unter dem Balken => Balken um ihre Hoehe einruecken
    local inset = templated and 16 or 0
    bar:SetPoint("TOPLEFT", list, "TOPRIGHT", 2, -inset)
    bar:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", 2, inset)
    bar:SetMinMaxValues(0, 0)
    bar:SetValueStep(1)
    if bar.SetObeyStepCount then bar:SetObeyStepCount(true) end
    bar.scrollStep = 1 -- Pfeil-Knoepfe der Vorlage: eine Zeile je Klick
    bar:SetScript("OnValueChanged", function(_, v)
        if page.listSyncing then return end
        local off = math.floor((tonumber(v) or 0) + 0.5)
        if off ~= P.listOffset then
            P.listOffset = off
            layoutList(page)
        end
    end)
    if bar.EnableMouseWheel then bar:EnableMouseWheel(true) end
    bar:SetScript("OnMouseWheel", function(_, delta) Hide.ScrollList(page, delta > 0 and 2 or -2) end)
    W.Tooltip(bar, function() return L.UI_EL_LIST_SCROLL_TIP end)
    page.listBar = bar
end

local function buildList(page)
    local list = CreateFrame("Frame", nil, page)
    list:SetPoint("TOPLEFT", 0, TOP)
    list:SetSize(LIST_W, LIST_H)
    W.Fill(list, C.panel)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta) Hide.ScrollList(page, delta > 0 and 2 or -2) end)
    page.rows = {}
    page.slots = {}
    for _, group in ipairs(Elements.GROUPS) do
        local h = W.Text(list, "GameFontNormalSmall", C.accent)
        h:SetText(L["GROUP_" .. group])
        page.slots[#page.slots + 1] = { header = true, widget = h }
        for _, entry in ipairs(Elements.CATALOG) do
            if entry.group == group then
                local id = entry.id
                local row = W.FlatButton(list, LIST_W - 8, ROW_H, "GameFontHighlightSmall")
                row.label:ClearAllPoints()
                row.label:SetPoint("LEFT", 24, 0)
                row.label:SetPoint("RIGHT", -76, 0)
                row.label:SetText(Elements.Label(id))
                if row.label.SetWordWrap then row.label:SetWordWrap(false) end -- einzeilig, zu Langes wird abgeschnitten
                if row.label.SetJustifyH then row.label:SetJustifyH("LEFT") end
                row.mark = W.Text(row, "GameFontNormalSmall", C.muted)
                row.mark:SetPoint("RIGHT", -4, 0)
                row.mark:SetWidth(72)
                if row.mark.SetJustifyH then row.mark:SetJustifyH("RIGHT") end
                if row.mark.SetWordWrap then row.mark:SetWordWrap(false) end
                row.check = W.Check(row, "", function(on)
                    local res, code = Elements.SetEnabled(id, on)
                    if res == nil then fail(page, code, id) end
                    P.selected = id
                    Config.Refresh()
                end)
                row.check:SetSize(18, 18)
                row.check:SetPoint("LEFT", 2, 0)
                row:SetScript("OnClick", function()
                    P.selected = id
                    P.condOffset = 0
                    setStatus(page, "")
                    Config.Refresh()
                end)
                W.Tooltip(row, function()
                    local e = entryOf(id)
                    local _, _, tip = marker(e)
                    local extra = EXTRA_TIP[id] and L[EXTRA_TIP[id]]
                    if extra then tip = tip and (tip .. "\n" .. extra) or extra end
                    -- Tooltip: voller Name, wo die Zeile eine Kurzform zeigt (L liefert fuer fehlende Schluessel den Schluessel)
                    local full = L["ELEMENT_TIP_" .. id]
                    if full == "ELEMENT_TIP_" .. id then full = Elements.Label(id) end
                    return full, tip
                end)
                row.id = id
                page.rows[id] = row
                page.slots[#page.slots + 1] = { widget = row }
            end
        end
    end
    buildScrollBar(page, list)
    page.list = list
    layoutList(page)
end

local function refreshList(page)
    for _, e in ipairs(Elements.List()) do
        local row = page.rows[e.id]
        if row then
            row.check:SetValue(e.enabled)
            row:SetSelected(e.id == P.selected)
            local text, c = marker(e)
            row.mark:SetText(text or "")
            W.Color(row.mark, c or C.muted)
            W.Color(row.label, e.status == "missing" and C.disabled or C.text)
        end
    end
    layoutList(page)
end

-- Bedingungen --------------------------------------------------------------------------------------
local function conditions()
    local cfg = Elements.GetConfig(P.selected)
    return cfg and cfg.conditions or {}
end

local function writeConditions(page, list)
    local ok, code = Elements.Set(P.selected, "conditions", list)
    if not ok then fail(page, code, P.selected) end
    return ok
end

local function refreshConditions(page)
    local list = conditions()
    local max = math.max(0, #list - Hide.COND_ROWS)
    if P.condOffset > max then P.condOffset = max end
    for i, row in ipairs(page.condRows) do
        local c = list[i + P.condOffset]
        row.index = i + P.condOffset
        if c then
            local reason = Config.StateReason(c.state, true)
            row.state = c.state
            row.note = Config.StateNote(c.state)
            row.slider.title:SetText(L["STATE_" .. c.state] .. (reason and (" " .. L.UI_STATE_UNAVAILABLE_SUFFIX) or ""))
            row.slider:SetValue(c.alpha)
            row.slider:SetActive(true)
            if reason then W.Color(row.slider.title, C.disabled) end
            row.reason = reason
            row:Show()
        else
            row.state, row.reason, row.note = nil, nil, nil
            row:Hide()
        end
    end
    page.condEmpty:SetShown(#list == 0)
    if #list > Hide.COND_ROWS then
        page.condPage:SetText(L.UI_COND_RANGE:format(P.condOffset + 1, math.min(#list, P.condOffset + Hide.COND_ROWS), #list))
        page.condUp:Show(); page.condDown:Show()
    else
        page.condPage:SetText("")
        page.condUp:Hide(); page.condDown:Hide()
    end
    -- Hinzufuegen: nur Zustaende, die noch nicht in der Liste sind; nicht verfuegbare gesperrt mit Grund
    local used = {}
    for _, c in ipairs(list) do used[c.state] = true end
    local opts = Config.StateOptions(used, true, true)
    page.addState:SetOptions(opts)
    local keep = page.addState:GetValue()
    local valid = false
    for _, o in ipairs(opts) do
        if o.value == keep and not o.disabled then valid = true end
    end
    if not valid then
        keep = nil
        for _, o in ipairs(opts) do
            if not o.disabled then keep = o.value break end
        end
    end
    page.addState:SetValue(keep)
    local full = #list >= Fader.MAX_CONDITIONS or keep == nil
    if full then page.addBtn:Disable() else page.addBtn:Enable() end
end

local function buildConditions(page, detail)
    local head = W.Header(detail, L.UI_CONDITIONS, 480)
    head:SetPoint("TOPLEFT", 0, -142)
    local hint = W.Text(detail, "GameFontHighlightSmall", C.muted)
    hint:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -8)
    hint:SetText(L.UI_CONDITIONS_HINT)

    page.condRows = {}
    local area = CreateFrame("Frame", nil, detail)
    area:SetPoint("TOPLEFT", 0, -184)
    area:SetSize(490, Hide.COND_ROWS * 40)
    area:EnableMouseWheel(true)
    local function scroll(delta)
        P.condOffset = math.max(0, P.condOffset - delta)
        refreshConditions(page)
    end
    area:SetScript("OnMouseWheel", function(_, delta) scroll(delta) end)
    for i = 1, Hide.COND_ROWS do
        local row = CreateFrame("Frame", nil, area)
        row:SetSize(490, 40)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * 40)
        row.slider = W.Slider(row, "", 0, 1, 0.05, 340, pct, function(v)
            local list = conditions()
            local c = list[row.index]
            if not c then return end
            c.alpha = v
            writeConditions(page, list)
            refreshList(page)
        end)
        row.slider:SetPoint("TOPLEFT", 0, 0)
        W.Tooltip(row.slider, function()
            if row.state then return L["STATE_" .. row.state], row.reason or row.note or L.UI_COND_ALPHA_TIP end
        end)
        row.remove = W.Button(row, L.UI_COND_REMOVE, 100, function()
            local list = conditions()
            if not list[row.index] then return end
            table.remove(list, row.index)
            writeConditions(page, list)
            Config.Refresh()
        end)
        row.remove:SetPoint("TOPLEFT", 370, -10)
        page.condRows[i] = row
    end
    page.condEmpty = W.Text(area, "GameFontHighlightSmall", C.muted)
    page.condEmpty:SetPoint("TOPLEFT", 0, -4)
    page.condEmpty:SetText(L.UI_COND_EMPTY)

    page.condPage = W.Text(detail, "GameFontHighlightSmall", C.muted)
    page.condUp = W.Button(detail, "<", 26, function() scroll(1) end)
    page.condDown = W.Button(detail, ">", 26, function() scroll(-1) end)
    page.condDown:SetPoint("TOPRIGHT", detail, "TOPLEFT", 490, -138)
    page.condUp:SetPoint("RIGHT", page.condDown, "LEFT", -2, 0)
    page.condPage:SetPoint("RIGHT", page.condUp, "LEFT", -6, 0)

    local addLabel = W.Text(detail, "GameFontNormalSmall", C.muted)
    addLabel:SetPoint("TOPLEFT", 0, -390)
    addLabel:SetText(L.UI_COND_ADD_LABEL)
    page.addState = W.Dropdown(detail, 220, nil, L.UI_COND_ADD_NONE)
    page.addState:SetPoint("TOPLEFT", 0, -406)
    page.addBtn = W.Button(detail, L.UI_COND_ADD, 120, function()
        local state = page.addState:GetValue()
        if not state or not (State.IsAvailable(state) or Config.IsCurveDriven(state)) then return end
        local list = conditions()
        for _, c in ipairs(list) do
            if c.state == state then return end
        end
        list[#list + 1] = { state = state, alpha = 1 }
        if writeConditions(page, list) then
            P.condOffset = math.max(0, #list - Hide.COND_ROWS)
            setStatus(page, L.UI_COND_ADDED:format(L["STATE_" .. state]), C.ok)
        end
        Config.Refresh()
    end)
    page.addBtn:SetPoint("LEFT", page.addState, "RIGHT", 10, 0)
end

-- Detail -------------------------------------------------------------------------------------------
local function buildDetail(page)
    local d = CreateFrame("Frame", nil, page)
    d:SetPoint("TOPLEFT", LIST_W + 20, TOP)
    d:SetSize(498, 436)
    page.detail = d

    page.title = W.Text(d, "GameFontNormalLarge", C.text)
    page.title:SetPoint("TOPLEFT", 0, 0)
    page.info = W.Text(d, "GameFontHighlightSmall", C.muted)
    page.info:SetPoint("TOPLEFT", page.title, "BOTTOMLEFT", 0, -5)
    page.info:SetWidth(490)

    local function setter(key)
        return function(v)
            local ok, code = Elements.Set(P.selected, key, v)
            if not ok then fail(page, code, P.selected) end
            refreshList(page)
        end
    end
    page.base = W.Slider(d, L.UI_BASE_ALPHA, 0, 1, 0.05, 230, pct, setter("baseAlpha"))
    page.base:SetPoint("TOPLEFT", 0, -48)
    W.Tooltip(page.base, function() return L.UI_BASE_ALPHA, L.UI_BASE_ALPHA_TIP end)
    page.click = W.Check(d, L.UI_CLICK_THROUGH, setter("clickThrough"))
    page.click:SetPoint("TOPLEFT", 262, -58)
    W.Tooltip(page.click, function() return L.UI_CLICK_THROUGH, L.UI_CLICK_THROUGH_TIP end)

    page.fadeIn = W.Slider(d, L.UI_FADE_IN, 0, Fader.MAX_TIME, 0.1, 150, sec, setter("fadeIn"))
    page.fadeIn:SetPoint("TOPLEFT", 0, -94)
    page.fadeOut = W.Slider(d, L.UI_FADE_OUT, 0, Fader.MAX_TIME, 0.1, 150, sec, setter("fadeOut"))
    page.fadeOut:SetPoint("TOPLEFT", 170, -94)
    page.delay = W.Slider(d, L.UI_DELAY, 0, Fader.MAX_TIME, 0.1, 150, sec, setter("delay"))
    page.delay:SetPoint("TOPLEFT", 340, -94)
    W.Tooltip(page.delay, function() return L.UI_DELAY, L.UI_DELAY_TIP end)

    buildConditions(page, d)
end

local function refreshDetail(page)
    local id = P.selected
    local e = entryOf(id)
    local cfg = Elements.GetConfig(id)
    if not (e and cfg) then return end
    page.title:SetText(Elements.Label(id))
    local info, c
    if e.status == "missing" and e.optional and not e.addonLoaded then
        info, c = L.UI_EL_ADDON_MISSING_TIP:format(e.addon or "?"), C.disabled
    elseif e.status == "missing" then info, c = L.ELEMENT_NOT_IN_CLIENT:format(Elements.Label(id)), C.disabled
    elseif e.status == "pending" then info, c = L.UI_EL_PENDING_TIP, C.muted
    elseif e.enabled and not e.active then info, c = L.UI_EL_ERROR_TIP, C.warn
    elseif e.active then info, c = L.UI_EL_ACTIVE, C.ok
    else info, c = L.UI_EL_OFF_HINT, C.muted end
    page.info:SetText(info)
    W.Color(page.info, c)
    page.base:SetValue(cfg.baseAlpha)
    page.fadeIn:SetValue(cfg.fadeIn)
    page.fadeOut:SetValue(cfg.fadeOut)
    page.delay:SetValue(cfg.delay)
    page.click:SetValue(cfg.clickThrough)
    refreshConditions(page)
end

-- Preset ---------------------------------------------------------------------------------------------
local function buildPreset(page)
    local label = W.Text(page, "GameFontNormalSmall", C.muted)
    label:SetPoint("TOPLEFT", 0, -6)
    label:SetText(L.UI_PRESET_LABEL)
    page.preset = W.Dropdown(page, 180, nil)
    page.preset:SetPoint("LEFT", label, "RIGHT", 10, 0)
    local opts = {}
    for _, key in ipairs(Presets.ORDER) do opts[#opts + 1] = { value = key, text = L["PRESET_" .. key] } end
    page.preset:SetOptions(opts)
    page.preset:SetValue(Presets.ORDER[1])
    page.presetBtn = W.Button(page, L.UI_PRESET_APPLY, 130, function() Hide.AskPreset(page) end)
    page.presetBtn:SetPoint("LEFT", page.preset, "RIGHT", 10, 0)
    W.Tooltip(page.presetBtn, function() return L.UI_PRESET_APPLY, L.UI_PRESET_TIP end)
    page.status = W.Text(page, "GameFontHighlightSmall", C.muted)
    page.status:SetPoint("LEFT", page.presetBtn, "RIGHT", 14, 0)
    page.status:SetPoint("RIGHT", page, "RIGHT", 0, 0)
end

-- Zeile "Fuer alle Elemente": je Zeitwert ein Regler mit eigenem Knopf; wirkt auf alle Elemente des aktiven Profils
-- (auch ausgeschaltete), die Einzelwerte bleiben danach einzeln aenderbar. Die Regler halten nur den Wunschwert.
Hide.ALL_DEFAULTS = { fadeIn = Elements.DEFAULTS.fadeIn, fadeOut = Elements.DEFAULTS.fadeOut, delay = Elements.DEFAULTS.delay }
Hide.allValues = { fadeIn = Hide.ALL_DEFAULTS.fadeIn, fadeOut = Hide.ALL_DEFAULTS.fadeOut, delay = Hide.ALL_DEFAULTS.delay }

--- Wert auf alle Elemente anwenden (Knopf-Handler); Rueckmeldung in der Statuszeile
function Hide.ApplyAll(page, key)
    local labels = { fadeIn = L.UI_FADE_IN, fadeOut = L.UI_FADE_OUT, delay = L.UI_DELAY }
    local v = Hide.allValues[key]
    local n, code = Elements.SetAllTimes(key, v)
    if not n then
        fail(page, code, key)
    else
        setStatus(page, L.UI_ALL_DONE:format(labels[key], sec(v), n), C.ok)
    end
    Config.Refresh()
end

local function buildAll(page)
    local label = W.Text(page, "GameFontNormalSmall", C.accent)
    label:SetPoint("TOPLEFT", 0, -46)
    label:SetText(L.UI_ALL_LABEL)
    local keys = { { "fadeIn", L.UI_FADE_IN }, { "fadeOut", L.UI_FADE_OUT }, { "delay", L.UI_DELAY } }
    page.all = {}
    for i, k in ipairs(keys) do
        local key, text = k[1], k[2]
        local x = 130 + (i - 1) * 176
        local s = W.Slider(page, text, 0, Fader.MAX_TIME, 0.1, 106, sec, function(v) Hide.allValues[key] = v end)
        s:SetPoint("TOPLEFT", x, -34)
        s:SetValue(Hide.allValues[key])
        local b = W.Button(page, L.UI_ALL_APPLY, 60, function() Hide.ApplyAll(page, key) end)
        b:SetPoint("TOPLEFT", x + 110, -43)
        W.Tooltip(b, function() return L.UI_ALL_APPLY_TITLE:format(text), L.UI_ALL_TIP end)
        page.all[key] = { slider = s, button = b }
    end
end

--- Rueckfrage "Preset uebernehmen" (das aktive Profil wird fuer alle Elemente ueberschrieben)
function Hide.AskPreset(page)
    local key = page.preset:GetValue()
    if not key then return end
    local name = W.Plain(Store.GetActiveName())
    Config.Confirm(L.UI_PRESET_CONFIRM:format(L["PRESET_" .. key], name), L.UI_PRESET_APPLY, function()
        local res, code = Presets.Apply(key)
        if not res then
            fail(page, code, key)
        else
            setStatus(page, L.PRESET_APPLIED:format(L["PRESET_" .. key], name), C.ok)
        end
        Config.Refresh()
    end)
end

Config.RegisterPage("hide", {
    label = "UI_TAB_HIDE",
    build = function(page)
        P.selected = P.selected or Elements.CATALOG[1].id
        buildPreset(page)
        buildAll(page)
        buildList(page)
        buildDetail(page)
        Hide.page = page
    end,
    refresh = function(page)
        refreshList(page)
        refreshDetail(page)
    end,
    availability = function(page)
        if page:IsShown() then refreshConditions(page) end
    end,
})
