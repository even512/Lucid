-- Live-Vorschau des Plaketten-Stils (Reiter Plaketten, Abschnitt "Aussehen"): eine gerenderte Beispiel-Plakette im
-- Einstellungsfenster, die jede Aenderung am Profil (nameplates.style) sofort zeigt.
--
-- Die Vorschau fasst KEINE echte Plakette an und liest keine Einheiten-API: sie baut eine eigene Attrappe aus Lucid-Frames
-- (Container mit Lebensbalken) und fuettert sie mit Beispielwerten (Haltung, Rang, Quest, Leben, Zauber, Ziel, Kampf).
-- Aufbau, Layout und Animation kommen aus demselben Code wie bei den echten Plaketten (Style.BuildOverlay/AnchorOverlay/
-- ShowOverlay/StepOverlay, BuildNameText/LayoutNameText, BuildLevelPlate/PlaceLevelPlate, BuildRankDecor/PlaceMedal,
-- BuildSeal/PlaceSeal, BuildThread/AnchorThread/LayoutThread/PlaceCast, Style.Layout/SnapLayout/PixelUnit); hier stehen
-- nur die Beispielwerte und die Entscheidungen, die in der Engine vom Client abhaengen (Preview.Resolve).
--
-- Die Vorschau zeigt das Design: Sichtbarkeitsregeln wie "Balken nur bei Bedarf" gelten hier nicht, der Balken ist immer da;
-- nur "Friedlich" zeigt (bei Haltung Friedlich) wie im Spiel allein den Namen.
--
-- Animationen (Fluessigkeit, Schein, Glimmen, Funke, Zauberfaden) laufen ueber das OnUpdate der Vorschau selbst: sie ruhen
-- von allein, solange der Reiter (und damit die Vorschau) nicht sichtbar ist.
local _, ns = ...
local Style, NP, L = ns.NameplateStyle, ns.Nameplates, ns.L

local Preview = {}
ns.StylePreview = Preview

Preview.SCALE = 2.2        -- Darstellungsgroesse (die Plakette ist im Spiel winzig)
Preview.BAR_W = 112        -- Breite des Lebensbalkens in Einheiten der Buehne
Preview.PLAIN_HEIGHT = 10  -- Balkenhoehe ohne Bronze-Rahmen (Blizzard-aehnlich)
Preview.CAST_LOOP = 3      -- Sekunden je Zauberdurchlauf
Preview.LEVEL_TEXT = "42"
Preview.PLAIN_COLORS = { hostile = { 0.85, 0.12, 0.12 }, neutral = { 1.0, 0.85, 0.10 }, friendly = { 0.15, 0.75, 0.15 } }
-- Standard: Ziel an, Leben 50 % - so sind Glut-Schein, Fuellungskante und Rahmen sofort beurteilbar
Preview.DEFAULT_SAMPLE = { stance = "hostile", rank = "normal", quest = "none", health = "50", cast = "none",
    target = true, combat = false, mark = false }
-- Auswahl je Beispielwert (Reihenfolge = Anzeige)
Preview.OPTIONS = {
    stance = { "hostile", "neutral", "friendly", "peaceful" },
    rank = { "normal", "elite", "rare", "rareelite", "boss", "eliteboss" },
    quest = { "none", "mark", "loot", "slay", "interact" },
    health = { "100", "75", "50", "35", "25", "20", "15", "10", "5" }, -- Prozent Leben (Glimmen nur unter der Schwelle)
    cast = { "none", "cast", "nokick" },
}
-- Hintergruende (Klick auf die Vorschau wechselt): dunkle Spielwelt / heller Tag - Glanz und Schein sind auf beiden beurteilbar
Preview.BACKGROUNDS = {
    dark = { top = { 0.05, 0.06, 0.08, 1 }, bottom = { 0.17, 0.15, 0.12, 1 } },
    light = { top = { 0.50, 0.58, 0.66, 1 }, bottom = { 0.58, 0.52, 0.40, 1 } },
}

local function partOn(c, name)
    if not (type(c) == "table" and Style.IMPLEMENTED[name]) then return false end
    local p = c[name]
    return type(p) == "table" and p.enabled == true
end
Preview.PartOn = partOn

