-- Reiter "Zonentext" (Spec B5, Oberflaechen-Delta): Modul an/aus, Mindestabstand, Glanz- und Lichtband-Staerke
-- (0-100 %, Nachtrag 03.11.), Verzierung (Stil + Groesse), je Ausloeser (Zone | Subzone |
-- Entdeckung) Anzeigen, Schrift, Groesse, Einblenden, Dauer, Ausblenden; Knoepfe Testen, Position verschieben und
-- zuruecksetzen. Alle Werte gehen ueber Zone.Validate ins aktive Profil und wirken sofort (Karten lesen die
-- Einstellungen beim Start). Der Reiter enthaelt keinen Fremdtext; Beschriftungen kommen aus den Locales.
local _, ns = ...
local Zone = ns.Zone
local Store = ns.Store
local Config, W = ns.Config, ns.Widgets
local L = ns.L
local C = W.COLORS

local ZoneTab = { selected = "zone" }
Config.Zone = ZoneTab

local function sec(v) return ("%g s"):format(v) end
local function px(v) return ("%g"):format(v) end
local function pct(v) return ("%g %%"):format(v) end

local function setStatus(page, text, c)
    page.status:SetText(text or "")
    W.Color(page.status, c or C.muted)
end

--- Abschnitt "zone" des aktiven Profils aendern: Kopie anpassen, ueber Zone.Validate pruefen, speichern.
local function update(page, mutate)
    local p = Store.GetActive()
    if not p then return nil end
    local z = Zone.GetConfig() -- frische, gueltige Kopie
    mutate(z)
    local clean = Zone.Validate(z)
    if not clean then
        setStatus(page, L.ZONE_VALUE_INVALID, C.warn)
        Config.Refresh()
        return nil
    end
    p.zone = clean
    setStatus(page, "")
    Config.Refresh()
    return true
end

local function triggerSetter(page, key)
    return function(v)
        update(page, function(z) z[ZoneTab.selected][key] = v end)
    end
end

