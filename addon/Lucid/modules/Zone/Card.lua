-- Card: Lucids Zonentext-Karte (B5 Z3), "Kino-Intro". Zeichnet die Karten, die Zone.lua bildet
-- (Zone.Present / Zone.Stop), und spielt Testkarten (/lucid zone test, spaeter Reiter "Testen").
--
-- Darstellung: Zeile 1 gross und zentriert (Elfenbein, OUTLINE, Schatten), bei der grossen Karte feine Linien links
-- und rechts (1 px, 16 px Abstand, 0,35 x Textbreite, 60-220 px, nach aussen auslaufend, kleine Raute am inneren
-- Ende); Zeile 2 (Subzone) 6 px darunter mit ~85 % Alpha; Untertitel "Entdeckt" 8 px unter der letzten Zeile in
-- gedaempftem Gold.
-- Grosse Karte zusaetzlich (Nachtraege 03.11., "cineastischer"): transparentes dunkles Lichtband hinter dem Text
-- (zwei Lagen aus einer weichen Verlaufs-Textur, Media/zone-band.tga), ein warmer Glanz hinter dem Titel
-- (Media/zone-glow.tga, radial), der einmal beim Einblenden aufleuchtet und abklingt, und ein Zoom 1,08 -> 1,0 der
-- Dekoration (Band, Glanz, Linien, Rauten) synchron zum Einblenden. Die Schrift bewegt sich nie, sie blendet nur.
-- Animation ("absolut fluessig"): native Animation-API (AnimationGroup mit Alpha/Scale), die Engine interpoliert jeden
-- Frame ohne Re-Layout; Pixel-Snapping ist an allen Regionen aus. Aufbau: Rahmen-Frame (Position, Ausblenden/Abloesen)
-- -> Inhalts-Frame (Einblenden) -> Deko-Frame (Zoom, darunter) und Text-Frame (darueber). Die Linien wachsen per
-- Scale-Animation vom Text nach aussen. Halten, Ausblenden Alpha easeIn; eine ersetzte Karte blendet in 0,3 s aus.
-- Client ohne Animation-API: Rueckfall auf reines Alpha per OnUpdate (ohne Zoom/Glanz, Linien voll).
-- Sicherheit: Texte nur per FontString:SetText (Zeilen kommen bereits durch Zone.Clean); eigene, ungeschuetzte Frames
-- ohne Maus; Schrift- und Texturpfade stehen fest im Code, nie aus Profil oder Import.
local ADDON_NAME, ns = ...
local Zone, Compat = ns.Zone, ns.Compat
local L = ns.L

local Card = {}
ns.ZoneCard = Card

Card.FRAME_NAME = "LucidZoneCard"
Card.STRATA = "HIGH"
Card.RETIRE = 0.3            -- s, Ausblenden einer ersetzten Karte
Card.SUB_FADE = 0.5          -- s, Einblenden eines nachgereichten Untertitels
Card.PRESET = 0.001          -- s, Rampe ohne Aenderung vor dem Halten (Alpha bleibt 1)
Card.ORN_GAP = 16            -- px Abstand Linie <-> Text
Card.ORN_FACTOR = 0.35       -- Linienlaenge = Faktor x Textbreite ...
Card.ORN_MIN, Card.ORN_MAX = 60, 220 -- ... begrenzt auf diese Laenge
Card.ORN_FROM = 0.01         -- Startbreite der wachsenden Linie (Anteil; nicht 0, Skalierung 0 meiden)
Card.DIAMOND = 5             -- px, Raute am inneren Linienende (aus drei Rechtecken, keine Drehung noetig)
Card.LINE2_GAP, Card.SUB_GAP = 6, 8
Card.SCREEN_FILL = 0.96      -- Anteil der Bildschirmbreite, den eine Karte mit Seiten-Ornamenten (pair) hoechstens fuellt
Card.SIDE_MIN_SHRINK = 0.2   -- so weit duerfen die Seiten (pair) beim Verkleinern hoechstens schrumpfen
Card.LINE2_ALPHA = 0.85
Card.ZOOM = 1.08             -- Startskalierung der Dekoration der grossen Karte (-> 1,0 synchron zum Einblenden)
local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"
Card.BAND_TEX = MEDIA .. "zone-band"
Card.GLOW_TEX = MEDIA .. "zone-glow"
Card.SWIRL_TEX = MEDIA .. "zone-swirl"
Card.FILIGREE_TEX = MEDIA .. "zone-filigree"
-- Toenung der Verzierungs-Texturen (die Schattierung - heller Grat, dunklere Unterkante - ist eingebacken)
Card.ORN_TINT = { 1, 0.86, 0.55 }
-- Verzierung der grossen Karte (Profil zone.ornament, Groesse zone.ornScale 50-200 %, 100 % = Werte hier):
--   simple   = Linien mit Rauten (Laenge 0,35 x Textbreite)
--   swirl    = je Seite eine Ranke aus SWIRL_TEX (rechte Seite; links dieselbe Textur per SetTexCoord gespiegelt).
--              Austauschbar: Pfad SWIRL_TEX + Seitenverhaeltnis aspect (Breite/Hoehe der Textur) + midY (Hoehe der
--              Strichmitte am inneren Ende, Anteil von oben); Vorlage -> TGA: node scripts/gen-zone-media.mjs --from.
--              Breite factor x Linienlaenge (begrenzt). Einblenden in draw s + leichtes Wachsen grow -> 1 (Ursprung
--              am Titel-Ende). (Das Aufzeichnen per Maske ist entfernt: im Client erschien nur eine Seite.)
--   filigree = Doppellinie mit Zier-Element unter dem Titelblock, kleiner gespiegelt darueber; blendet in draw s ein
--              und waechst dabei leicht aus der Mitte (grow -> 1)
--   weitere = Vorlagen-Stile aus Ornaments.lua (erzeugt: node scripts/gen-zone-media.mjs --templates aus
--              docs/ornament-src/recipes.json; neuer Stil = Vorlage + Rezept-Eintrag, dann das Kommando)
--   none     = keine Verzierung (Band und Glanz bleiben)
--   Zonen-Motive = Vorlagen-Stile mit "auto": true im Rezept; bei zone.autoOrnament waehlt die Karte das Motiv ihrer
--              Zone (ZoneMotifs.lua, uiMapID aus card.mapID), sonst gilt zone.ornament (Card.ResolveOrnament)
-- Einsatz: zone.ornDelay s nach Kartenstart (0 = zusammen mit dem Titel), Einblenden zone.ornFade s (Alpha easeOut,
-- Wachsen grow -> 1 ueber 1,3 x ornFade); gilt fuer alle Textur-Stile, die schlichten Linien wachsen mit der Karte.
-- Stil-Tabelle: kind "sides" (links/rechts vom Titel; Breite factor x Linienlaenge in [min, max], midY = Hoehe der
-- Strichmitte am inneren Ende), "pair" (wie "sides", aber zwei eigenstaendige Seiten left/right mit je eigenem
-- aspect/midY/srcW/levels; gleicher Massstab, die breitere Seite bekommt factor x Linienlaenge), "frame" (Rahmen um die Titelzeilen; innerW/innerH = gemessene Innenflaeche als
-- Anteil, marginX/marginY Rand um den Text, mindestens min breit) oder "bar" (Leiste unter dem Titelblock, Breite
-- Textbreite + extra in [min, max];
-- top = Groesse einer zweiten Leiste ueber dem Titel, flipBottom/flipTop spiegeln senkrecht; fill = Anteil der
-- Texturhoehe mit Inhalt, der Rest ist Rand bis zur Zweierpotenz). aspect = Breite/Hoehe der Textur.
-- Eine eingebaute Textur tauschen: Pfad + aspect/midY/fill aus der Ausgabe von gen-zone-media.mjs --from eintragen.
Card.STYLES = {
    swirl = { kind = "sides", tex = Card.SWIRL_TEX, factor = 1.8, min = 160, max = 380, aspect = 8, midY = 64 / 128,
        gap = 8, alpha = 0.95, grow = 0.94, draw = 1.1 },
    filigree = { kind = "bar", tex = Card.FILIGREE_TEX, extra = 180, min = 240, max = 600, aspect = 512 / 48, fill = 1,
        gap = 4, top = 0.7, flipTop = true, alpha = 0.9, grow = 0.94, draw = 0.9 },
}
-- eingebaute Stile: Stufen/Kacheln aus Ornaments.lua (O.builtin, erzeugt wie die Vorlagen)
for name, levels in pairs((ns.ZoneOrnaments or {}).builtin or {}) do
    if Card.STYLES[name] then Card.STYLES[name].levels = levels end
end
-- Vorlagen-Stile (Ornaments.lua): Textur aus Media, Werte unveraendert uebernommen
for name, S in pairs((ns.ZoneOrnaments or {}).styles or {}) do
    local copy = {}
    for k, v in pairs(S) do copy[k] = v end
    Card.STYLES[name] = copy
end
Card.SWIRL, Card.FILIGREE = Card.STYLES.swirl, Card.STYLES.filigree

-- Zonen-Motive (Spec lucid-change-zonen-ornamente): Vorlagen-Stile mit "auto": true im Rezept (O.motif[name]).
-- Sie sind zusaetzlich als fester Stil waehlbar; bei zone.autoOrnament waehlt die Karte das Motiv der Zone
-- (ZoneMotifs.byMap[uiMapID]).
function Card.IsMotif(name)
    local m = (ns.ZoneOrnaments or {}).motif
    return type(m) == "table" and m[name] == true
end

--- Motiv der Zonenkarte mapID (Name) oder nil: Tabelle ZoneMotifs.byMap, unabhaengig davon, ob es geladen ist
function Card.MotifFor(mapID)
    local byMap = (ns.ZoneMotifs or {}).byMap
    if type(byMap) ~= "table" or type(mapID) ~= "number" or mapID ~= mapID then return nil end
    return byMap[mapID]
end

