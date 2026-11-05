-- Gemeinsamer Rahmen-Zeichner (B9/W1, aus modules/Minimap/Frame.lua herausgeloest): zeichnet den Bronze-Rahmen nach dem
-- Neun-Teile-Prinzip (vier Ecken in fester Groesse, vier gedehnte Kantenstreifen, optional Mittelschmuck) um ein beliebiges
-- sichtbares Rechteck eines Anker-Frames. Daten (Stile, Stufen) kommen aus modules/Minimap/Frames.lua.
-- Aufbau: FrameBorder.New(host) legt die Texturen als Kinder von host an; host liegt (wie bei der Minimap) auf der Ebene des
-- Ankers und hebt dessen Skala auf (SetScale(1 / u)), so ist die Staerke unabhaengig von der Kartengroesse.
-- Layout(anchor, params): style, borderSize (%), u (Skala des Ankers), W/H (sichtbares Rechteck in Host-Einheiten), l/t/r/b
-- (Einzug des sichtbaren Rechtecks im Anker, in Anker-Einheiten). Nur eigene Frames/Texturen werden beschrieben.
local ADDON_NAME, ns = ...
local Compat = ns.Compat

local FB = {}
ns.FrameBorder = FB

local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"
local OVERLAP = 0.12 -- Anteil der Bandstaerke, der nach innen ueber die Kartenkante ragt
local CORNER_NAMES = { TL = "TOPLEFT", TR = "TOPRIGHT", BL = "BOTTOMLEFT", BR = "BOTTOMRIGHT" }
local MIDS = { "top", "bottom", "left", "right" }
FB.MIDS = MIDS

--- Physische Pixel je UI-Einheit (wie Card.PixelsPerUnit): Bildschirmhoehe / 768
function FB.PixelsPerUnit()
    if type(GetPhysicalScreenSize) == "function" then
        local ok, _, h = pcall(GetPhysicalScreenSize)
        h = ok and Compat.Num(h) or nil
        if h and h > 0 then return h / 768 end
    end
    return 1
end

local function frames() return ns.MinimapFrames or { order = {}, styles = {} } end

--- Rahmen-Zeichner fuer host anlegen. Liefert Objekt mit .pieces, .mids (Texturen) und :Layout / :HideAll
function FB.New(host)
    local self = { host = host, pieces = {}, mids = {} }
    for _, key in ipairs({ "top", "bottom", "left", "right", "TL", "TR", "BL", "BR" }) do
        self.pieces[key] = host:CreateTexture(nil, "ARTWORK", nil, CORNER_NAMES[key] and 2 or 1)
    end
    for _, key in ipairs(MIDS) do self.mids[key] = host:CreateTexture(nil, "ARTWORK", nil, 3) end
    return setmetatable(self, { __index = FB })
end

--- Texturkoordinaten (Atlas w x h, Rechteck r) mit halbem Texel Einzug gegen Randsickern; transposed = Kantenstreifen links/rechts
local function setCoords(tex, atlas, r, transposed)
    local x0, x1 = (r.x + 0.5) / atlas.w, (r.x + r.w - 0.5) / atlas.w
    local y0, y1 = (r.y + 0.5) / atlas.h, (r.y + r.h - 0.5) / atlas.h
    if transposed then
        tex:SetTexCoord(x0, y0, x1, y0, x0, y1, x1, y1) -- UL, LL, UR, LR: Streifen ist transponiert abgelegt
    else
        tex:SetTexCoord(x0, x1, y0, y1)
    end
end

--- gewaehlte Stufe: kleinste mit c >= benoetigte Eckgroesse in Pixeln, sonst die groesste
local function pickLevel(style, needPx)
    local best
    for _, lv in ipairs(style.levels) do
        best = lv
        if lv.c >= needPx then break end
    end
    return best
end

function FB:HideAll()
    for _, tex in pairs(self.pieces) do tex:Hide() end
    for _, tex in pairs(self.mids) do tex:Hide() end
end

