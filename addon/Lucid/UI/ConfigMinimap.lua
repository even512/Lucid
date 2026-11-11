-- Reiter "Minimap" (Spec B6, Oberflaechen-Delta): zwei Ansichten.
--  Karte:    Form (rund | quadratisch | rechteckig), Seitenverhaeltnis (nur bei rechteckig), Rahmenstil (inkl. "ohne"),
--            Rahmenstaerke, Groesse, N-Markierung; Abschnitt Zonen-Ornament (Schalter, Groesse, Deckkraft, horizontal/vertikal verschieben, ueber Sonne und Mond legen; nur
--            Rechteck 4:3, Ornament.lua).
--  Elemente: (M6) je Element Sichtbarkeit Immer | Maus darueber | Aus (Standortname, Uhr, Kalender, Post, Tracking,
--            Schwierigkeit, Expansion-Knopf, Addon-Fach, Zoom-Knoepfe, Addon-Knoepfe), Lage von Standortname und Uhr
--            (Blizzard | oben | unten im Rahmen), Schriftgroesse, Bronze-Ton.
-- Alle Werte gehen ueber Minimap.Set (Validate, Profil, sofort anwenden); die Vorschau ist die echte Minimap. Im Kampf
-- wartet die Anwendung bis Kampfende (Hinweis in der Statuszeile). Der Reiter enthaelt keinen Fremdtext; Beschriftungen
-- kommen aus den Locales.
local _, ns = ...
local MM = ns.Minimap
local Config, W = ns.Config, ns.Widgets
local L = ns.L
local C = W.COLORS

local MinimapTab = { view = "map" }
Config.Minimap = MinimapTab

local function pct(v) return ("%g %%"):format(v) end
local function px(v) return ("%g"):format(v) end

local function setStatus(page, text, c)
    page.status:SetText(text or "")
    W.Color(page.status, c or C.muted)
end

--- Abschnitt "minimap" des aktiven Profils aendern (Minimap.Set prueft, speichert und wendet an)
local function update(page, changes)
    local ok, res = MM.Set(changes)
    if not ok then
        setStatus(page, L.MINIMAP_VALUE_INVALID, C.warn)
    elseif ok == "deferred" then
        setStatus(page, L.MINIMAP_DEFERRED, C.muted)
    else
        setStatus(page, "")
    end
    Config.Refresh()
    return ok, res
end