--- Welcher Verzierungs-Stil gilt fuer die Karte (rein, ohne Frames)? Liefert Stil, Herkunft:
---   "none" im Profil          => "none", "fixed" (ausdruecklich abgeschaltet, gilt auch mit Automatik)
---   Automatik an + Motiv da   => Motiv, "auto"
---   Automatik an, Motiv fehlt => cfg.ornament, "fallback" (Zone ohne Eintrag/Instanz, Motiv nicht geladen)
---   Automatik aus             => cfg.ornament, "fixed"
--- loaded(name) -> bool legt fest, ob ein Motiv zeigbar ist (Standard: Stil bekannt; die Karte prueft zusaetzlich,
--- ob die Textur ladbar ist).
function Card.ResolveOrnament(cfg, mapID, loaded)
    local fixed = type(cfg) == "table" and cfg.ornament or "swirl"
    if fixed == "none" then return "none", "fixed" end
    if type(cfg) ~= "table" or cfg.autoOrnament == false then return fixed, "fixed" end
    local motif = Card.MotifFor(mapID)
    if motif and (loaded and loaded(motif) or (not loaded and Card.STYLES[motif] ~= nil)) then return motif, "auto" end
    return fixed, "fallback"
end
-- Lichtband hinter der grossen Karte: zwei Lagen (aussen/innen), Textur laeuft nach allen Seiten weich auf 0 aus.
-- Ueberstand: waagerecht ueber das Ornament hinaus, senkrecht ueber Ober-/Unterkante der Zeilen.
Card.BAND_INNER = { alpha = 0.25, padY = 12 }
Card.BAND_OUTER = { alpha = 0.22, padY = 28 }
Card.BAND_PAD_X = 40
-- Staerke aus dem Profil (zone.glow / zone.band, 0-100 %): 50 % = die Werte hier, 100 % = doppelt, 0 % = aus.
-- Glanz hinter dem Titel (nur grosse Karte, einmal je Karte): warmes Gold, Spitze alpha; Breite Textbreite + 2 x padX,
-- Hoehe height x Schriftgroesse. Zeiten relativ zum Einblenden: Start nach delay x fadeIn, Aufleuchten ueber
-- rise x fadeIn, danach Abklingen ueber decay s auf 0.
-- Die Staerke steckt in der Spitze der Alpha-Animation (ToAlpha), nicht im Vertex-Alpha: im Client ist das
-- Vertex-Alpha dasselbe Alpha, das die Animation absolut setzt (sonst waere jede Staerke > 0 voll an).
Card.GLOW = { alpha = 0.3, padX = 48, height = 2.2, delay = 0.15, rise = 0.5, decay = 1.6 }

local IVORY = { 1, 0.93, 0.76 }
local GOLD_SUB = { 0.86, 0.72, 0.45 }
local GOLD_LINE = { 0.80, 0.66, 0.38 }

-- Schriften ---------------------------------------------------------------------------------------
local FONT_DIR = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Fonts\\"
local FALLBACK_FONT = "Fonts\\FRIZQT__.TTF"
Card.FONT_PATHS = {
    frizqt = "Fonts\\FRIZQT__.TTF",
    morpheus = "Fonts\\MORPHEUS.TTF",
    arialn = "Fonts\\ARIALN.TTF",
    skurri = "Fonts\\SKURRI.TTF",
    cinzel = FONT_DIR .. "Cinzel-Regular.ttf",
    cormorant = FONT_DIR .. "CormorantGaramond-Medium.ttf",
    marcellus = FONT_DIR .. "Marcellus-Regular.ttf",
}
-- Clients mit nicht-lateinischer Schrift: dort decken nur die Client-Schriften die Glyphen ab
local NON_LATIN = { ruRU = true, zhCN = true, zhTW = true, koKR = true }

local function clientFont()
    local f = _G.STANDARD_TEXT_FONT
    if type(f) == "string" and f ~= "" then return f end
    return FALLBACK_FONT
end

local function nonLatin()
    return type(GetLocale) == "function" and NON_LATIN[GetLocale()] == true
end

--- Pfad zu einem Schriftschluessel. "client", unbekannte Schluessel und nicht-lateinische Clients => STANDARD_TEXT_FONT.
function Card.FontPath(key)
    if key == "client" or nonLatin() then return clientFont() end
    return Card.FONT_PATHS[key] or clientFont()
end

-- SetFont mit pcall; Erfolg = kein Fehler und kein false (Clients ohne Rueckgabewert: GetFont muss etwas liefern)
local function trySetFont(fs, path, size)
    local ok, r = pcall(fs.SetFont, fs, path, size, "OUTLINE")
    if not ok or r == false then return false end
    if r == nil then
        local okGet, p = pcall(fs.GetFont, fs)
        return okGet and type(p) == "string"
    end
    return true
end

local probeFs
-- Mit dem Addon ausgelieferte Schriften: immer verfuegbar (die Probe scheitert im echten Client teils faelschlich)
local BUNDLED = { cinzel = true, cormorant = true, marcellus = true }

--- true, wenn die Schrift nutzbar ist. Mitgelieferte Schriften: immer (ausser nicht-lateinischer Client).
--- Skurri wird per Probe-SetFont geprueft; ein negatives Ergebnis wird nicht gemerkt (erneute Probe beim
--- naechsten Aufruf, z.B. beim Oeffnen des Reiters). Nicht-lateinische Clients: nur "client".
function Card.FontAvailable(key)
    if key == "client" then return true end
    if nonLatin() or not Card.FONT_PATHS[key] then return false end
    if BUNDLED[key] then return true end
    if not probeFs then
        local f = CreateFrame("Frame", nil, UIParent)
        f:Hide()
        probeFs = f:CreateFontString(nil, "OVERLAY")
    end
    return trySetFont(probeFs, Card.FONT_PATHS[key], 12)
end

--- Schrift setzen mit Rueckfall: gewaehlte Schrift -> STANDARD_TEXT_FONT -> Schrift von GameFontNormal ->
--- SetFontObject(GameFontNormal). Liefert den wirksamen Pfad (oder "object").
function Card.ApplyFont(fs, key, size)
    local path = Card.FontAvailable(key) and Card.FontPath(key) or clientFont()
    if trySetFont(fs, path, size) then return path end
    local std = clientFont()
    if std ~= path and trySetFont(fs, std, size) then return std end
    local obj = _G.GameFontNormal
    if type(obj) == "table" and type(obj.GetFont) == "function" then
        local ok, p = pcall(obj.GetFont, obj)
        if ok and type(p) == "string" and trySetFont(fs, p, size) then return p end
    end
    if type(obj) == "table" then pcall(fs.SetFontObject, fs, obj) end
    return "object"
end

-- Frames ------------------------------------------------------------------------------------------
local frames = {}            -- zwei Karten: die laufende und ggf. eine ausblendende
local active = nil           -- laufende Karte (Frame)
local GLOW_COLOR = { 1, 0.84, 0.55 }

-- Pixel-Snapping aus (sonst rasten animierte Regionen in 1-px-Stufen ein); nur wo der Client es kennt
local function noSnap(r)
    if type(r.SetSnapToPixelGrid) == "function" then pcall(r.SetSnapToPixelGrid, r, false) end
    if type(r.SetTexelSnappingBias) == "function" then pcall(r.SetTexelSnappingBias, r, 0) end
end

local function newText(c)
    local fs = c:CreateFontString(nil, "OVERLAY")
    noSnap(fs)
    -- Grundschrift, damit SetText("") vor dem ersten ApplyFont nicht "Font not set" wirft
    if type(_G.GameFontNormal) == "table" then pcall(fs.SetFontObject, fs, _G.GameFontNormal) end
    fs:SetJustifyH("CENTER")
    fs:SetWordWrap(false)
    fs:SetShadowColor(0, 0, 0, 0.8)
    fs:SetShadowOffset(2, -2)
    return fs
end

-- waagerechter Verlauf, der nach aussen auslaeuft (outerIsMin: aeusseres Ende liegt links); true bei Erfolg.
-- SetGradient nur per Existenz-/pcall-Pruefung (aeltere Clients: andere Signatur).
local function fadeOutward(t, r, g, b, a, outerIsMin)
    return type(CreateColor) == "function" and type(t.SetGradient) == "function" and pcall(function()
        local solid, clear = CreateColor(r, g, b, a), CreateColor(r, g, b, 0)
        if outerIsMin then t:SetGradient("HORIZONTAL", clear, solid) else t:SetGradient("HORIZONTAL", solid, clear) end
    end) == true
end

-- Linie mit Verlauf nach aussen; Rueckfall: einfache Linie, niedrige Alpha
local function newLine(c, outerIsMin)
    local t = c:CreateTexture(nil, "ARTWORK")
    noSnap(t)
    t:SetHeight(1)
    t:SetColorTexture(1, 1, 1, 1)
    local r, g, b = GOLD_LINE[1], GOLD_LINE[2], GOLD_LINE[3]
    if not fadeOutward(t, r, g, b, 0.9, outerIsMin) then t:SetColorTexture(r, g, b, 0.45) end
    return t
end

-- Raute am inneren Linienende: senkrechter Strich (1 x n), waagerechter Strich (n x 1) und Mittelquadrat
-- (n-2 x n-2) ergeben zusammen eine pixelgenaue Raute, ganz ohne Bilddatei oder Drehung.
-- Groesse der Raute: Kantenlaenge n (ungerade), Strichstaerke s (wie die Linie)
local function sizeDiamond(parts, n, s)
    for i, size in ipairs({ { s, n }, { n, s }, { n - 2 * s, n - 2 * s } }) do
        parts[i]:SetSize(math.max(1, size[1]), math.max(1, size[2]))
    end
end

local function newDiamond(c, line, side)
    local parts = {}
    for i = 1, 3 do
        local t = c:CreateTexture(nil, "ARTWORK", nil, 1)
        noSnap(t)
        t:SetColorTexture(GOLD_LINE[1], GOLD_LINE[2], GOLD_LINE[3], 0.9)
        t:SetPoint("CENTER", line, side, 0, 0)
        parts[i] = t
    end
    sizeDiamond(parts, Card.DIAMOND, 1)
    return parts
end

