-- Reiter "Karte" (Spec B9, W4): Lucid-Kartenmodus fuer die Weltkarte. An/Aus, Kopfzeile, Raender, Questliste, Rahmenstil und
-- -staerke, Skala, Deckkraft, Lauf-Fade, Platzierung (auto | Lucid | extern, Hinweis zu Open Map) und Tastenuebernahme (M).
-- Alle Werte gehen ueber Map.Set (Validate, Profil, sofort anwenden); im Kampf wartet die Anwendung bis Kampfende.
local _, ns = ...
local Map = ns.Map
local Config, W = ns.Config, ns.Widgets
local L = ns.L
local C = W.COLORS

local Tab = {}
Config.Map = Tab

local function pct(v) return ("%g %%"):format(v) end

local function setStatus(page, text, c)
    page.status:SetText(text or "")
    W.Color(page.status, c or C.muted)
end

local function update(page, changes)
    local ok = Map.Set(changes)
    if not ok then
        setStatus(page, L.MAP_VALUE_INVALID:format("?"), C.warn)
    elseif ok == "deferred" then
        setStatus(page, L.MAP_DEFERRED, C.muted)
    else
        setStatus(page, "")
    end
    Config.Refresh()
    return ok
end

local function label(page, text, x, y)
    local fs = W.Text(page, "GameFontNormalSmall", C.muted)
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function check(page, key, text, tip, x, y)
    local cb = W.Check(page, text, function(v) update(page, { [key] = v }) end)
    cb:SetPoint("TOPLEFT", x, y)
    if tip then W.Tooltip(cb, function() return text, tip end) end
    page[key] = cb
    return cb
end

local function slider(page, key, text, tip, x, y, lo, hi, step)
    local s = W.Slider(page, text, lo, hi, step, 340, pct, function(v) update(page, { [key] = v }) end)
    s:SetPoint("TOPLEFT", x, y)
    if tip then W.Tooltip(s, function() return text, tip end) end
    page[key] = s
    return s
end

