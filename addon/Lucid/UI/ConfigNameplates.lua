-- Reiter "Plaketten" (Spec B7, Oberflaechen-Delta): Ein/Aus, Gegner und Freunde getrennt ("in Ruhe zeigen" + Bedingungen),
-- Ziel immer zeigen, Sichtweite (Schalter + Regler), weich/hart + Dauer, kleine Voreinstellungen und Hinweise zu Taste V
-- und Instanzen. Zweite Ansicht "Aussehen" (Plaketten-Stil mit Live-Vorschau): UI/ConfigNameplatesLook.lua. Alles geht ueber Nameplates.Set/SetMany (geprueft wie beim Import) und wirkt sofort; im Kampf
-- wartet die Sichtweite bis Kampfende. Beschriftungen kommen aus den Locales, der Reiter zeigt keinen Fremdtext.
local _, ns = ...
local NP = ns.Nameplates
local Config, W = ns.Config, ns.Widgets
local L = ns.L
local C = W.COLORS

local Tab = {}
Config.Nameplates = Tab

-- Zustaende, die der Reiter anbietet (Reihenfolge = Anzeige); "mouseover" gibt es fuer Plaketten nicht
local CONDITIONS = { "combat", "target", "focus", "resting", "city", "group", "raid", "instance", "mounted" }
Tab.CONDITIONS = CONDITIONS

local function setStatus(page, text, c)
    page.status:SetText(text or "")
    W.Color(page.status, c or C.muted)
end

local function apply(page, changes)
    local ok, code = NP.SetMany(changes)
    if not ok then
        setStatus(page, L[code or "NP_VALUE_INVALID"], C.warn)
    elseif InCombatLockdown() and next(ns.CVars.Pending()) then
        setStatus(page, L.NP_DEFERRED, C.muted)
    else
        setStatus(page, "")
    end
    Config.Refresh()
    return ok
end
Tab.Apply = apply
Tab.SetStatus = setStatus