--- Entscheidungen der Vorschau aus Stil-Einstellungen c und Beispielwerten s (reine Logik, keine Frames).
function Preview.Resolve(c, s)
    local r = {}
    r.frame = partOn(c, "frame")
    r.height = r.frame and c.frame.height or Preview.PLAIN_HEIGHT
    r.stance = s.stance == "peaceful" and "friendly" or s.stance
    if not Style.COLORS[r.stance] then r.stance = "hostile" end
    r.peaceful = s.stance == "peaceful" and partOn(c, "peaceful")
    r.health = (tonumber(s.health) or 100) / 100
    r.target = s.target == true
    r.combat = s.combat == true
    r.glow = partOn(c, "targetGlow") and r.target
    -- Baustein 7: Glimmen unter der Schwelle (Profilwert lowHealth.threshold)
    r.ember = r.frame and partOn(c, "lowHealth") and r.health < Style.LowThreshold(c)
    -- Baustein 8: Stufe und Rang
    local rp = Style.RANK_PREVIEW[s.rank] or Style.RANK_PREVIEW.normal
    r.rank, r.boss = rp.rank, rp.boss == true
    r.level = partOn(c, "levelRank")
    r.levelText = nil
    if r.level then
        if r.boss then r.levelText = ""
        elseif c.levelRank.onlyDiff then r.levelText = nil -- Beispiel-Stufe weicht nicht ab: kein Plaettchen
        else r.levelText = Preview.LEVEL_TEXT end
    end
    -- Baustein 9: Quest-Symbol
    r.quest = (partOn(c, "questSeal") and s.quest ~= "none") and s.quest or nil
    -- Baustein 11: Zauberfaden
    r.mark = s.mark == true -- Zielmarkierung (Totenkopf) mittig ueber dem Namen
    r.cast = (partOn(c, "castThread") and s.cast ~= "none") and s.cast or nil
    r.nokick = s.cast == "nokick"
    -- Farben
    r.fillColor = Style.COLORS[r.stance]
    r.tint = Style.FLOW_TINT[r.stance]
    r.nameColor = Style.NameColor(r.stance, r.peaceful) or Style.FONT_COLOR
    r.nameAlpha = (r.peaceful and not r.target) and Style.PEACEFUL.alpha or 1
    r.font = partOn(c, "font")
    return r
end

-- Aufbau ----------------------------------------------------------------------------------------------------
local function buildPlate(stage)
    local R = CreateFrame("Frame", nil, stage)
    R:SetSize(Preview.BAR_W, Preview.PLAIN_HEIGHT)
    R:SetPoint("CENTER", stage, "CENTER", 0, 3)
    R.bars = CreateFrame("Frame", nil, R)
    R.bars:SetAllPoints(R)
    local pl = { R = R }
    -- Lebensbalken wie Blizzards (StatusBar mit Fuellungs-Textur); ohne Bronze-Rahmen sichtbar, sonst unsichtbarer Anker
    pl.plain = CreateFrame("Frame", nil, R)
    pl.plain:SetAllPoints(R)
    pl.plainBack = pl.plain:CreateTexture(nil, "BACKGROUND")
    pl.plainBack:SetAllPoints(pl.plain)
    pl.plainBack:SetColorTexture(0.05, 0.05, 0.05, 0.9)
    local hb = CreateFrame("StatusBar", nil, R)
    hb:SetAllPoints(R)
    pcall(hb.SetStatusBarTexture, hb, Style.FILL_TEX)
    pcall(hb.SetMinMaxValues, hb, 0, 1)
    pl.hb = hb
    pl.ov = Style.BuildOverlay(R.bars)
    pl.nameFrame = Style.BuildNameText(R)
    pl.level = Style.BuildLevelPlate(R.bars)
    pl.medal = Style.BuildRankDecor(R.bars)
    pl.seal = Style.BuildSeal(R)
    -- Zielmarkierung wie Blizzards RaidTargetFrame: eigener Frame mit der Symbol-Textur (Totenkopf), Lage aus Style.PlaceRaid
    local rf = CreateFrame("Frame", nil, R)
    rf.tex = rf:CreateTexture(nil, "OVERLAY")
    rf.tex:SetAllPoints(rf)
    rf.tex:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    if type(SetRaidTargetIconTexture) == "function" then pcall(SetRaidTargetIconTexture, rf.tex, 8)
    else rf.tex:SetTexCoord(0.75, 1, 0.25, 0.5) end -- Totenkopf
    pl.raid = rf
    -- Zauberleiste (Statusbar) samt Faden
    local cb = CreateFrame("StatusBar", nil, R)
    pcall(cb.SetStatusBarTexture, cb, Style.FILL_TEX)
    pcall(cb.SetMinMaxValues, cb, 0, 1)
    pl.cast = cb
    pl.thread = Style.BuildThread(cb)
    return pl
