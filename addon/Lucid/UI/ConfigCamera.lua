-- Reiter "Kamera" (Spec B8, K2): Ein/Aus, Voreinstellungen, Regelliste (Grundwerte + Regeln je Zustand, Reihenfolge =
-- Prioritaet, die erste zutreffende gewinnt), Werte-Editor je Eintrag (Haken "setzen" + Regler), Schalter fuer die
-- Bewegungsuebelkeit-Abschaltung und die Experimental-Warnung. Alles geht ueber Camera.Set/SetMany (geprueft wie beim
-- Import) und wirkt sofort; nur gesetzte Werte werden geschrieben, der Rest bleibt bei Blizzard. Beschriftungen kommen
-- aus den Locales, der Reiter zeigt keinen Fremdtext.
local _, ns = ...
local Camera, CVars = ns.Camera, ns.CameraCVars
local Config, W = ns.Config, ns.Widgets
local L = ns.L
local C = W.COLORS

local Tab = {}
Config.Camera = Tab

local sel = 0          -- 0 = Grundwerte, i = Regel i
local section = "base" -- Werte-Gruppe im Editor
local addState = Camera.RULE_STATES[1]
local presetSel = Camera.PRESET_ORDER[1] -- gewaehlte Voreinstellung (wirkt erst mit "Uebernehmen")
local ROW_Y, ROW_H, COL_X, COL_W = -128, 50, { 276, 524 }, 232

local function copy(t)
    local out = {}
    for k, v in pairs(t) do out[k] = v end
    return out
end

local function enable(b, on)
    if on then b:Enable() else b:Disable() end
end

local function setStatus(page, text, c)
    page.status:SetText(text or "")
    W.Color(page.status, c or C.muted)
end

local function pendingNote(page)
    if InCombatLockdown() and next(CVars.Pending()) then setStatus(page, L.CAM_DEFERRED, C.muted) else setStatus(page, "") end
end

local function report(page, ok, code)
    if not ok then
        setStatus(page, L[code or "CAM_VALUE_INVALID"]:format(table.concat(Camera.Conflicts(), ", ")), C.warn)
    else
        pendingNote(page)
    end
    Config.Refresh()
    return ok
end

local function labelOf(rule, i, active)
    return ("%d. %s%s"):format(i, L["STATE_" .. rule.state], active and L.UI_CAM_ACTIVE_MARK or "")
end

local function currentCvars(cfg)
    if sel == 0 then return cfg.base.cvars end
    return cfg.rules[sel] and cfg.rules[sel].cvars or {}
end

--- Werte des gewaehlten Eintrags speichern (Grundwerte oder Regel sel)
local function commit(page, cvars)
    if sel == 0 then return report(page, Camera.Set("base.cvars", cvars)) end
    local rules = Camera.GetConfig().rules
    if not rules[sel] then return end
    rules[sel].cvars = cvars
    return report(page, Camera.Set("rules", rules))
end

--- Startwert beim Setzen eines Werts: in Regeln der Grundwert, sonst Blizzards aktueller Wert, sonst Untergrenze
local function startValue(p)
    local base = Camera.GetConfig().base.cvars[p.id]
    if sel ~= 0 and base ~= nil then return base end
    local cur = tonumber(CVars.Baseline(p.id) or CVars.Get(p.id))
    if cur and p.id == "cameraFov" then
        local lo, hi = Camera.FovRange()
        cur = math.max(lo, math.min(hi, cur))
    end
    local v = cur and Camera.ValidValue(p.id, cur)
    if v ~= nil then return v end
    if p.kind == "enum" then return p.values[1] end
    return p.min or 0
end

local function fmtFor(p)
    if p.kind == "bool" then return function(v) return v >= 1 and L.CAM_ON or L.CAM_OFF end end
    local decimals = (p.step and p.step < 1) and ((p.step < 0.1) and 2 or 1) or 0
    return function(v) return ("%." .. decimals .. "f"):format(v) end
end

local function tip(widget, p)
    W.Tooltip(widget, function()
        local key = "UI_CAM_P_" .. p.id .. "_TIP"
        local text = L[key]
        if text == key then text = nil end
        return L["UI_CAM_P_" .. p.id], text
    end)
end

