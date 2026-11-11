-- Reiter Plaketten, Ansicht "Aussehen" (Spec Plaketten-Stil, Oberflaechen-Delta). Zwei klar getrennte Bereiche:
--   VORSCHAU (umrahmter Kasten oben): die Live-Vorschau (UI/StylePreview.lua) und rechts daneben die BEISPIELWERTE
--   (Haltung, Rang, Quest, Leben, Zauber, Ziel, Kampf). Beispielwerte aendern nichts im Spiel. Nur die Haken vor den an einen
--   Baustein gebundenen Beispielen (Rang/Quest/Leben/Zauber) sind echte Einstellungen (derselbe Profilwert wie in der
--   Bausteinliste, in der Farbe der Einstellungen umrandet); ist der Baustein aus, ist das Beispiel ausgegraut.
--   EINSTELLUNGEN (darunter, mit Trennlinie): drei Spalten: Stil (Schalter, Voreinstellungen, Balkenhoehe, Schrift), Bausteine
--   1-6 mit Unteroptionen, Bausteine 7-11 mit Unteroptionen, Glimm-Schwelle und Tiefe-Werten.
--
-- Alles geht ueber Nameplates.SetMany (Tab.Apply, geprueft wie beim Import) bzw. Style.Actions und wirkt sofort; die Vorschau
-- liest dasselbe Profil und fasst keine echten Plaketten an. Beschriftungen und Tooltips kommen aus den Locales.
local _, ns = ...
local NP, W, L = ns.Nameplates, ns.Widgets, ns.L
local C = W.COLORS

local Look = {}
ns.NameplateLook = Look

-- Lage (Pixel im Aussehen-Bereich, y nach unten negativ)
Look.BOX_H = 158                       -- Kasten "Vorschau"
Look.PREVIEW_W, Look.PREVIEW_H = 440, 128
Look.PREVIEW_X, Look.PREVIEW_Y = 6, -24 -- Vorschaufeld im Kasten
Look.SAMPLE_X, Look.SAMPLE_Y, Look.SAMPLE_ROW = 462, -24, 22
Look.HEAD_Y = -166                     -- Ueberschrift "Einstellungen"
Look.BAND_Y = -190                     -- Oberkante der drei Spalten
Look.COL = { a = 0, b = 252, c = 518 }
Look.COL_W = 236
Look.ROW_H = 16
Look.BLIZZ_BUTTON_W = 74
-- Beispielzustand -> Baustein, der ihn zeigt
Look.SAMPLE_PART = { rank = "levelRank", quest = "questSeal", health = "lowHealth", cast = "castThread" }

-- Bausteine 1-6 links, 7-11 rechts
Look.COLUMN_OF = { frame = "b", colors = "b", font = "b", barOnDemand = "b", peaceful = "b", targetGlow = "b",
    lowHealth = "c", levelRank = "c", questSeal = "c", depth = "c", castThread = "c" }
-- Bausteine, die Kurven (Leben secret) brauchen
local NEEDS_CURVE = { barOnDemand = true, lowHealth = true }

local function style() return NP.GetConfig().style end

--- Grund, warum ein Baustein im Client nicht wirkt (nil = verfuegbar)
function Look.Unavailable(part)
    if not ns.NameplateStyle.IMPLEMENTED[part] then return L.UI_NPL_NOT_IMPL end
    if NEEDS_CURVE[part] and not ns.NameplateStyle.CurveApi() then return L.UI_NPL_NO_CURVE end
    return nil
end

local function valueAt(st, path)
    local part, sub = path:match("^([^%.]+)%.?(.*)$")
    local p = type(st) == "table" and st[part]
    if type(p) ~= "table" then return false end
    if sub == "" then return p.enabled == true end
    return p[sub] == true
end
Look.ValueAt = valueAt

local function setPressed(b, on)
    b.active = on and true or false
    if on then pcall(b.LockHighlight, b) else pcall(b.UnlockHighlight, b) end
end