--- Bedingungsliste mit/ohne name, in der festen Reihenfolge des Reiters
local function toggled(list, name, on)
    local set = {}
    for _, c in ipairs(list) do set[c] = true end
    set[name] = on or nil
    local out = {}
    for _, c in ipairs(CONDITIONS) do
        if set[c] then out[#out + 1] = c end
    end
    -- Bedingungen aus anderen Quellen (Import) bleiben erhalten
    for _, c in ipairs(list) do
        local known = false
        for _, k in ipairs(CONDITIONS) do if k == c then known = true end end
        if not known and set[c] then out[#out + 1] = c end
    end
    return out
end

local function buildGroup(page, key, title, x)
    local g = {}
    local head = W.Header(page.vis, title, 360)
    head:SetPoint("TOPLEFT", x, -78)
    g.base = W.Check(page.vis, L.UI_NP_BASE, function(v) apply(page, { [key .. ".baseShow"] = v }) end)
    g.base:SetPoint("TOPLEFT", x, -102)
    W.Tooltip(g.base, function() return L.UI_NP_BASE, L.UI_NP_BASE_TIP end)
    g.keep = W.Check(page.vis, L.UI_NP_KEEP_TARGET, function(v) apply(page, { [key .. ".keepTarget"] = v }) end)
    g.keep:SetPoint("TOPLEFT", x, -336)
    W.Tooltip(g.keep, function() return L.UI_NP_KEEP_TARGET, L.UI_NP_KEEP_TARGET_TIP end)
    g.when = W.Text(page.vis, "GameFontNormalSmall", C.muted)
    g.when:SetPoint("TOPLEFT", x + 4, -130)
    g.when:SetText(L.UI_NP_WHEN)
    g.checks = {}
    for i, name in ipairs(CONDITIONS) do
        local cb = W.Check(page.vis, L["STATE_" .. name], function(v)
            local cfg = NP.GetConfig()
            apply(page, { [key .. ".conditions"] = toggled(cfg[key].conditions, name, v) })
        end)
        cb:SetPoint("TOPLEFT", x, -148 - (i - 1) * 20)
        local reason = Config.StateReason(name)
        if reason then W.Tooltip(cb, function() return L["STATE_" .. name], reason end) end
        g.checks[name] = cb
    end
    return g
end

--- Ansicht wechseln: "vis" (Sichtbarkeit), "look" (Aussehen mit Live-Vorschau) oder "far" (Quest-Fernsicht)
function Tab.SelectView(page, id)
    if id ~= "vis" and id ~= "look" and id ~= "far" then return false end
    page.view = id
    page.vis:SetShown(id == "vis")
    page.look:SetShown(id == "look")
    page.far:SetShown(id == "far")
    page.presetLabel:SetShown(id == "vis")
    for _, b in pairs(page.presets) do b:SetShown(id == "vis") end
    for vid, b in pairs(page.views) do
        b:SetSelected(vid == id)
        W.Color(b.label, vid == id and C.accent or C.muted)
    end
    Config.Refresh()
    return true
end

Config.RegisterPage("nameplates", {
    label = "UI_TAB_NAMEPLATES",
    build = function(page)
        page.enabled = W.Check(page, L.UI_NP_ENABLE, function(v) apply(page, { enabled = v }) end)
        page.enabled:SetPoint("TOPLEFT", 0, -4)
        W.Tooltip(page.enabled, function() return L.UI_NP_ENABLE, L.UI_NP_ENABLE_TIP end)

        page.presetLabel = W.Text(page, "GameFontNormalSmall", C.muted)
        page.presetLabel:SetPoint("TOPLEFT", 330, -9)
        page.presetLabel:SetText(L.UI_NP_PRESETS)
        local x = 330 + 86
        page.presets = {}
        for _, id in ipairs(NP.PRESET_ORDER) do
            local b = W.Button(page, L["UI_NP_PRESET_" .. id], 112, function()
                local ok, code = NP.ApplyPreset(id)
                if not ok then setStatus(page, L[code or "NP_VALUE_INVALID"], C.warn) else setStatus(page, "") end
                Config.Refresh()
            end)
            b:SetPoint("TOPLEFT", x, -3)
            page.presets[id] = b
            x = x + 116
        end

        -- Ansicht "Sichtbarkeit" (bisheriger Inhalt) in einem Container, daneben "Aussehen" (Plaketten-Stil, Live-Vorschau)
        page.vis = CreateFrame("Frame", nil, page)
        page.vis:SetAllPoints(page)
        page.look = CreateFrame("Frame", nil, page)
        page.look:SetPoint("TOPLEFT", 0, -72)
        page.look:SetPoint("BOTTOMRIGHT", 0, 22)
        page.look:Hide()
        page.far = CreateFrame("Frame", nil, page)
        page.far:SetPoint("TOPLEFT", 0, -72)
        page.far:SetPoint("BOTTOMRIGHT", 0, 22)
        page.far:Hide()
        page.views = {}
        local vx = 0
        for _, id in ipairs({ "vis", "look", "far" }) do
            local b = W.FlatButton(page, 130, 24, "GameFontNormal")
            b:SetPoint("TOPLEFT", vx, -36)
            b.label:SetText(L["UI_NP_VIEW_" .. id])
            if b.label.SetJustifyH then b.label:SetJustifyH("CENTER") end
            b:SetScript("OnClick", function() Tab.SelectView(page, id) end)
            page.views[id] = b
            vx = vx + 134
        end
        W.Tooltip(page.views.look, function() return L.UI_NP_VIEW_look, L.UI_NP_VIEW_look_TIP end)
        W.Tooltip(page.views.far, function() return L.UI_NP_VIEW_far, L.UI_NP_VIEW_far_TIP end)

        page.enemies = buildGroup(page, "enemies", L.NP_ENEMIES, 0)
        page.friends = buildGroup(page, "friends", L.NP_FRIENDS, 390)

        page.radiusOn = W.Check(page.vis, L.UI_NP_RADIUS, function(v) apply(page, { ["radius.enabled"] = v }) end)
        page.radiusOn:SetPoint("TOPLEFT", 0, -360)
        W.Tooltip(page.radiusOn, function() return L.UI_NP_RADIUS, L.UI_NP_RADIUS_TIP end)
        page.radius = W.Slider(page.vis, L.UI_NP_RADIUS_YARDS, NP.RADIUS_MIN, NP.RADIUS_MAX, 1, 340,
            function(v) return ("%g m"):format(v) end, function(v) apply(page, { ["radius.yards"] = v }) end)
        page.radius:SetPoint("TOPLEFT", 4, -384)

        page.fadeLabel = W.Text(page.vis, "GameFontNormalSmall", C.muted)
        page.fadeLabel:SetPoint("TOPLEFT", 390, -340)
        page.fadeLabel:SetText(L.UI_NP_FADE)
        page.fade = W.Dropdown(page.vis, 200, function(v) apply(page, { fade = v }) end)
        page.fade:SetPoint("TOPLEFT", 390, -356)
        page.fade:SetOptions({
            { value = "soft", text = L.NP_FADE_soft },
            { value = "hard", text = L.NP_FADE_hard },
        })
        W.Tooltip(page.fade, function() return L.UI_NP_FADE, L.UI_NP_FADE_TIP end)
        page.duration = W.Slider(page.vis, L.UI_NP_FADE_DURATION, 0, NP.FADE_DURATION_MAX, 0.1, 340,
            function(v) return ("%g s"):format(v) end, function(v) apply(page, { fadeDuration = v }) end)
        page.duration:SetPoint("TOPLEFT", 394, -384)

        page.note = W.Text(page.vis, "GameFontHighlightSmall", C.muted)
        page.note:SetPoint("TOPLEFT", 4, -432)
        page.note:SetWidth(740) -- bis zu 4 Zeilen (2 Absaetze), endet spaetestens bei y=-482
        page.note:SetText(L.UI_NP_NOTE_V .. "\n" .. L.UI_NP_NOTE_INSTANCE)
        page.status = W.Text(page, "GameFontHighlightSmall", C.muted)
        page.status:SetPoint("TOPLEFT", 4, -486) -- eine Zeile, endet bei y=-498 (Seite: 504 px)
        page.status:SetWidth(740)
        ns.NameplateLook.Build(page, page.look)
        ns.NameplateFarView.Build(page, page.far)
        Tab.page = page
        Tab.SelectView(page, "vis")
    end,
    refresh = function(page)
        local cfg = NP.GetConfig()
        if page.view == "look" then ns.NameplateLook.Refresh(page, page.look) end
        if page.view == "far" then ns.NameplateFarView.Refresh(page, page.far) end
        page.enabled:SetValue(cfg.enabled)
        for key, g in pairs({ enemies = page.enemies, friends = page.friends }) do
            local group = cfg[key]
            g.base:SetValue(group.baseShow)
            g.base:SetActive(cfg.enabled)
            g.keep:SetValue(group.keepTarget)
            g.keep:SetActive(cfg.enabled and cfg.fade == "soft")
            local set = {}
            for _, c in ipairs(group.conditions) do set[c] = true end
            for name, cb in pairs(g.checks) do
                cb:SetValue(set[name])
                cb:SetActive(cfg.enabled and Config.StateReason(name) == nil)
            end
        end
        page.radiusOn:SetValue(cfg.radius.enabled)
        page.radiusOn:SetActive(cfg.enabled)
        page.radius:SetValue(cfg.radius.yards)
        page.radius:SetActive(cfg.enabled and cfg.radius.enabled)
        page.fade:SetValue(cfg.fade)
        page.duration:SetValue(cfg.fadeDuration)
        page.duration:SetActive(cfg.enabled and cfg.fade == "soft")
    end,
})