-- Weiche Flaeche aus einer mitgelieferten Verlaufs-Textur (Alpha laeuft im Bild selbst auf 0 aus, keine harten
-- Kanten), eingefaerbt per SetVertexColor, normales Blending. Textur nicht ladbar => nil (dann keine Flaeche: eine
-- harte Flaeche waere aufdringlicher als gar keine).
-- Textur mit Mipmaps laden (trilineare Filterung; sonst aliasen grosse Texturen bei kleiner Anzeige = Treppen).
-- Signatur Retail 12.x: SetTexture(pfad, wrapH, wrapV, filter); kennt ein Client das nicht, ohne Zusatzargumente.
local function loadSmooth(t, path, filter)
    local ok, res = pcall(t.SetTexture, t, path, "CLAMP", "CLAMP", filter or "TRILINEAR")
    if ok and res ~= false then return ok, res end
    return pcall(t.SetTexture, t, path)
end

local function newSoft(c, sub, path, r, g, b, a)
    local t = c:CreateTexture(nil, "BACKGROUND", nil, sub)
    local ok, res = loadSmooth(t, path)
    if not ok or res == false or type(t.SetVertexColor) ~= "function" then
        t:Hide()
        return nil
    end
    noSnap(t)
    -- Farbe ueber das Vertex-Alpha 1; die Deckkraft kommt aus SetAlpha bzw. der Alpha-Animation (dasselbe Alpha)
    t:SetVertexColor(r, g, b, 1)
    t:SetAlpha(a)
    if type(t.SetBlendMode) == "function" then pcall(t.SetBlendMode, t, "BLEND") end
    return t
end

-- Verzierungs-Textur (Ranke/Filigran) in der Titelfarbe der Linien; texCoord spiegelt (links bzw. oben)
local function newOrnTex(c, path, texCoord)
    local t = newSoft(c, 0, path, Card.ORN_TINT[1], Card.ORN_TINT[2], Card.ORN_TINT[3], 1)
    if not t then return nil end
    pcall(t.SetDrawLayer, t, "ARTWORK", 0)
    t.baseCoord = texCoord
    if texCoord and type(t.SetTexCoord) == "function" then pcall(t.SetTexCoord, t, unpack(texCoord)) end
    t:Hide()
    return t
end