local function label(page, group, text, x, y)
    local fs = W.Text(page, "GameFontNormalSmall", C.muted)
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    group[#group + 1] = fs
    return fs
end

local function ratioKey(r) return (r:gsub(":", "_")) end

Config.RegisterPage("minimap", {
    label = "UI_TAB_MINIMAP",
    build = function(page)
        page.groups = { map = {}, elements = {} }
        local gm, ge = page.groups.map, page.groups.elements

        -- Ansichten
        page.views = {}
        for i, key in ipairs({ "map", "elements" }) do
            local b = W.FlatButton(page, 120, 24, "GameFontHighlight")
            b:SetPoint("TOPLEFT", (i - 1) * 126, -2)
            b.label:SetText(L[key == "map" and "UI_MINIMAP_VIEW_MAP" or "UI_MINIMAP_VIEW_ELEMENTS"])
            b:SetScript("OnClick", function()
                MinimapTab.view = key
                Config.Refresh()
            end)
            page.views[key] = b
        end

        -- Ansicht Karte, Zeile 1: Form und Seitenverhaeltnis
        page.shapeLabel = label(page, gm, L.UI_MINIMAP_SHAPE, 4, -40)
        page.shape = W.Dropdown(page, 220, function(v) update(page, { shape = v }) end)
        page.shape:SetPoint("TOPLEFT", 4, -56)
        local shapes = {}
        for _, key in ipairs(MM.SHAPES) do shapes[#shapes + 1] = { value = key, text = L["MINIMAP_SHAPE_" .. key] } end
        page.shape:SetOptions(shapes)
        W.Tooltip(page.shape, function() return L.UI_MINIMAP_SHAPE, L.UI_MINIMAP_SHAPE_TIP end)
        gm[#gm + 1] = page.shape

        page.ratioLabel = label(page, gm, L.UI_MINIMAP_RATIO, 300, -40)
        page.ratio = W.Dropdown(page, 220, function(v) update(page, { rectRatio = v }) end)
        page.ratio:SetPoint("TOPLEFT", 300, -56)
        local ratios = {}
        for _, key in ipairs(MM.RATIOS) do ratios[#ratios + 1] = { value = key, text = L["MINIMAP_RATIO_" .. ratioKey(key)] } end
        page.ratio:SetOptions(ratios)
        W.Tooltip(page.ratio, function() return L.UI_MINIMAP_RATIO, L.UI_MINIMAP_RATIO_TIP end)
        gm[#gm + 1] = page.ratio

        -- Zeile 2: Rahmenstil und Staerke
        page.borderLabel = label(page, gm, L.UI_MINIMAP_BORDER, 4, -106)
        page.border = W.Dropdown(page, 220, function(v) update(page, { border = v }) end)
        page.border:SetPoint("TOPLEFT", 4, -122)
        local borders = {}
        for _, key in ipairs(MM.BORDERS) do borders[#borders + 1] = { value = key, text = L["MINIMAP_BORDER_" .. key] } end
        page.border:SetOptions(borders)
        W.Tooltip(page.border, function() return L.UI_MINIMAP_BORDER, L.UI_MINIMAP_BORDER_TIP end)
        gm[#gm + 1] = page.border

        local rb = MM.LIMITS.borderSize
        page.borderSize = W.Slider(page, L.UI_MINIMAP_BORDER_SIZE, rb[1], rb[2], 5, 220, pct, function(v)
            update(page, { borderSize = v })
        end)
        page.borderSize:SetPoint("TOPLEFT", 300, -106)
        W.Tooltip(page.borderSize, function() return L.UI_MINIMAP_BORDER_SIZE, L.UI_MINIMAP_BORDER_SIZE_TIP end)
        gm[#gm + 1] = page.borderSize

        -- Zeile 3: Groesse und N-Markierung
        local rs = MM.LIMITS.scale
        page.scale = W.Slider(page, L.UI_MINIMAP_SCALE, rs[1], rs[2], 5, 220, pct, function(v)
            update(page, { scale = v })
        end)
        page.scale:SetPoint("TOPLEFT", 4, -182)
        W.Tooltip(page.scale, function() return L.UI_MINIMAP_SCALE, L.UI_MINIMAP_SCALE_TIP end)
        gm[#gm + 1] = page.scale

        page.north = W.Check(page, L.UI_MINIMAP_NORTH, function(on) update(page, { northMarker = on }) end)
        page.north:SetPoint("TOPLEFT", 300, -186)
        W.Tooltip(page.north, function() return L.UI_MINIMAP_NORTH, L.UI_MINIMAP_NORTH_TIP end)
        gm[#gm + 1] = page.north

        -- Zeile 4: Lucids eigener Minimap-Knopf (Button.lua)
        page.button = W.Check(page, L.UI_MINIMAP_BUTTON, function(on)
            MM.Set({ button = on }, true) -- eigener Knopf: Karte nicht neu anwenden, daher im Kampf keine Wartemeldung
            setStatus(page, "")
            Config.Refresh()
        end)
        page.button:SetPoint("TOPLEFT", 4, -226)
        W.Tooltip(page.button, function() return L.UI_MINIMAP_BUTTON, L.UI_MINIMAP_BUTTON_TIP end)
        gm[#gm + 1] = page.button

        page.note = W.Text(page, "GameFontHighlightSmall", C.muted)
        page.note:SetPoint("TOPLEFT", 4, -274)
        page.note:SetWidth(520)
        page.note:SetText(L.UI_MINIMAP_NOTE)
        gm[#gm + 1] = page.note

        -- Abschnitt Zonen-Ornament (Ornament.lua): Schalter und drei Regler, live; wirkt nur bei Rechteck 4:3
        page.ornLabel = label(page, gm, L.UI_MINIMAP_ORN, 4, -306)
        page.orn = W.Check(page, L.UI_MINIMAP_ORN_ON, function(on) update(page, { ornament = on }) end)
        page.orn:SetPoint("TOPLEFT", 4, -324)
        W.Tooltip(page.orn, function() return L.UI_MINIMAP_ORN_ON, L.UI_MINIMAP_ORN_ON_TIP end)
        gm[#gm + 1] = page.orn
        page.ornHint = W.Text(page, "GameFontHighlightSmall", C.muted)
        page.ornHint:SetPoint("TOPLEFT", 300, -328)
        page.ornHint:SetWidth(320)
        page.ornHint:SetText(L.UI_MINIMAP_ORN_HINT)
        gm[#gm + 1] = page.ornHint
        local function ornSlider(key, step, fmt, x, y)
            local lim = MM.LIMITS[key]
            local labelKey = ({ ornamentSize = "UI_MINIMAP_ORN_SIZE", ornamentOffsetX = "UI_MINIMAP_ORN_OFFX",
                ornamentOffsetY = "UI_MINIMAP_ORN_OFFY",
                ornamentAlpha = "UI_MINIMAP_ORN_ALPHA" })[key]
            local sl = W.Slider(page, L[labelKey], lim[1], lim[2], step, 220, fmt, function(v) update(page, { [key] = v }) end)
            sl:SetPoint("TOPLEFT", x, y)
            W.Tooltip(sl, function() return L[labelKey], L[labelKey .. "_TIP"] end)
            gm[#gm + 1] = sl
            return sl
        end
        page.ornSize = ornSlider("ornamentSize", 5, pct, 4, -360)
        page.ornAlpha = ornSlider("ornamentAlpha", 5, pct, 300, -360)
        page.ornOffX = ornSlider("ornamentOffsetX", 1, px, 4, -414)
        page.ornOffY = ornSlider("ornamentOffsetY", 1, px, 300, -414)
        page.ornTop = W.Check(page, L.UI_MINIMAP_ORN_TOP, function(on) update(page, { ornamentTop = on }) end)
        page.ornTop:SetPoint("TOPLEFT", 4, -458)
        W.Tooltip(page.ornTop, function() return L.UI_MINIMAP_ORN_TOP, L.UI_MINIMAP_ORN_TOP_TIP end)
        gm[#gm + 1] = page.ornTop

        -- Ansicht Elemente: Sichtbarkeit je Element (drei Spalten)
        local visOptions = {}
        for _, v in ipairs(MM.VIS) do visOptions[#visOptions + 1] = { value = v, text = L["MINIMAP_VIS_" .. v] } end
        page.el = {}
        for i, key in ipairs(MM.ELEMENT_KEYS) do
            local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
            local x, y = 4 + col * 250, -40 - row * 60 -- 11 Elemente in 4 Reihen
            label(page, ge, L["UI_MINIMAP_EL_" .. key], x, y)
            local dd = W.Dropdown(page, 200, function(v) update(page, { elements = { [key] = v } }) end)
            dd:SetPoint("TOPLEFT", x, y - 16)
            dd:SetOptions(visOptions)
            W.Tooltip(dd, function() return L["UI_MINIMAP_EL_" .. key], L["UI_MINIMAP_EL_" .. key .. "_TIP"] ~= "UI_MINIMAP_EL_" .. key .. "_TIP"
                and L["UI_MINIMAP_EL_" .. key .. "_TIP"] or L.UI_MINIMAP_EL_TIP end)
            ge[#ge + 1] = dd
            page.el[key] = dd
        end

        -- Lage von Standortname und Uhr, Schrift
        local posOptions = {}
        for _, v in ipairs(MM.POS) do posOptions[#posOptions + 1] = { value = v, text = L["MINIMAP_POS_" .. v] } end
        page.pos = {}
        local posLabels = { zone = "UI_MINIMAP_ZONEPOS", clock = "UI_MINIMAP_CLOCKPOS", coords = "UI_MINIMAP_COORDSPOS" }
        for i, key in ipairs(MM.TEXT_ELEMENTS) do
            local x, y = 4 + (i - 1) * 250, -290
            page["posLabel" .. key] = label(page, ge, L[posLabels[key]], x, y)
            local dd = W.Dropdown(page, 200, function(v) update(page, { elements = { [key .. "Pos"] = v } }) end)
            dd:SetPoint("TOPLEFT", x, y - 16)
            dd:SetOptions(posOptions)
            W.Tooltip(dd, function() return L[posLabels[key]], L.UI_MINIMAP_POS_TIP end)
            ge[#ge + 1] = dd
            page.pos[key] = dd
        end
        local rf = MM.LIMITS.fontSize
        page.fontSize = W.Slider(page, L.UI_MINIMAP_FONTSIZE, rf[1], rf[2], 1, 220, px, function(v)
            update(page, { elements = { fontSize = v } })
        end)
        page.fontSize:SetPoint("TOPLEFT", 4, -354)
        ge[#ge + 1] = page.fontSize
        page.bronze = W.Check(page, L.UI_MINIMAP_BRONZE, function(on) update(page, { elements = { bronze = on } }) end)
        page.bronze:SetPoint("TOPLEFT", 250, -358)
        W.Tooltip(page.bronze, function() return L.UI_MINIMAP_BRONZE, L.UI_MINIMAP_BRONZE_TIP end)
        ge[#ge + 1] = page.bronze

        page.elementsNote = W.Text(page, "GameFontHighlightSmall", C.muted)
        page.elementsNote:SetPoint("TOPLEFT", 4, -412)
        page.elementsNote:SetWidth(620)
        page.elementsNote:SetText(L.UI_MINIMAP_ELEMENTS_NOTE)
        ge[#ge + 1] = page.elementsNote

        page.status = W.Text(page, "GameFontHighlightSmall", C.muted)
        page.status:SetPoint("TOPLEFT", 4, -494)
        page.status:SetWidth(620)
        MinimapTab.page = page
    end,
    refresh = function(page)
        local cfg = MM.GetConfig()
        local eckig = cfg.shape ~= "round"
        local el = cfg.elements
        for key, b in pairs(page.views) do
            b:SetSelected(key == MinimapTab.view)
            W.Color(b.label, key == MinimapTab.view and C.accent or C.muted)
        end
        for key, group in pairs(page.groups) do
            for _, w in ipairs(group) do
                if key == MinimapTab.view then w:Show() else w:Hide() end
            end
        end
        page.shape:SetValue(cfg.shape)
        page.ratio:SetValue(cfg.rectRatio)
        page.ratio:SetActive(cfg.shape == "rect")
        W.Color(page.ratioLabel, cfg.shape == "rect" and C.muted or C.disabled)
        page.border:SetValue(cfg.border)
        page.borderSize:SetValue(cfg.borderSize)
        page.borderSize:SetActive(eckig and cfg.border ~= "none")
        page.scale:SetValue(cfg.scale)
        page.north:SetValue(cfg.northMarker)
        page.button:SetValue(cfg.button)
        local ornFits = cfg.shape == "rect" and cfg.rectRatio == "4:3"
        page.orn:SetValue(cfg.ornament)
        page.ornSize:SetValue(cfg.ornamentSize)
        page.ornOffX:SetValue(cfg.ornamentOffsetX)
        page.ornOffY:SetValue(cfg.ornamentOffsetY)
        page.ornAlpha:SetValue(cfg.ornamentAlpha)
        page.ornTop:SetValue(cfg.ornamentTop)
        page.ornTop:SetActive(cfg.ornament and ornFits)
        for _, sl in ipairs({ page.ornSize, page.ornOffX, page.ornOffY, page.ornAlpha }) do sl:SetActive(cfg.ornament and ornFits) end
        W.Color(page.ornHint, ornFits and C.muted or C.warn)
        for key, dd in pairs(page.el) do dd:SetValue(el[key]) end
        for key, dd in pairs(page.pos) do
            dd:SetValue(el[key .. "Pos"])
            dd:SetActive(eckig) -- Lage im Rahmen nur bei eckiger Form
            W.Color(page["posLabel" .. key], eckig and C.muted or C.disabled)
        end
        local own = eckig and (el.zonePos ~= "blizzard" or el.clockPos ~= "blizzard" or el.coordsPos ~= "blizzard")
        page.fontSize:SetValue(el.fontSize)
        page.fontSize:SetActive(own)
        page.bronze:SetValue(el.bronze)
        if MM.IsPending() then
            setStatus(page, L.MINIMAP_DEFERRED, C.muted)
        elseif page.status:GetText() == L.MINIMAP_DEFERRED then
            setStatus(page, "")
        end
    end,
})