local function fontOptions()
    local opts = {}
    for _, key in ipairs(Zone.FONT_KEYS) do
        local ok = ns.ZoneCard == nil or ns.ZoneCard.FontAvailable(key)
        local text = L["ZONE_FONT_" .. key]
        if not ok then text = text .. " " .. L.ZONE_FONT_UNAVAILABLE end
        opts[#opts + 1] = { value = key, text = text, disabled = not ok }
    end
    return opts
end

Config.RegisterPage("zone", {
    label = "UI_TAB_ZONE",
    build = function(page)
        page.enable = W.Check(page, L.UI_ZONE_ENABLE, function(on)
            local ok, code = Zone.SetEnabled(on)
            if not ok then setStatus(page, L[code or "ZONE_VALUE_INVALID"], C.warn) else setStatus(page, "") end
            Config.Refresh()
        end)
        page.enable:SetPoint("TOPLEFT", 0, -6)
        W.Tooltip(page.enable, function() return L.UI_ZONE_ENABLE, L.UI_ZONE_ENABLE_TIP end)

        page.minGap = W.Slider(page, L.UI_ZONE_MINGAP, Zone.LIMITS.minGap[1], Zone.LIMITS.minGap[2], 5, 160, sec, function(v)
            update(page, function(z) z.minGap = v end)
        end)
        page.minGap:SetPoint("TOPLEFT", 4, -38)
        W.Tooltip(page.minGap, function() return L.UI_ZONE_MINGAP, L.UI_ZONE_MINGAP_TIP end)
        -- Staerke von Glanz und Lichtband (gelten fuer alle Ausloeser; nur die grosse Karte zeigt beides)
        for i, key in ipairs(Zone.STRENGTH_KEYS) do
            local label, tip = L["UI_ZONE_" .. key:upper()], L["UI_ZONE_" .. key:upper() .. "_TIP"]
            local r = Zone.LIMITS.strength
            page[key] = W.Slider(page, label, r[1], r[2], 5, 160, pct, function(v)
                update(page, function(z) z[key] = v end)
            end)
            page[key]:SetPoint("TOPLEFT", 4 + i * 182, -38)
            W.Tooltip(page[key], function() return label, tip end)
        end
        -- Verzierung der grossen Karte: Stil (Auswahl) und Groesse (rechte Spalte)
        page.ornLabel = W.Text(page, "GameFontNormalSmall", C.muted)
        page.ornLabel:SetPoint("TOPLEFT", 560, -38)
        page.ornLabel:SetText(L.UI_ZONE_ORNAMENT)
        page.ornament = W.Dropdown(page, 180, function(v)
            update(page, function(z) z.ornament = v end)
        end)
        page.ornament:SetPoint("TOPLEFT", 560, -54)
        local opts = {}
        for _, key in ipairs(Zone.ORNAMENTS) do opts[#opts + 1] = { value = key, text = L["ZONE_ORNAMENT_" .. key] } end
        page.ornament:SetOptions(opts)
        W.Tooltip(page.ornament, function() return L.UI_ZONE_ORNAMENT, L.UI_ZONE_ORNAMENT_TIP end)
        local rs = Zone.LIMITS.ornScale
        page.ornScale = W.Slider(page, L.UI_ZONE_ORN_SCALE, rs[1], rs[2], 5, 180, pct, function(v)
            update(page, function(z) z.ornScale = v end)
        end)
        page.ornScale:SetPoint("TOPLEFT", 560, -100)
        W.Tooltip(page.ornScale, function() return L.UI_ZONE_ORN_SCALE, L.UI_ZONE_ORN_SCALE_TIP end)
        local rd = Zone.LIMITS.ornDelay
        page.ornDelay = W.Slider(page, L.UI_ZONE_ORN_DELAY, rd[1], rd[2], 0.1, 180, sec, function(v)
            update(page, function(z) z.ornDelay = v end)
        end)
        page.ornDelay:SetPoint("TOPLEFT", 560, -148)
        W.Tooltip(page.ornDelay, function() return L.UI_ZONE_ORN_DELAY, L.UI_ZONE_ORN_DELAY_TIP end)
        local rf = Zone.LIMITS.ornFade
        page.ornFade = W.Slider(page, L.UI_ZONE_ORN_FADE, rf[1], rf[2], 0.1, 180, sec, function(v)
            update(page, function(z) z.ornFade = v end)
        end)
        page.ornFade:SetPoint("TOPLEFT", 560, -196)
        W.Tooltip(page.ornFade, function() return L.UI_ZONE_ORN_FADE, L.UI_ZONE_ORN_FADE_TIP end)

        local head = W.Header(page, L.UI_ZONE_TRIGGERS, 520)
        head:SetPoint("TOPLEFT", 0, -92)
        page.tabs = {}
        for i, key in ipairs(Zone.TRIGGERS) do
            local b = W.FlatButton(page, 120, 24, "GameFontHighlight")
            b:SetPoint("TOPLEFT", (i - 1) * 126, -116)
            b.label:SetText(L["ZONE_TRIGGER_" .. key])
            b:SetScript("OnClick", function()
                ZoneTab.selected = key
                Config.Refresh()
            end)
            page.tabs[key] = b
        end

        page.show = W.Check(page, L.UI_ZONE_SHOW, function(on)
            update(page, function(z) z[ZoneTab.selected].on = on end)
        end)
        page.show:SetPoint("TOPLEFT", 0, -148)

        page.fontLabel = W.Text(page, "GameFontNormalSmall", C.muted)
        page.fontLabel:SetPoint("TOPLEFT", 4, -180)
        page.fontLabel:SetText(L.UI_ZONE_FONT)
        page.font = W.Dropdown(page, 220, function(v)
            update(page, function(z) z[ZoneTab.selected].font = v end)
        end)
        page.font:SetPoint("TOPLEFT", 4, -196)
        page.font:SetOptions(fontOptions())

        local lim = Zone.LIMITS
        page.size = W.Slider(page, L.UI_ZONE_SIZE, lim.size[1], lim.size[2], 1, 250, px, triggerSetter(page, "size"))
        page.size:SetPoint("TOPLEFT", 300, -180)
        page.fadeIn = W.Slider(page, L.UI_ZONE_FADE_IN, lim.fadeIn[1], lim.fadeIn[2], 0.1, 250, sec,
            triggerSetter(page, "fadeIn"))
        page.fadeIn:SetPoint("TOPLEFT", 4, -240)
        page.hold = W.Slider(page, L.UI_ZONE_HOLD, lim.hold[1], lim.hold[2], 0.1, 250, sec, triggerSetter(page, "hold"))
        page.hold:SetPoint("TOPLEFT", 300, -240)
        page.fadeOut = W.Slider(page, L.UI_ZONE_FADE_OUT, lim.fadeOut[1], lim.fadeOut[2], 0.1, 250, sec,
            triggerSetter(page, "fadeOut"))
        page.fadeOut:SetPoint("TOPLEFT", 4, -290)

        page.test = W.Button(page, L.UI_ZONE_TEST, 110, function()
            if ns.ZoneCard then ns.ZoneCard.Test(ZoneTab.selected) end
        end)
        page.test:SetPoint("TOPLEFT", 4, -350)
        page.move = W.Button(page, L.UI_ZONE_MOVE, 170, function()
            if ns.ZoneMove then ns.ZoneMove.Start() end
        end)
        page.move:SetPoint("TOPLEFT", 124, -350)
        page.reset = W.Button(page, L.UI_ZONE_RESET_POS, 170, function()
            if ns.ZoneMove and ns.ZoneMove.ResetPosition() then ns.Print(L.ZONE_POS_RESET) end
        end)
        page.reset:SetPoint("TOPLEFT", 304, -350)

        page.note = W.Text(page, "GameFontHighlightSmall", C.muted)
        page.note:SetPoint("TOPLEFT", 4, -396)
        page.note:SetWidth(520)
        page.note:SetText(L.UI_ZONE_NOTE)
        page.status = W.Text(page, "GameFontHighlightSmall", C.muted)
        page.status:SetPoint("TOPLEFT", 4, -440)
        page.status:SetWidth(520)
        ZoneTab.page = page
    end,
    refresh = function(page)
        local cfg = Zone.GetConfig()
        local sel = ZoneTab.selected
        local t = cfg[sel]
        page.enable:SetValue(cfg.enabled)
        page.minGap:SetValue(cfg.minGap)
        page.glow:SetValue(cfg.glow)
        page.band:SetValue(cfg.band)
        page.ornament:SetValue(cfg.ornament)
        page.ornScale:SetValue(cfg.ornScale)
        page.ornScale:SetActive(cfg.ornament ~= "none")
        page.ornDelay:SetValue(cfg.ornDelay)
        page.ornDelay:SetActive(cfg.ornament ~= "simple" and cfg.ornament ~= "none")
        page.ornFade:SetValue(cfg.ornFade)
        page.ornFade:SetActive(cfg.ornament ~= "simple" and cfg.ornament ~= "none")
        for key, b in pairs(page.tabs) do
            b:SetSelected(key == sel)
            W.Color(b.label, key == sel and C.accent or C.muted)
        end
        page.show:SetValue(t.on)
        page.font:SetValue(t.font)
        page.size:SetValue(t.size)
        page.fadeIn:SetValue(t.fadeIn)
        page.hold:SetValue(t.hold)
        page.fadeOut:SetValue(t.fadeOut)
        page.font:SetActive(t.on)
        W.Color(page.fontLabel, t.on and C.muted or C.disabled)
        for _, k in ipairs({ "size", "fadeIn", "hold", "fadeOut" }) do page[k]:SetActive(t.on) end
    end,
})