--- Reihenfolge der Zeilen: Baustein, danach seine Unteroptionen
local function rowsFor(part)
    local rows = { { path = part } }
    for _, sub in ipairs(NP.STYLE_PRESET_SUB_ORDER) do
        if sub:match("^([^%.]+)") == part then rows[#rows + 1] = { path = sub, sub = true } end
    end
    return rows
end

local function labelOf(path)
    return L["NP_PANEL_P_" .. path:gsub("%.", "_")] or path
end

--- Kasten "Vorschau": Ueberschrift, Untertitel, Vorschaufeld, Beispielwerte
local function buildPreviewBox(page, look)
    local Tab = ns.Config.Nameplates
    local box = CreateFrame("Frame", nil, look)
    box:SetPoint("TOPLEFT", 0, 0)
    box:SetSize(768, Look.BOX_H)
    W.Fill(box, C.panel)
    W.Border(box, { C.line[1], C.line[2], C.line[3], 0.5 })
    look.box = box
    local title = W.Text(box, "GameFontNormal", C.accent)
    title:SetPoint("TOPLEFT", 8, -5)
    title:SetText(L.UI_NPL_PREVIEW)
    local sub = W.Text(box, "GameFontHighlightSmall", C.muted)
    sub:SetPoint("LEFT", title, "RIGHT", 10, -1)
    sub:SetText(L.UI_NPL_PREVIEW_SUB)
    local sh = W.Text(box, "GameFontNormalSmall", C.muted)
    sh:SetPoint("TOPLEFT", Look.SAMPLE_X, -7)
    sh:SetText(L.UI_NPL_SAMPLE)

    look.preview = ns.StylePreview.Build(box, Look.PREVIEW_W, Look.PREVIEW_H)
    look.preview:SetPoint("TOPLEFT", Look.PREVIEW_X, Look.PREVIEW_Y)
    look.preview.onChange = function() ns.Config.Refresh() end -- Aenderung von aussen (Slash, Import): Anzeige nachziehen
    W.Tooltip(look.preview, function() return L.UI_NPL_PREVIEW, L.UI_NPL_PREVIEW_TIP end)

    look.samples, look.sampleChecks = {}, {}
    local sx, y = Look.SAMPLE_X, Look.SAMPLE_Y
    for _, key in ipairs({ "stance", "rank", "quest", "health", "cast" }) do
        local lab = W.Text(box, "GameFontNormalSmall", C.muted)
        lab:SetPoint("TOPLEFT", sx + 26, y - 5)
        lab:SetText(L["UI_NPL_S_" .. key])
        -- Beispiel an einen Baustein gebunden: ECHTE Einstellung als Haken davor (derselbe Profilwert wie in der Liste unten)
        local part = Look.SAMPLE_PART[key]
        if part then
            local cb = W.Check(box, "", function(on) Tab.Apply(page, { ["style." .. part .. ".enabled"] = on }) end)
            cb:SetPoint("TOPLEFT", sx, y)
            W.Border(cb, { C.accent[1], C.accent[2], C.accent[3], 0.9 }) -- Farbe der Einstellungen: wirkt wirklich
            W.Tooltip(cb, function()
                local reason = Look.Unavailable(part)
                local text = L.UI_NPL_SAMPLE_CHECK_TIP:format(labelOf(part))
                if reason then text = text .. "\n|cffff9966" .. reason .. "|r" end
                return L.UI_NPL_SAMPLE_CHECK_TITLE:format(labelOf(part)), text
            end)
            cb.part = part
            look.sampleChecks[key] = cb
        end
        local dd = W.Dropdown(box, 160, function(v) look.preview:SetSample(key, v) end)
        dd:SetPoint("TOPLEFT", sx + 80, y)
        if part and key ~= "health" then dd.samplePart = part end -- Leben bleibt immer waehlbar (Haken wirkt nur aufs Glimmen)
        W.Tooltip(dd, function()
            if dd.samplePart and dd.disabled then return L["UI_NPL_S_" .. key], L.UI_NPL_SAMPLE_OFF end
            if key == "quest" then return L.UI_NPL_S_quest, L.UI_NPL_QUEST_NOTE end
        end)
        local opts = {}
        for _, v in ipairs(ns.StylePreview.OPTIONS[key]) do opts[#opts + 1] = { value = v, text = L["UI_NPL_" .. key .. "_" .. v] } end
        dd:SetOptions(opts)
        dd:SetValue(look.preview:GetSample()[key])
        look.samples[key] = dd
        y = y - Look.SAMPLE_ROW
    end
    for i, key in ipairs({ "target", "combat", "mark" }) do
        local cb = W.Check(box, L["UI_NPL_S_" .. key], function(v) look.preview:SetSample(key, v) end)
        cb:SetPoint("TOPLEFT", sx + ({ 0, 70, 150 })[i], y - 1)
        cb:SetValue(look.preview:GetSample()[key])
        look.samples[key] = cb
    end
end

function Look.Build(page, look)
    local Tab = ns.Config.Nameplates
    local Style = ns.NameplateStyle
    look.checks, look.presetButtons = {}, {}

    buildPreviewBox(page, look)

    -- Einstellungen: Ueberschrift mit Trennlinie, rechts daneben der Hinweis zum Zustand -------------------------------
    local head = W.Header(look, L.UI_NPL_SETTINGS, 768)
    head:SetPoint("TOPLEFT", 0, Look.HEAD_Y)
    look.note = W.Text(look, "GameFontHighlightSmall", C.muted)
    look.note:SetPoint("LEFT", head, "LEFT", 120, 0)
    look.note:SetWidth(640)
    look.note:SetJustifyH("LEFT")

    -- Spalte A: Stil ----------------------------------------------------------------------------------------
    local ax, cw, by = Look.COL.a, Look.COL_W, Look.BAND_Y
    look.styleOn = W.Check(look, L.UI_NPL_STYLE_ON, function(v)
        Style.Actions.SetEnabled(v)
        ns.Config.Refresh()
    end)
    look.styleOn:SetPoint("TOPLEFT", ax, by)
    W.Tooltip(look.styleOn, function() return L.UI_NPL_STYLE_ON, L.UI_NPL_STYLE_ON_TIP end)
    local px = ax
    for _, id in ipairs(NP.STYLE_PRESET_ORDER) do
        local b = W.Button(look, L["UI_NP_STYLE_PRESET_" .. id], Look.BLIZZ_BUTTON_W, function()
            local ok, code = NP.ApplyStylePreset(id)
            Tab.SetStatus(page, ok and "" or L[code or "NP_VALUE_INVALID"], ok and nil or C.warn)
            ns.Config.Refresh()
        end)
        b:SetPoint("TOPLEFT", px, by - 28)
        W.Tooltip(b, function() return L["UI_NP_STYLE_PRESET_" .. id], L["UI_NPL_PRESET_TIP_" .. id] end)
        look.presetButtons[id] = b
        px = px + Look.BLIZZ_BUTTON_W + 4
    end
    look.presetNow = W.Text(look, "GameFontHighlightSmall", C.muted)
    look.presetNow:SetPoint("TOPLEFT", ax + 2, by - 54)
    look.height = W.Slider(look, L.UI_NPL_HEIGHT, NP.STYLE_HEIGHT_MIN, NP.STYLE_HEIGHT_MAX, 1, 112,
        function(v) return ("%g px"):format(v) end, function(v) Tab.Apply(page, { ["style.frame.height"] = v }) end)
    look.height:SetPoint("TOPLEFT", ax, by - 70)
    W.Tooltip(look.height.slider, function() return L.UI_NPL_HEIGHT, L.UI_NPL_HEIGHT_TIP end)
    look.fontSize = W.Slider(look, L.UI_NPL_FONTSIZE, NP.STYLE_FONT_SIZE_MIN, NP.STYLE_FONT_SIZE_MAX, 1, 112,
        function(v) return ("%g"):format(v) end, function(v) Tab.Apply(page, { ["style.font.size"] = v }) end)
    look.fontSize:SetPoint("TOPLEFT", ax + 122, by - 70)
    local fl = W.Text(look, "GameFontNormalSmall", C.muted)
    fl:SetPoint("TOPLEFT", ax, by - 112)
    fl:SetText(L.UI_NPL_FONT)
    look.face = W.Dropdown(look, cw - 40, function(v) Tab.Apply(page, { ["style.font.face"] = v }) end)
    look.face:SetPoint("TOPLEFT", ax, by - 126)
    local fonts = {}
    for _, f in ipairs(NP.STYLE_FONTS) do fonts[#fonts + 1] = { value = f, text = L["ZONE_FONT_" .. f] or f } end
    look.face:SetOptions(fonts)
    W.Tooltip(look.face, function() return L.UI_NPL_FONT, L.UI_NPL_FONT_TIP end)
    -- Groesse: alle Plaketten gleich gross (keine Entfernungs-Skalierung) und Zielgroesse; Tiefe hat Vorrang vor "gleich gross"
    look.uniform = W.Check(look, L.UI_NPL_UNIFORM, function(v) Tab.Apply(page, { ["style.uniformSize"] = v }) end)
    look.uniform:SetPoint("TOPLEFT", ax, by - 154)
    W.Tooltip(look.uniform, function()
        local text = L.UI_NPL_UNIFORM_TIP
        if valueAt(style(), "depth") then text = text .. "\n|cffff9966" .. L.UI_NPL_UNIFORM_DEPTH .. "|r" end
        return L.UI_NPL_UNIFORM, text
    end)
    look.targetScale = W.Slider(look, L.UI_NPL_TARGETSCALE, NP.STYLE_TARGET_MIN * 100, NP.STYLE_TARGET_MAX * 100, 5, cw - 4,
        function(v) return ("%d %%"):format(v) end, function(v) Tab.Apply(page, { ["style.targetScale"] = v / 100 }) end)
    look.targetScale:SetPoint("TOPLEFT", ax, by - 178)
    W.Tooltip(look.targetScale.slider, function() return L.UI_NPL_TARGETSCALE, L.UI_NPL_TARGETSCALE_TIP end)

    -- Spalten B und C: Bausteine und Unteroptionen ----------------------------------------------------------------
    local ys = { b = by, c = by }
    for _, part in ipairs(NP.STYLE_PARTS) do
        local col = Look.COLUMN_OF[part]
        for _, row in ipairs(rowsFor(part)) do
            local path = row.path
            local cb = W.Check(look, labelOf(path), function(on)
                Tab.Apply(page, { ["style." .. (row.sub and path or (path .. ".enabled"))] = on })
            end)
            cb:SetPoint("TOPLEFT", Look.COL[col] + (row.sub and 18 or 0), ys[col])
            cb.rowY = ys[col]
            ys[col] = ys[col] - Look.ROW_H
            local tipKey = "UI_NPL_T_" .. path:gsub("%.", "_")
            W.Tooltip(cb, function()
                local reason = Look.Unavailable(part)
                local text = L[tipKey] or ""
                if reason then text = text .. "\n|cffff9966" .. reason .. "|r" end
                return labelOf(path), text
            end)
            cb.part, cb.path, cb.isSub = part, path, row.sub == true
            look.checks[path] = cb
        end
    end
    -- Glimm-Schwelle (Execute-Bereich): kleiner Regler rechts neben dem Haken "Glimmen bei wenig Leben"
    look.lowThreshold = W.Slider(look, "", NP.STYLE_LOW_MIN * 100, NP.STYLE_LOW_MAX * 100, 1, 56,
        function(v) return ("%d %%"):format(v) end,
        function(v) Tab.Apply(page, { ["style.lowHealth.threshold"] = v / 100 }) end)
    look.lowThreshold:SetPoint("TOPLEFT", Look.COL.c + 180, look.checks.lowHealth.rowY + 6) -- hinter dem Label (~170 px), nicht darueber
    W.Tooltip(look.lowThreshold.slider, function() return L.UI_NPL_LOW, L.UI_NPL_LOW_TIP end)
    -- Tiefe-Werte (Baustein 10) unter den Haken der rechten Spalte
    local dx, dy = Look.COL.c, ys.c - 4
    look.depthHead = W.Text(look, "GameFontNormalSmall", C.muted)
    look.depthHead:SetPoint("TOPLEFT", dx, dy)
    look.depthHead:SetText(L.UI_NPL_DEPTH)
    dy = dy - 12
    local function pct(v) return ("%d %%"):format(math.floor(v * 100 + 0.5)) end
    local function meters(v) return ("%g m"):format(v) end
    look.depth = {}
    local defs = {
        { "minScale", L.UI_NPL_DEPTH_SCALE, 0.5, 1, 0.05, pct, 0, 0 },
        { "minAlpha", L.UI_NPL_DEPTH_ALPHA, 0.2, 1, 0.05, pct, 126, 0 },
        { "near", L.UI_NPL_DEPTH_NEAR, 0, 30, 1, meters, 0, -38 },
        { "far", L.UI_NPL_DEPTH_FAR, 15, 80, 5, meters, 126, -38 },
    }
    for _, d in ipairs(defs) do
        local key = d[1]
        local s = W.Slider(look, d[2], d[3], d[4], d[5], 112, d[6], function(v) Tab.Apply(page, { ["style.depth." .. key] = v }) end)
        s:SetPoint("TOPLEFT", dx + d[7], dy + d[8])
        W.Tooltip(s.slider, function()
            -- Quest-Fernsicht mit Radius: die Entfernungs-Alpha gehoert dem Radius (Vorrang), nur die Groesse bleibt bei der Tiefe
            if key ~= "minScale" and ns.NameplateStyle.RadiusAlphaDesired(NP.GetConfig()) then
                return d[2], L.UI_NPL_DEPTH_TIP .. "\n|cffff9966" .. L.UI_NPL_DEPTH_QF .. "|r"
            end
            return d[2], L.UI_NPL_DEPTH_TIP
        end)
        look.depth[key] = s
    end
end

function Look.Refresh(page, look)
    local Style = ns.NameplateStyle
    local st = style()
    look.styleOn:SetValue(st.enabled)
    local current = NP.StylePresetOf(st)
    for id, b in pairs(look.presetButtons) do setPressed(b, id == current) end
    look.presetNow:SetText(L.UI_NPL_PRESET_NOW:format(L["UI_NP_STYLE_PRESET_" .. current]))
    look.height:SetValue(st.frame.height)
    look.height:SetActive(st.frame.enabled)
    look.fontSize:SetValue(st.font.size)
    look.fontSize:SetActive(st.font.enabled)
    look.face:SetValue(st.font.face)
    look.face:SetActive(st.font.enabled)
    look.uniform:SetValue(st.uniformSize)
    look.uniform:SetActive(not valueAt(st, "depth")) -- Tiefe bestimmt die Groesse ferner Plaketten (Vorrang)
    look.targetScale:SetValue(math.floor(st.targetScale * 100 + 0.5))
    for path, cb in pairs(look.checks) do
        local reason = Look.Unavailable(cb.part)
        cb:SetValue(valueAt(st, path))
        local parentOn = not cb.isSub or valueAt(st, cb.part)
        cb:SetActive(reason == nil and parentOn)
    end
    -- Beispiele: der Haken davor ist dieselbe Einstellung wie in der Liste; ohne Baustein ist das Beispiel ausgegraut
    for key, cb in pairs(look.sampleChecks) do
        cb:SetValue(valueAt(st, cb.part))
        cb:SetActive(Look.Unavailable(cb.part) == nil)
        local dd = look.samples[key]
        if dd.samplePart then dd:SetActive(valueAt(st, cb.part)) end
    end
    look.lowThreshold:SetValue(math.floor(Style.LowThreshold(st) * 100 + 0.5))
    look.lowThreshold:SetActive(st.lowHealth.enabled and Look.Unavailable("lowHealth") == nil)
    local radiusAlpha = Style.RadiusAlphaDesired(NP.GetConfig()) ~= nil -- Fernsicht + Radius: Alpha-Haelfte der Tiefe ruht
    for key, s in pairs(look.depth) do
        s:SetValue(st.depth[key])
        s:SetActive(st.depth.enabled and Look.Unavailable("depth") == nil and (key == "minScale" or not radiusAlpha))
    end
    -- Hinweise: Fremd-Plaketten-Addon (Grund) bzw. Stil aus
    local blocker = Style.Conflict()
    if blocker then
        look.note:SetText(L.UI_NPL_BLOCKED:format(W.Plain(blocker)))
        W.Color(look.note, C.warn)
    elseif not st.enabled then
        look.note:SetText(L.UI_NPL_OFF_NOTE)
        W.Color(look.note, C.muted)
    else
        look.note:SetText(L.UI_NPL_ON_NOTE)
        W.Color(look.note, C.muted)
    end
    look.preview:Update()
end