-- Stueck aus Kacheln (Vorlagen-Stile): Halter-Frame mit einem Vorrat Texturen. layoutPiece legt Abschnitte des
-- Inhalts (Anteile 0..1, je mit Anzeigebreite) nebeneinander, teilt sie an Kachelgrenzen und schneidet per SetTexCoord
-- zu. Stufe: die kleinste, deren Inhaltsbreite die physische Anzeigebreite erreicht; Filter LINEAR, solange die
-- Textur hoechstens doppelt so gross ist wie die Anzeige (scharf), darueber TRILINEAR (Mipmaps gegen Treppen).
Card.PIECE_POOL = 16
local function newPiece(parent, S)
    local first = S.levels[1] and S.levels[1].tiles[1]
    if not first then return nil end
    local holder = CreateFrame("Frame", nil, parent)
    holder:EnableMouse(false)
    noSnap(holder)
    holder:Hide()
    holder.isPiece, holder.pool = true, {}
    -- Vorrat: mindestens PIECE_POOL, bei Streifen-Stufen (pair) so viele wie die Stufe mit den meisten Kacheln braucht
    local size = Card.PIECE_POOL
    for _, lv in ipairs(S.levels) do size = math.max(size, #lv.tiles) end
    for i = 1, size do
        local t = newSoft(holder, 0, MEDIA .. first.file, Card.ORN_TINT[1], Card.ORN_TINT[2], Card.ORN_TINT[3], 1)
        if not t then return nil end
        pcall(t.SetDrawLayer, t, "ARTWORK", 0)
        t:Hide()
        holder.pool[i] = t
    end
    return holder
end

-- Physische Pixel je UI-Einheit: effektive Skala x (Bildschirmhoehe in Pixeln / 768). Bei UI-Skala 1,0 sind das auf
-- 1440p 1,875 Pixel je Einheit (ohne diesen Faktor waere die Stufe um fast die Haelfte zu klein = hochskaliert).
function Card.PixelsPerUnit()
    if type(GetPhysicalScreenSize) == "function" then
        local ok, _, h = pcall(GetPhysicalScreenSize)
        h = ok and Compat.Num(h) or nil
        if h and h > 0 then return h / 768 end
    end
    return 1
end

local function effScale(f)
    local ok, v = pcall(f.GetEffectiveScale, f)
    v = ok and Compat.Num(v) or nil
    return ((v and v > 0) and v or 1) * Card.PixelsPerUnit()
end

--- segs = { { c0, c1, w }, ... } in Inhaltsreihenfolge; mirror spiegelt waagerecht, flip senkrecht
local function layoutPiece(piece, S, segs, h, mirror, flip, eff)
    local perContent = 0 -- Anzeigebreite je ganzer Inhaltsbreite (physische Pixel)
    for _, sg in ipairs(segs) do -- gedehnte Abschnitte (sg[4]) bestimmen die Aufloesung nicht
        if sg[2] > sg[1] and not sg[4] then perContent = math.max(perContent, sg[3] / (sg[2] - sg[1])) end
    end
    perContent = perContent * (eff or 1)
    local level = S.levels[#S.levels]
    for _, lv in ipairs(S.levels) do
        if lv.cw >= perContent then level = lv break end
    end
    local filter = (perContent > 0 and level.cw / perContent >= 2) and "TRILINEAR" or "LINEAR"
    piece.level, piece.filter = level, filter
    local t1 = level.tiles[1]
    -- srcLimited: groesste Stufe und so breit wie die Vorlage selbst (mehr Aufloesung gibt die Vorlage nicht her)
    piece.debug = { cw = level.cw, tiles = #level.tiles, texW = t1 and t1.w or 0, texH = t1 and t1.h or 0,
        phys = perContent, filter = filter, srcLimited = level == S.levels[#S.levels] and (S.srcW or 0) > 0
            and level.cw >= 0.75 * S.srcW }
    -- Abschnitte an den Kachelgrenzen teilen
    -- Kacheln mit y0/y1 (Streifen-Stufen, Layout pair) liegen uebereinander und werden ueber Offsets gesetzt, alle anderen
    -- hintereinander (Kette); totalW = Summe der Abschnittsbreiten
    local subs, segX, striped = {}, 0, false
    for _, sg in ipairs(segs) do
        for _, tile in ipairs(level.tiles) do
            local a, b = math.max(sg[1], tile.from), math.min(sg[2], tile.to)
            if b > a then
                subs[#subs + 1] = { tile = tile, a = a, b = b, w = sg[3] * (b - a) / (sg[2] - sg[1]),
                    x = segX + (a - sg[1]) / (sg[2] - sg[1]) * sg[3] }
                if tile.y0 then striped = true end
            end
        end
        segX = segX + sg[3]
    end
    local totalW = segX
    local total, prev = 0, nil
    for i = 1, math.max(Card.PIECE_POOL, #piece.pool) do
        local sub = subs[mirror and (#subs + 1 - i) or i]
        local t = piece.pool[i]
        if not t then break end
        if sub then
            local tile, file = sub.tile, MEDIA .. sub.tile.file
            if t.curFile ~= file or t.curFilter ~= filter then
                loadSmooth(t, file, filter)
                t.curFile, t.curFilter = file, filter
            end
            local span = tile.to - tile.from
            local ua = tile.u0 + (sub.a - tile.from) / span * (tile.u1 - tile.u0)
            local ub = tile.u0 + (sub.b - tile.from) / span * (tile.u1 - tile.u0)
            local l, r = ua, ub
            if mirror then l, r = ub, ua end
            local v0, v1 = tile.v0, tile.v1
            if flip then v0, v1 = v1, v0 end
            if type(t.SetTexCoord) == "function" then pcall(t.SetTexCoord, t, l, r, v0, v1) end
            t:ClearAllPoints()
            if tile.y0 then
                local xo = mirror and (totalW - sub.x - sub.w) or sub.x
                t:SetSize(sub.w, (tile.y1 - tile.y0) * h)
                t:SetPoint("TOPLEFT", piece, "TOPLEFT", xo, -tile.y0 * h)
            else
                t:SetSize(sub.w, h)
                if prev then t:SetPoint("TOPLEFT", prev, "TOPRIGHT", 0, 0) else t:SetPoint("TOPLEFT", piece, "TOPLEFT", 0, 0) end
                prev = t
                total = total + sub.w
            end
            t:Show()
        else
            t:Hide()
        end
    end
    piece:SetSize(striped and totalW or total, h)
end

-- Groesse setzen: Stueck per layoutPiece, eingebaute Textur per SetSize (Spiegelung ist dort schon gesetzt)
local function sizeOrn(x, S, segs, w, h, mirror, flip, eff)
    if x.isPiece then
        layoutPiece(x, S, segs or { { 0, 1, w } }, h, mirror, flip, eff)
        return
    end
    -- eingebaute Textur: Stufe nach physischer Breite, Filter wie bei den Stuecken
    if S.files then
        local need, lv = w * (eff or 1), S.files[#S.files]
        for _, l in ipairs(S.files) do if l.cw >= need then lv = l break end end
        local filter = (need > 0 and lv.cw / need >= 2) and "TRILINEAR" or "LINEAR"
        x.debug = { cw = lv.cw, tiles = 1, texW = lv.cw, texH = 0, phys = need, filter = filter }
        local file = MEDIA .. lv.file
        if x.curFile ~= file or x.curFilter ~= filter then
            local ok, res = loadSmooth(x, file, filter)
            if ok and res ~= false then
                x.curFile, x.curFilter = file, filter
                if x.baseCoord and type(x.SetTexCoord) == "function" then pcall(x.SetTexCoord, x, unpack(x.baseCoord)) end
            end
        end
    end
    x:SetSize(w, h)
end

-- Lichtband-Lage (dunkel), oben mittig an der Karte ausgerichtet
local function newBand(c, spec, sub)
    local t = newSoft(c, sub, Card.BAND_TEX, 0, 0, 0, spec.alpha)
    if not t then return nil end
    t:SetPoint("TOP", c, "TOP", 0, spec.padY)
    return { t = t, padY = spec.padY, alpha = spec.alpha }
end

-- Glanz (warmes Gold, radial) mittig hinter Zeile 1; startet unsichtbar (Alpha 0), nur die Animation hebt ihn an
local function newGlow(c, line1)
    local t = newSoft(c, 2, Card.GLOW_TEX, GLOW_COLOR[1], GLOW_COLOR[2], GLOW_COLOR[3], Card.GLOW.alpha)
    if not t then return nil end
    t:SetAlpha(0)
    t:Hide()
    t:SetPoint("CENTER", line1, "CENTER", 0, 0)
    return t
end

-- Animation-API -----------------------------------------------------------------------------------
-- Alles per Existenz-/pcall-Pruefung: fehlt etwas Unverzichtbares, liefert buildAnims nil (Rueckfall OnUpdate).

local function setSmoothing(anim, s)
    if type(anim.SetSmoothing) == "function" then pcall(anim.SetSmoothing, anim, s) end
end

local function newAlpha(group, order, from, to, smoothing)
    local a = group:CreateAnimation("Alpha")
    a:SetOrder(order)
    a:SetFromAlpha(from)
    a:SetToAlpha(to)
    a:SetDuration(1)
    setSmoothing(a, smoothing)
    return a
end

-- Skalierung von -> nach; neue (SetScaleFrom/To) und alte Namen (SetFromScale/ToScale). false: nicht moeglich.
local function setScaleRange(anim, fx, fy, tx, ty)
    if type(anim.SetScaleFrom) == "function" and type(anim.SetScaleTo) == "function" then
        return pcall(function() anim:SetScaleFrom(fx, fy); anim:SetScaleTo(tx, ty) end) == true
    end
    if type(anim.SetFromScale) == "function" and type(anim.SetToScale) == "function" then
        return pcall(function() anim:SetFromScale(fx, fy); anim:SetToScale(tx, ty) end) == true
    end
    return false
end

-- geglaetteter Fortschritt 0..1 einer laufenden Animation (oder nil, wenn der Client ihn nicht liefert)
local function smoothProgress(anim)
    for _, m in ipairs({ "GetSmoothProgress", "GetProgress" }) do
        if type(anim[m]) == "function" then
            local ok, p = pcall(anim[m], anim)
            p = ok and Compat.Num(p) or nil
            if p then return math.max(0, math.min(1, p)) end
        end
    end
    return nil
end

local onInFinished, finish -- weiter unten

local function buildAnims(f)
    local c = f.content
    if type(f.CreateAnimationGroup) ~= "function" or type(c.CreateAnimationGroup) ~= "function" then return nil end
    local ok, A = pcall(function()
        local A = { groups = {}, lines = {}, glow = {} }
        local function group(owner, toFinal, onFinished)
            local g = owner:CreateAnimationGroup()
            if toFinal and type(g.SetToFinalAlpha) == "function" then g:SetToFinalAlpha(true) end
            if onFinished then g:SetScript("OnFinished", onFinished) end
            A.groups[#A.groups + 1] = g
            return g
        end
        -- Einblenden (Inhalt = Schrift + Deko): nur Alpha, die Schrift bewegt sich nie
        A.inGroup = group(c, true, function() onInFinished(f) end)
        A.fadeIn = newAlpha(A.inGroup, 1, 0, 1, "OUT")
        -- Zoom nur der Dekoration (Band, Glanz, Linien, Rauten), synchron zum Einblenden
        A.zoomGroup = group(f.deco, false)
        A.zoom = A.zoomGroup:CreateAnimation("Scale")
        if type(A.zoom.SetOrigin) == "function" then A.zoom:SetOrigin("CENTER", 0, 0) end
        setSmoothing(A.zoom, "OUT")
        A.zoomOk = setScaleRange(A.zoom, Card.ZOOM, Card.ZOOM, 1, 1)
        -- Ausblenden (Rahmen): Stufe 1 Rampe (nachgereichter Untertitel: vom aktuellen Alpha weich auf 1, sonst
        -- PRESET s auf 1), Stufe 2 nach dem Rest des Haltens Alpha easeIn auf 0
        A.outGroup = group(f, true, function() finish(f) end)
        A.ramp = newAlpha(A.outGroup, 1, 1, 1, "OUT")
        A.fadeOut = newAlpha(A.outGroup, 2, 1, 0, "IN")
        -- Abloesen durch eine neue Karte
        A.retireGroup = group(f, true, function() finish(f) end)
        A.retire = newAlpha(A.retireGroup, 1, 1, 0, "NONE")
        A.retire:SetDuration(Card.RETIRE)
        -- nachgereichter Untertitel
        A.subGroup = group(f.sub, true, function() f.sub:SetAlpha(1) end)
        A.subIn = newAlpha(A.subGroup, 1, 0, 1, "OUT")
        A.subIn:SetDuration(Card.SUB_FADE)
        -- Linien wachsen vom Text nach aussen (Ursprung = inneres Ende); ohne Skalierungs-API bleiben sie voll
        for _, def in ipairs({ { f.ornL, "RIGHT" }, { f.ornR, "LEFT" } }) do
            local g = group(def[1], false)
            local s = g:CreateAnimation("Scale")
            if type(s.SetOrigin) == "function" then s:SetOrigin(def[2], 0, 0) end
            setSmoothing(s, "OUT")
            if setScaleRange(s, Card.ORN_FROM, 1, 1, 1) then A.lines[#A.lines + 1] = { group = g, anim = s } end
        end
        -- Glanz: Aufleuchten, dann Abklingen auf 0 (bleibt danach unsichtbar)
        if f.glow then
            local g = group(f.glow, true)
            A.glow[1] = { group = g, rise = newAlpha(g, 1, 0, 1, "OUT"), decay = newAlpha(g, 2, 1, 0, "IN_OUT"), tex = f.glow }
        end
        -- Verzierungen: leichtes Wachsen (Ursprung am Titel-Ende bzw. in der Mitte) + Alpha, beides ab dem Einsatz.
        -- A.addStyle haengt die Animationen eines Stils an; Zonen-Motive entstehen erst bei Bedarf (ensureStyle)
        -- und rufen es spaeter auf.
        A.orn = {}
        function A.addStyle(st, spec)
            local defs
            if spec.kind == "sides" or spec.kind == "pair" then
                defs ={ { st.a, "LEFT" }, { st.b, "RIGHT" } }
            else
                defs = { { st.a, "CENTER" }, { st.b, "CENTER" } }
            end
            for _, def in ipairs(defs) do
                local t, origin = def[1], def[2]
                if t then
                    local g = group(t, true)
                    local sc = g:CreateAnimation("Scale")
                    if type(sc.SetOrigin) == "function" then sc:SetOrigin(origin, 0, 0) end
                    setSmoothing(sc, "OUT")
                    setScaleRange(sc, spec.grow, spec.grow, 1, 1)
                    A.orn[t] = { group = g, scale = sc, alpha = newAlpha(g, 1, 0, spec.alpha, "OUT") }
                end
            end
        end
        for name, spec in pairs(Card.STYLES) do
            local st = f.styleTex[name]
            if st then A.addStyle(st, spec) end
        end
        return A
    end)
    if ok then return A end
    return nil
end

local function stopAnims(f)
    if not f.A then return end
    for _, g in ipairs(f.A.groups) do pcall(g.Stop, g) end
end

local fallbackUpdate

--- Texturen eines Stils anlegen: { a, b } oder nil, wenn eine Textur nicht ladbar ist.
--- sides a = rechts, b = links (gespiegelt); bar a = unten, b = oben (optional)
local function makeStyleTex(o, S)
    local a, b
    if S.kind == "pair" then
        -- zwei eigenstaendige Seiten (S.right / S.left), je mit eigenen Stufen
        a = S.right and newPiece(o, S.right) or nil
        b = a and S.left and newPiece(o, S.left) or nil
    elseif S.levels then
        -- Vorlagen-Stil: Stuecke aus Kacheln (Stufe/Filter je Anzeigegroesse, siehe layoutPiece)
        a = newPiece(o, S)
        b = a and (S.kind == "sides" or S.top) and newPiece(o, S) or nil
    elseif S.kind == "sides" then
        a = newOrnTex(o, S.tex)
        b = a and newOrnTex(o, S.tex, { 1, 0, 0, 1 })
    else
        a = newOrnTex(o, S.tex, S.flipBottom and { 0, 1, 1, 0 } or nil)
        b = a and S.top and newOrnTex(o, S.tex, S.flipTop and { 0, 1, 1, 0 } or nil)
    end
    if a and ((S.kind ~= "sides" and S.kind ~= "pair") or b) then return { a = a, b = b } end
    return nil
end

--- Stil des Rahmens bereitstellen (Motive werden hier erst angelegt). true, wenn er zeigbar ist.
local function ensureStyle(f, name)
    if f.styleTex[name] then return true end
    local S = Card.STYLES[name]
    if not S or f.styleTried[name] or not f.ornFrame then return false end
    f.styleTried[name] = true
    local ok, st = pcall(makeStyleTex, f.ornFrame, S)
    if not (ok and st) then return false end
    -- die Animation muss mit: ohne sie scheiterte startIn beim Einblenden => Stil gilt dann als nicht ladbar
    if f.A and f.A.addStyle then
        if not pcall(f.A.addStyle, st, S) or not f.A.orn[st.a] then
            st.a:Hide()
            if st.b then st.b:Hide() end
            return false
        end
    end
    f.styleTex[name] = st
    return true
end

local function newFrame(name)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetFrameStrata(Card.STRATA)
    f:EnableMouse(false)
    f:SetClampedToScreen(true)
    f:SetSize(400, 60)
    f:Hide()
    noSnap(f)
    -- Rahmen (Ausblenden/Abloesen) -> Inhalt (Einblenden) -> Deko (Zoom, unten) + Text (ruhig, oben)
    local function child(parent, levelUp)
        local x = CreateFrame("Frame", nil, parent)
        x:EnableMouse(false)
        x:SetAllPoints(parent)
        noSnap(x)
        if levelUp then pcall(x.SetFrameLevel, x, parent:GetFrameLevel() + levelUp) end
        return x
    end
    local c = child(f)
    local d, t = child(c, 1), child(c, 3)
    -- Verzierung in einem eigenen Frame direkt am Rahmen (nicht im Inhalt): ihr Alpha haengt nur an ihrer eigenen
    -- Animation, nicht zusaetzlich am Einblenden des Titels (sonst wartet sie trotz Einsatz 0 s). Ebene zwischen
    -- Deko (Band, Glanz, Linien) und Text.
    local o = child(f)
    pcall(o.SetFrameLevel, o, c:GetFrameLevel() + 2)
    f.content, f.deco, f.text, f.ornFrame = c, d, t, o
    f.line1, f.line2, f.sub = newText(t), newText(t), newText(t)
    f.line1:SetPoint("TOP", t, "TOP", 0, 0)
    f.line2:SetPoint("TOP", f.line1, "BOTTOM", 0, -Card.LINE2_GAP)
    f.line1:SetTextColor(IVORY[1], IVORY[2], IVORY[3])
    f.line2:SetTextColor(IVORY[1], IVORY[2], IVORY[3])
    f.line2:SetAlpha(Card.LINE2_ALPHA)
    f.sub:SetTextColor(GOLD_SUB[1], GOLD_SUB[2], GOLD_SUB[3])
    f.ornL, f.ornR = newLine(d, true), newLine(d, false)
    f.ornL:SetPoint("RIGHT", f.line1, "LEFT", -Card.ORN_GAP, 0)
    f.ornR:SetPoint("LEFT", f.line1, "RIGHT", Card.ORN_GAP, 0)
    f.dmL, f.dmR = newDiamond(d, f.ornL, "RIGHT"), newDiamond(d, f.ornR, "LEFT")
    f.bands = {}
    for i, spec in ipairs({ Card.BAND_OUTER, Card.BAND_INNER }) do
        f.bands[#f.bands + 1] = newBand(d, spec, i - 1)
    end
    f.glow = newGlow(d, f.line1) -- nil: Textur nicht ladbar => kein Glanz
    -- Verzierungen (nil: Textur nicht ladbar => Stil faellt auf "simple" zurueck). Zonen-Motive (O.motif) entstehen
    -- erst bei der ersten Karte, die sie braucht (ensureStyle): 40 weitere Stile mit je einem Vorrat Texturen waeren
    -- sonst bei jedem Start geladen.
    f.styleTex, f.styleTried = {}, {}
    for name, S in pairs(Card.STYLES) do
        if not Card.IsMotif(name) then
            f.styleTried[name] = true
            local st = makeStyleTex(o, S)
            if st then f.styleTex[name] = st end
        end
    end
    local sw, fl = f.styleTex.swirl or {}, f.styleTex.filigree or {}
    f.swR, f.swL, f.filB, f.filT = sw.a, sw.b, fl.a, fl.b -- Kurznamen (Diagnose/Tests)
    f.A = buildAnims(f)
    if not f.A then f:SetScript("OnUpdate", fallbackUpdate) end
    return f
end

local function ensureFrames()
    if not frames[1] then
        frames[1] = newFrame(Card.FRAME_NAME)
        frames[2] = newFrame(Card.FRAME_NAME .. "B")
    end
end

local function textWidth(fs)
    local ok, w = pcall(fs.GetStringWidth, fs)
    w = ok and Compat.Num(w) or nil
    return w or 0
end

-- Position aus dem Profil (Zone.GetConfig ist immer gueltig: point aus fester Liste, x/y begrenzt). Einmal je Karte;
-- Der Zoom ist reine Animation und veraendert den Anker nicht.
local function place(f)
    local p = f.pos
    f:ClearAllPoints()
    f:SetPoint(p.point, UIParent, p.point, p.x, p.y)
end

finish = function(f)
    f.anim = nil
    f:Hide()
    stopAnims(f)
    if f.glow then f.glow:SetAlpha(0) end
    if active == f then active = nil end
end

local function easeOut(t) return 1 - (1 - t) * (1 - t) end

-- Seitliche Ornamente (sides/pair): halbe Breite der breitesten Zeile, die vertikal im Bereich einer Seite liegt
-- (Textur der Hoehe h mit Mitte dy ueber/unter der Titelmitte; Zeile 1 zaehlt immer, Zeile 2/Untertitel aus f.rows).
local function sideReach(f, w1, h, dy)
    local need = w1 / 2
    for _, row in ipairs(f.rows or {}) do
        if row.top > dy - h / 2 and row.bottom < dy + h / 2 then need = math.max(need, row.w / 2) end
    end
    return need
end

-- Verkleinerungsfaktor (<= 1), damit eine Karte mit Seiten-Ornamenten (innere Kante bei half + gap, Seitenbreite
-- widest) nicht breiter als der Bildschirm wird; ohne bekannte Bildschirmbreite 1
local function screenShrink(half, gap, widest)
    local ok, sw = pcall(UIParent.GetWidth, UIParent)
    sw = ok and Compat.Num(sw) or nil
    if not (sw and sw > 0 and widest > 0) then return 1 end
    local avail = sw * Card.SCREEN_FILL / 2 - half - gap
    if widest <= avail then return 1 end
    return math.max(Card.SIDE_MIN_SHRINK, avail / widest)
end

-- Verzierung je Stil zeigen/verstecken und einmal je Karte bemessen (das Wachsen macht die Animation).
-- Liefert die waagerechte Ausdehnung ueber die halbe Textbreite hinaus (fuer Band und Frame-Breite) und die
-- zusaetzliche Hoehe unter dem Titelblock (Filigran).
local function setOrnament(f, style, k, w1, lastLine, linesH)
    local simple, S, st = style == "simple", Card.STYLES[style], f.styleTex[style]
    for _, t in ipairs({ f.ornL, f.ornR, unpack(f.dmL) }) do t:SetShown(simple) end
    for _, t in ipairs(f.dmR) do t:SetShown(simple) end
    for name, x in pairs(f.styleTex) do
        x.a:SetShown(name == style)
        if x.b then x.b:SetShown(name == style) end
    end
    f.ornTex, f.ornSpec, f.subAnchor, f.subPad = {}, S, nil, 0
    local eff = effScale(f)
    if simple then
        local s = k >= 1.5 and 2 or 1
        f.ornL:SetSize(f.ornLen * k, s)
        f.ornR:SetSize(f.ornLen * k, s)
        local n = 2 * math.floor(2.5 * k) + 1
        sizeDiamond(f.dmL, n, s)
        sizeDiamond(f.dmR, n, s)
        return Card.ORN_GAP + f.ornLen * k, 0
    elseif S and st and S.kind == "sides" then
        local w = math.min(S.max, math.max(S.min, S.factor * f.ornLen)) * k
        local h = w / S.aspect
        local dy = (S.midY - 0.5) * h -- Strichmitte am inneren Ende auf die Mitte der Titelzeile
        local half = sideReach(f, w1, h, dy) -- Abstand nach der breitesten Zeile neben der Seite (wie bei pair)
        local extra = half - w1 / 2
        local q = screenShrink(half, S.gap, w)
        w, h, dy = w * q, h * q, dy * q
        sizeOrn(st.a, S, nil, w, h, false, false, eff)
        sizeOrn(st.b, S, nil, w, h, true, false, eff)
        st.a:ClearAllPoints()
        st.b:ClearAllPoints()
        st.a:SetPoint("LEFT", f.line1, "RIGHT", S.gap + extra, dy)
        st.b:SetPoint("RIGHT", f.line1, "LEFT", -S.gap - extra, dy)
        f.ornTex = { st.b, st.a }
        return S.gap + extra + w, 0
    elseif S and st and S.kind == "pair" then
        -- zwei eigenstaendige Seiten: rechts die rechte, links die linke Haelfte der Vorlage (nicht Spiegelbild).
        -- Gleicher Massstab (UI-Einheiten je Vorlagen-Pixel) fuer beide, ausgehend von der breiteren Seite, die
        -- wie bei "sides" factor x Linienlaenge in [min, max] bekommt; die inneren Spitzen (midY) liegen auf Titelmitte.
        -- Die linke Textur ist beim Erzeugen gespiegelt abgelegt (inneres Ende links wie bei jeder Seite) und wird
        -- hier wieder zurueckgespiegelt: auf dem Bildschirm steht sie so, wie sie in der Vorlage links stand.
        local R, Lf = S.right, S.left
        local wRef = math.min(S.max, math.max(S.min, S.factor * f.ornLen)) * k
        local wide = math.max(R.srcW or 0, Lf.srcW or 0)
        local function size(X)
            local w = (wide > 0 and (X.srcW or 0) > 0) and wRef * X.srcW / wide or wRef
            return w, w / X.aspect
        end
        local wr, hr = size(R)
        local wl, hl = size(Lf)
        -- Abstand nach der breitesten Textzeile neben den Seiten (Zeile 1, Zeile 2, Untertitel; Seitenmitte auf
        -- (midY - 0,5) x Hoehe). Beide Seiten bekommen den groesseren Zuschlag (symmetrisch); Groesse/Breite der
        -- Seiten bleiben nach Zeile 1.
        local half = math.max(sideReach(f, w1, hr, (R.midY - 0.5) * hr), sideReach(f, w1, hl, (Lf.midY - 0.5) * hl))
        local extra = half - w1 / 2
        local widest = math.max(wl, wr)
        local q = screenShrink(half, S.gap, widest) -- nie breiter als der Bildschirm: proportional verkleinern
        wr, hr, wl, hl, widest = wr * q, hr * q, wl * q, hl * q, widest * q
        sizeOrn(st.a, R, nil, wr, hr, false, false, eff)
        sizeOrn(st.b, Lf, nil, wl, hl, true, false, eff)
        st.a:ClearAllPoints()
        st.b:ClearAllPoints()
        st.a:SetPoint("LEFT", f.line1, "RIGHT", S.gap + extra, (R.midY - 0.5) * hr)
        st.b:SetPoint("RIGHT", f.line1, "LEFT", -S.gap - extra, (Lf.midY - 0.5) * hl)
        f.ornTex = { st.b, st.a }
        return S.gap + extra + widest, 0
    elseif S and st and S.kind == "frame" then
        -- Rahmen (Kartusche) um den Zonennamen: Hoehe so, dass Zeile 1 (plus Rand) in die gemessene Innenhoehe
        -- passt (x Verzierungsgroesse); ist der Name breiter als die Innenflaeche, werden die beiden Dehnstreifen
        -- breiter gezogen (Enden und Mitte bleiben unverzerrt). Zeile 2 und Untertitel stehen unter dem Rahmen.
        local size1 = f.line1Size or 44
        local h = (size1 + 2 * (S.marginY or 6)) / math.max(0.05, S.innerH) * k
        local wn = h * S.aspect
        local extra = math.max(0, w1 + 2 * (S.marginX or 20) - S.innerW * wn)
        local w = wn + extra
        local pad = (1 - S.fill) / 2 * h
        -- 5 Abschnitte: Ende, Dehnstreifen, Mitte, Dehnstreifen, Ende (nur die Dehnstreifen werden breiter)
        local u, d = S.stretchU, S.stretchW
        layoutPiece(st.a, S, { { 0, u, wn * u }, { u, u + d, wn * d + extra / 2, true }, { u + d, 1 - u - d, wn * (1 - 2 * u - 2 * d) },
            { 1 - u - d, 1 - u, wn * d + extra / 2, true }, { 1 - u, 1, wn * u } }, h, false, false, eff)
        st.a:ClearAllPoints()
        st.a:SetPoint("CENTER", f.line1, "CENTER", 0, 0)
        f.ornTex = { st.a }
        -- Zeile 2 unter den Rahmen; der Untertitel folgt Zeile 2 bzw. dem Rahmen
        local below = h * S.fill / 2 - size1 / 2 + (S.gap or 0) -- Rahmen unter der Unterkante von Zeile 1
        if f.line2:IsShown() then
            f.line2:ClearAllPoints()
            f.line2:SetPoint("TOP", st.a, "BOTTOM", 0, pad - (S.gap or 0))
        else
            f.subAnchor, f.subPad = st.a, pad - (S.gap or 0)
        end
        return math.max(Card.ORN_GAP, w / 2 - w1 / 2), math.max(0, below)
    elseif S and st then
        local w = math.min(S.max, math.max(S.min, w1 + S.extra)) * k
        local h = w / S.aspect
        local pad = (1 - S.fill) / 2 * h -- leerer Rand oben/unten in der Textur
        sizeOrn(st.a, S, nil, w, h, false, S.flipBottom and st.a.isPiece, eff)
        st.a:ClearAllPoints()
        st.a:SetPoint("TOP", lastLine, "BOTTOM", 0, -S.gap + pad)
        f.ornTex = { st.a }
        if st.b then
            sizeOrn(st.b, S, nil, w * S.top, h * S.top, false, S.flipTop and st.b.isPiece, eff)
            st.b:ClearAllPoints()
            st.b:SetPoint("BOTTOM", f.line1, "TOP", 0, S.gap - pad * S.top)
            f.ornTex[2] = st.b
        end
        f.subAnchor, f.subPad = st.a, pad
        return math.max(Card.ORN_GAP, w / 2 - w1 / 2), S.gap + h * S.fill
    end
    return Card.ORN_GAP + (f.ornLen or 0), 0
end

-- Untertitel setzen/ausblenden; liefert die Hoehe, die er unter der letzten Zeile braucht
local function setSubtitle(f, card, cfg)
    if card.subtitle then
        Card.ApplyFont(f.sub, cfg.discovery.font, cfg.discovery.size)
        f.sub:SetText(Zone.Clean(card.subtitle))
        f.sub:ClearAllPoints()
        local above = f.subAnchor or (f.line2:IsShown() and f.line2 or f.line1)
        f.sub:SetPoint("TOP", above, "BOTTOM", 0, -Card.SUB_GAP + (f.subAnchor and f.subPad or 0))
        f.sub:Show()
        return Card.SUB_GAP + cfg.discovery.size
    end
    f.sub:SetText("")
    f.sub:Hide()
    return 0
end

-- Lichtband nur bei der grossen Karte (mit Ornament): Breite ueber das Ornament hinaus, Hoehe ueber alle Zeilen
local function fitBands(f)
    local half = f.ornLen and (textWidth(f.line1) / 2 + f.ornExt + Card.BAND_PAD_X)
    for _, b in ipairs(f.bands) do
        if half and f.bandK > 0 then
            b.t:SetSize(2 * half, f.baseH + f.subH + 2 * b.padY)
            b.t:SetAlpha(b.alpha * f.bandK)
            b.t:Show()
        else
            b.t:Hide()
        end
    end
end

-- Glanz nur bei der grossen Karte und nur mit Animation-API: mittig hinter Zeile 1, etwas breiter als der Text
local function fitGlow(f, size)
    local g = f.glow
    f.glowOn = g ~= nil and f.ornLen ~= nil and f.A ~= nil and f.glowK > 0
    if not g then return end
    if f.glowOn then
        g:SetSize(textWidth(f.line1) + 2 * Card.GLOW.padX, size * Card.GLOW.height)
    end
    g:SetAlpha(0)
    g:SetShown(f.glowOn)
end

-- Frame-Groesse aus den Zeilen (auch nach einem nachgereichten Untertitel neu berechnet)
local function fit(f)
    local ext = math.max(Card.ORN_GAP + Card.ORN_MAX, f.ornExt or 0)
    local w = math.max(textWidth(f.line1), textWidth(f.line2), textWidth(f.sub)) + 2 * ext + 20
    f:SetSize(math.max(400, w), f.baseH + f.subH)
    fitBands(f)
end

local function layout(f, card, cfg)
    local t1 = cfg[card.lines[1].trigger] or (card.kind == "big" and cfg.zone or cfg.subzone)
    Card.ApplyFont(f.line1, t1.font, t1.size)
    f.line1:SetText(card.lines[1].text)
    local height = t1.size
    f.line1Size = t1.size
    -- Standardlage von Zeile 2 (der Rahmen-Stil setzt sie unter den Rahmen)
    f.line2:ClearAllPoints()
    f.line2:SetPoint("TOP", f.line1, "BOTTOM", 0, -Card.LINE2_GAP)
    if card.lines[2] then
        Card.ApplyFont(f.line2, cfg.subzone.font, cfg.subzone.size)
        f.line2:SetText(card.lines[2].text)
        f.line2:Show()
        height = height + Card.LINE2_GAP + cfg.subzone.size
    else
        f.line2:SetText("")
        f.line2:Hide()
    end
    local w1 = textWidth(f.line1)
    -- Zeilen unter Zeile 1 mit senkrechter Lage (relativ zur Mitte von Zeile 1, nach oben positiv) und Breite; das
    -- Layout "pair" haelt die Seiten davon fern. Der Untertitel wird dafuer schon hier gesetzt (setSubtitle wiederholt es).
    f.rows = {}
    local y = -t1.size / 2
    if card.lines[2] then
        local top = y - Card.LINE2_GAP
        y = top - cfg.subzone.size
        f.rows[#f.rows + 1] = { top = top, bottom = y, w = textWidth(f.line2) }
    end
    if card.subtitle then
        Card.ApplyFont(f.sub, cfg.discovery.font, cfg.discovery.size)
        f.sub:SetText(Zone.Clean(card.subtitle))
        local top = y - Card.SUB_GAP
        f.rows[#f.rows + 1] = { top = top, bottom = top - cfg.discovery.size, w = textWidth(f.sub) }
    end
    f.ornLen = card.ornament and math.min(Card.ORN_MAX, math.max(Card.ORN_MIN, Card.ORN_FACTOR * w1)) or nil
    -- Stil nur bei der grossen Karte; Textur fehlt => schlicht
    local style, mode
    if f.ornLen and card.motif then
        -- Testkarte eines bestimmten Motivs (/lucid zone test <motiv>): unabhaengig von Haken, Stil und Zone;
        -- Motiv ohne ladbare Textur => schlicht, Herkunft "missing" (der Aufrufer meldet es im Chat)
        style, mode = card.motif, "test"
        if not (Card.STYLES[style] and ensureStyle(f, style)) then style, mode = "simple", "missing" end
    elseif f.ornLen then
        style, mode = Card.ResolveOrnament(cfg, card.mapID, function(name) return ensureStyle(f, name) end)
        -- Textur des gewaehlten Stils nicht ladbar => schlicht (auch beim festen Stil, wie bisher)
        if Card.STYLES[style] and not ensureStyle(f, style) then style = "simple" end
    end
    f.ornStyle, f.ornMap, f.ornMode = style, card.mapID, mode
    local extH
    f.ornExt, extH = setOrnament(f, style, (tonumber(cfg.ornScale) or 100) / 100, w1,
        f.line2:IsShown() and f.line2 or f.line1, height)
    f.baseH = height + extH
    f.subH = setSubtitle(f, card, cfg)
    -- Staerke-Faktoren (Zone.GetConfig liefert geklemmte 0-100; aeltere Profile ohne Feld => Standard 50)
    f.ornDelay = tonumber(cfg.ornDelay) or 0.2
    f.ornFade = tonumber(cfg.ornFade) or 0.6
    f.glowK = (tonumber(cfg.glow) or 50) / 50
    f.bandK = (tonumber(cfg.band) or 50) / 50
    fitGlow(f, t1.size)
    fit(f)
end

local function timings(cfg, card)
    local t = cfg[card.trigger] or cfg.zone
    return t.fadeIn, t.hold, t.fadeOut
end

-- Zeitplan ----------------------------------------------------------------------------------------
-- f.anim haelt den Zeitplan der Karte (phase "in" | "out" | "retire"). Mit Animation-API zeichnet die Engine, der
-- Zeitplan dient nur der Entscheidung (Untertitel nachreichen, Abloesen); im Rueckfall treibt ihn fallbackUpdate.

-- Alpha des Rahmens in der Phase "out" rechnerisch (Rueckfall bzw. wenn der Client keinen Fortschritt liefert);
-- zweiter Wert true = Ausblenden vorbei
local function outAlphaAt(a, now)
    local e = now - a.outStart
    if e < a.rampDur then return a.rampFrom + (1 - a.rampFrom) * easeOut(math.max(0, e) / a.rampDur) end
    e = e - a.rampDur - a.delay
    if e <= 0 then return 1 end
    local u = e / a.fadeOut
    if u >= 1 then return 0, true end
    return 1 - u * u
end

-- aktuelles Alpha des Rahmens (ohne das Einblenden des Inhalts)
local function frameAlpha(f)
    local a, A, now = f.anim, f.A, GetTime()
    if not a then return f:GetAlpha() or 1 end
    if a.phase == "retire" then
        return a.retireFrom * math.max(0, 1 - (now - a.retireAt) / Card.RETIRE)
    elseif a.phase == "out" then
        if A then
            local e = now - a.outStart
            if e < a.rampDur then
                local p = smoothProgress(A.ramp)
                if p then return a.rampFrom + (1 - a.rampFrom) * p end
            elseif e < a.rampDur + a.delay then
                return 1
            else
                local p = smoothProgress(A.fadeOut)
                if p then return 1 - p end
            end
        end
        return (outAlphaAt(a, now))
    end
    if A then return 1 end -- Einblenden: der Rahmen steht auf 1, das Einblenden traegt der Inhalt
    return easeOut(math.max(0, math.min(1, (now - a.start) / a.fadeIn)))
end

-- Halten (Rest) + Ausblenden starten. from < 1: das Alpha steigt zuerst in SUB_FADE s weich auf 1 (nachgereichter
-- Untertitel waehrend des Ausblendens). Das Halten beginnt jetzt (bzw. bei at) neu.
local function startOut(f, from, at)
    local a = f.anim
    local rampDur = from < 1 and Card.SUB_FADE or Card.PRESET
    a.phase, a.outStart, a.rampFrom, a.rampDur = "out", at or GetTime(), from, rampDur
    a.delay = math.max(0, a.hold - rampDur)
    local A = f.A
    if not A then return end
    A.outGroup:Stop()
    f:SetAlpha(from)
    A.ramp:SetFromAlpha(from)
    A.ramp:SetDuration(rampDur)
    A.fadeOut:SetStartDelay(a.delay)
    A.fadeOut:SetDuration(a.fadeOut)
    A.outGroup:Play()
end

onInFinished = function(f)
    f.content:SetAlpha(1) -- Endzustand auch ohne SetToFinalAlpha
    local a = f.anim
    if a and a.phase == "in" then startOut(f, 1) end
end

local function startIn(f, big)
    local A, a, c = f.A, f.anim, f.content
    stopAnims(f)
    f.sub:SetAlpha(1)
    if not A then
        c:SetAlpha(1)
        f:SetAlpha(0)
        for _, t in ipairs(f.ornTex) do
            t:SetAlpha(f.ornSpec.alpha)
        end
        return
    end
    f:SetAlpha(1)
    c:SetAlpha(0)
    A.fadeIn:SetDuration(a.fadeIn)
    A.inGroup:Play()
    if big and A.zoomOk then
        A.zoom:SetDuration(a.fadeIn)
        A.zoomGroup:Play()
    end
    if f.ornStyle == "simple" then
        for _, l in ipairs(A.lines) do
            l.anim:SetDuration(a.fadeIn)
            l.group:Play()
        end
    end
    for _, t in ipairs(f.ornTex) do
        local o = A.orn[t]
        local spec = f.ornSpec
        local delay = f.ornDelay or 0
        t:SetAlpha(0)
        o.scale:SetStartDelay(delay)
        o.alpha:SetStartDelay(delay)
        -- Alpha easeOut (sofort sichtbar, weich auslaufend) ueber zone.ornFade s, Wachsen etwas laenger
        local fade = f.ornFade or 0.6
        o.scale:SetDuration(fade * 1.3)
        o.alpha:SetDuration(fade)
        o.group:Play()
    end
    if big and f.glowOn then
        local G = Card.GLOW
        local peak = G.alpha * f.glowK -- Staerke = Spitze der Animation
        for _, g in ipairs(A.glow) do
            g.tex:SetAlpha(0)
            g.rise:SetStartDelay(G.delay * a.fadeIn)
            g.rise:SetDuration(G.rise * a.fadeIn)
            g.rise:SetToAlpha(peak)
            g.decay:SetFromAlpha(peak)
            g.decay:SetDuration(G.decay)
            g.group:Play()
        end
    end
end

-- nachgereichten Untertitel einblenden
local function fadeSubIn(f)
    f.sub:SetAlpha(0)
    if f.A then
        f.A.subGroup:Stop()
        f.sub:SetAlpha(0)
        f.A.subGroup:Play()
    else
        f.anim.subAt = GetTime()
    end
end

local function retire(f)
    local a = f.anim
    if not a or a.phase == "retire" then return end
    local from = frameAlpha(f)
    a.phase, a.retireAt, a.retireFrom = "retire", GetTime(), from
    if f.A then
        f.A.outGroup:Stop()
        f:SetAlpha(from)
        f.A.retire:SetFromAlpha(from)
        f.A.retireGroup:Play()
    end
end

-- Rueckfall ohne Animation-API: nur Alpha des Rahmens, solange eine Karte laeuft
fallbackUpdate = function(f)
    local a = f.anim
    if not a then f:Hide() return end
    local now = GetTime()
    if a.phase == "retire" then
        local u = (now - a.retireAt) / Card.RETIRE
        if u >= 1 then finish(f) return end
        f:SetAlpha(a.retireFrom * (1 - u))
        return
    end
    if a.phase == "in" then
        local t = (now - a.start) / a.fadeIn
        if t < 1 then
            f:SetAlpha(easeOut(math.max(0, t)))
        else
            startOut(f, 1, a.start + a.fadeIn)
        end
    end
    if a.phase == "out" then
        local v, done = outAlphaAt(a, now)
        if done then finish(f) return end
        f:SetAlpha(v)
    end
    if a.subAt then
        local s = (now - a.subAt) / Card.SUB_FADE
        if s >= 1 then
            f.sub:SetAlpha(1)
            a.subAt = nil
        else
            f.sub:SetAlpha(math.max(0, s))
        end
    end
end

--- Karte zeigen. Ersetzt die laufende (die blendet in 0,3 s aus). upgrade = true: gleiche Zeilen wie die laufende
--- Karte, nur der Untertitel kommt hinzu (er blendet ein, die Karte haelt mit den Zeiten der Entdeckung neu).
function Card.Show(card, upgrade)
    if type(card) ~= "table" or type(card.lines) ~= "table" or not card.lines[1] then return nil end
    ensureFrames()
    local cfg = Zone.GetConfig()
    if upgrade and active and active.anim and active.sig == Zone.CardSig(card) then
        local f, a = active, active.anim
        f.subH = setSubtitle(f, card, cfg)
        fit(f) -- Breite und Hoehe neu (der Untertitel kann breiter sein als die Zeilen)
        local _, hold, fadeOut = timings(cfg, card)
        a.hold, a.fadeOut = hold, math.max(0.01, fadeOut)
        fadeSubIn(f)
        -- Halten beginnt neu. Lief schon das Ausblenden, springt das Alpha nicht hart auf 1, sondern steigt in
        -- SUB_FADE s vom aktuellen Wert weich an (gleichzeitig mit dem Einblenden des Untertitels). Im Einblenden
        -- gelten die neuen Zeiten ab dessen Ende.
        if a.phase == "out" then startOut(f, frameAlpha(f)) end
        return f
    end
    local old = active
    if old then retire(old) end
    local f
    for _, x in ipairs(frames) do
        if x ~= old and not x.anim then f = x break end
    end
    if not f then
        -- Drei Karten in Folge: beide Frames sind belegt (die vorletzte blendet noch aus, die letzte wurde eben
        -- abgeloest). Bewusst: die noch ausblendende vorletzte Karte endet hart (sofort versteckt), weil es nur zwei
        -- Frames gibt; sichtbar bleibt das kaum, sie stand ohnehin kurz vor dem Ende der 0,3-s-Ausblendung.
        f = (frames[1] ~= old) and frames[1] or frames[2]
        finish(f)
    end
    f.pos = cfg.pos
    f.sig = Zone.CardSig(card)
    layout(f, card, cfg)
    local fadeIn, hold, fadeOut = timings(cfg, card)
    f.anim = { phase = "in", start = GetTime(), fadeIn = math.max(0.01, fadeIn), hold = hold,
        fadeOut = math.max(0.01, fadeOut) }
    place(f)
    f:Show()
    startIn(f, card.ornament == true)
    Card.RememberDebug(f)
    active = f
    return f
end

-- Diagnose der Verzierungs-Texturen der zuletzt gezeigten Karte (/lucid zone debug)
function Card.RememberDebug(f)
    local out = {}
    for i, x in ipairs(f.ornTex or {}) do
        if x.debug then
            local d = x.debug
            out[#out + 1] = { style = f.ornStyle or "?", part = i, cw = d.cw, tiles = d.tiles, texW = d.texW, texH = d.texH,
                phys = d.phys, filter = d.filter, srcLimited = d.srcLimited }
        end
    end
    Card.lastDebug = { style = f.ornStyle, ppu = Card.PixelsPerUnit(), eff = effScale(f), parts = out,
        map = f.ornMap, mode = f.ornMode }
end

--- Diagnose-Zeilen (fuer Tests und /lucid zone debug)
function Card.DebugLines()
    local d = Card.lastDebug
    if not d then return { L.ZONE_DEBUG_NONE } end
    local lines = { L.ZONE_DEBUG_HEAD:format(tostring(d.style or "-"), d.eff, d.ppu) }
    if #d.parts == 0 then lines[2] = L.ZONE_DEBUG_NOPARTS end
    for _, p in ipairs(d.parts) do
        lines[#lines + 1] = L.ZONE_DEBUG_LINE:format(p.part, p.cw, p.tiles, p.texW, p.texH, p.phys, p.filter,
            p.cw >= p.phys - 0.5 and L.ZONE_DEBUG_OK or (p.srcLimited and L.ZONE_DEBUG_SRC or L.ZONE_DEBUG_LOW))
    end
    -- Zeile "Karte <uiMapID>, Motiv <name> (automatisch | fest | Rueckfall)": nur bei der grossen Karte
    if d.mode then
        lines[#lines + 1] = L.ZONE_DEBUG_MOTIF:format(d.map and tostring(d.map) or "-", tostring(d.style or "-"),
            L["ZONE_DEBUG_MODE_" .. d.mode] or d.mode)
    end
    return lines
end

Zone.commands.debug = function()
    for _, line in ipairs(Card.DebugLines()) do ns.Print(line) end
end
ns.AddHelp("HELP_ZONE_DEBUG")

--- alle Karten sofort beenden (Ladebildschirm, Profilwechsel, Modul aus)
function Card.Stop()
    if Card.StopSequence then Card.StopSequence() end -- laeuft /lucid zone test alle, endet auch die Reihe
    for _, f in ipairs(frames) do finish(f) end
    active = nil
end

--- laufende Karte (Frame) oder nil (Tests/Diagnose)
function Card.Active() return active end

-- Anschluss an Zone.lua: Zone.Present merkt weiter die Karten (Zone.shown) und zeichnet sie jetzt.
-- Ein Fehler beim Zeichnen geht an den Fehler-Handler des Clients und haelt die Auswertung nicht an.
do
    local record = Zone.Present
    function Zone.Present(card, upgrade)
        record(card, upgrade)
        local ok, err = pcall(Card.Show, card, upgrade)
        if not ok then geterrorhandler()(err) end
    end
    function Zone.Stop() Card.Stop() end
end

-- Ladebildschirm: der Bildschirm ist verdeckt, jede Karte (auch eine Testkarte) endet sofort
Compat.TryOn("LOADING_SCREEN_ENABLED", function() Card.Stop() end)

-- Testen ------------------------------------------------------------------------------------------
-- Testkarten gehen direkt an Zone.Present: keine Auswertung (Zone.Decide), keine Zeitstempel, kein Eintrag in die
-- Entdeckungsliste, lastZone bleibt. Text: echte Zone/Subzone, sonst Beispieltext.
local TEST_ALIASES = { [""] = "zone", zone = "zone", subzone = "subzone", entdeckung = "discovery", discovery = "discovery" }

local function readText(fn)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn)
    if not ok or Compat.IsSecret(v) or type(v) ~= "string" or v == "" then return nil end
    return v
end

--- Testausloeser aus Eingabe ("", zone, subzone, entdeckung, discovery) oder nil
function Card.TestTrigger(arg)
    return TEST_ALIASES[(arg or ""):lower()]
end

-- Motiv-Tests (/lucid zone test <motiv> | alle | stop) ---------------------------------------------
-- Name-Vergleich: Kleinschreibung, ohne Leerzeichen und Satzzeichen ("Wald von Elwynn" = "waldvonelwynn")
local function norm(s)
    if type(s) ~= "string" then return "" end
    return (s:lower():gsub("[%s%p]", ""))
end

--- Motiv aus Eingabe: Motivname aus ZoneMotifs.order oder Anzeigename (deDE/enUS/aktuelle Sprache), sonst nil
function Card.TestMotif(arg)
    local key = norm(arg)
    if key == "" then return nil end
    local order = (ns.ZoneMotifs or {}).order
    if type(order) ~= "table" then return nil end
    for _, name in ipairs(order) do
        if norm(name) == key then return name end
    end
    local langs = {}
    for _, lang in ipairs({ "deDE", "enUS" }) do langs[#langs + 1] = (ns.Locales or {})[lang] end
    langs[#langs + 1] = L
    for _, name in ipairs(order) do
        for _, loc in ipairs(langs) do
            if norm(loc["ZONE_ORNAMENT_" .. name]) == key then return name end
        end
    end
    return nil
end

--- Anzeigename des Motivs (aktuelle Sprache), sonst der Motivname
function Card.MotifLabel(motif)
    local label = L["ZONE_ORNAMENT_" .. tostring(motif)]
    return type(label) == "string" and label ~= "" and label or tostring(motif)
end

--- uiMapIDs des Motivs: Tabellenreihenfolge (ZoneMotifs.ids), sonst aufsteigend aus byMap
local function motifMapIds(motif)
    local M = ns.ZoneMotifs or {}
    if type(M.ids) == "table" and type(M.ids[motif]) == "table" then return M.ids[motif] end
    local ids = {}
    for id, name in pairs(M.byMap or {}) do
        if name == motif then ids[#ids + 1] = id end
    end
    table.sort(ids)
    return ids
end

--- Titel und Karte der Test-Karte: Name der ersten Zone des Motivs (lokalisiert, falls der Client einen liefert),
--- sonst das Motiv-Label; zweite Rueckgabe: uiMapID der Zone (oder die erste ID)
function Card.MotifTitle(motif)
    local ids = motifMapIds(motif)
    if C_Map and C_Map.GetMapInfo then
        for _, id in ipairs(ids) do
            local ok, info = pcall(C_Map.GetMapInfo, id)
            local name = ok and type(info) == "table" and info.name or nil
            if type(name) == "string" and not Compat.IsSecret(name) and name ~= "" then return name, id end
        end
    end
    return Card.MotifLabel(motif), ids[1]
end

--- Testkarte eines bestimmten Motivs abspielen (grosse Karte, unabhaengig von Haken und aktueller Zone); fehlt die
--- Textur, meldet der Chat es und die Karte zeigt ersatzweise den schlichten Stil. Liefert die Karte oder nil.
function Card.TestMotifCard(motif)
    if type(motif) ~= "string" then return nil end
    local cfg = Zone.GetConfig()
    local title, mapID = Card.MotifTitle(motif)
    local label = Card.MotifLabel(motif)
    local function ln(text, trigger) return { text = Zone.Clean(text), trigger = trigger } end
    local card = { kind = "big", ornament = true, trigger = "zone", motif = motif, mapID = mapID, lines = { ln(title, "zone") } }
    if cfg.subzone.on then card.lines[2] = ln(label, "subzone") end
    card.stamps, card.test = {}, true
    Zone.Present(card)
    local f = active
    if f and f.ornMode == "missing" then ns.Print(L.ZONE_TEST_MOTIF_MISSING, Zone.Esc(label)) end
    return card
end

local seq = nil -- laufende Reihe { n = naechstes Motiv } oder nil; nur ein Zeitgeber je Schritt (kein Ticker)

--- laufende Reihe beenden (true, wenn eine lief); die Karte selbst bleibt (Card.Stop beendet beides)
function Card.StopSequence()
    local was = seq ~= nil
    seq = nil
    return was
end

function Card.SequenceRunning() return seq ~= nil end

local function seqStep(run)
    if seq ~= run then return end
    local order = (ns.ZoneMotifs or {}).order or {}
    local motif = order[run.n]
    if not motif then
        seq = nil
        ns.Print(L.ZONE_TEST_ALL_DONE, #order)
        return
    end
    ns.Print(L.ZONE_TEST_ALL_STEP, run.n, #order, Zone.Esc(Card.MotifLabel(motif)))
    Card.TestMotifCard(motif)
    if seq ~= run then return end -- Present hat die Reihe beendet (z. B. Fehler)
    run.n = run.n + 1
    -- naechstes Motiv erst, wenn die Karte ausgeblendet ist: Gesamtdauer der Karte + 0,5 s
    local cfg = Zone.GetConfig()
    local gap = (tonumber(cfg.zone.fadeIn) or 0) + (tonumber(cfg.zone.hold) or 0) + (tonumber(cfg.zone.fadeOut) or 0) + 0.5
    if C_Timer and C_Timer.After then
        C_Timer.After(gap, function() seqStep(run) end)
    else
        seq = nil
    end
end

--- alle Motive in der Reihenfolge von ZoneMotifs.order nacheinander abspielen (ersetzt eine laufende Reihe)
function Card.TestAll()
    local order = (ns.ZoneMotifs or {}).order
    if type(order) ~= "table" or #order == 0 then return false end
    local run = { n = 1 }
    seq = run
    seqStep(run)
    return true
end

--- synthetische Karte fuer einen Ausloeser ("zone" | "subzone" | "discovery") abspielen; liefert die Karte
function Card.Test(which)
    if which ~= "zone" and which ~= "subzone" and which ~= "discovery" then return nil end
    Card.StopSequence() -- eine einzelne Testkarte beendet die Reihe
    local cfg = Zone.GetConfig()
    local zone = readText(GetZoneText) or L.ZONE_SAMPLE_ZONE
    local sub = readText(GetSubZoneText)
    if not sub or sub == zone then sub = L.ZONE_SAMPLE_SUBZONE end
    local function ln(text, trigger) return { text = Zone.Clean(text), trigger = trigger } end
    local card
    if which == "subzone" then
        card = { kind = "small", ornament = false, trigger = "subzone", lines = { ln(sub, "subzone") } }
    else
        card = { kind = "big", ornament = true, trigger = which, lines = { ln(zone, "zone") }, mapID = Zone.CurrentMapId() }
        if cfg.subzone.on then card.lines[2] = ln(sub, "subzone") end
        if which == "discovery" then card.subtitle = L.ZONE_DISCOVERED end
    end
    card.stamps, card.test = {}, true
    Zone.Present(card)
    return card
end

Zone.commands.test = function(arg)
    arg = arg or ""
    local key = arg:lower()
    if key == "stop" then
        local was = Card.StopSequence()
        Card.Stop()
        ns.Print(was and L.ZONE_TEST_STOPPED or L.ZONE_TEST_NOTHING)
        return
    end
    if key == "alle" or key == "all" then
        Card.TestAll()
        return
    end
    local which = Card.TestTrigger(arg)
    if which then
        Card.Test(which)
        return
    end
    local motif = Card.TestMotif(arg)
    if motif then
        Card.StopSequence()
        Card.TestMotifCard(motif)
        return
    end
    ns.Print(L.ZONE_TEST_INVALID, Zone.Esc(arg))
end
ns.AddHelp("HELP_ZONE_TEST")