local function buildParam(page, p, index)
    local x = COL_X[(index - 1) % 2 + 1]
    local y = ROW_Y - math.floor((index - 1) / 2) * ROW_H
    local w = { param = p }
    w.check = W.Check(page, "", function(on)
        local cvars = copy(currentCvars(Camera.GetConfig()))
        cvars[p.id] = on and startValue(p) or nil
        commit(page, cvars)
    end)
    w.check:SetPoint("TOPLEFT", x - 4, y - 14)
    W.Tooltip(w.check, function() return L.UI_CAM_SET, L.UI_CAM_SET_TIP end)
    if p.kind == "enum" then
        w.title = W.Text(page, "GameFontNormalSmall", C.muted)
        w.title:SetPoint("TOPLEFT", x + 24, y)
        w.title:SetText(L["UI_CAM_P_" .. p.id])
        w.dropdown = W.Dropdown(page, COL_W - 28, function(v)
            local cvars = copy(currentCvars(Camera.GetConfig()))
            cvars[p.id] = v
            commit(page, cvars)
        end)
        w.dropdown:SetPoint("TOPLEFT", x + 24, y - 16)
        local options = {}
        for _, v in ipairs(p.values) do options[#options + 1] = { value = v, text = L["CAM_ENUM_" .. p.id .. "_" .. v] } end
        w.dropdown:SetOptions(options)
        tip(w.dropdown, p)
        w.control = w.dropdown
    else
        local lo, hi = p.min or 0, p.max or 1
        if p.id == "cameraFov" then lo, hi = Camera.FovRange() end -- Grenzen des Clients, sonst 50 bis 90
        local step = p.kind == "bool" and 1 or p.step
        w.slider = W.Slider(page, L["UI_CAM_P_" .. p.id], lo, hi, step, COL_W - 28, fmtFor(p), function(v)
            local cvars = copy(currentCvars(Camera.GetConfig()))
            cvars[p.id] = v
            commit(page, cvars)
        end)
        w.slider:SetPoint("TOPLEFT", x + 24, y)
        tip(w.slider.slider, p)
        w.control = w.slider
    end
    return w
end

local function showSection(page)
    for _, w in ipairs(page.params) do
        local on = w.param.section == section
        for _, f in ipairs({ w.check, w.slider, w.dropdown, w.title }) do
            if f then if on then f:Show() else f:Hide() end end
        end
    end
    for _, f in ipairs({ page.zoomCheck, page.zoomSlider, page.secondsSlider, page.zoomNote }) do
        if section == "zoom" then f:Show() else f:Hide() end
    end
    if section == "action" then page.offsetSecondsSlider:Show() else page.offsetSecondsSlider:Hide() end
end

Config.RegisterPage("camera", {
    label = "UI_TAB_CAMERA",
    build = function(page)
        page.enabled = W.Check(page, L.UI_CAM_ENABLE, function(v) report(page, Camera.Set("enabled", v)) end)
        page.enabled:SetPoint("TOPLEFT", 0, -4)
        W.Tooltip(page.enabled, function() return L.UI_CAM_ENABLE, L.UI_CAM_ENABLE_TIP end)

        page.presetLabel = W.Text(page, "GameFontNormalSmall", C.muted)
        page.presetLabel:SetPoint("TOPLEFT", 276, -9)
        page.presetLabel:SetText(L.UI_CAM_PRESETS)
        -- Voreinstellung: Auswahl + "Uebernehmen" (sechs Knoepfe passen nicht in die Zeile, und das Ersetzen aller Regeln
        -- soll ein bewusster zweiter Klick sein)
        page.presetDropdown = W.Dropdown(page, 200, function(v) presetSel = v end)
        page.presetDropdown:SetPoint("TOPLEFT", 276 + 86, -3)
        local presetOptions = {}
        for _, id in ipairs(Camera.PRESET_ORDER) do presetOptions[#presetOptions + 1] = { value = id, text = L["UI_CAM_PRESET_" .. id] } end
        page.presetDropdown:SetOptions(presetOptions)
        W.Tooltip(page.presetDropdown, function() return L["UI_CAM_PRESET_" .. presetSel], L["UI_CAM_PRESET_" .. presetSel .. "_TIP"] end)
        page.presetApply = W.Button(page, L.UI_CAM_PRESET_APPLY, 100, function() report(page, Camera.ApplyPreset(presetSel)) end)
        page.presetApply:SetPoint("TOPLEFT", 276 + 86 + 208, -3)
        W.Tooltip(page.presetApply, function() return L["UI_CAM_PRESET_" .. presetSel], L.UI_CAM_PRESET_APPLY_TIP end)

        page.locked = W.Text(page, "GameFontHighlightSmall", C.warn)
        page.locked:SetPoint("TOPLEFT", 4, -30)
        page.locked:SetWidth(740)
        page.locked:Hide()

        -- Regelliste (links)
        local head = W.Header(page, L.UI_CAM_RULES, 250)
        head:SetPoint("TOPLEFT", 0, -56)
        page.rows = {}
        for i = 0, Camera.MAX_RULES do
            local b = W.FlatButton(page, 250, 22, "GameFontHighlight")
            b:SetPoint("TOPLEFT", 0, -80 - i * 22)
            b:SetScript("OnClick", function()
                sel = i
                Config.Refresh()
            end)
            page.rows[i] = b
        end
        local by = -80 - (Camera.MAX_RULES + 1) * 22 - 6
        page.up = W.Button(page, L.UI_CAM_UP, 78, function()
            local rules = Camera.GetConfig().rules
            if sel < 2 then return end
            rules[sel], rules[sel - 1] = rules[sel - 1], rules[sel]
            sel = sel - 1
            report(page, Camera.Set("rules", rules))
        end)
        page.up:SetPoint("TOPLEFT", 0, by)
        page.down = W.Button(page, L.UI_CAM_DOWN, 78, function()
            local rules = Camera.GetConfig().rules
            if sel < 1 or sel >= #rules then return end
            rules[sel], rules[sel + 1] = rules[sel + 1], rules[sel]
            sel = sel + 1
            report(page, Camera.Set("rules", rules))
        end)
        page.down:SetPoint("TOPLEFT", 82, by)
        page.remove = W.Button(page, L.UI_CAM_REMOVE, 86, function()
            local rules = Camera.GetConfig().rules
            if sel < 1 or not rules[sel] then return end
            table.remove(rules, sel)
            sel = math.min(sel, #rules)
            report(page, Camera.Set("rules", rules))
        end)
        page.remove:SetPoint("TOPLEFT", 164, by)
        page.addLabel = W.Text(page, "GameFontNormalSmall", C.muted)
        page.addLabel:SetPoint("TOPLEFT", 0, by - 30)
        page.addLabel:SetText(L.UI_CAM_ADD_FOR)
        page.addState = W.Dropdown(page, 160, function(v) addState = v end)
        page.addState:SetPoint("TOPLEFT", 0, by - 46)
        local options = {}
        for _, name in ipairs(Camera.RULE_STATES) do options[#options + 1] = { value = name, text = L["STATE_" .. name] } end
        page.addState:SetOptions(options)
        page.add = W.Button(page, L.UI_CAM_ADD, 86, function()
            local rules = Camera.GetConfig().rules
            if #rules >= Camera.MAX_RULES then return end
            rules[#rules + 1] = { state = addState, cvars = {} }
            sel = #rules
            report(page, Camera.Set("rules", rules))
        end)
        page.add:SetPoint("TOPLEFT", 164, by - 45)
        page.order = W.Text(page, "GameFontHighlightSmall", C.muted)
        page.order:SetPoint("TOPLEFT", 0, by - 76)
        page.order:SetWidth(250)
        page.order:SetText(L.UI_CAM_ORDER_NOTE)

        -- Editor (rechts)
        page.editHead = W.Header(page, "", 468)
        page.editHead:SetPoint("TOPLEFT", 270, -56)
        page.sectionDropdown = W.Dropdown(page, 200, function(v)
            section = v
            showSection(page)
            Config.Refresh()
        end)
        page.sectionDropdown:SetPoint("TOPLEFT", 270, -80)
        local sections = {}
        for _, s in ipairs(Camera.SECTIONS) do sections[#sections + 1] = { value = s, text = L["UI_CAM_SEC_" .. s] } end
        page.sectionDropdown:SetOptions(sections)
        page.ruleHint = W.Text(page, "GameFontHighlightSmall", C.muted)
        page.ruleHint:SetPoint("TOPLEFT", 480, -84)
        page.ruleHint:SetWidth(260)

        page.params = {}
        local counters = {}
        for _, p in ipairs(Camera.PARAMS) do
            if not p.hidden then
                counters[p.section] = (counters[p.section] or 0) + 1
                page.params[#page.params + 1] = buildParam(page, p, counters[p.section])
            end
        end
        -- Gruppe "Zoom": Ziel-Distanz des gewaehlten Eintrags + Dauer des weichen Uebergangs (gilt fuer alle)
        local function commitZoom(v)
            local cfg = Camera.GetConfig()
            if sel == 0 then
                report(page, Camera.Set("base", { cvars = cfg.base.cvars, zoom = v }))
            elseif cfg.rules[sel] then
                cfg.rules[sel].zoom = v
                report(page, Camera.Set("rules", cfg.rules))
            end
        end
        local function currentZoom(cfg)
            if sel == 0 then return cfg.base.zoom end
            return cfg.rules[sel] and cfg.rules[sel].zoom or nil
        end
        Tab.currentZoom = currentZoom
        page.zoomCheck = W.Check(page, "", function(on)
            if not on then return commitZoom(nil) end
            local cur = Camera.Zoom.Saved() or (type(GetCameraZoom) == "function" and GetCameraZoom()) or 10
            commitZoom(math.max(Camera.ZOOM_MIN, math.min(Camera.ZOOM_MAX, math.floor(cur + 0.5))))
        end)
        page.zoomCheck:SetPoint("TOPLEFT", 272, -142)
        W.Tooltip(page.zoomCheck, function() return L.UI_CAM_SET, L.UI_CAM_SET_TIP end)
        page.zoomSlider = W.Slider(page, L.UI_CAM_ZOOM, Camera.ZOOM_MIN, Camera.ZOOM_MAX, 1, 400,
            function(v) return ("%g m"):format(v) end, function(v) commitZoom(v) end)
        page.zoomSlider:SetPoint("TOPLEFT", 300, -128)
        W.Tooltip(page.zoomSlider.slider, function() return L.UI_CAM_ZOOM, L.UI_CAM_ZOOM_TIP end)
        page.secondsSlider = W.Slider(page, L.UI_CAM_ZOOM_SECONDS, Camera.ZOOM_SECONDS_MIN, 3, 0.1, 400,
            function(v) return ("%g s"):format(v) end, function(v) report(page, Camera.Set("zoomSeconds", v)) end)
        page.secondsSlider:SetPoint("TOPLEFT", 300, -190)
        page.zoomNote = W.Text(page, "GameFontHighlightSmall", C.muted)
        page.zoomNote:SetPoint("TOPLEFT", 300, -240)
        page.zoomNote:SetWidth(440)
        page.zoomNote:SetText(L.UI_CAM_ZOOM_NOTE)
        -- Uebergangsdauer des Schulterversatzes (gilt fuer alle Eintraege), in der Gruppe "Action Cam"
        page.offsetSecondsSlider = W.Slider(page, L.UI_CAM_OFFSET_SECONDS, Camera.OFFSET_SECONDS_MIN, Camera.OFFSET_SECONDS_MAX, 0.1, 400,
            function(v) return v <= 0 and L.UI_CAM_OFFSET_INSTANT or ("%g s"):format(v) end,
            function(v) report(page, Camera.Set("offsetSeconds", v)) end)
        page.offsetSecondsSlider:SetPoint("TOPLEFT", 300, -282)
        W.Tooltip(page.offsetSecondsSlider.slider, function() return L.UI_CAM_OFFSET_SECONDS, L.UI_CAM_OFFSET_SECONDS_TIP end)
        showSection(page)

        -- Schalter und Hinweise (unten)
        page.comfort = W.Check(page, L.UI_CAM_COMFORT, function(v) report(page, Camera.Set("autoComfort", v)) end)
        page.comfort:SetPoint("TOPLEFT", 270, -330)
        W.Tooltip(page.comfort, function() return L.UI_CAM_COMFORT, L.UI_CAM_COMFORT_TIP end)
        page.popup = W.Check(page, L.UI_CAM_POPUP, function(v) report(page, Camera.Set("suppressPopup", v)) end)
        page.popup:SetPoint("TOPLEFT", 270, -354)
        W.Tooltip(page.popup, function() return L.UI_CAM_POPUP, L.UI_CAM_POPUP_TIP end)
        page.offset = W.Check(page, L.UI_CAM_OFFSET, function(v) report(page, Camera.Set("offsetByDistance", v)) end)
        page.offset:SetPoint("TOPLEFT", 270, -378)
        W.Tooltip(page.offset, function() return L.UI_CAM_OFFSET, L.UI_CAM_OFFSET_TIP end)

        page.note = W.Text(page, "GameFontHighlightSmall", C.muted)
        page.note:SetPoint("TOPLEFT", 270, -408)
        page.note:SetWidth(480)
        page.note:SetText(L.UI_CAM_NOTE_COMFORT .. "\n" .. L.UI_CAM_NOTE_POPUP)
        page.status = W.Text(page, "GameFontHighlightSmall", C.muted)
        page.status:SetPoint("TOPLEFT", 4, -486) -- eine Zeile (Seite: 504 px)
        page.status:SetWidth(740)
        Tab.page = page
    end,
    refresh = function(page)
        local cfg = Camera.GetConfig()
        local locked = Camera.IsLocked()
        if sel > #cfg.rules then sel = #cfg.rules end
        local usable = not locked
        page.enabled:SetValue(cfg.enabled)
        page.enabled:SetActive(usable)
        page.presetDropdown:SetValue(presetSel)
        page.presetDropdown:SetActive(usable)
        enable(page.presetApply, usable)
        if locked then
            page.locked:SetText(L.CAM_LOCKED:format(table.concat(Camera.Conflicts(), ", ")))
            page.locked:Show()
        else
            page.locked:Hide()
        end
        local active = Camera.ActiveRule(cfg)
        page.rows[0].label:SetText(L.UI_CAM_BASE_ROW)
        page.rows[0]:SetSelected(sel == 0)
        for i = 1, Camera.MAX_RULES do
            local row, rule = page.rows[i], cfg.rules[i]
            if rule then
                row.label:SetText(labelOf(rule, i, cfg.enabled and active == i))
                row:SetSelected(sel == i)
                row:Show()
            else
                row:Hide()
            end
        end
        enable(page.up, sel > 1)
        enable(page.down, sel >= 1 and sel < #cfg.rules)
        enable(page.remove, sel >= 1)
        enable(page.add, #cfg.rules < Camera.MAX_RULES)
        page.addState:SetValue(addState)

        local title = sel == 0 and L.UI_CAM_BASE_ROW or labelOf(cfg.rules[sel], sel, false)
        page.editHead:SetText(L.UI_CAM_EDIT:format(title))
        page.sectionDropdown:SetValue(section)
        page.ruleHint:SetText(sel == 0 and L.UI_CAM_BASE_HINT or L.UI_CAM_RULE_HINT)
        local cvars = currentCvars(cfg)
        for _, w in ipairs(page.params) do
            local v = cvars[w.param.id]
            local set = v ~= nil
            w.check:SetValue(set)
            w.check:SetActive(usable)
            if w.slider then
                w.slider:SetValue(set and v or startValue(w.param))
                w.slider:SetActive(usable and set)
            else
                w.dropdown:SetValue(set and v or w.param.values[1])
                w.dropdown:SetActive(usable and set)
            end
        end
        local z = Tab.currentZoom(cfg)
        page.zoomCheck:SetValue(z ~= nil)
        page.zoomCheck:SetActive(usable)
        page.zoomSlider:SetValue(z or 10)
        page.zoomSlider:SetActive(usable and z ~= nil)
        page.secondsSlider:SetValue(cfg.zoomSeconds)
        page.secondsSlider:SetActive(usable)
        page.offsetSecondsSlider:SetValue(cfg.offsetSeconds)
        page.offsetSecondsSlider:SetActive(usable)
        page.comfort:SetValue(cfg.autoComfort)
        page.comfort:SetActive(usable)
        page.popup:SetValue(cfg.suppressPopup)
        page.popup:SetActive(usable)
        page.offset:SetValue(cfg.offsetByDistance)
        page.offset:SetActive(usable)
    end,
})