--- Rahmen um das sichtbare Rechteck von anchor legen. Liefert Zustandstabelle { mids, style, level, k, cornerPx } oder nil,
--- wenn der Stil unbekannt ist.
function FB:Layout(anchor, p)
    local m, frame, pieces, mids = anchor, self.host, self.pieces, self.mids
    local u, W, H, l, t, r, b = p.u, p.W, p.H, p.l, p.t, p.r, p.b
    local style = frames().styles[p.style]
    if not style then return nil end
    local k = style.units / style.cs * p.borderSize / 100
    k = math.min(k, 0.45 * math.min(W, H) / style.cs) -- die Ecken duerfen sich nicht ueberlappen
    local lv = pickLevel(style, style.cs * k * FB.PixelsPerUnit() * frame:GetEffectiveScale())
    local tHk, tVk, cs = style.tH * k, style.tV * k, style.cs * k
    local xL, xR = u * l - (tVk - OVERLAP * tVk), -(u * r) + (tVk - OVERLAP * tVk)
    local yT, yB = -(u * t) + (tHk - OVERLAP * tHk), u * b - (tHk - OVERLAP * tHk)
    local ca, sa = lv.corners, lv.strips
    local path = MEDIA .. ca.file
    -- Ecken: Ueberstand (bx, by) ragt ueber das Band hinaus
    local corners = {
        TL = { "TOPLEFT", xL - ca.TL.bx * k, yT + ca.TL.by * k },
        TR = { "TOPRIGHT", xR + ca.TR.bx * k, yT + ca.TR.by * k },
        BL = { "BOTTOMLEFT", xL - ca.BL.bx * k, yB - ca.BL.by * k },
        BR = { "BOTTOMRIGHT", xR + ca.BR.bx * k, yB - ca.BR.by * k },
    }
    for key, pos in pairs(corners) do
        local tex, d = pieces[key], ca[key]
        tex:SetTexture(path)
        setCoords(tex, ca, d.r)
        tex:ClearAllPoints()
        tex:SetPoint(pos[1], m, pos[1], pos[2], pos[3])
        tex:SetSize(d.sw * k, d.sh * k)
        tex:Show()
    end
    -- Kantenstreifen zwischen den Ecken, an den Ecken des Ankers verankert
    local spath = MEDIA .. sa.file
    local function strip(key, tl, brRel, x1, y1, x2, y2, transposed)
        local tex = pieces[key]
        tex:SetTexture(spath)
        setCoords(tex, sa, sa[key], transposed)
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", m, tl, x1, y1)
        tex:SetPoint("BOTTOMRIGHT", m, brRel, x2, y2)
        tex:Show()
    end
    strip("top", "TOPLEFT", "TOPRIGHT", xL + cs, yT, xR - cs, yT - tHk)
    strip("bottom", "BOTTOMLEFT", "BOTTOMRIGHT", xL + cs, yB + tHk, xR - cs, yB)
    strip("left", "TOPLEFT", "BOTTOMLEFT", xL, yT - cs, xL + tVk, yB + cs, true)
    strip("right", "TOPRIGHT", "BOTTOMRIGHT", xR - tVk, yT - cs, xR, yB + cs, true)
    -- Mittelschmuck (Pfeil, Raute ...): mittig an jeder Kante des sichtbaren Rechtecks, ragt nach aussen ueber das Band
    local ma = lv.mids
    local cxo, cyo = u * (l - r) / 2, u * (b - t) / 2 -- Mitte des sichtbaren Rechtecks relativ zur Mitte des Ankers
    local midAt = ma and {
        top = { "TOP", cxo, yT + ma.top.out * k },
        bottom = { "BOTTOM", cxo, yB - ma.bottom.out * k },
        left = { "LEFT", xL - ma.left.out * k, cyo },
        right = { "RIGHT", xR + ma.right.out * k, cyo },
    }
    for _, key in ipairs(MIDS) do
        local tex = mids[key]
        if ma then
            local d, pt = ma[key], midAt[key]
            tex:SetTexture(MEDIA .. ma.file)
            setCoords(tex, ma, d.r)
            tex:ClearAllPoints()
            tex:SetPoint(pt[1], m, pt[1], pt[2], pt[3])
            tex:SetSize(d.sw * k, d.sh * k)
            tex:Show()
        else
            tex:Hide()
        end
    end
    return { mids = ma ~= nil, style = p.style, level = lv.c, k = k, cornerPx = cs * frame:GetEffectiveScale() * FB.PixelsPerUnit() }
end