end

local function setLevels(pl, base)
    pl.R:SetFrameLevel(base)
    pl.ov.glow:SetFrameLevel(base)
    pl.plain:SetFrameLevel(base + 1)
    pl.ov.back:SetFrameLevel(base + 1)
    pl.hb:SetFrameLevel(base + 2)
    pl.ov.fill:SetFrameLevel(base + 3)
    pl.ov.fillIn:SetFrameLevel(base + 3)
    pl.ov:SetFrameLevel(base + 4)
    pl.ov.emberFrame:SetFrameLevel(base + 5)
    pl.medal:SetFrameLevel(base + 5)
    pl.level:SetFrameLevel(base + 6)
    pl.nameFrame:SetFrameLevel(base + 6)
    pl.seal:SetFrameLevel(base + 6)
    pl.raid:SetFrameLevel(base + 7)
    pl.cast:SetFrameLevel(base + 3)
end

--- Name: mit Baustein 3 wie die Engine, sonst Blizzard-aehnlich (weiss, mittig ueber dem Balken)
local function applyName(pl, r, c, Lo, unit)
    local nf, R = pl.nameFrame, pl.R
    local fs = nf.text
    local N = Style.NAME
    if r.font then
        local P = Style.PEACEFUL
        local size = r.peaceful and math.max(P.minSize, c.font.size + P.sizeDelta) or c.font.size
        Style.LayoutNameText(nf, R, c.font.face, size, r.height, unit, r.peaceful)
        fs:SetTextColor(r.nameColor[1], r.nameColor[2], r.nameColor[3])
        nf.veil:SetShown(c.font.veil == true)
        nf.veil:SetAlpha(r.peaceful and P.veilAlpha or N.veilAlpha)
    else
        nf:ClearAllPoints()
        nf:SetAllPoints(R)
        fs:ClearAllPoints()
        fs:SetPoint("BOTTOM", R, "TOP", 0, 3)
        fs:SetFont(_G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        fs:SetShadowColor(0, 0, 0, 0)
        fs:SetTextColor(1, 1, 1)
        nf.veil:Hide()
    end
    fs:SetText(L["UI_NPL_NAME_" .. (r.peaceful and "peaceful" or r.stance)] or "")
    nf:SetAlpha(r.font and r.nameAlpha or 1)
    nf:Show()
end

local function applyLevel(pl, r, c, Lo, unit)
    local p, d, R = pl.level, pl.medal, pl.R
    if not r.level then
        p:Hide()
        d:Hide()
        return
    end
    local even = unit and (2 * unit) or nil
    local w, h = Style.PxRound(Lo.levelW, even), Style.PxRound(Lo.levelH, even)
    Style.PlaceLevelPlate(p, R, Lo, unit, w, h, r.height, c.font.face)
    p.text:SetText(type(r.levelText) == "string" and not r.boss and r.levelText or "")
    p.skull:SetShown(r.boss)
    p:SetShown(r.boss or type(r.levelText) == "string")
    if r.rank then
        local rare = r.rank == "rare" or r.rank == "rareelite"
        Style.PlaceMedal(d, p, Lo, unit, even, w, h)
        d.elite:SetShown(not rare)
        d.rare:SetShown(rare)
        d:Show()
    else
        d:Hide()
    end
end

local function applySeal(pl, r, Lo, unit)
    local sf = pl.seal
    if not r.quest then
        sf:Hide()
        return
    end
    Style.PlaceSeal(sf, pl.R, Lo, unit, r.quest ~= "mark" and r.quest or nil)
    sf:Show()
end

local function applyRaid(pl, r, c, Lo, unit)
    local rf = pl.raid
    if not r.mark then
        rf:Hide()
        return
    end
    local P = Style.PEACEFUL
    local nameSize = Style.RAID.defaultNameSize
    if r.font then nameSize = r.peaceful and math.max(P.minSize, c.font.size + P.sizeDelta) or c.font.size end
    Style.PlaceRaid(rf, pl.R, Lo, unit, nameSize, r.height, r.peaceful)
    rf:Show()
end

local function applyCast(pl, r, c, unit)
    local cb, t = pl.cast, pl.thread
    if not r.cast then
        cb:Hide()
        return
    end
    local CL = Style.PlaceCast(cb, pl.R, r.height, unit)
    local okT, fill = pcall(cb.GetStatusBarTexture, cb)
    if okT and type(fill) == "table" then pcall(fill.SetAlpha, fill, 0) end
    Style.AnchorThread(t, cb, unit)
    Style.StyleThreadName(t, c)
    Style.SetCastInfo(t, L.NP_ST_CAST_DEFAULT, r.nokick)
    local lvl = cb:GetFrameLevel()
    t:SetFrameLevel(lvl + 1)
    Style.LayoutThread(t, cb, CL)
    cb:Show()
    t:Show()
end

--- Signatur der Stil-Einstellungen: aendert sie sich (egal ob Reiter, Slash oder Import), wird die Vorschau neu gezeichnet
local function signature(style)
    local out = { tostring(style.enabled) }
    local function add(v) out[#out + 1] = tostring(v) end
    for _, name in ipairs(NP.STYLE_PARTS) do
        local p = style[name]
        add(name)
        if type(p) == "table" then
            local keys = {}
            for k in pairs(p) do keys[#keys + 1] = k end
            table.sort(keys)
            for _, k in ipairs(keys) do add(k) add(p[k]) end
        end
    end
    return table.concat(out, "|")
end
Preview.Signature = signature

--- Vorschau neu zeichnen (aus dem Profil und den Beispielwerten)
local function update(pv)
    local c = NP.GetConfig().style
    pv.sig = signature(c)
    local r = Preview.Resolve(c, pv.sample)
    pv.resolved = r
    local pl = pv.plate
    local R, ov = pl.R, pl.ov
    R:SetSize(Preview.BAR_W, r.height)
    setLevels(pl, pv:GetFrameLevel() + 2)
    local unit = Style.PixelUnit(R)
    local Lo = Style.SnapLayout(Style.Layout(r.height), unit)
    pv.layout = Lo
    -- Lebensbalken (Blizzards eigener bleibt unsichtbar, sobald Lucids Rahmen die Fuellung zeigt)
    pcall(pl.hb.SetValue, pl.hb, r.health)
    local okT, ft = pcall(pl.hb.GetStatusBarTexture, pl.hb)
    local fill = (okT and type(ft) == "table") and ft or pl.hb
    if fill ~= pl.hb then pcall(fill.SetAlpha, fill, r.frame and 0 or 1) end
    local pc = Preview.PLAIN_COLORS[r.stance] or Preview.PLAIN_COLORS.hostile
    if partOn(c, "colors") then pc = Style.COLORS[r.stance] end
    pcall(pl.hb.SetStatusBarColor, pl.hb, pc[1], pc[2], pc[3])
    pl.plain:SetShown(not r.frame and not r.peaceful)
    pl.hb:SetShown(not r.peaceful)
    -- Rahmen/Roehre/Schein: dieselben Funktionen wie die echten Plaketten
    Style.AnchorOverlay(ov, R, fill, r.height, unit)
    local F = r.frame and c.frame or {}
    Style.ShowOverlay(ov, { frame = r.frame, glow = r.glow, flow = F.living == true, capsule = F.capsule == true,
        inset = F.inset == true, meniscus = F.meniscus == true, glass = F.glass == true, ember = r.ember })
    local col = r.fillColor
    ov.base:SetVertexColor(col[1], col[2], col[3])
    Style.SetFlowTint(ov, r.tint)
    -- Glimmen: in der Engine setzt die Kurve das Frame-Alpha (secret); die Vorschau kennt den Wert und setzt es selbst
    ov.emberFrame:SetAlpha(r.ember and 1 or 0)
    applyName(pl, r, c, Lo, unit)
    applyLevel(pl, r, c, Lo, unit)
    applySeal(pl, r, Lo, unit)
    applyRaid(pl, r, c, Lo, unit)
    applyCast(pl, r, c, unit)
    -- Friedlich: Balkengruppe ganz weg (nur der Name bleibt), wie im Spiel
    R.bars:SetShown(not r.peaceful)
    pv.castOn = r.cast ~= nil
end

-- Animation (der Schritt je Overlay ist Style.StepOverlay; laeuft nur, solange die Vorschau sichtbar ist) ----------
local function tick(pv, dt)
    local pl, r = pv.plate, pv.resolved
    if not (pl and r) then return end
    pv.acc = (pv.acc or 0) + dt
    if pv.acc < 0.033 then return end
    local step = pv.acc
    pv.acc = 0
    pv.time = (pv.time or 0) + step
    Style.StepOverlay(pl.ov, pv.time, true, true)
    if pv.castOn then
        pcall(pl.cast.SetValue, pl.cast, (pv.time % Preview.CAST_LOOP) / Preview.CAST_LOOP)
        Style.AnimateThread(pl.thread, step)
    end
    -- Aenderungen von aussen (Slash, Import, anderer Reiter) alle 0,25 s bemerken
    pv.watch = (pv.watch or 0) + step
    if pv.watch >= 0.25 then
        pv.watch = 0
        if signature(NP.GetConfig().style) ~= pv.sig then
            update(pv)
            if pv.onChange then pv.onChange() end -- z. B. Reiter: Haken und Knoepfe nachziehen
        end
    end
end

local function applyBackground(pv)
    local B = Preview.BACKGROUNDS[pv.background] or Preview.BACKGROUNDS.dark
    local ok = pcall(pv.bg.SetGradient, pv.bg, "VERTICAL", CreateColor(B.bottom[1], B.bottom[2], B.bottom[3], B.bottom[4]),
        CreateColor(B.top[1], B.top[2], B.top[3], B.top[4]))
    if not ok then pv.bg:SetColorTexture(B.top[1], B.top[2], B.top[3], B.top[4]) end
end

--- Vorschau-Rahmen bauen. parent: Elternteil, width/height: Groesse des Vorschaufelds in Pixeln.
function Preview.Build(parent, width, height)
    local pv = CreateFrame("Frame", nil, parent)
    pv:SetSize(width, height)
    pv.bg = pv:CreateTexture(nil, "BACKGROUND")
    pv.bg:SetAllPoints(pv)
    pv.bg:SetColorTexture(0.1, 0.1, 0.1, 1)
    pv.background = "dark"
    applyBackground(pv)
    local W = ns.Widgets
    if W and W.Border then W.Border(pv, { 0.62, 0.85, 1, 0.22 }) end
    pv.stage = CreateFrame("Frame", nil, pv)
    pv.stage:SetSize(width / Preview.SCALE, height / Preview.SCALE)
    pv.stage:SetScale(Preview.SCALE)
    pv.stage:SetPoint("CENTER", pv, "CENTER", 0, 0)
    pv.plate = buildPlate(pv.stage)
    pv.sample = {}
    for k, v in pairs(Preview.DEFAULT_SAMPLE) do pv.sample[k] = v end
    pv.time, pv.acc = 0, 0
    function pv:SetSample(key, value)
        if Preview.DEFAULT_SAMPLE[key] == nil then return false end
        self.sample[key] = value
        update(self)
        return true
    end
    function pv:GetSample() return self.sample end
    function pv:Update() update(self) end
    --- Hintergrund wechseln ("dark" | "light")
    function pv:SetBackground(mode)
        if not Preview.BACKGROUNDS[mode] then return false end
        self.background = mode
        applyBackground(self)
        return true
    end
    pv:EnableMouse(true)
    pv:SetScript("OnMouseUp", function(self) self:SetBackground(self.background == "dark" and "light" or "dark") end)
    pv:SetScript("OnUpdate", function(self, dt)
        local ok, err = pcall(tick, self, dt)
        if not ok then self.lastError = tostring(err) end
    end)
    update(pv)
    return pv
end