Config.RegisterPage("map", {
    label = "UI_TAB_MAP",
    build = function(page)
        check(page, "enabled", L.UI_MAP_ENABLE, L.UI_MAP_ENABLE_TIP, 0, -4)

        local h1 = W.Header(page, L.UI_MAP_LAYOUT, 740)
        h1:SetPoint("TOPLEFT", 0, -34)
        check(page, "hideHeader", L.UI_MAP_HEADER, L.UI_MAP_HEADER_TIP, 0, -58)
        check(page, "hideEdges", L.UI_MAP_EDGES, L.UI_MAP_EDGES_TIP, 390, -58)

        label(page, L.UI_MAP_QUESTLOG, 4, -90)
        page.questLog = W.Dropdown(page, 220, function(v) update(page, { questLog = v }) end)
        page.questLog:SetPoint("TOPLEFT", 4, -106)
        local ql = {}
        for _, k in ipairs(Map.QUESTLOG) do ql[#ql + 1] = { value = k, text = L["MAP_QUESTLOG_" .. k] } end
        page.questLog:SetOptions(ql)
        W.Tooltip(page.questLog, function() return L.UI_MAP_QUESTLOG, L.UI_MAP_QUESTLOG_TIP end)

        label(page, L.UI_MINIMAP_BORDER, 394, -90)
        page.border = W.Dropdown(page, 220, function(v) update(page, { border = v }) end)
        page.border:SetPoint("TOPLEFT", 394, -106)
        local bs = {}
        for _, k in ipairs(Map.BORDERS) do bs[#bs + 1] = { value = k, text = L["MINIMAP_BORDER_" .. k] } end
        page.border:SetOptions(bs)
        W.Tooltip(page.border, function() return L.UI_MINIMAP_BORDER, L.UI_MAP_BORDER_TIP end)

        local rb, rs, ra = Map.LIMITS.borderSize, Map.LIMITS.scale, Map.LIMITS.alpha
        slider(page, "borderSize", L.UI_MINIMAP_BORDER_SIZE, L.UI_MINIMAP_BORDER_SIZE_TIP, 4, -146, rb[1], rb[2], 5)
        slider(page, "scale", L.UI_MINIMAP_SCALE, L.UI_MAP_SCALE_TIP, 394, -146, rs[1], rs[2], 5)
        slider(page, "alpha", L.UI_MAP_ALPHA, L.UI_MAP_ALPHA_TIP, 4, -196, ra[1], ra[2], 5)

        local h2 = W.Header(page, L.UI_MAP_FADE_HEAD, 740)
        h2:SetPoint("TOPLEFT", 0, -246)
        check(page, "runFade", L.UI_MAP_RUNFADE, L.UI_MAP_RUNFADE_TIP, 0, -270)
        local rr = Map.LIMITS.runAlpha
        slider(page, "runAlpha", L.UI_MAP_RUNALPHA, L.UI_MAP_RUNALPHA_TIP, 394, -266, rr[1], rr[2], 5)

        local h3 = W.Header(page, L.UI_MAP_PLACE_HEAD, 740)
        h3:SetPoint("TOPLEFT", 0, -316)
        label(page, L.UI_MAP_PLACEMENT, 4, -344)
        page.placement = W.Dropdown(page, 300, function(v) update(page, { placement = v }) end)
        page.placement:SetPoint("TOPLEFT", 4, -360)
        local pl = {}
        for _, k in ipairs(Map.PLACEMENTS) do pl[#pl + 1] = { value = k, text = L["MAP_PLACEMENT_" .. k] } end
        page.placement:SetOptions(pl)
        W.Tooltip(page.placement, function() return L.UI_MAP_PLACEMENT, L.UI_MAP_PLACEMENT_TIP end)
        page.resetPos = W.Button(page, L.UI_MAP_RESET_POS, 200, function() update(page, { pos = false }) end)
        page.resetPos:SetPoint("TOPLEFT", 394, -357)
        page.openMap = W.Text(page, "GameFontHighlightSmall", C.muted)
        page.openMap:SetPoint("TOPLEFT", 4, -392)
        page.openMap:SetWidth(740)

        check(page, "takeKey", L.UI_MAP_TAKEKEY, L.UI_MAP_TAKEKEY_TIP, 0, -430)
        page.note = W.Text(page, "GameFontHighlightSmall", C.muted)
        page.note:SetPoint("TOPLEFT", 4, -456)
        page.note:SetWidth(740)
        page.note:SetText(L.UI_MAP_NOTE)
        page.status = W.Text(page, "GameFontHighlightSmall", C.muted)
        page.status:SetPoint("TOPLEFT", 4, -486)
        page.status:SetWidth(740)
        Tab.page = page
    end,
    refresh = function(page)
        local cfg = Map.GetConfig()
        local on = cfg.enabled
        page.enabled:SetValue(on)
        for _, k in ipairs({ "hideHeader", "hideEdges", "runFade", "takeKey" }) do
            page[k]:SetValue(cfg[k])
            page[k]:SetActive(on)
        end
        page.questLog:SetValue(cfg.questLog)
        page.border:SetValue(cfg.border)
        page.placement:SetValue(cfg.placement)
        for _, k in ipairs({ "borderSize", "scale", "alpha" }) do
            page[k]:SetValue(cfg[k])
            page[k]:SetActive(on)
        end
        page.borderSize:SetActive(on and cfg.border ~= "none")
        page.runAlpha:SetValue(cfg.runAlpha)
        page.runAlpha:SetActive(on and cfg.runFade)
        page.resetPos:SetEnabled(on and cfg.pos ~= false)
        if Map.OpenMapLoaded() then
            page.openMap:SetText(Map.ExternalPlacement(cfg) and L.UI_MAP_OPENMAP_EXTERNAL or L.UI_MAP_OPENMAP_LUCID)
        else
            page.openMap:SetText("")
        end
    end,
})
