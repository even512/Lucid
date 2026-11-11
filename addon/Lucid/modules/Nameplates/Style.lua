-- Plaketten-Stil (Delta "Immersiver Plaketten-Stil"): Skin-Engine fuer Blizzards Namensplaketten.
-- Bausteine mit Wirkung: 1 Bronze-Rahmen (schmaler Balken im Schlitz eines Bronze-Rahmens aus Gemini-Vorlage,
-- Blizzards Rand und gelbe Ziel-/Bedrohungs-Hervorhebung aus), 2 Glutfarben nach Haltung, 3 Schrift (Name links ueber
-- dem Balken, Farbe nach Haltung, Schatten), 4 Balken nur bei Bedarf, 5 Friedlich nur Name, 6 Ziel-Glut,
-- 7 Glimmen bei wenig Leben, 8 Stufe & Rang (Plaettchen, Drachen-Medaille Elite/Rar, Totenkopf), 9 Quest-Zeichen,
-- 10 Tiefe (Plaketten-CVars ueber eine eigene Instanz des CVar-Treibers), 11 Zauberfaden.
--
-- Etappe 4a: Rang aus UnitClassification/UnitLevel (lesbar); Quest-Siegel aus C_QuestLog.UnitIsRelatedToActiveQuest
-- (lesbar, neu bei QUEST_LOG_UPDATE/UNIT_QUEST_LOG_CHANGED, gedrosselt); Tiefe ueber CVarDriver "nameplatestyle"
-- (Sicherung/owned-Marker/Kampfpuffer, Ausschalten/Abmelden stellt zurueck); Zauberfaden: Blizzards Zauberleiste
-- haengt im Schlitz eines eigenen Zauberleisten-Rahmens (np-castframe, Laschen am Lebensbalken-Rahmen), ihre
-- Regionen werden unsichtbar (Alpha 0, wiederherstellbar) und ein eigener Faden (Kind-Frame der Leiste, erbt deren
-- Sichtbarkeit und Ausblenden) haengt an ihrer Fuellungs-Textur - der Fortschritt wird nie gelesen. Zaubername und
-- "nicht unterbrechbar" kommen aus UnitCastingInfo/UnitChannelInfo und gehen unveraendert an SetText bzw.
-- SetAlphaFromBoolean. /lucid nameplates style cast zeigt denselben Faden an einer Lucid-eigenen Leiste (Simulation).
--
-- Etappe 3 (Bausteine 4/5/7): Rahmen, Roehre, Ziel-Schein und Stufen-Plaettchen liegen in einem Unter-Frame "bars" des
-- Containers (der Name nicht). Volles Leben ist secret (UnitHealthPercent): "bars" bekommt als Alpha den Kurvenwert
-- UnitHealthPercent(unit, false, Kurve) mit der Kurve (0,1) (DEMAND.full,1) (1,a) - a ist das Alpha bei vollem Leben
-- (0 = nur Name, 1 = Balken); der Client rechnet, Lucid vergleicht nie. Kampf (lesbar, PLAYER_REGEN_*) und Ziel heben a
-- auf 1, das Ein-/Ausblenden laeuft ueber a in DEMAND.steps Stufen (je Stufe eine wiederverwendete Kurve), so blendet
-- ein schon verletzter Gegner nicht kurz aus. Friedliche NPCs (UnitCanAttack false, kein Spieler/Spieler-Begleiter)
-- verstecken "bars" ganz und Blizzards Balken (Alpha 0), Name kleiner und blass. Glimmen: eigene Lage in einem
-- Unter-Frame der Roehre, Frame-Alpha = Kurve(Leben) secret (1 unter EMBER.threshold, sonst 0), Textur-Alpha pulsiert
-- ueber den Treiber. Scheitert der Kurvenweg, bleibt der Balken still immer sichtbar und das Glimmen aus.
--
-- Stil aus = Plaketten exakt wie Blizzard: solange der Stil nie an war (auch keine Vorschau), wird nichts angefasst; nur
-- die Nachher-Hooks auf NamePlateUnitFrameMixin stehen schon ab dem Laden (sie beenden sich ohne Stil sofort), die
-- uebrigen Hooks kommen erst beim ersten Einschalten. Ausschalten stellt Textur/Atlas, Farbe, Schrift, Anker und Hoehe des Balkens und des Namens,
-- Blizzards Rand, Hervorhebungen und Stufenanzeige sofort wieder her (Originale werden beim Anwenden gemerkt und
-- nachgefuehrt, wenn Blizzard selbst etwas aendert; Zustand in einer Schwachschluessel-Tabelle).
--
-- Taint: nur hooksecurefunc-Nachher-Hooks (einmal installiert, beim ersten Bedarf), keine Felder auf Blizzard-Frames,
-- keine ersetzte Methode, nur eigene Frames als Overlay (Elternteil UnitFrame). Die CompactUnitFrame_*-Funktionen
-- laufen auch fuer Raid-/Gruppenrahmen: der Hook reagiert nur auf UnitFrames von Plaketten (unit "nameplateN" und von
-- C_NamePlate bestaetigt). Forbidden Plaketten werden uebersprungen. Jeder Hook-Rumpf laeuft per pcall, Fehler landen
-- in /lucid nameplates style debug. Secret Values werden nie verglichen, nur unveraendert an Blizzards Setter
-- zurueckgereicht. Schreibzugriffe gehen laut S0 auch im Kampf (kein Puffer). Die Sichtbarkeit (Plates.lua,
-- UnitFrame-Alpha) bleibt unberuehrt.
local ADDON_NAME, ns = ...
local Compat, Nameplates = ns.Compat, ns.Nameplates
local L = ns.L

local Style = {}
ns.NameplateStyle = Style
Nameplates.Style = Style

local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"
Style.FILL_TEX = MEDIA .. "np-fill"
Style.FRAME_TEX = MEDIA .. "np-frame"
Style.LEVEL_TEX = MEDIA .. "np-level"
Style.GLOW_TEX = MEDIA .. "np-glow"
-- Lebensfluessigkeit aus der Vorlage np-liquid-v1 (waagrecht nahtlos): farbig (feindlich) und entsaettigt (zum Toenen)
Style.FLOW_TEX = MEDIA .. "np-liquid"
Style.FLOW_TEX_MONO = MEDIA .. "np-liquid-mono"
-- Rahmen-Textur (scripts/gen-nameplate-media.mjs): Breite, Hoehe, Kappenbreite und Lage des durchsichtigen Schlitzes
-- (Bandstaerke oben/unten, Einzug links/rechts) in Textur-Pixeln; der Test misst die Datei nach
Style.FRAME_GEOMETRY = { w = 256, h = 32, cap = 32, top = 7, bottom = 6, left = 22, right = 22 }
-- Bausteine mit Wirkung (ein Teil von 8 vorgezogen)
Style.IMPLEMENTED = { frame = true, colors = true, font = true, barOnDemand = true, peaceful = true, targetGlow = true,
    lowHealth = true, levelRank = true, questSeal = true, depth = true, castThread = true }
-- Baustein 8: Zier-Texturen (Platzhalter bis zur Freigabe der Gemini-Vorlagen, scripts/gen-nameplate-media.mjs)
Style.ELITE_TEX = MEDIA .. "np-elite"
Style.RARE_TEX = MEDIA .. "np-rare"
Style.SKULL_TEX = MEDIA .. "np-skull"
Style.QUEST_TEX = MEDIA .. "np-quest"
-- diff: "deutlicher Unterschied" ab so vielen Stufen; skull: Totenkopf im Plaettchen (Anteil der Plaettchenhoehe).
-- Elite/Rar (Freigabe, Layout R2): das normale Plaettchen mit Zahl/Totenkopf bleibt; die Drachen-Medaille
-- (np-elite/np-rare, quadratisch, Hoehe medal x Rahmenhoehe; 3,0 per Vorschau preview-zier2.png) liegt dahinter, ihre Scheibenmitte disc (Anteile der Textur,
-- aus scripts/gen-nameplate-media.mjs decorDisc gemessen; der Test prueft sie nach) auf der Plaettchenmitte, um shift x
-- Medaillenhoehe nach rechts versetzt - das Plaettchen verdeckt die Scheibe, Fluegel/Kopf/Schwanz ragen heraus.
Style.RANK = { diff = 3, skull = 0.8, medal = 3.0, shift = 0.13, disc = { x = 0.34, y = 0.4748 } }
-- Baustein 11: Zauberleisten-Rahmen (Freigabe np-castframe-v1, 3-teilig wie np-frame; Lage im Rahmen in
-- Textur-Pixeln, scripts/gen-nameplate-media.mjs measureCastSlit, der Test misst die Datei nach) und Schild (np-shield)
Style.CASTFRAME_TEX = MEDIA .. "np-castframe"
Style.SHIELD_TEX = MEDIA .. "np-shield"
-- Zauber-Magie (Freigabe np-castmagic-v1): orange-gold bzw. grau (silbrig getoent, nicht unterbrechbar); Funken-Flash
-- an der fuellenden Kante (np-spark-v1, additiv)
Style.CASTMAGIC_TEX = MEDIA .. "np-castmagic"
Style.CASTMAGIC_MONO_TEX = MEDIA .. "np-castmagic-mono"
Style.SPARK_TEX = MEDIA .. "np-spark"
-- Animation: zwei Lagen stroemen nach rechts (Zauberrichtung; speedA/speedB Texturbreiten/s, repeatA/B Texturbreiten ueber
-- die Fuellung, vA/vB/vSpan Ausschnitt wie bei der Lebensfluessigkeit), Lage B (additiv, gespiegelt) laesst die Runen
-- aufglimmen (bBase +- bAmp, Periode bPeriod); Funken: Hoehe sparkSize x Rahmenhoehe, Streifen bei sparkStreak der
-- Texturbreite (gemessen, gen-nameplate-media.mjs) auf der Fuellungskante, Flackern zwischen sparkMin und sparkMax
-- (Runde 2, Textur im Spiel nicht erkennbar: schneller, Lage B kraeftiger, Leiste hoeher ueber CAST.frameScale)
-- (Runde 3, R2 "zu wild": Tempo 1,4 x der ersten Fassung, Lage B moderat)
Style.CAST_ANIM = { repeatA = 0.5, repeatB = 0.7, speedA = 0.084, speedB = 0.14, vA = 0.0625, vB = 0.5625, vSpan = 0.375,
    aAlpha = 0.95, bBase = 0.38, bAmp = 0.3, bPeriod = 1.4, sparkStreak = 0.6171875, sparkSize = 1.8,
    sparkMin = 0.7, sparkMax = 1.0, sparkRate = 11 }
Style.CAST_GEOMETRY = { w = 256, h = 32, cap = 32, bandTop = 10, top = 15, bottom = 4, left = 15, right = 15 }
-- Faden im Schlitz des Rahmens: frameScale = Rahmenhoehe (mit Laschen) / Hoehe des Lebensbalken-Rahmens; inset = Einzug je
-- Seite (Anteil der Lebensbalken-Rahmenhoehe; 0 = Kappen unter den Kappen, 0,4 nach Vorschau preview-cast.png); dock = so viele UI-Einheiten ragen die Laschen
-- hinter die Unterkante des Lebensbalken-Rahmens ("eingehaengt"); shield = Schildhoehe / Rahmenhoehe (auf der linken
-- Kappe); halo/Glutfarbe/silbrig/Name wie bisher
Style.CAST = { frameScale = 1.1, inset = 0.4, dock = 1, shield = 1.25, halo = 2, color = { 1.0, 0.50, 0.16 }, haloAlpha = 0.45,
    silver = { 0.80, 0.82, 0.88 }, track = { 0.10, 0.05, 0.03, 0.55 }, nameDelta = -3, nameMin = 7, tick = 0.1,
    simDefault = 3, simMin = 0.5, simMax = 30, nameMax = 40 }
-- Baustein 4: ab full gilt das Leben als voll (Muster Spielerrahmen "hurt"), Blende fade s in steps Stufen
Style.DEMAND = { full = 0.99999, steps = 8, fade = 0.25 }
-- Baustein 5: Name kleiner (sizeDelta), blass (alpha; als Ziel voll), Schleier nur noch angedeutet, Farbe gedaempft
Style.PEACEFUL = { sizeDelta = -2, minSize = 6, alpha = 0.6, veilAlpha = 0.12,
    colors = { friendly = { 0.74, 0.76, 0.62 }, neutral = { 0.80, 0.72, 0.56 } } }
-- Baustein 7: unter threshold (Lebensanteil; Standard 20 % = Execute-Bereich, Profilwert style.lowHealth.threshold) glimmt eine helle Lage ueber der Fluessigkeit, Alpha pulsiert 0 bis alphaMax
-- Runde 3 (Glimmen kaum zu sehen): wärmer/heller (additiv), Puls alphaMin bis alphaMax statt 0 bis 0,5
Style.EMBER = { threshold = 0.20, color = { 1.0, 0.74, 0.38 }, alphaMin = 0.15, alphaMax = 0.70, period = 1.8 }

-- Glutfarben nach Haltung (Baustein 2), mit dem warmen Verlauf der Fuellung multipliziert
Style.COLORS = { -- mit der matten Fuellung (Rost/Kohle, glimmende Oberkante) multipliziert
    hostile = { 0.92, 0.44, 0.17 },  -- Glut
    neutral = { 0.90, 0.62, 0.22 },  -- bernstein
    friendly = { 0.50, 0.62, 0.34 }, -- gedaempftes Moosgruen
    tapped = { 0.50, 0.47, 0.45 },   -- grau-asche
}
-- Namensfarben nach Haltung (Baustein 3): warm, wie die Vorlage
Style.NAME_COLORS = { -- gedaempftes Pergament-Gold (Wahl R7: Variante B), angeschlagen grau
    hostile = { 0.90, 0.80, 0.60 },
    neutral = { 0.90, 0.80, 0.60 },
    friendly = { 0.90, 0.80, 0.60 },
    tapped = { 0.66, 0.64, 0.60 },
}
-- eigener Name: Einzug/Abstand zum Rahmen, weicher dunkler Schatten statt dicker Kontur
-- (Wahl R7, Variante B): ohne Kontur, weicher dunkelbrauner Schatten; dahinter ein weicher Tinten-Schleier
-- (np-veil, dunkle Vertexfarbe, Alpha veilAlpha), der ueber veilPadX/veilPadY um den Text auslaeuft
Style.NAME = { x = 2, y = 1, flags = "", shadow = { 0.08, 0.04, 0.016, 0.8 }, shadowX = 1, shadowY = -1,
    veil = { 0.05, 0.03, 0.012 }, veilAlpha = 0.38, veilPadX = 16, veilPadY = 6 }
Style.VEIL_TEX = MEDIA .. "np-veil"
Style.FONT_COLOR = { 0.93, 0.84, 0.62 }                 -- warmes Pergament-Gold (Haltung nicht lesbar)
Style.LEVEL_COLOR = { 0.95, 0.86, 0.66 }
Style.BACK_COLOR = { 0.024, 0.016, 0.012, 0.88 }        -- nur noch fuer aeltere Vorschauen (preview-nameplate.mjs)
-- Ziel-Schein (Baustein 6): eng, weich, dunkles Glut-Orange, normales Mischen (ADD wuerde auf hellem Boden gelb),
-- atmet langsam zwischen alphaMin und alphaMax. Textur np-glow (w x h, Kappen cap, Rand inner) in Textur-Pixeln.
Style.GLOW = { w = 64, h = 32, cap = 16, inner = 9, color = { 0.86, 0.36, 0.10 }, alphaMin = 0.55, alphaMax = 0.80, period = 2 }
-- Lebendige Fuellung (Runde 5): stroemende Lebensfluessigkeit. Zwei Lagen derselben Textur fliessen in dieselbe
-- Richtung mit verschiedenen, langsamen Geschwindigkeiten (speedA/speedB in Texturbreiten/s), B gespiegelt und
-- versetzt; beide wogen leicht senkrecht (sway, Perioden swayA/swayB in s; gezeigt wird die halbe Texturhoehe) und
-- pulsieren in der Helligkeit mit verschiedenen Perioden. A (normal gemischt) traegt das Bild, B (additiv) laesst
-- Lichtfaeden aufscheinen. Jede Lage zeigt hoechstens 0,75 Texturbreiten (keine sichtbaren Wiederholungen); der
-- Ausschnitt ist so flach zugeschnitten, dass das Bild bei 5 px Hoehe nicht in Streifen zerfaellt.
Style.ANIM = {
    -- Textur: obere Haelfte = ruhiger Ausschnitt A, untere = Ausschnitt B (gen-nameplate-media.mjs LIQUID); je Lage
    -- wird vSpan der Hoehe gezeigt (ab vA/vB, +-sway), repeatA/repeatB Texturbreiten ueber die Fuellung (<= 0,75)
    repeatA = 0.55, repeatB = 0.75, vA = 0.0625, vB = 0.5625, vSpan = 0.375,
    speedA = 0.010, speedB = 0.017, sway = 0.03, swayA = 6.3, swayB = 7.9,
    aAlpha = 0.92, aBright = 0.86, aPulse = 0.14, aPeriod = 3.1, bBase = 0.2, bAmp = 0.14, bPeriod = 4.7,
    edgeBase = 0.35, edgeAmp = 0.15, edgeRate = 3.1,
}
-- Haltung: feindlich = farbige Textur; sonst die entsaettigte Textur, per Vertexfarbe getoent
Style.FLOW_TINT = {
    hostile = { tex = "color", color = { 1, 1, 1 } },
    neutral = { tex = "mono", color = { 1.0, 0.70, 0.28 } },   -- bernstein
    friendly = { tex = "mono", color = { 0.52, 0.74, 0.38 } }, -- moosgruen
    tapped = { tex = "mono", color = { 0.58, 0.55, 0.52 } },
}
Style.EDGE_COLOR = { 1.0, 0.80, 0.68 }                 -- Meniskus: heller weicher Saum an der Oberflaeche
-- Roehre (Runde 8, Wahl C; Teile schaltbar unter Baustein 1): Schlitz-Hintergrund (Verlauf oben/unten),
-- Meniskus, innerer Schatten, Glasglanz (gerade sichtbar); das Fuellungsende bleibt eine normale Schnittkante (R9)
Style.TUBE = {
    backTop = { 0.13, 0.04, 0.03, 0.90 }, backBottom = { 0.06, 0.02, 0.015, 0.94 },
    meniscusHeight = 1,
    insetAlpha = 0.75, glassAlpha = 0.22, glassTop = 0.12, glassHeight = 0.16,
    underX = 4, underY = 2, -- Textur-Pixel unter das Rahmenband (kleiner als Band oben 7 / Kappe 22, siehe FRAME_GEOMETRY)
}
Style.MASK_TEX = MEDIA .. "np-mask-capsule"
Style.INSET_TEX = MEDIA .. "np-inset"
Style.GLASS_TEX = MEDIA .. "np-glass"
-- Endblende (Etappe 3): Maske ueber dem Schlitz, laesst Meniskus und Glasglanz zu beiden Roehrenenden weich auslaufen
Style.ENDFADE_TEX = MEDIA .. "np-endfade"
Style.FONT_FLAGS = "OUTLINE"                            -- duenne Kontur ...
Style.SHADOW = { color = { 0, 0, 0, 0.9 }, x = 1, y = -1 } -- ... plus Schatten (Lesbarkeit)
Style.FRAME_EXTRA = 6                                   -- Rahmenhoehe = Balkenhoehe + 6 (Fuellung 5 -> Rahmen 11)

local states = setmetatable({}, { __mode = "k" }) -- UnitFrame -> Zustand (Originale, angewendete Bausteine, Overlay)
local active = false   -- Modul aktiv (nach PLAYER_LOGIN)
local cfg = nil        -- zwischengespeicherte Stil-Einstellungen (Refresh), damit der Hook-Pfad billig bleibt
local testActive = false
local testFrame = nil  -- UnitFrame der aktuellen Ziel-Plakette in der Vorschau
-- Vorschau "klebrig": jede Plakette, die in der Vorschau gestylt wurde, bleibt es, bis sie fuer eine andere Einheit
-- wiederverwendet wird (naechstes Hinzufuegen) oder die Vorschau endet - nie mitten in Blizzards Ausblenden nach dem
-- Abwaehlen zurueckstellen (die Spur zeigte: wantFor wurde beim Abwaehlen false, Blizzard-Optik waehrend des Ausblendens)
local testSticky = setmetatable({}, { __mode = "k" })
local hooksInstalled = false
local hookStatus = {}  -- Funktionsname -> "ok" | "missing" | "failed"
local errors = {}      -- letzte Fehler (hoechstens MAX_ERRORS)
local errorCount = 0
local MAX_ERRORS = 5

local function recordError(err)
    errorCount = errorCount + 1
    errors[#errors + 1] = string.sub(tostring(err), 1, 160)
    while #errors > MAX_ERRORS do table.remove(errors, 1) end
end

-- Fremd-Plaketten-Addons: ist eines geladen, bleiben Stil und Vorschau aus (die Sichtbarkeitsregeln laufen weiter)
Style.CONFLICT_ADDONS = { "Plater", "Kui_Nameplates", "TidyPlates", "TidyPlates_ThreatPlates", "Platynator", "ElvUI" }
local blocker = nil    -- Name des blockierenden Addons oder nil (berechnet in Refresh, nicht im Hook-Pfad)

local function addonLoaded(name)
    local fn = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
    if type(fn) ~= "function" then return false end
    local ok, v = pcall(fn, name)
    return ok and (v == true or v == 1)
end

--- ElvUI blockiert nur mit aktivem Plaketten-Modul; ist die Einstellung nicht lesbar, gilt "geladen" als aktiv
local function elvNameplatesOn()
    local ok, on = pcall(function()
        local E = _G.ElvUI and _G.ElvUI[1]
        local np = E and E.private and E.private.nameplates
        if type(np) ~= "table" or type(np.enable) ~= "boolean" then return true end
        return np.enable
    end)
    return not ok or on ~= false
end

--- Name des geladenen Fremd-Plaketten-Addons oder nil
function Style.Conflict()
    for _, name in ipairs(Style.CONFLICT_ADDONS) do
        if addonLoaded(name) and (name ~= "ElvUI" or elvNameplatesOn()) then return name end
    end
    return nil
end

local function engaged() return active and cfg ~= nil and not blocker and (cfg.enabled or testActive) end

local function field(t, key)
    if type(t) ~= "table" then return nil end
    local ok, v = pcall(function() return t[key] end)
    if ok then return v end
    return nil
end

local function call(obj, method, ...)
    local fn = field(obj, method)
    if type(fn) ~= "function" then return false end
    return pcall(fn, obj, ...)
end

-- Plaketten erkennen ---------------------------------------------------------------------------------
local function plateForUnit(unit)
    if not (C_NamePlate and type(C_NamePlate.GetNamePlateForUnit) == "function") then return nil end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if not ok or type(plate) ~= "table" then return nil end
    if Compat.QueryBool(plate, "IsForbidden") == true then return nil end
    return plate
end

--- Zustand eines Plaketten-UnitFrames (neu angelegt beim ersten Anfassen) oder nil fuer alles andere
--- (Raid-/Gruppenrahmen, forbidden, nicht bestaetigt).
local function stateFor(uf)
    if type(uf) ~= "table" then return nil end
    local st = states[uf]
    if st then
        if Compat.QueryBool(uf, "IsForbidden") == true then return nil end
        return st
    end
    local unit = rawget(uf, "unit")
    if type(unit) ~= "string" or not unit:find("^nameplate") then return nil end
    if Compat.QueryBool(uf, "IsForbidden") == true then return nil end
    local plate
    if C_NamePlate and type(C_NamePlate.GetNamePlateForUnit) == "function" then
        plate = plateForUnit(unit)
        if not plate or field(plate, "UnitFrame") ~= uf then return nil end
    else
        local ok, p = call(uf, "GetParent")
        plate = ok and p or nil
    end
    if type(plate) ~= "table" then return nil end
    st = { plate = plate, hidden = {} }
    states[uf] = st
    return st
end

local function frameOfUnit(unit)
    local plate = plateForUnit(unit)
    local uf = field(plate, "UnitFrame")
    if type(uf) ~= "table" or Compat.QueryBool(uf, "IsForbidden") == true then return nil end
    return uf
end

local function healthBar(uf)
    local hb = field(uf, "healthBar")
    if type(hb) ~= "table" then hb = field(field(uf, "HealthBarsContainer"), "healthBar") end
    return type(hb) == "table" and hb or nil
end

--- Konfiguration fuer diesen Frame: Stil an (alle Plaketten) oder Vorschau (nur Ziel-Plakette), sonst nil
local function wantFor(uf)
    if not active or not cfg or blocker then return nil end
    if cfg.enabled or (testActive and (uf == testFrame or testSticky[uf])) then return cfg end
    return nil
end

local function partOn(c, name)
    if not c or not Style.IMPLEMENTED[name] then return false end
    local p = c[name]
    return type(p) == "table" and p.enabled == true
end

-- Gemeinsame Helfer ----------------------------------------------------------------------------------
local function readFlag(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, ...)
    if not ok or Compat.IsSecret(v) then return nil end
    return v
end

local function near(a, b) return math.abs(a - b) < 0.1 end

--- Masse der Plakette aus der Balkenhoehe (auch fuer scripts/preview-nameplate.mjs): Rahmenhoehe = Balken + FRAME_EXTRA,
--- die Fuellung sitzt mittig im (etwas hoeheren) Schlitz. Raender um den Balken, Kappenbreite, Schlitz-Ueberstand,
--- Stufen-Plaettchen (kaum hoeher als der Rahmen) in UI-Einheiten.
function Style.Layout(height)
    local G = Style.FRAME_GEOMETRY
    local total = height + Style.FRAME_EXTRA
    local scale = total / G.h
    local slit = (G.h - G.top - G.bottom) * scale
    local extra = math.max(0, (slit - height) / 2)
    local levelH = total + 2
    return {
        scale = scale, total = total, cap = G.cap * scale, slit = slit, slitExtra = extra,
        padL = G.left * scale, padR = G.right * scale, padT = G.top * scale + extra, padB = G.bottom * scale + extra,
        levelH = levelH, levelW = levelH * 2, levelFont = math.max(8, levelH - 4),
        -- Ziel-Schein: Rand um den Rahmen (Textur-Rand inner/(h - 2 inner) der Rahmenhoehe), Kappen rund
        glowPad = total * Style.GLOW.inner / (Style.GLOW.h - 2 * Style.GLOW.inner),
        glowCap = (total + 2 * total * Style.GLOW.inner / (Style.GLOW.h - 2 * Style.GLOW.inner)) * Style.GLOW.cap / Style.GLOW.h,
    }
end

--- Haltung der Einheit: "hostile" | "neutral" | "friendly" | "tapped" | nil (nicht lesbar)
function Style.Stance(unit)
    if type(unit) ~= "string" then return nil end
    if readFlag(UnitIsTapDenied, unit) then return "tapped" end
    local reaction = Compat.Num(readFlag(UnitReaction, unit, "player"))
    if reaction then
        if reaction >= 5 then return "friendly" end
        if reaction == 4 then return "neutral" end
        return "hostile"
    end
    local attack = readFlag(UnitCanAttack, "player", unit)
    if attack == nil then return nil end
    return attack and "hostile" or "friendly"
end

--- Glutfarbe zur Haltung der Einheit oder nil (nicht lesbar: Blizzards Farbe bleibt)
function Style.StanceColor(unit)
    local s = Style.Stance(unit)
    return s and Style.COLORS[s] or nil
end

--- Blizzard-Regionen ausblenden (Alpha 0) und ihr Alpha je Baustein merken. Ist eine Region inzwischen wieder sichtbar,
--- hat Blizzard sie selbst gesetzt: dieses Alpha wird zum Original (Lucid setzt hier nie ein Alpha > 0).
local function hideRegions(st, part, list)
    local h = st.hidden[part]
    if not h then
        h = {}
        st.hidden[part] = h
    end
    for _, r in ipairs(list) do
        local okA, a = call(r, "GetAlpha")
        a = okA and Compat.Num(a) or nil
        if h[r] == nil then h[r] = a or 1 elseif a and a > 0.001 then h[r] = a end
        call(r, "SetAlpha", 0)
    end
end

local function restoreRegions(st, part)
    local h = st.hidden[part]
    if not h then return end
    for r, a in pairs(h) do call(r, "SetAlpha", a) end
    st.hidden[part] = nil
end

--- Regionen eines UnitFrames nach Feldpfaden (fehlende werden uebergangen, doppelte nur einmal)
local function regionsAt(uf, paths, exclude)
    local out, seen = {}, {}
    for _, p in ipairs(paths) do
        local r = field(uf, p[1])
        if p[2] then r = field(r, p[2]) end
        if type(r) == "table" and r ~= exclude and not seen[r] and type(field(r, "SetAlpha")) == "function" then
            seen[r] = true
            out[#out + 1] = r
        end
    end
    return out
end

--- Ankerpunkte einer Region lesen (fuer die Wiederherstellung); nil, wenn nicht lesbar
local function readPoints(obj)
    local okN, n = call(obj, "GetNumPoints")
    n = okN and Compat.Num(n) or nil
    if not n or n < 1 then return nil end
    local pts = {}
    for i = 1, n do
        local ok, p, rel, rp, x, y = call(obj, "GetPoint", i)
        if not ok or type(p) ~= "string" then return nil end
        pts[i] = { p, rel, rp, x, y }
    end
    return pts
end

local function setPoints(obj, pts)
    call(obj, "ClearAllPoints")
    for _, p in ipairs(pts) do call(obj, "SetPoint", p[1], p[2], p[3], p[4], p[5]) end
end

-- Baustein 1: Bronze-Rahmen ---------------------------------------------------------------------------
--- Statusbar-Textur lesen: Atlas (isAtlas = true) oder Pfad/ID; nil, wenn nicht lesbar
local function readBarTexture(hb)
    local ok, tex = call(hb, "GetStatusBarTexture")
    if not ok or type(tex) ~= "table" then return nil end
    local okA, atlas = call(tex, "GetAtlas")
    if okA and not Compat.IsSecret(atlas) and type(atlas) == "string" and atlas ~= "" then return atlas, true, tex end
    local okT, t = call(tex, "GetTexture")
    if okT and not Compat.IsSecret(t) and (type(t) == "string" or type(t) == "number") then return t, false, tex end
    return nil
end

local function restoreBarTexture(hb, orig, isAtlas)
    call(hb, "SetStatusBarTexture", orig)
    if not isAtlas then return end
    -- Atlas-Original (z. B. "UI-HUD-CoolDownManager-Bar"): nimmt der Setter den Atlasnamen nicht an, direkt per SetAtlas
    local now = readBarTexture(hb)
    if now ~= orig then
        local ok, tex = call(hb, "GetStatusBarTexture")
        if ok and type(tex) == "table" then call(tex, "SetAtlas", orig) end
    end
end

-- Blizzards Rand/Hintergrund des Balkens und die gelbe Ziel-/Bedrohungs-Hervorhebung (bei Stil aus)
local FRAME_HIDE = {
    { "HealthBarsContainer", "border" }, { "HealthBarsContainer", "background" },
    { "healthBar", "border" }, { "healthBar", "background" }, { "healthBar", "bgTexture" },
    { "healthBar", "selectedBorder" }, { "selectionHighlight" }, { "aggroHighlight" }, { "aggroHighlightBase" }, { "aggroHighlightAdditive" },
    { "aggroFlash" },
}

--- Wohin der Balken verankert wird (der Container, in dem er liegt)
local function barHolder(uf, pts)
    local c = field(uf, "HealthBarsContainer")
    if type(c) == "table" then return c end
    local rel = pts and pts[1] and pts[1][2]
    return type(rel) == "table" and rel or nil
end

--- Balkenhoehe: Blizzard verankert den Balken oben und unten im Container (eine Hoehe allein greift dann nicht).
--- Lucid verankert ihn links/rechts mittig im Container und setzt die Hoehe; die Original-Anker kommen beim
--- Ausschalten zurueck. Ohne lesbare Anker: Rueckfall auf die Hoehe des Containers.
local function captureBar(uf, st, hb)
    local o = { tex = nil, isAtlas = nil }
    o.tex, o.isAtlas = readBarTexture(hb)
    o.points = readPoints(hb)
    o.holder = barHolder(uf, o.points)
    local okH, hgt = call(hb, "GetHeight")
    o.barHeight = okH and Compat.Num(hgt) or nil
    if not (o.points and o.holder) then
        o.points = nil
        o.box = field(uf, "HealthBarsContainer")
        if type(o.box) ~= "table" then o.box = hb end
        local okB, bh = call(o.box, "GetHeight")
        o.boxHeight = okB and Compat.Num(bh) or nil
        if o.boxHeight and o.boxHeight <= 0 then o.boxHeight = nil end
    end
    st.barOrig = o
end

--- Stil liegt schon an: was Blizzard seitdem selbst gesetzt hat, wird zum neuen Original (Lucid setzt nie einen
--- Atlas; Anker/Hoehe werden mit den zuletzt von Lucid gesetzten verglichen).
local function refreshBarOrig(st, hb)
    local o = st.barOrig
    local cur, isAtlas = readBarTexture(hb)
    if isAtlas then o.tex, o.isAtlas = cur, true end
    if o.points then
        local pts = readPoints(hb)
        local mine = pts and #pts == 2 and pts[1][1] == "LEFT" and pts[1][2] == o.holder and pts[2][1] == "RIGHT"
        if pts and not mine then -- Blizzard hat neu verankert
            o.points = pts
            local okH, h = call(hb, "GetHeight")
            o.barHeight = okH and Compat.Num(h) or o.barHeight
        end
    elseif o.boxHeight then
        local okH, h = call(o.box, "GetHeight")
        h = okH and Compat.Num(h) or nil
        if h and h > 0 and not (st.appliedHeight and near(h, st.appliedHeight)) then o.boxHeight = h end
    end
end

local function applyBar(uf, st, hb, on, height)
    if on then
        if not st.bar then captureBar(uf, st, hb) else refreshBarOrig(st, hb) end
        local o = st.barOrig
        if o.tex ~= nil then call(hb, "SetStatusBarTexture", Style.FILL_TEX) end -- nur mit lesbarem Original
        if o.points then
            call(hb, "ClearAllPoints")
            call(hb, "SetPoint", "LEFT", o.holder, "LEFT", 0, 0)
            call(hb, "SetPoint", "RIGHT", o.holder, "RIGHT", 0, 0)
            call(hb, "SetHeight", height)
        elseif o.boxHeight then
            call(o.box, "SetHeight", height)
        end
        st.appliedHeight = height -- zuletzt von Lucid gesetzt: Vergleichsbasis fuer Blizzards Aenderungen
        st.bar = true
    elseif st.bar then
        local o = st.barOrig
        if o.tex ~= nil then restoreBarTexture(hb, o.tex, o.isAtlas) end
        if o.points then
            setPoints(hb, o.points)
            if o.barHeight then call(hb, "SetHeight", o.barHeight) end
        elseif o.boxHeight then
            call(o.box, "SetHeight", o.boxHeight)
        end
        st.bar = false
    end
end

-- Overlay (eigene Frames am UnitFrame, erben so dessen Alpha und blenden mit B7/Plates.lua aus):
--   ov        Rahmen (3 Teile, ARTWORK); darunter die Roehre: Schlitz-Hintergrund (BACKGROUND) und die Fuellungs-Lagen
--             (BORDER: Grundfarbe, zwei Fluessigkeits-Lagen, Meniskus, innerer Schatten, Glasglanz),
--             mit Kapsel-Maske; Blizzards Fuellung ist dabei unsichtbar
--   ov.glow   unter allem: enger warmer Schein um den Rahmen (nur am Ziel, BLEND, atmet langsam)
-- Ein gemeinsamer Treiber (ein OnUpdate, ~30 Bilder/s, ruht ohne Arbeit) bewegt die Fuellung, laesst die Oberkante
-- flackern und den Ziel-Schein atmen; er liest keine (ggf. geheimen) Lebenswerte: die Fuellungs-Textur haengt an
-- Blizzards Statusbar-Textur und wird mit ihr breiter/schmaler.
local animated = setmetatable({}, { __mode = "k" }) -- ov -> true, solange Fuellung, Schein oder Glimmen laeuft
local fading = setmetatable({}, { __mode = "k" })   -- UnitFrame -> true, solange "bars" ein-/ausblendet (Baustein 4)
local driver, driverOn, driverTime, driverAcc = nil, false, 0, 0
local steppers = {} -- weitere Animationen am selben Treiber (QuestFar.lua: Atmen der Fern-Symbole), fn(t) -> laeuft noch?
local setDemandAlpha -- Baustein 4 (weiter unten), vom Treiber fuer die Blende gerufen
local updateListeners -- Ereignisse der Bausteine 4/7 an/ab (weiter unten), aus Refresh gerufen

--- Zittern (Runde 9): Die Plakette rutscht pro Bild um Bruchteile eines Pixels. Texte (Name, Stufe) rastet der Client
--- immer auf ganze Pixel ein; Texturen ebenfalls, aber jede Kante fuer sich. Lagen mit gebrochenem Abstand zum Balken
--- (z. B. Rahmen 7,48 Einheiten links) runden deshalb mal so, mal so -> Versatz zwischen Rahmen, Fuellung und Name.
--- Loesung "alles gleich snappen": alle eigenen Texturen rasten ein (wie Text, der sich nicht freigeben laesst), und alle
--- Abstaende zum gemeinsamen Bezug (healthBar) sind ganze Bildschirmpixel (Style.SnapLayout) - dann verschiebt sich
--- beim Rutschen alles gemeinsam um denselben Pixel.
local function snapTex(t)
    if type(t) ~= "table" then return t end
    if t.SetSnapToPixelGrid then pcall(t.SetSnapToPixelGrid, t, true) end
    if t.SetTexelSnappingBias then pcall(t.SetTexelSnappingBias, t, 0) end
    return t
end
Style.SnapTexture = snapTex

--- Groesse eines Bildschirmpixels in UI-Einheiten der Region (nil, wenn nicht lesbar). GetEffectiveScale enthaelt die
--- Plaketten-Skalierung (Entfernung/Ziel/global): bei jeder Aenderung werden die Abstaende neu gerundet (Anker-Cache).
function Style.PixelUnit(region)
    local okE, eff = pcall(function() return region:GetEffectiveScale() end)
    eff = okE and Compat.Num(eff) or nil
    local physH = type(GetPhysicalScreenSize) == "function" and select(2, GetPhysicalScreenSize()) or nil
    physH = Compat.Num(physH)
    if not (eff and eff > 0 and physH and physH > 0) then return nil end
    return 768 / physH / eff
end

local function pxRound(v, unit)
    if not unit or type(v) ~= "number" then return v end
    return math.floor(v / unit + 0.5) * unit
end
Style.PxRound = pxRound

--- Layout auf ganze Bildschirmpixel gerundet (alle Abstaende/Masse ausser dem Massstab)
function Style.SnapLayout(L, unit)
    if not unit then return L end
    local out = {}
    for k, v in pairs(L) do out[k] = (k == "scale") and v or pxRound(v, unit) end
    return out
end

local function threeSlice(parent, layer, path, capU)
    local l, m, r = parent:CreateTexture(nil, layer), parent:CreateTexture(nil, layer), parent:CreateTexture(nil, layer)
    for _, t in ipairs({ l, m, r }) do t:SetTexture(path) end
    l:SetTexCoord(0, capU, 0, 1)
    m:SetTexCoord(capU, 1 - capU, 0, 1)
    r:SetTexCoord(1 - capU, 1, 0, 1)
    l:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    l:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    r:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
    r:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    m:SetPoint("TOPLEFT", l, "TOPRIGHT", 0, 0)
    m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT", 0, 0)
    return l, m, r
end

--- Zustand der beiden Fluessigkeits-Lagen zum Zeitpunkt t (auch fuer scripts/preview-nameplate.mjs): TexCoords,
--- Alpha, Helligkeit. Lage B ist gespiegelt (u0 > u1) und um eine halbe Wiederholung versetzt.
function Style.FlowState(t, phase, la, lb)
    local A = Style.ANIM
    la, lb = la or {}, lb or {} -- im Treiber wiederverwendet (keine neuen Tabellen je Bild)
    phase = phase or 0
    local p = phase * 6.28
    local ua = (phase + t * A.speedA) % 1
    local ub = (phase + 0.5 + t * A.speedB) % 1
    local va = A.vA + A.sway * math.sin(t * 2 * math.pi / A.swayA + p)
    local vb = A.vB + A.sway * math.sin(t * 2 * math.pi / A.swayB + p + 1.1)
    la.u0, la.u1, la.v0, la.v1, la.alpha = ua, ua + A.repeatA, va, va + A.vSpan, A.aAlpha
    la.bright = A.aBright + A.aPulse * math.sin(t * 2 * math.pi / A.aPeriod + p)
    lb.u0, lb.u1, lb.v0, lb.v1, lb.bright = ub + A.repeatB, ub, vb, vb + A.vSpan, 1
    lb.alpha = math.max(0, A.bBase + A.bAmp * math.sin(t * 2 * math.pi / A.bPeriod + p + 1.9))
    return la, lb
end

--- beide Lagen eines Overlays auf den Zustand zum Zeitpunkt t setzen (Toenung ov.tint)
local function setFlow(ov, t)
    ov.fsA, ov.fsB = ov.fsA or {}, ov.fsB or {}
    local la, lb = Style.FlowState(t, ov.phase, ov.fsA, ov.fsB)
    local c = ov.tint or Style.FLOW_TINT.hostile.color
    ov.flow:SetTexCoord(la.u0, la.u1, la.v0, la.v1)
    ov.flow:SetAlpha(la.alpha)
    ov.flow:SetVertexColor(c[1] * la.bright, c[2] * la.bright, c[3] * la.bright)
    ov.flow2:SetTexCoord(lb.u0, lb.u1, lb.v0, lb.v1)
    ov.flow2:SetAlpha(lb.alpha)
end

--- Ein Animationsschritt eines Overlays zum Zeitpunkt t: Fluessigkeit, Meniskus-Flackern, Ziel-Schein, Glimmen. visible/
--- glowVisible: ob Overlay bzw. Schein gerade sichtbar sind (unsichtbare ruhen). Liefert true, wenn etwas lief.
--- Gemeinsam fuer den Treiber und die Vorschau im Reiter (Style.StepOverlay).
local function stepOverlay(ov, t, visible, glowVisible)
    local A = Style.ANIM
    local busy = false
    if ov.flowOn and visible then
        busy = true
        local p = ov.phase * 6.28
        pcall(setFlow, ov, t)
        local f = A.edgeBase + A.edgeAmp * math.sin(t * A.edgeRate + p) * math.sin(t * A.edgeRate * 0.37 + 1.3)
        pcall(ov.edge.SetAlpha, ov.edge, f)
    end
    if ov.glowOn and glowVisible then
        busy = true
        local g = Style.GLOW
        local a = g.alphaMin + (g.alphaMax - g.alphaMin) * (0.5 + 0.5 * math.sin(t * math.pi * 2 / g.period))
        pcall(ov.glow.SetAlpha, ov.glow, a)
    end
    if ov.emberOn and visible then
        -- Glimmen: Textur-Alpha pulsiert (lesbar); ob es ueberhaupt glimmt, steht secret im Frame-Alpha darueber
        busy = true
        local E = Style.EMBER
        local a = E.alphaMin + (E.alphaMax - E.alphaMin) * (0.5 + 0.5 * math.sin(t * math.pi * 2 / E.period + ov.phase * 6.28))
        pcall(ov.ember.SetAlpha, ov.ember, a)
    end
    return busy
end
Style.StepOverlay = stepOverlay

local function driverStep(dt)
    driverTime = driverTime + dt
    driverAcc = driverAcc + dt
    if driverAcc < 0.033 then return end
    local stepDt = driverAcc
    driverAcc = 0
    local busy = false
    local A = Style.ANIM
    local t = driverTime
    for ov in pairs(animated) do
        -- unsichtbare Overlays (entfernte/ausgeblendete Plaketten im Pool) ruhen und halten den Treiber nicht wach;
        -- beim naechsten Anwenden weckt layoutOverlay ihn wieder
        -- ebenso Plaketten, die B7 per UnitFrame-Alpha 0 versteckt (IsVisible bleibt dort true; Quest-Fernsicht: viele)
        local hidden = ov.ownerFrame and ns.Plates.IsHidden(ov.ownerFrame)
        local visible = not hidden and Compat.QueryBool(ov, "IsVisible") ~= false
        local glowVisible = not hidden and Compat.QueryBool(ov.glow, "IsVisible") ~= false
        if stepOverlay(ov, t, visible, glowVisible) then busy = true end
        if not (ov.flowOn or ov.glowOn or ov.emberOn) then animated[ov] = nil end
    end
    for _, fn in ipairs(steppers) do
        local ok, more = pcall(fn, t)
        if not ok then recordError(more) elseif more then busy = true end
    end
    -- Baustein 4: Blende des Alphas bei vollem Leben (lesbar, 0..1) Richtung Ziel, Dauer DEMAND.fade
    for uf in pairs(fading) do
        local st = states[uf]
        if not (st and st.demandOn and st.demandGoal) then
            fading[uf] = nil
        else
            local goal = st.demandGoal
            local l, step = st.demandLevel or goal, stepDt / Style.DEMAND.fade
            if goal > l then l = math.min(goal, l + step) else l = math.max(goal, l - step) end
            st.demandLevel = l
            local ok, err = pcall(setDemandAlpha, uf, st)
            if not ok then recordError(err) end
            if l == goal then fading[uf] = nil else busy = true end
        end
    end
    if not busy and driver then
        driverOn = false
        driver:Hide()
    end
end

function Style.DriverActive() return driverOn == true end

--- weitere Animation am gemeinsamen Treiber anmelden (einmalig); fn(t) liefert true, solange sie laeuft
function Style.AddStepper(fn)
    for _, f in ipairs(steppers) do if f == fn then return end end
    steppers[#steppers + 1] = fn
end

--- Animation eines Overlays abmelden (Plakette entfernt)
local function stopAnimation(ov)
    if not ov then return end
    ov.flowOn, ov.glowOn, ov.emberOn = false, false, false
    animated[ov] = nil
end

--- Treiber wecken; ov (optional) meldet ein Overlay mit laufender Animation an
local wakeDriver
function Style.WakeDriver() wakeDriver(nil) end
function wakeDriver(ov)
    if ov then animated[ov] = true end
    if not driver then
        driver = CreateFrame("Frame")
        driver:SetScript("OnUpdate", function(_, dt)
            local ok, err = pcall(driverStep, dt)
            if not ok then recordError(err) end
        end)
    end
    if not driverOn then
        driverOn = true
        driver:Show()
    end
end

-- Roehre (Runde 8, Wahl C): Blizzards Fuellung bleibt unsichtbar (Alpha 0, wiederherstellbar); Lucid zeigt die
-- Fuellung selbst in eigenen Lagen, alle an Blizzards Fuellungs-Textur verankert (deren Breite folgt dem Leben, ohne es zu
-- lesen) und mit einer Kapsel-Maske auf den Schlitz beschnitten (runde Enden): leerer Teil rotbraun mit Tiefe, Grundfarbe,
-- zwei Fluessigkeits-Lagen, Meniskus, innerer Schatten, Glasglanz (Fuellungsende: normale Schnittkante).
local function addMask(ov, t, maskKey)
    ov.maskable[#ov.maskable + 1] = t
    ov.maskOf[t] = maskKey or "mask" -- welche Kapsel-Maske (ov.mask bzw. ov.fillMask im Clip-Frame) die Lage rundet
    return t
end

--- Gemeinsamer Container (Runde 10): EIN eigener Frame am UnitFrame, deckungsgleich mit dem healthBar; alle Lucid-Teile
--- (Rahmen, Roehre, Schein, Name, Schleier, Stufen-Plaettchen) sind seine Kinder und mit ganzzahligen Pixel-Abstaenden an
--- ihm verankert. So haben alle dieselbe effektive Skalierung und denselben Bezug und springen beim subpixeligen Rutschen
--- der Plakette gemeinsam. Unter-Frame r.bars (deckungsgleich) traegt alles ausser dem Namen: Rahmen/Roehre, Schein,
--- Plaettchen; sein Alpha steuert Baustein 4 (ggf. secret), Baustein 5 versteckt ihn.
local function ensureRoot(st, uf, hb)
    local r = st.root
    if not r then
        r = CreateFrame("Frame", nil, uf)
        r.bars = CreateFrame("Frame", nil, r)
        r.bars:SetAllPoints(r)
        st.root = r
    end
    if r.anchorBar ~= hb then
        r.anchorBar = hb
        r:ClearAllPoints()
        r:SetAllPoints(hb)
    end
    local okL, lvl = call(hb, "GetFrameLevel")
    lvl = okL and Compat.Num(lvl) or nil
    if lvl and r.level ~= lvl then
        r.level = lvl
        r:SetFrameLevel(math.max(0, lvl - 3))
        r.bars:SetFrameLevel(math.max(0, lvl - 3))
    end
    r:Show()
    return r
end

local overlayCount = 0
--- Rahmen, Roehre, Fuellungs-Lagen, Glimmen und Ziel-Schein als Kinder von holder (die Vorschau im Reiter baut sich aus
--- demselben Code: Style.BuildOverlay)
local function buildOverlay(holder)
    local G = Style.FRAME_GEOMETRY
    local T = Style.TUBE
    local ov = CreateFrame("Frame", nil, holder)
    ov.maskable, ov.maskOf = {}, {}
    ov.left, ov.mid, ov.right = threeSlice(ov, "ARTWORK", Style.FRAME_TEX, G.cap / G.w)
    -- Runde 7 (Fluessigkeit wurde mit dem Leben gestaucht): die Fuellungs-Lagen liegen in fester Groesse ueber die
    -- ganze Schlitzbreite in ov.fillIn; ov.fill (SetClipsChildren) reicht vom Schlitz links bis zur rechten Kante von
    -- Blizzards Fuellungs-Textur und deckt sie auf (nur Anker, kein Lebenswert gelesen). Darunter ov.back mit dem leeren
    -- Schlitz; Rahmen, Schatten und Glanz bleiben in ov darueber.
    ov.back = CreateFrame("Frame", nil, holder)
    ov.fill = CreateFrame("Frame", nil, holder)
    call(ov.fill, "SetClipsChildren", true)
    ov.fillIn = CreateFrame("Frame", nil, ov.fill)
    -- leerer Teil des Schlitzes: dunkles, leicht durchscheinendes Rotbraun, oben/unten dunkler
    ov.slitBack = ov.back:CreateTexture(nil, "BACKGROUND", nil, 0) -- nicht maskiert: fuellt die Innenform des Rahmens ganz
    ov.slitBack:SetColorTexture(1, 1, 1, 1)
    local okG = pcall(ov.slitBack.SetGradient, ov.slitBack, "VERTICAL",
        CreateColor(T.backBottom[1], T.backBottom[2], T.backBottom[3], T.backBottom[4]),
        CreateColor(T.backTop[1], T.backTop[2], T.backTop[3], T.backTop[4]))
    if not okG then ov.slitBack:SetColorTexture(T.backTop[1], T.backTop[2], T.backTop[3], T.backTop[4]) end
    -- Grundfarbe der Fuellung (matt, nach Haltung getoent) und die beiden Fluessigkeits-Lagen
    local fi = ov.fillIn
    ov.base = addMask(ov, fi:CreateTexture(nil, "BORDER", nil, -3), "fillMask")
    ov.base:SetTexture(Style.FILL_TEX)
    ov.flow = addMask(ov, fi:CreateTexture(nil, "BORDER", nil, -2), "fillMask")
    ov.flow:SetTexture(Style.FLOW_TEX, "REPEAT", "REPEAT")
    if ov.flow.SetBlendMode then ov.flow:SetBlendMode("BLEND") end
    ov.flow2 = addMask(ov, fi:CreateTexture(nil, "BORDER", nil, -1), "fillMask") -- gespiegelt, additiv, pulsiert gegenlaeufig
    ov.flow2:SetTexture(Style.FLOW_TEX, "REPEAT", "REPEAT")
    if ov.flow2.SetBlendMode then ov.flow2:SetBlendMode("ADD") end
    -- Meniskus (heller weicher Saum an der Oberflaeche; flackert leicht ueber den Treiber)
    ov.edge = addMask(ov, fi:CreateTexture(nil, "BORDER", nil, 0), "fillMask")
    local e = Style.EDGE_COLOR
    ov.edge:SetColorTexture(e[1], e[2], e[3], 1)
    if ov.edge.SetBlendMode then ov.edge:SetBlendMode("ADD") end
    -- innerer Schatten (Rahmen wirft Schatten, Fuellung sitzt vertieft) und feiner Glasglanz
    ov.inset = addMask(ov, ov:CreateTexture(nil, "BORDER", nil, 3))
    ov.inset:SetTexture(Style.INSET_TEX)
    ov.inset:SetVertexColor(0, 0, 0, T.insetAlpha)
    ov.glass = addMask(ov, ov:CreateTexture(nil, "BORDER", nil, 4))
    -- Glanz laeuft an beiden Enden weich aus (np-glass: Alpha-Verlauf ueber je ~18 %, R10), statt hart vor der Kappe
    ov.glass:SetTexture(Style.GLASS_TEX)
    ov.glass:SetVertexColor(1, 0.97, 0.92, T.glassAlpha)
    -- Kapsel-Maske ueber den Schlitz (runde Enden); fehlt die Masken-API im Client, bleibt alles eckig
    local okM, mask = pcall(ov.CreateMaskTexture, ov)
    if okM and mask then
        local okT = pcall(mask.SetTexture, mask, Style.MASK_TEX, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        ov.mask = okT and mask or nil
    end
    -- Endblende fuer die hellen Linien (Meniskus, Glanz): immer an, unabhaengig von der Kapsel; bezogen auf den Schlitz,
    -- nicht aufs Fuellungsende (dessen harte Schnittkante bleibt)
    local okF, fmask = pcall(ov.CreateMaskTexture, ov)
    if okF and fmask and pcall(fmask.SetTexture, fmask, Style.ENDFADE_TEX, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") then
        ov.endMask = fmask
        pcall(ov.glass.AddMaskTexture, ov.glass, fmask)
    end
    -- dieselben Masken im Clip-Frame der Fuellung (Masken wirken auf Lagen desselben Frames)
    local okM2, mask2 = pcall(fi.CreateMaskTexture, fi)
    if okM2 and mask2 and pcall(mask2.SetTexture, mask2, Style.MASK_TEX, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") then
        ov.fillMask = mask2
    end
    local okF2, fmask2 = pcall(fi.CreateMaskTexture, fi)
    if okF2 and fmask2 and pcall(fmask2.SetTexture, fmask2, Style.ENDFADE_TEX, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") then
        ov.fillEndMask = fmask2
        pcall(ov.edge.AddMaskTexture, ov.edge, fmask2)
    end
    -- Glimmen (Baustein 7): eigener Unter-Frame ueber den Lagen der Roehre (Frame-Alpha = Kurvenwert, secret), darin
    -- eine helle, additive Lage an der Fuellung (Textur-Alpha pulsiert) mit eigener Kapsel-Maske ueber dem Schlitz
    local ef = CreateFrame("Frame", nil, ov)
    ef:SetAllPoints(ov)
    ov.emberFrame = ef
    ov.ember = ef:CreateTexture(nil, "ARTWORK")
    ov.ember:SetTexture(Style.FILL_TEX)
    local ec = Style.EMBER.color
    ov.ember:SetVertexColor(ec[1], ec[2], ec[3], 0)
    if ov.ember.SetBlendMode then ov.ember:SetBlendMode("ADD") end
    snapTex(ov.ember)
    local okEM, emask = pcall(ef.CreateMaskTexture, ef)
    if okEM and emask and pcall(emask.SetTexture, emask, Style.MASK_TEX, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE") then
        ov.emberMask = emask
        pcall(ov.ember.AddMaskTexture, ov.ember, emask)
    end
    ef:SetAlpha(0)
    ef:Hide()
    -- Ziel-Schein: eigener Frame ganz unten, Textur 3-teilig (Kappen bleiben rund), normales Mischen (BLEND)
    local glow = CreateFrame("Frame", nil, holder)
    glow.left, glow.mid, glow.right = threeSlice(glow, "BACKGROUND", Style.GLOW_TEX, Style.GLOW.cap / Style.GLOW.w)
    local gc = Style.GLOW.color
    for _, t in ipairs({ glow.left, glow.mid, glow.right }) do
        t:SetVertexColor(gc[1], gc[2], gc[3])
        if t.SetBlendMode then t:SetBlendMode("BLEND") end
    end
    ov.glow = glow
    overlayCount = overlayCount + 1
    ov.phase = (overlayCount * 0.618) % 1 -- jede Plakette laeuft leicht versetzt
    for _, t in ipairs(ov.maskable) do snapTex(t) end
    for _, t in ipairs({ ov.left, ov.mid, ov.right, glow.left, glow.mid, glow.right }) do snapTex(t) end
    ov:Hide()
    ov.back:Hide()
    ov.fill:Hide()
    glow:Hide()
    for _, t in ipairs(ov.maskable) do t:Hide() end
    return ov
end
Style.BuildOverlay = buildOverlay

local function ensureOverlay(st, uf)
    if st.overlay then return st.overlay end
    st.overlay = buildOverlay((st.root and st.root.bars) or uf)
    st.overlay.ownerFrame = uf -- fuer den Treiber: von B7 per UnitFrame-Alpha versteckte Plaketten ruhen
    return st.overlay
end

--- Kapsel-Maske an/aus (AddMaskTexture/RemoveMaskTexture auf Lucids eigenen Lagen)
local function setMasked(ov, on)
    if not ov.mask or ov.masked == on then return end
    ov.masked = on
    for _, t in ipairs(ov.maskable) do
        local m = ov[ov.maskOf[t] or "mask"]
        if m then
            if on then pcall(t.AddMaskTexture, t, m) else pcall(t.RemoveMaskTexture, t, m) end
        end
    end
end

--- Rahmen, Roehre, Fuellung, Glimmen und Schein eines Overlays an den Container R legen (ohne Ebenen); curFill = Fuellungs-
--- Textur des Lebensbalkens. Gemeinsam fuer echte Plaketten und die Vorschau im Reiter (Style.AnchorOverlay).
local function anchorOverlay(ov, R, curFill, height, unit)
    local L = Style.SnapLayout(Style.Layout(height), unit)
    local T = Style.TUBE
    ov:ClearAllPoints()
    ov:SetPoint("TOPLEFT", R, "TOPLEFT", -L.padL, L.padT)
    ov:SetPoint("BOTTOMRIGHT", R, "BOTTOMRIGHT", L.padR, -L.padB)
    ov.left:SetWidth(L.cap)
    ov.right:SetWidth(L.cap)
    -- Schlitz-Rechteck: Balken plus Ueberstand oben/unten
    local function slit(t)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", R, "TOPLEFT", 0, L.slitExtra)
        t:SetPoint("BOTTOMRIGHT", R, "BOTTOMRIGHT", 0, -L.slitExtra)
    end
    -- unter den Rahmen: Innenkontur der Kappen ist abgerundet (Textur), deshalb reichen Schlitz-Hintergrund, Maske und
    -- Fuellung um underX/underY Textur-Pixel unter das Band (der Rahmen liegt darueber, keine Luecken an den Enden)
    local ux, uy = pxRound(T.underX * L.scale, unit), pxRound(T.underY * L.scale, unit)
    local function under(t)
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", R, "TOPLEFT", -ux, L.slitExtra + uy)
        t:SetPoint("BOTTOMRIGHT", R, "BOTTOMRIGHT", ux, -L.slitExtra - uy)
    end
    under(ov.slitBack)
    under(ov.inset) -- Enden unter den Kappen (Kapsel-Maske rundet), keine senkrechte Schattenkante vor der Kappe
    if ov.mask then under(ov.mask) end
    if ov.endMask then slit(ov.endMask) end
    if ov.fillMask then under(ov.fillMask) end
    if ov.fillEndMask then slit(ov.fillEndMask) end
    ov.back:ClearAllPoints()
    ov.back:SetAllPoints(ov)
    under(ov.fillIn) -- feste Groesse ueber den ganzen Schlitz (unter die Kappen)
    ov.glass:ClearAllPoints()
    ov.glass:SetPoint("TOPLEFT", R, "TOPLEFT", pxRound(L.slit * 0.6, unit), pxRound(L.slitExtra - L.slit * T.glassTop, unit))
    ov.glass:SetPoint("TOPRIGHT", R, "TOPRIGHT", -pxRound(L.slit * 0.6, unit), pxRound(L.slitExtra - L.slit * T.glassTop, unit))
    ov.glass:SetHeight(math.max(unit or 1, pxRound(L.slit * T.glassHeight, unit)))
    local glow = ov.glow
    glow:ClearAllPoints()
    glow:SetPoint("TOPLEFT", R, "TOPLEFT", -L.padL - L.glowPad, L.padT + L.glowPad)
    glow:SetPoint("BOTTOMRIGHT", R, "BOTTOMRIGHT", L.padR + L.glowPad, -L.padB - L.glowPad)
    glow.left:SetWidth(L.glowCap)
    glow.right:SetWidth(L.glowCap)
    -- Fuellung (Runde 7): Clip-Frame vom Schlitz links (unter der Kappe) bis zur rechten Kante von Blizzards
    -- Fuellungs-Textur plus ux (bei vollem Leben unter die rechte Kappe, Kapsel-Rundung; das Fuellungsende sitzt ux
    -- weiter rechts und bleibt eine harte Schnittkante). Die Lagen darin haben feste Groesse (Balkenhoehe, ganze Breite).
    local anchor = curFill
    ov.fill:ClearAllPoints()
    ov.fill:SetPoint("TOPLEFT", R, "TOPLEFT", -ux, L.slitExtra + uy)
    ov.fill:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", ux, -L.slitExtra - uy)
    for _, t in ipairs({ ov.base, ov.flow, ov.flow2 }) do
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", R, "TOPLEFT", -ux, 0)
        t:SetPoint("BOTTOMRIGHT", R, "BOTTOMRIGHT", ux, 0)
    end
    ov.edge:ClearAllPoints()
    ov.edge:SetPoint("TOPLEFT", R, "TOPLEFT", -ux, 0)
    ov.edge:SetPoint("TOPRIGHT", R, "TOPRIGHT", ux, 0) -- Fuellungsende (Clip): normale Schnittkante (R9)
    ov.edge:SetHeight(T.meniscusHeight)
    -- Glimmen: genau ueber der Fuellung (nicht unter das Rahmenband), Maske ueber den Schlitz
    ov.ember:ClearAllPoints()
    ov.ember:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
    ov.ember:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", ux, 0) -- Fuellungsende wie die Fluessigkeit
    if ov.emberMask then slit(ov.emberMask) end
end
Style.AnchorOverlay = anchorOverlay

--- Teile des Overlays zeigen/verstecken. parts: { frame, glow, flow, capsule, inset, meniscus, glass, ember }; setzt die
--- Animations-Merker (flowOn/glowOn/emberOn)
local function showOverlay(ov, parts)
    local frame = parts.frame
    ov.left:SetShown(frame)
    ov.mid:SetShown(frame)
    ov.right:SetShown(frame)
    ov.slitBack:SetShown(frame)
    ov.base:SetShown(frame)
    ov.flow:SetShown(frame and parts.flow)
    ov.flow2:SetShown(frame and parts.flow)
    ov.edge:SetShown(frame and parts.meniscus)
    ov.inset:SetShown(frame and parts.inset)
    ov.glass:SetShown(frame and parts.glass)
    setMasked(ov, frame and parts.capsule)
    ov:SetShown(frame)
    ov.back:SetShown(frame)
    ov.fill:SetShown(frame)
    ov.glow:SetShown(parts.glow)
    local showFlow = frame and parts.flow
    local ember = frame and parts.ember == true
    ov.emberFrame:SetShown(ember)
    if not ember then ov.emberFrame:SetAlpha(0) end
    ov.flowOn, ov.glowOn, ov.emberOn = showFlow and true or false, parts.glow and true or false, ember
    if parts.glow then ov.glow:SetAlpha(Style.GLOW.alphaMax) end
end
Style.ShowOverlay = showOverlay

--- Fluessigkeit farbig oder entsaettigt (nur beim Wechsel neu laden), Toenung und Farbe der zweiten Lage
local function setFlowTint(ov, tint)
    if ov.flowTex ~= tint.tex then
        ov.flowTex = tint.tex
        local path = tint.tex == "mono" and Style.FLOW_TEX_MONO or Style.FLOW_TEX
        ov.flow:SetTexture(path, "REPEAT", "REPEAT")
        ov.flow2:SetTexture(path, "REPEAT", "REPEAT")
    end
    ov.tint = tint.color
    ov.flow2:SetVertexColor(tint.color[1], tint.color[2], tint.color[3])
end
Style.SetFlowTint = setFlowTint

--- Overlay an den Balken legen (nur bei geaendertem Balken/Hoehe/Ebene neu verankern) und Teile zeigen.
--- parts: { frame, glow, flow, capsule, inset, meniscus, glass }
local function layoutOverlay(st, uf, hb, height, parts)
    local R = ensureRoot(st, uf, hb)
    local ov = ensureOverlay(st, uf)
    local okL, lvl = call(hb, "GetFrameLevel")
    lvl = okL and Compat.Num(lvl) or nil
    local unit = Style.PixelUnit(hb)
    local okFT, curFill = call(hb, "GetStatusBarTexture")
    curFill = (okFT and type(curFill) == "table") and curFill or hb
    if not (ov.anchorBar == hb and ov.anchorHeight == height and ov.anchorLevel == lvl and ov.anchorUnit == unit
        and ov.anchorFill == curFill) then
        ov.anchorBar, ov.anchorHeight, ov.anchorLevel, ov.anchorUnit, ov.anchorFill = hb, height, lvl, unit, curFill
        anchorOverlay(ov, R, curFill, height, unit)
        if lvl then
            ov.back:SetFrameLevel(lvl)                  -- leerer Schlitz
            ov.fill:SetFrameLevel(lvl + 1)              -- Fuellung (Clip) darueber
            ov.fillIn:SetFrameLevel(lvl + 1)
            ov:SetFrameLevel(lvl + 2)                   -- Rahmen, Schatten, Glanz ueber der Fuellung
            ov.emberFrame:SetFrameLevel(lvl + 3)        -- ueber den Lagen der Roehre
            ov.glow:SetFrameLevel(math.max(0, lvl - 2)) -- ganz unten
        end
    end
    showOverlay(ov, parts)
    local showFlow = ov.flowOn
    -- Grundfarbe der Fuellung: Glut nach Haltung (ohne Einheit: zuletzt gezeigte)
    local col = Style.StanceColor(field(uf, "unit")) or st.lastColor or Style.COLORS.hostile
    ov.base:SetVertexColor(col[1], col[2], col[3])
    if showFlow then
        local stance = Style.Stance(field(uf, "unit")) or st.lastStance or "hostile" -- ohne Einheit: zuletzt gezeigte
        setFlowTint(ov, Style.FLOW_TINT[stance])
        setFlow(ov, driverTime) -- sofort ein gueltiges Bild (der Treiber setzt es danach fort)
    end
    if ov.flowOn or ov.glowOn or ov.emberOn then wakeDriver(ov) end
end

local function hideOverlay(st)
    local ov = st.overlay
    if not ov then return end
    ov:Hide()
    ov.back:Hide()
    ov.fill:Hide()
    ov.glow:Hide()
    for _, t in ipairs(ov.maskable) do t:Hide() end
    ov.emberFrame:Hide()
    ov.emberFrame:SetAlpha(0)
    ov.flowOn, ov.glowOn, ov.emberOn = false, false, false
end

--- Blizzards Fuellungs-Textur unsichtbar (Lucid zeigt die Fuellung selbst) bzw. zurueck; Blizzard kann das Alpha ueber
--- SetStatusBarColor zuruecksetzen - deshalb nach jedem Faerben erneut (applyColors/UpdateHealthColor-Hook).
local function hideBlizzardFill(st, hb, on)
    local ok, tex = call(hb, "GetStatusBarTexture")
    if not ok or type(tex) ~= "table" then return end
    if on then
        if st.fillAlphaOrig == nil then
            local okA, a = call(tex, "GetAlpha")
            st.fillAlphaOrig = okA and Compat.Num(a) or 1
        end
        call(tex, "SetAlpha", 0)
        st.fillHidden = true
    elseif st.fillHidden then
        call(tex, "SetAlpha", st.fillAlphaOrig or 1)
        st.fillHidden, st.fillAlphaOrig = false, nil
    end
end

--- Hoehe, an der Rahmen/Glut/Plaettchen ausgerichtet werden: Stil-Hoehe, sonst Blizzards Balkenhoehe
local function layoutHeight(hb, c)
    if partOn(c, "frame") then return c.frame.height end
    local ok, h = call(hb, "GetHeight")
    h = ok and Compat.Num(h) or nil
    return (h and h > 0) and h or 6
end

-- Kurven (Bausteine 4 und 7) ------------------------------------------------------------------------
-- Leben fremder Einheiten ist secret: nur UnitHealthPercent(unit, false, Kurve) liefert einen (secret) Kurvenwert, der
-- unveraendert an SetAlpha geht. Kurven werden einmal erzeugt und wiederverwendet. Laesst sich keine Kurve anlegen
-- (ohne Einheitsbezug), gilt der Weg sofort fuer die Sitzung als gestoert; scheitert ein Aufruf mit Einheit (z. B. eben
-- entfernte Einheit), erst nach CURVE_FAIL_LIMIT Fehlschlaegen hintereinander (ein Erfolg setzt zurueck). Einzelne
-- Fehlschlaege zeigen den Balken (Rueckfall) bzw. kein Glimmen. Gestoert: Balken immer sichtbar, kein Glimmen.
local curveBroken = false
local curveFails = 0
Style.CURVE_FAIL_LIMIT = 3

local function curveFailed()
    curveFails = curveFails + 1
    if curveFails >= Style.CURVE_FAIL_LIMIT then curveBroken = true end
end
local demandCurves = {} -- Stufe k (0..steps-1) -> Kurve (0,1) (full,1) (1,k/steps)
local emberCurve = nil  -- (0,1) (threshold-,1) (threshold,0) (1,0)
local emberCurveTh = nil -- Schwelle, fuer die emberCurve angelegt wurde (neue Kurve nur bei geaenderter Schwelle)

local function curveApi()
    return not curveBroken and type(UnitHealthPercent) == "function" and type(C_CurveUtil) == "table"
        and type(C_CurveUtil.CreateCurve) == "function"
end
Style.CurveApi = curveApi
function Style.CurveBroken() return curveBroken end

local function makeCurve(points)
    local ok, c = pcall(function()
        local cv = C_CurveUtil.CreateCurve()
        for _, p in ipairs(points) do cv:AddPoint(p[1], p[2]) end
        return cv
    end)
    if ok and c then return c end
    curveBroken = true
    return nil
end

local function demandCurve(k)
    if not curveApi() then return nil end
    if not demandCurves[k] then
        demandCurves[k] = makeCurve({ { 0, 1 }, { Style.DEMAND.full, 1 }, { 1, k / Style.DEMAND.steps } })
    end
    return demandCurves[k]
end

--- Schwelle des Glimmens (Lebensanteil) aus den Stil-Einstellungen, sonst der Standard
function Style.LowThreshold(c)
    local p = type(c) == "table" and c.lowHealth
    local th = type(p) == "table" and p.threshold or nil
    if type(th) == "number" and th == th and th >= 0.05 and th <= 0.5 then return th end
    return Style.EMBER.threshold
end

local function lowCurve()
    if not curveApi() then return nil end
    local th = Style.LowThreshold(cfg)
    if not emberCurve or emberCurveTh ~= th then
        emberCurveTh = th
        emberCurve = makeCurve({ { 0, 1 }, { th - 0.0001, 1 }, { th, 0 }, { 1, 0 } }) -- glimmt nur UNTER der Schwelle
    end
    return emberCurve
end

--- Kurvenwert fuer die Einheit (secret oder Zahl) oder nil (Einheit weg/kein Wert; wirft der Aufruf: gestoert)
local function healthValue(unit, curve)
    if not curve or type(unit) ~= "string" then return nil end
    local ok, v = pcall(UnitHealthPercent, unit, false, curve)
    if not ok then
        curveFailed()
        return nil
    end
    if Compat.IsSecret(v) or type(v) == "number" then return v end
    return nil
end

--- Alpha (secret oder Zahl) setzen; nimmt der Frame es nicht, ist der Kurvenweg gestoert
local function setCurveAlpha(f, v)
    if v ~= nil and pcall(f.SetAlpha, f, v) then
        curveFails = 0
        return true
    end
    if v ~= nil then curveFailed() end
    return false
end

-- Baustein 7: Glimmen bei wenig Leben - Frame-Alpha aus der Kurve (neu bei Leben-Ereignissen und beim Anwenden)
local function applyEmber(uf, st)
    local ov = st.overlay
    if not (ov and ov.emberOn) then return end
    local unit = field(uf, "unit")
    if type(unit) ~= "string" then return end -- ohne Einheit: letzter Stand
    if not setCurveAlpha(ov.emberFrame, healthValue(unit, lowCurve())) then ov.emberFrame:SetAlpha(0) end
end

-- Baustein 1 (Rahmen, Balken, Blizzard-Rand/Hervorhebung) + Baustein 6 (Ziel-Glut) ---------------------------
local function applyFrame(uf, st, c)
    local hb = healthBar(uf)
    if not hb then return end
    local frameOn = partOn(c, "frame")
    local height = layoutHeight(hb, c)
    applyBar(uf, st, hb, frameOn, height)
    if frameOn then
        if not st.frameRegions then st.frameRegions = regionsAt(uf, FRAME_HIDE, hb) end
        hideRegions(st, "frame", st.frameRegions)
    else
        restoreRegions(st, "frame")
    end
    local glowOn = partOn(c, "targetGlow") and readFlag(UnitIsUnit, field(uf, "unit"), "target") == true
    hideBlizzardFill(st, hb, frameOn)
    if frameOn or glowOn then
        local F = frameOn and c.frame or {}
        layoutOverlay(st, uf, hb, height, { frame = frameOn, glow = glowOn, flow = F.living == true, capsule = F.capsule == true,
            inset = F.inset == true, meniscus = F.meniscus == true, glass = F.glass == true,
            ember = partOn(c, "lowHealth") and curveApi() })
        applyEmber(uf, st)
        st.frame = true
    elseif st.frame then
        hideOverlay(st)
        st.frame = false
    end
end

-- Baustein 2: Glutfarben nach Haltung ------------------------------------------------------------------
local function applyColors(uf, st, c)
    local hb = healthBar(uf)
    if not hb then return end
    -- Haltung nicht lesbar: Blizzards Farbe; Frame gerade ohne Einheit (Ausblenden/Entfernen): zuletzt gezeigte Glut
    local unit = field(uf, "unit")
    local color = nil
    if partOn(c, "colors") then
        color = Style.StanceColor(unit)
        if not color and type(unit) ~= "string" and st.colors then color = st.lastColor end
    end
    if color then
        st.lastColor = color
        st.lastStance = Style.Stance(unit) or st.lastStance
        if not st.colors then -- noch Blizzards Farbe: frisch merken
            local ok, r, g, b, a = call(hb, "GetStatusBarColor")
            if ok then st.colorOrig = { r, g, b, a } end
        end
        call(hb, "SetStatusBarColor", color[1], color[2], color[3])
        if st.fillHidden then -- Lucid zeigt die Fuellung selbst: Blizzards bleibt unsichtbar, unsere bekommt die Farbe
            hideBlizzardFill(st, hb, true)
            if st.overlay then st.overlay.base:SetVertexColor(color[1], color[2], color[3]) end
        end
        st.colors = true
    elseif st.colors then
        -- Blizzards eigene Farbe: ihr Zwischenspeicher am Balken (r/g/b, nur gelesen), sonst das gemerkte Original
        local r, g, b = Compat.Num(field(hb, "r")), Compat.Num(field(hb, "g")), Compat.Num(field(hb, "b"))
        if r and g and b then
            call(hb, "SetStatusBarColor", r, g, b)
        elseif st.colorOrig then
            local o = st.colorOrig
            call(hb, "SetStatusBarColor", o[1], o[2], o[3], o[4])
        end
        st.colors = false
    end
end

-- Baustein 3: Schrift --------------------------------------------------------------------------------
local fontCache = {}
local function fontPath(face)
    if fontCache[face] then return fontCache[face] end
    local Card = ns.ZoneCard
    local path
    if Card and type(Card.FontAvailable) == "function" and Card.FontAvailable(face) then path = Card.FontPath(face) end
    if type(path) ~= "string" then path = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF" end
    fontCache[face] = path
    return path
end
Style.FontPath = fontPath

local function setFont(fs, path, size, flags)
    local ok, r = call(fs, "SetFont", path, size, flags or Style.FONT_FLAGS)
    return ok and r ~= false
end

--- Schrift setzen mit Rueckfall auf die Client-Schrift; liefert den wirksamen Pfad
local function setFontSafe(fs, face, size, flags)
    local path = fontPath(face)
    if not setFont(fs, path, size, flags) then
        path = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
        setFont(fs, path, size, flags)
    end
    return path
end

-- Name (Runde 7): Blizzards Namens-FontString laesst sich im Client nicht zuverlaessig steuern (style debug:
-- GetPoint wirft, Anker links+rechts am Container => gekuerzt, mittig, Textfarbe weiss trotz SetTextColor). Lucid
-- zeigt deshalb einen eigenen FontString (eigener Frame am UnitFrame, Text aus UnitName) und blendet Blizzards Namen
-- per Alpha 0 aus (wiederherstellbar). Sichtbar nur, wenn Blizzard den Namen zeigt (Vereinfacht/Nur-Name-Logik bleibt).
local function buildNameText(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.text = f:CreateFontString(nil, "OVERLAY")
    f.text:SetJustifyH("LEFT")
    f.veil = f:CreateTexture(nil, "BACKGROUND") -- Tinten-Schleier hinter dem Namen (Teil Baustein 3, schaltbar)
    f.veil:SetTexture(Style.VEIL_TEX)
    local N = Style.NAME
    f.veil:SetVertexColor(N.veil[1], N.veil[2], N.veil[3], N.veilAlpha)
    f.veil:SetPoint("TOPLEFT", f.text, "TOPLEFT", -N.veilPadX, N.veilPadY)
    f.veil:SetPoint("BOTTOMRIGHT", f.text, "BOTTOMRIGHT", N.veilPadX, -N.veilPadY)
    snapTex(f.veil)
    if f.text.SetWordWrap then f.text:SetWordWrap(false) end
    f:Hide()
    return f
end
Style.BuildNameText = buildNameText

local function ensureNameText(st, uf)
    if st.nameText then return st.nameText end
    st.nameText = buildNameText(st.root or uf)
    return st.nameText
end

--- Name an den Container R legen (Groesse size, Schrift face; friedlich: mittig an der Stelle des Balkens)
local function layoutNameText(f, R, face, size, height, unit, peaceful)
    local fs, N = f.text, Style.NAME
    local L = Style.SnapLayout(Style.Layout(height), unit)
    f:ClearAllPoints()
    f:SetAllPoints(R)
    fs:ClearAllPoints()
    if peaceful then
        fs:SetPoint("BOTTOM", R, "BOTTOM", 0, 0) -- kein Balken: Name dort, wo sonst der Balken saesse
    else
        fs:SetPoint("BOTTOMLEFT", R, "TOPLEFT", pxRound(N.x, unit), pxRound(L.padT + N.y, unit)) -- ein Anker: nie gekuerzt; frei ueber dem Rahmen (Ueberlappung verworfen)
    end
    -- feste, ganzzahlige Zeilenhoehe und unten ausgerichtet: die Schrift sitzt nicht auf halben Pixeln
    fs:SetHeight(pxRound(size * 1.3, unit))
    if fs.SetJustifyV then fs:SetJustifyV("BOTTOM") end
    setFontSafe(fs, face, size, N.flags)
    fs:SetShadowColor(N.shadow[1], N.shadow[2], N.shadow[3], N.shadow[4])
    fs:SetShadowOffset(N.shadowX, N.shadowY)
end
Style.LayoutNameText = layoutNameText

--- Namensfarbe nach Haltung (friedlich: gedaempfte Farben) oder nil
function Style.NameColor(stance, peaceful)
    return (peaceful and stance and Style.PEACEFUL.colors[stance]) or (stance and Style.NAME_COLORS[stance]) or nil
end

local function applyFont(uf, st, c)
    local bfs = field(uf, "name")
    local hb = healthBar(uf)
    if partOn(c, "font") and hb then
        if type(bfs) == "table" then hideRegions(st, "font", { bfs }) end
        local R = ensureRoot(st, uf, hb)
        local f = ensureNameText(st, uf)
        local fs = f.text
        local height = layoutHeight(hb, c)
        local N = Style.NAME
        local unit = Style.PixelUnit(hb)
        local peaceful = st.peaceful == true -- Baustein 5: nur Name, kleiner, mittig an der Stelle des Balkens
        local P = Style.PEACEFUL
        local size = peaceful and math.max(P.minSize, c.font.size + P.sizeDelta) or c.font.size
        if f.anchorBar ~= hb or f.anchorHeight ~= height or f.face ~= c.font.face or f.size ~= size or f.unit ~= unit
            or f.peaceful ~= peaceful then
            f.anchorBar, f.anchorHeight, f.face, f.size, f.unit, f.peaceful = hb, height, c.font.face, size, unit, peaceful
            layoutNameText(f, R, c.font.face, size, height, unit, peaceful)
        end
        local unit = field(uf, "unit")
        local stance = Style.Stance(unit)
        local F = Style.NameColor(stance, peaceful)
            or (type(unit) ~= "string" and st.lastNameColor) or Style.FONT_COLOR -- ohne Einheit: zuletzt gezeigte
        st.lastNameColor = F
        fs:SetTextColor(F[1], F[2], F[3])
        if type(unit) == "string" and type(UnitName) == "function" then
            local ok, name = pcall(UnitName, unit)
            if ok and name ~= nil then pcall(fs.SetText, fs, name) end -- auch ein geheimer Name geht unveraendert durch
        end
        local okL, lvl = call(hb, "GetFrameLevel")
        lvl = okL and Compat.Num(lvl) or nil
        if lvl then f:SetFrameLevel(lvl + 3) end
        f.veil:SetShown(c.font.veil == true)
        f.veil:SetAlpha(peaceful and P.veilAlpha or N.veilAlpha) -- friedlich: Schleier nur angedeutet
        -- Blizzard blendet den Namen bei vereinfachten Plaketten aus: dann auch Lucids Namen (nicht lesbar = zeigen)
        f:SetShown(Compat.QueryBool(bfs, "IsShown") ~= false)
        st.font = true
    elseif st.font then
        restoreRegions(st, "font")
        if st.nameText then
            st.nameText:Hide()
            st.nameText:SetAlpha(1)
        end
        st.font = false
    end
end

-- Baustein 8 (Teil): Stufe im Bronze-Plaettchen rechts am Balken ---------------------------------------
-- Blizzards Stufe und Rang-Symbol (ClassificationFrame mit classificationIndicator, z. B. goldener Elite-Drache links am
-- Namen): Lucid zeigt beides selbst (Plaettchen, Drachen-Medaille), deshalb Alpha 0 (wiederherstellbar)
local LEVEL_HIDE = { { "LevelFrame" }, { "PlayerLevelDiffFrame" }, { "ClassificationFrame" },
    { "ClassificationFrame", "classificationIndicator" } }

--- Stufentext: Zahl, "??" fuer Stufe -1 (Boss/zu hoch), nil wenn nicht lesbar
function Style.LevelText(unit)
    if type(unit) ~= "string" then return nil end
    local lvl = Compat.Num(readFlag(UnitLevel, unit))
    if not lvl then return nil end
    if lvl < 0 then return "??" end
    return tostring(math.floor(lvl))
end

-- Rang-Vorschau (/lucid nameplates style rank ...): ueberschreibt nur die Darstellung von Rang/Boss/Quest an allen
-- sichtbaren gestylten Plaketten (gleiche Funktionen wie der echte Stil), bis "off" oder /reload
Style.RANK_PREVIEW = {
    normal = { rank = nil, boss = false }, elite = { rank = "elite", boss = false }, rare = { rank = "rare", boss = false },
    rareelite = { rank = "rareelite", boss = false }, boss = { rank = nil, boss = true },
    eliteboss = { rank = "elite", boss = true }, quest = { quest = true },
    loot = { quest = true, obj = "loot" }, slay = { quest = true, obj = "slay" }, interact = { quest = true, obj = "interact" },
}
Style.RANK_PREVIEW_ORDER = { "normal", "elite", "rare", "rareelite", "boss", "eliteboss", "quest", "loot", "slay", "interact" }
local rankPreview = nil -- Schluessel aus RANK_PREVIEW oder nil
function Style.RankPreview() return rankPreview end

--- Rang der Einheit: "rareelite" | "elite" | "rare" | nil, dazu boss = Weltboss oder Stufe -1 (??)
function Style.Rank(unit)
    if type(unit) ~= "string" then return nil, false end
    local c = readFlag(UnitClassification, unit)
    if type(c) ~= "string" then c = nil end
    local lvl = Compat.Num(readFlag(UnitLevel, unit))
    local boss = c == "worldboss" or (lvl ~= nil and lvl < 0)
    if c == "rareelite" or c == "elite" or c == "rare" then return c, boss end
    return nil, boss
end

--- true, wenn die Stufe deutlich (RANK.diff) von der des Spielers abweicht; nicht lesbar = true (zeigen)
function Style.LevelDiffers(unit)
    local a = Compat.Num(readFlag(UnitLevel, unit))
    local b = Compat.Num(readFlag(UnitLevel, "player"))
    if not (a and b) then return true end
    return math.abs(a - b) >= Style.RANK.diff
end

local function buildLevelPlate(parent)
    local p = CreateFrame("Frame", nil, parent)
    p.tex = p:CreateTexture(nil, "ARTWORK")
    p.tex:SetTexture(Style.LEVEL_TEX)
    p.tex:SetAllPoints(p)
    snapTex(p.tex)
    p.text = p:CreateFontString(nil, "OVERLAY")
    p.text:SetAllPoints(p) -- Text fuellt das (gerade bemessene) Plaettchen, Ausrichtung macht die Schrift-Engine
    p.text:SetJustifyH("CENTER")
    if p.text.SetJustifyV then p.text:SetJustifyV("MIDDLE") end
    -- Totenkopf statt Zahl (Boss / Stufe ??)
    p.skull = p:CreateTexture(nil, "OVERLAY")
    p.skull:SetTexture(Style.SKULL_TEX)
    p.skull:SetPoint("CENTER", p, "CENTER", 0, 0)
    snapTex(p.skull)
    p.skull:Hide()
    p:Hide()
    return p
end
Style.BuildLevelPlate = buildLevelPlate

local function ensureLevelPlate(st, uf)
    if st.levelPlate then return st.levelPlate end
    st.levelPlate = buildLevelPlate((st.root and st.root.bars) or uf)
    return st.levelPlate
end

--- Plaettchen rechts neben den Container R legen: L = gerundetes Layout, w/h = Plaettchenmasse, bh = tatsaechliche
--- Balkenhoehe, face = Schrift. Gegen Zittern (Runde 10): an der Balken-Oberkante verankert statt an der Mitte (bei ungerader
--- Balkenhoehe laege sie auf einem halben Pixel), Masse auf eine gerade Pixelzahl, damit die mittig gesetzte Zahl auf ganzen
--- Pixeln sitzt.
local function placeLevelPlate(p, R, L, px, w, h, bh, face)
    p:ClearAllPoints()
    p:SetPoint("TOPLEFT", R, "TOPRIGHT", pxRound(L.padR + 1, px), pxRound((h - bh) / 2, px))
    p:SetSize(w, h)
    setFontSafe(p.text, face, L.levelFont)
    local S, LC = Style.SHADOW, Style.LEVEL_COLOR
    p.text:SetShadowColor(S.color[1], S.color[2], S.color[3], S.color[4])
    p.text:SetShadowOffset(S.x, S.y)
    p.text:SetTextColor(LC[1], LC[2], LC[3])
    local sk = pxRound(h * Style.RANK.skull, px)
    p.skull:SetSize(sk, sk)
end
Style.PlaceLevelPlate = placeLevelPlate

--- Drachen-Medaille hinter das Plaettchen p legen (nur bei geaenderten Massen neu verankern)
local function placeMedal(d, p, L, px, even, w, h)
    local mh = pxRound(L.total * Style.RANK.medal, even)
    local key = tostring(mh) .. tostring(px) .. tostring(w) .. tostring(h)
    if d.key ~= key then
        d.key = key
        local D = Style.RANK.disc
        d:ClearAllPoints()
        -- Scheibenmitte auf die Plaettchenmitte, leicht nach rechts (Kopf sichtbar); ganze Pixel
        d:SetPoint("TOPLEFT", p, "CENTER", pxRound(-mh * D.x + mh * Style.RANK.shift, px), pxRound(mh * D.y, px))
        d:SetSize(mh, mh)
    end
end
Style.PlaceMedal = placeMedal

--- Drachen-Medaille (Elite: Bronze, Rar/Rar-Elite: Silber): eigener Frame in der Balken-Gruppe hinter dem Plaettchen
local function buildRankDecor(parent)
    local d = CreateFrame("Frame", nil, parent)
    d.rare = d:CreateTexture(nil, "ARTWORK", nil, 0)
    d.rare:SetTexture(Style.RARE_TEX)
    d.rare:SetAllPoints(d)
    d.elite = d:CreateTexture(nil, "ARTWORK", nil, 1)
    d.elite:SetTexture(Style.ELITE_TEX)
    d.elite:SetAllPoints(d)
    for _, t in ipairs({ d.rare, d.elite }) do snapTex(t) end
    d:Hide()
    return d
end
Style.BuildRankDecor = buildRankDecor

local function ensureRankDecor(st, uf)
    if st.rankDecor then return st.rankDecor end
    st.rankDecor = buildRankDecor((st.root and st.root.bars) or uf)
    return st.rankDecor
end

local function applyLevel(uf, st, c)
    local hb = healthBar(uf)
    local unit = field(uf, "unit")
    local on = hb ~= nil and partOn(c, "levelRank")
    -- text: Stufe (String), false = bewusst aus (nur bei deutlichem Unterschied), nil = nicht lesbar
    local text, rank, boss = nil, nil, false
    if on then
        if type(unit) == "string" then
            text = Style.LevelText(unit)
            rank, boss = Style.Rank(unit)
            local pv = rankPreview and Style.RANK_PREVIEW[rankPreview]
            if pv and not pv.quest then rank, boss = pv.rank, pv.boss end
            if text and c.levelRank.onlyDiff and not boss and not Style.LevelDiffers(unit) then text = false end
            st.lastLevel, st.lastRank, st.lastBoss = text, rank, boss
        elseif st.level then
            text, rank, boss = st.lastLevel, st.lastRank, st.lastBoss -- ohne Einheit: zuletzt gezeigte
        end
    end
    local manage = on and (text ~= nil or rank ~= nil or boss)
    if manage then
        if not st.levelRegions then st.levelRegions = regionsAt(uf, LEVEL_HIDE) end
        hideRegions(st, "level", st.levelRegions)
        local R = ensureRoot(st, uf, hb)
        local p = ensureLevelPlate(st, uf)
        local height = layoutHeight(hb, c)
        local px = Style.PixelUnit(hb)
        local L = Style.SnapLayout(Style.Layout(height), px)
        local even = px and (2 * px) or nil
        local w, h = pxRound(L.levelW, even), pxRound(L.levelH, even)
        if p.anchorBar ~= hb or p.anchorHeight ~= height or p.unit ~= px then
            p.anchorBar, p.anchorHeight, p.unit = hb, height, px
            local okH, bh = call(hb, "GetHeight")
            bh = okH and Compat.Num(bh) or height
            placeLevelPlate(p, R, L, px, w, h, bh, c.font.face)
        end
        local okL, lvl = call(hb, "GetFrameLevel")
        lvl = okL and Compat.Num(lvl) or nil
        if lvl then p:SetFrameLevel(lvl + 3) end
        local rare = rank == "rare" or rank == "rareelite"
        local medal = rank ~= nil -- Elite/Rar/Rar-Elite: Drache hinter dem Plaettchen
        local showPlate = boss or type(text) == "string"
        p.text:SetText(type(text) == "string" and not boss and text or "")
        p.skull:SetShown(boss)
        p:SetShown(showPlate)
        if medal then
            local d = ensureRankDecor(st, uf)
            placeMedal(d, p, L, px, even, w, h)
            if lvl then d:SetFrameLevel(lvl + 2) end -- unter dem Plaettchen (lvl + 3)
            d.elite:SetShown(not rare)
            d.rare:SetShown(rare)
            d:Show()
        elseif st.rankDecor then
            st.rankDecor:Hide()
        end
        st.level = true
    elseif st.level then
        restoreRegions(st, "level")
        if st.levelPlate then
            st.levelPlate:Hide()
            st.levelPlate.skull:Hide()
        end
        if st.rankDecor then st.rankDecor:Hide() end
        st.level = false
    end
end

-- Baustein 9: Quest-Zeichen (goldenes Ausrufezeichen, Freigabe) links neben dem Namen ---------------
--- true, wenn die Einheit zu einer aktiven Quest gehoert (lesbar laut S0; secret/Fehler = nein)
function Style.QuestRelated(unit)
    if type(unit) ~= "string" then return false end
    local q = C_QuestLog and field(C_QuestLog, "UnitIsRelatedToActiveQuest")
    return readFlag(q, unit) == true
end

-- Questie-Bruecke (Wunsch): ist Questie geladen und bereit, ist Questie.API.GetQuestObjectiveIconForUnit(guid) die
-- Wahrheit fuer das Ziel-Symbol. Der gelieferte Icon-Pfad wird ueber Questies eigene Tabellen (Questie.icons, Profil
-- ICON_*) auf einen Typ abgebildet: loot -> Beutel, slay -> gekreuzte Schwerter, interact/event/talk -> Panzerhandschuh.
-- Kein Icon = kein Ziel (auch kein "!"). Nicht eindeutiger oder unbekannter Pfad: Lucid zeichnet nichts und laesst
-- Questies eigenes Symbol stehen. Questies Plaketten-Symbole (Kind-Frames der Plakette mit Icon/lastIcon) werden nur
-- dann auf Alpha 0 gesetzt, wenn Lucid an ihrer Stelle ein Symbol zeigt; sonst und beim Ausschalten zurueck.
-- Nur Lesen in Questies Tabellen, keine Aufrufe ausser der oeffentlichen API, kein Schreiben in Questie.
-- Platz des Ziel-Symbols: Hoehe size x Rahmenhoehe, Abstand gap (UI-Einheiten) vor der linken Rahmenkante
Style.QUEST_SYMBOL = { size = 1.4, gap = 1 }
Style.OBJ_TEX = { loot = MEDIA .. "np-obj-loot", slay = MEDIA .. "np-obj-slay", interact = MEDIA .. "np-obj-interact" }
Style.QUESTIE_KINDS = { -- Questie.icons-Schluessel bzw. Profilfeld -> Lucid-Typ
    icons = { loot = "loot", slay = "slay", interact = "interact", event = "interact", talk = "interact" },
    profile = { ICON_LOOT = "loot", ICON_SLAY = "slay", ICON_INTERACT = "interact", ICON_EVENT = "interact",
        ICON_TALK = "interact" },
}
local questieHidden = setmetatable({}, { __mode = "k" }) -- Questie-Frame -> urspruengliches Alpha

local function normPath(p)
    if type(p) == "number" then return tostring(p) end
    if type(p) ~= "string" then return nil end
    return (p:lower():gsub("/", "\\"))
end

--- Questie, falls bereit: API-Funktion und Questie-Tabelle
local function questieReady()
    local Q = _G.Questie
    if type(Q) ~= "table" then return nil end
    local api = field(Q, "API")
    if type(api) ~= "table" or field(api, "isReady") ~= true then return nil end
    local fn = field(api, "GetQuestObjectiveIconForUnit")
    if type(fn) ~= "function" then return nil end
    return fn, Q
end

--- Pfad -> Typ (false = mehrdeutig) und Menge aller bekannten Questie-Symbolpfade, aus Questies Tabellen;
--- zwischengespeichert, neu nur wenn sich Questie-Tabelle, Icon-Tabelle oder die Profil-Symbole aendern
local mapCache = { sig = nil, kinds = nil, all = nil, builds = 0 }
function Style.QuestieMapBuilds() return mapCache.builds end -- Diagnose/Test: wie oft die Tabellen neu gebaut wurden
local function questieSig(Q)
    local profile = field(field(Q, "db"), "profile")
    local sig = tostring(Q) .. "|" .. tostring(field(Q, "icons")) .. "|" .. tostring(profile)
    if type(profile) == "table" then
        for key in pairs(Style.QUESTIE_KINDS.profile) do sig = sig .. "|" .. tostring(field(profile, key)) end
    end
    return sig
end
local buildQuestieMaps
local function questieMaps(Q)
    local sig = questieSig(Q)
    if mapCache.sig ~= sig then
        mapCache.kinds, mapCache.all = buildQuestieMaps(Q)
        mapCache.sig, mapCache.builds = sig, mapCache.builds + 1
    end
    return mapCache.kinds, mapCache.all
end
function buildQuestieMaps(Q)
    local kinds, all = {}, {}
    local function add(path, kind)
        local k = normPath(path)
        if not k then return end
        all[k] = true
        if kind == nil then return end
        if kinds[k] == nil then kinds[k] = kind elseif kinds[k] ~= kind then kinds[k] = false end
    end
    local icons = field(Q, "icons")
    if type(icons) == "table" then
        for key, path in pairs(icons) do add(path, Style.QUESTIE_KINDS.icons[key] or "other") end
    end
    local profile = field(field(Q, "db"), "profile")
    if type(profile) == "table" then
        for key, kind in pairs(Style.QUESTIE_KINDS.profile) do add(field(profile, key), kind) end
    end
    return kinds, all
end

--- Ziel-Typ der Einheit nach Questie: kind ("loot"|"slay"|"interact") oder nil, Status ("ok"|"none"|"unknown"|
--- "unavailable"), Pfad
function Style.QuestieKind(unit)
    local fn, Q = questieReady()
    if not fn then return nil, "unavailable" end
    local guid = readFlag(UnitGUID, unit)
    if type(guid) ~= "string" then return nil, "unavailable" end
    local ok, path = pcall(fn, guid)
    if not ok then return nil, "unavailable" end
    if path == nil then return nil, "none" end
    local kinds = questieMaps(Q)
    local kind = kinds[normPath(path) or ""]
    if kind == "loot" or kind == "slay" or kind == "interact" then return kind, "ok", path end
    return nil, "unknown", path
end

--- Quest-Symbol einer Einheit nach derselben Regel wie Baustein 9: want (Symbol zeigen), kind ("loot"|"slay"|"interact" oder
--- nil fuer das "!"), Status (wie QuestieKind). Questie ist die Wahrheit; ohne Questie "!" ueber C_QuestLog.
function Style.QuestSymbol(unit)
    local k, status = Style.QuestieKind(unit)
    if status == "unavailable" then return Style.QuestRelated(unit), nil, status end
    return k ~= nil, k, status
end

local replacing = setmetatable({}, { __mode = "k" }) -- Plakette -> true, solange Lucid dort Questies Symbol ersetzt

--- gemerkte (ausgeblendete) Questie-Frames pruefen: haengt einer nicht mehr an einer Plakette, an der Lucid ersetzt,
--- oder ist sein Symbol keines von Questie mehr, kommt sein Alpha zurueck (Questie verschiebt Pool-Frames selbst)
local function auditQuestieHidden(all)
    for f, a in pairs(questieHidden) do
        local okP, parent = call(f, "GetParent")
        if not (okP and parent and replacing[parent] and all and all[normPath(field(f, "lastIcon")) or ""]) then
            call(f, "SetAlpha", a)
            questieHidden[f] = nil
        end
    end
end

--- Questies Symbol-Frames an der Plakette: ausblenden, wenn Lucid ersetzt, sonst (und ohne Stil) zurueck. Laeuft nur,
--- wenn Lucid hier ersetzt oder irgendwo Questie-Frames ausgeblendet hat (sonst nichts zu tun).
local function syncQuestieFrames(st, replace)
    local plate = st.plate
    if type(plate) ~= "table" then return end
    if replace then replacing[plate] = true else replacing[plate] = nil end
    if not replace and next(questieHidden) == nil then return end
    local Q = _G.Questie
    if type(Q) ~= "table" then
        auditQuestieHidden(nil)
        return
    end
    local _, all = questieMaps(Q)
    if replace then
        local n = select("#", plate:GetChildren())
        for i = 1, n do
            local f = select(i, plate:GetChildren())
            if questieHidden[f] == nil and type(field(f, "Icon")) == "table" and all[normPath(field(f, "lastIcon")) or ""] then
                local okA, a = call(f, "GetAlpha")
                questieHidden[f] = (okA and Compat.Num(a)) or 1
            end
            if questieHidden[f] ~= nil then call(f, "SetAlpha", 0) end
        end
    end
    auditQuestieHidden(all)
end

--- alle von Lucid ausgeblendeten Questie-Symbole zurueck (Stil aus)
local function restoreQuestieFrames()
    for f, a in pairs(questieHidden) do call(f, "SetAlpha", a) end
    questieHidden = setmetatable({}, { __mode = "k" })
    replacing = setmetatable({}, { __mode = "k" })
end
Style.RestoreQuestieFrames = restoreQuestieFrames
--- Questies Symbol an einer Plakette aus-/einblenden (Quest-Fernsicht, nur wenn der Stil nicht selbst ersetzt)
function Style.SyncQuestie(plate, replace) syncQuestieFrames({ plate = plate }, replace) end

--- Ziel-Symbol (Beutel/Schwerter/Handschuh/"!") als Kind des Containers R
local function buildSeal(R)
    local sf = CreateFrame("Frame", nil, R)
    sf.tex = sf:CreateTexture(nil, "OVERLAY")
    sf.tex:SetAllPoints(sf)
    snapTex(sf.tex)
    return sf
end
Style.BuildSeal = buildSeal

--- Symbol links neben der Leiste (vor der linken Rahmenkappe), senkrecht auf der Balkenmitte (Runde 6); kind = Typ
--- (loot/slay/interact) oder nil fuer das "!"; L = gerundetes Layout
local function placeSeal(sf, R, L, px, kind)
    local tex = kind and Style.OBJ_TEX[kind] or Style.QUEST_TEX
    if sf.texPath ~= tex then
        sf.texPath = tex
        sf.tex:SetTexture(tex)
    end
    local size = pxRound(L.total * Style.QUEST_SYMBOL.size, px) -- Hoehe
    local width = kind and size or pxRound(size / 2, px) -- Ziel-Symbole quadratisch, "!" halb so breit
    local key = tostring(size) .. tostring(px) .. tostring(width) .. tostring(L.padL)
    if sf.key ~= key then
        sf.key = key
        sf:ClearAllPoints()
        sf:SetPoint("RIGHT", R, "LEFT", -pxRound(L.padL + Style.QUEST_SYMBOL.gap, px), 0)
        sf:SetSize(width, size)
    end
end
Style.PlaceSeal = placeSeal

local function applyQuest(uf, st, c)
    local hb = healthBar(uf)
    local unit = field(uf, "unit")
    local want, kind = false, nil -- want: Symbol zeigen; kind: Questie-Typ (sonst "!")
    local pv = rankPreview and Style.RANK_PREVIEW[rankPreview]
    local pvQuest = pv and pv.quest and c ~= nil -- Rang-Vorschau: auch bei ausgeschaltetem Baustein 9
    if hb and (partOn(c, "questSeal") or pvQuest) then
        if type(unit) == "string" then
            if pvQuest then
                want, kind = true, pv.obj
                st.questie = { status = "preview" }
            else
                local k, status, path = Style.QuestieKind(unit)
                st.questie = { kind = k, status = status, path = path }
                if status == "unavailable" then
                    want = Style.QuestRelated(unit) -- ohne Questie: "!" ueber C_QuestLog
                else
                    want, kind = k ~= nil, k -- Questie ist die Wahrheit: kein Icon = kein Symbol
                end
            end
            st.lastQuest, st.lastQuestKind = want, kind
        else
            want, kind = st.lastQuest == true, st.lastQuestKind -- ohne Einheit: zuletzt gezeigt
        end
    end
    -- Questies eigenes Symbol nur ausblenden, wenn Lucid an seiner Stelle ein Questie-Symbol zeigt
    syncQuestieFrames(st, want and kind ~= nil and not pvQuest)
    if want then
        local R = ensureRoot(st, uf, hb)
        local sf = st.seal
        if not sf then
            sf = buildSeal(R)
            st.seal = sf
        end
        local px = Style.PixelUnit(hb)
        placeSeal(sf, R, Style.SnapLayout(Style.Layout(layoutHeight(hb, c)), px), px, kind)
        local okL, lvl = call(hb, "GetFrameLevel")
        lvl = okL and Compat.Num(lvl) or nil
        if lvl then sf:SetFrameLevel(lvl + 4) end
        sf:Show()
        st.quest = true
    elseif st.quest then
        if st.seal then st.seal:Hide() end
        st.quest = false
    end
end

-- Zielmarkierung (Blizzards RaidTargetFrame: Totenkopf, Kreis, Stern ...): bei aktivem Stil mittig UEBER dem Namen statt links vor
-- der Leiste (dort liegen die Quest-Symbole; 09.11.). Nur Anker und Groesse des Blizzard-Frames, nichts am Icon selbst.
-- Blizzard verankert den Frame ausschliesslich in NamePlateUnitFrameMixin:UpdateAnchors (Quelle Blizzard_NamePlateUnitFrame.lua,
-- 12.x): normal RIGHT am HealthBarsContainer-LEFT (0, 0), im Nur-Name-Modus BOTTOM am Namen-TOP (0, 10), Groesse 22 x 22 (XML).
-- Auf Plaketten sind Anker per GetPoint nicht immer lesbar (restricted): Lucid verschiebt den Frame trotzdem (der Mixin-Hook
-- ruft nach jedem UpdateAnchors erneut) und gibt beim Ausschalten die ORIGINAL-Anker zurueck, wenn sie lesbar waren, sonst
-- diese feste Blizzard-Standardverankerung. size = Kantenlaenge x Rahmenhoehe, gap = Abstand ueber dem Namen (UI-Einheiten).
Style.RAID = { size = 1.4, gap = 2, defaultNameSize = 12, defaultSize = 22, onlyNameOffset = 10 }

--- Zielmarkierung rf mittig ueber den Namen legen: R = Container, L = gerundetes Layout, nameSize = Schriftgroesse des Namens,
--- height = Balkenhoehe, peaceful = Name sitzt an der Stelle des Balkens. Auch fuer die Vorschau im Reiter (Style.PlaceRaid).
local function placeRaid(rf, R, L, px, nameSize, height, peaceful)
    local nameH = pxRound(nameSize * 1.3, px)
    local y
    if peaceful then
        y = math.max(0, nameH - height) + Style.RAID.gap -- kein Balken: Name steht unten im Container, ueber dem Balkenplatz
    else
        y = L.padT + Style.NAME.y + nameH + Style.RAID.gap -- Name: links, ueber dem Rahmen
    end
    local size = pxRound(L.total * Style.RAID.size, px)
    rf:ClearAllPoints()
    rf:SetPoint("BOTTOM", R, "TOP", 0, pxRound(y, px))
    rf:SetSize(size, size)
end
Style.PlaceRaid = placeRaid

--- Blizzards Standardverankerung des RaidTargetFrame wiederherstellen (Anker nicht lesbar gewesen)
local function restoreRaidDefault(uf, rf)
    rf:ClearAllPoints()
    if Compat.QueryBool(uf, "IsShowOnlyName") == true and type(field(uf, "name")) == "table" then
        rf:SetPoint("BOTTOM", field(uf, "name"), "TOP", 0, Style.RAID.onlyNameOffset)
    else
        local box = field(uf, "HealthBarsContainer")
        if type(box) ~= "table" then box = healthBar(uf) end
        if type(box) == "table" then rf:SetPoint("RIGHT", box, "LEFT", 0, 0) end
    end
end

local function applyRaidTarget(uf, st, c)
    local rf = field(uf, "RaidTargetFrame")
    local hb = healthBar(uf)
    local ok = c ~= nil and hb ~= nil and type(rf) == "table" and Compat.QueryBool(rf, "IsForbidden") ~= true
        and type(field(rf, "SetPoint")) == "function"
    if ok then
        local R = ensureRoot(st, uf, hb)
        local pts = readPoints(rf) -- nil, wenn nicht lesbar: dann wird trotzdem verschoben
        if pts and pts[1] and pts[1][2] ~= R then -- Original (erstes Mal bzw. Blizzard hat neu verankert)
            local okW, w = call(rf, "GetWidth")
            local okH, h = call(rf, "GetHeight")
            st.raidOrig = { points = pts, w = okW and Compat.Num(w) or nil, h = okH and Compat.Num(h) or nil }
        end
        st.raidReadable = pts ~= nil
        local height = layoutHeight(hb, c)
        local px = Style.PixelUnit(hb)
        local P = Style.PEACEFUL
        local peaceful = st.peaceful == true
        local nameSize = Style.RAID.defaultNameSize
        if partOn(c, "font") then
            nameSize = peaceful and math.max(P.minSize, c.font.size + P.sizeDelta) or c.font.size
        end
        placeRaid(rf, R, Style.SnapLayout(Style.Layout(height), px), px, nameSize, height, peaceful)
        st.raid = true
    elseif st.raid then
        local o = st.raidOrig
        if type(rf) == "table" then
            if o and o.points then setPoints(rf, o.points) else restoreRaidDefault(uf, rf) end
            local w, h = o and o.w, o and o.h
            call(rf, "SetSize", w or Style.RAID.defaultSize, h or Style.RAID.defaultSize)
        end
        st.raid = false
    end
end

-- Baustein 11: Zauberfaden -----------------------------------------------------------------------------
--- Blizzards Zauberleiste der Plakette (Aufbau zur Laufzeit) und der Pfad, auf dem sie gefunden wurde
local function findCastBar(uf)
    local cb = field(uf, "castBar")
    if type(cb) == "table" then return cb, "castBar" end
    local box = field(uf, "CastBarsContainer")
    if type(box) ~= "table" then return nil end
    for _, k in ipairs({ "castBar", "CastBar", "castingBar" }) do
        local x = field(box, k)
        if type(x) == "table" then return x, "CastBarsContainer." .. k end
    end
    local ok, kids = pcall(function() return { box:GetChildren() } end)
    for _, k in ipairs(ok and kids or {}) do
        local okT, t = call(k, "GetObjectType")
        if okT and t == "StatusBar" then return k, "CastBarsContainer[StatusBar]" end
    end
    return nil
end
Style.FindCastBar = findCastBar

--- Masse der Zauberleiste relativ zum Container (Lebensbalken) aus der Balkenhoehe, auf ganze Bildschirmpixel: Schlitz
--- (= Leiste) links/rechts/oben/Hoehe, Rand des Rahmens um den Schlitz, Kappenbreite, Schild
function Style.CastLayout(height, px)
    local L = Style.SnapLayout(Style.Layout(height), px)
    local G, C = Style.CAST_GEOMETRY, Style.CAST
    local fh = pxRound(L.total * C.frameScale, px)
    local sc = fh / G.h
    local inset = pxRound(C.inset * L.total, px)
    local frameTop = -L.padB + pxRound(C.dock, px) -- Oberkante der Laschen, unter der Container-Unterkante
    local CL = {
        sc = sc, fh = fh, cap = pxRound(G.cap * sc, px),
        slitL = pxRound(-L.padL + inset + G.left * sc, px), slitR = pxRound(L.padR - inset - G.right * sc, px),
        slitTop = pxRound(frameTop - G.top * sc, px),
        slitH = math.max(px or 1, pxRound((G.h - G.top - G.bottom) * sc, px)),
        padL = pxRound(G.left * sc, px), padR = pxRound(G.right * sc, px), padT = pxRound(G.top * sc, px),
        padB = pxRound(G.bottom * sc, px),
        shield = pxRound(fh * C.shield, px),
        bandMid = pxRound((G.bandTop + (G.h - G.bandTop) / 2) * sc, px), -- Bandmitte von der Rahmen-Oberkante
    }
    return CL
end

--- Leiste (Blizzards oder Lucids Simulation) in den Schlitz des Zauberleisten-Rahmens unter dem Lebensbalken legen;
--- liefert das Layout
local function placeCast(bar, R, height, px)
    local CL = Style.CastLayout(height, px)
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", R, "BOTTOMLEFT", CL.slitL, CL.slitTop)
    bar:SetPoint("TOPRIGHT", R, "BOTTOMRIGHT", CL.slitR, CL.slitTop)
    bar:SetHeight(CL.slitH)
    return CL
end
Style.PlaceCast = placeCast

--- Faden an einer Statusbar: Kind-Frame der Leiste (erbt Sichtbarkeit/Alpha), Spur ueber die ganze Breite, glimmender
--- Kern + Schein an der Fuellungs-Textur der Leiste (Breite = Fortschritt, ohne ihn zu lesen), silberne Lage fuer
--- "nicht unterbrechbar" (eigener Frame, Alpha per SetAlphaFromBoolean), Name klein darunter
local function buildThread(bar)
    local C = Style.CAST
    local t = CreateFrame("Frame", nil, bar)
    t:SetAllPoints(bar)
    t.track = t:CreateTexture(nil, "BACKGROUND")
    t.track:SetColorTexture(C.track[1], C.track[2], C.track[3], C.track[4])
    t.track:SetAllPoints(bar)
    -- Runde 7: Faden-Lagen in fester Groesse (ganze Schlitzbreite) in t.clipIn; t.clip (SetClipsChildren) reicht vom
    -- Schlitz links bis zur rechten Kante der Fuellungs-Textur und deckt sie auf (Textur wurde gestaucht).
    -- Der Kern liegt UNTER der Magie (vorher OVERLAY ueber ARTWORK: der unterbrechbare Faden war flach orange).
    t.clip = CreateFrame("Frame", nil, t)
    call(t.clip, "SetClipsChildren", true)
    t.clipIn = CreateFrame("Frame", nil, t.clip)
    local ci = t.clipIn
    t.halo = ci:CreateTexture(nil, "BACKGROUND")
    t.halo:SetTexture(Style.FILL_TEX)
    t.halo:SetVertexColor(C.color[1], C.color[2], C.color[3], C.haloAlpha)
    if t.halo.SetBlendMode then t.halo:SetBlendMode("ADD") end
    t.core = ci:CreateTexture(nil, "BORDER")
    t.core:SetColorTexture(1, 1, 1, 1)
    t.core:SetVertexColor(C.color[1], C.color[2], C.color[3])
    -- Magie: zwei stroemende Lagen ueber dem Kern (A deckt, B additiv und gespiegelt: Runen glimmen)
    t.flowA = ci:CreateTexture(nil, "ARTWORK", nil, 1)
    t.flowA:SetTexture(Style.CASTMAGIC_TEX, "REPEAT", "REPEAT")
    t.flowA:SetAlpha(Style.CAST_ANIM.aAlpha)
    t.flowB = ci:CreateTexture(nil, "ARTWORK", nil, 2)
    t.flowB:SetTexture(Style.CASTMAGIC_TEX, "REPEAT", "REPEAT")
    if t.flowB.SetBlendMode then t.flowB:SetBlendMode("ADD") end
    t.silverFrame = CreateFrame("Frame", nil, t) -- Schild (nicht unterbrechbar), ausserhalb des Clips
    t.silverFrame:SetAllPoints(t)
    t.silverFlow = CreateFrame("Frame", nil, ci) -- silberne Magie im Clip, Alpha wie silverFrame
    t.silverFlow:SetAllPoints(ci)
    t.silverFlow:SetAlpha(0)
    t.silver = t.silverFlow:CreateTexture(nil, "OVERLAY")
    t.silver:SetTexture(Style.CASTMAGIC_MONO_TEX, "REPEAT", "REPEAT") -- dieselbe Magie, silbrig getoent
    t.silver:SetVertexColor(C.silver[1], C.silver[2], C.silver[3])
    t.silverFrame:SetAlpha(0)
    -- Funken-Flash an der fuellenden Kante (ueber Rahmen und Silber)
    t.fx = CreateFrame("Frame", nil, t)
    t.fx:SetAllPoints(t)
    t.spark = t.fx:CreateTexture(nil, "OVERLAY")
    t.spark:SetTexture(Style.SPARK_TEX)
    if t.spark.SetBlendMode then t.spark:SetBlendMode("ADD") end
    -- Rahmen (3-teilig, ueber dem Faden) und Schild auf der linken Kappe (nur nicht unterbrechbar: in silverFrame)
    t.box = CreateFrame("Frame", nil, t)
    t.box.left, t.box.mid, t.box.right = threeSlice(t.box, "ARTWORK", Style.CASTFRAME_TEX,
        Style.CAST_GEOMETRY.cap / Style.CAST_GEOMETRY.w)
    -- Diagnose: liefert SetTexture false, fehlt die Datei im Client (neue Dateien erst nach Spiel-Neustart)
    local okF, r = pcall(t.box.left.SetTexture, t.box.left, Style.CASTFRAME_TEX)
    if not okF then t.frameOk = false elseif r == nil then t.frameOk = "?" else t.frameOk = r ~= false end
    t.shield = t.silverFrame:CreateTexture(nil, "OVERLAY", nil, 2)
    t.shield:SetTexture(Style.SHIELD_TEX)
    t.name = t:CreateFontString(nil, "OVERLAY")
    t.name:SetJustifyH("LEFT")
    if t.name.SetWordWrap then t.name:SetWordWrap(false) end
    for _, x in ipairs({ t.track, t.halo, t.core, t.flowA, t.flowB, t.silver, t.box.left, t.box.mid, t.box.right, t.shield }) do
        snapTex(x)
    end
    return t
end

--- Funken an die Fuellungskante: der helle Streifen der Textur sitzt auf der rechten Kante der Fuellung
local function anchorSpark(t)
    if not (t.fill and t.sparkSize) then return end
    local sz = t.sparkSize
    t.spark:ClearAllPoints()
    t.spark:SetPoint("CENTER", t.fill, "RIGHT", math.floor((0.5 - Style.CAST_ANIM.sparkStreak) * sz + 0.5), 0)
    t.spark:SetSize(sz, sz)
end

--- Animation des Fadens (je Bild): Stroemung nach rechts, Runen glimmen, Funken flackern; liest keine Zauberwerte
local function animateThread(t, dt)
    local A = Style.CAST_ANIM
    t.time = (t.time or 0) + (dt or 0)
    local tm = t.time
    local ua = (-tm * A.speedA) % 1
    local ub = (0.37 - tm * A.speedB) % 1
    t.flowA:SetTexCoord(ua, ua + A.repeatA, A.vA, A.vA + A.vSpan)
    t.flowB:SetTexCoord(ub + A.repeatB, ub, A.vB, A.vB + A.vSpan) -- gespiegelt
    t.flowB:SetAlpha(math.max(0, A.bBase + A.bAmp * math.sin(tm * 2 * math.pi / A.bPeriod)))
    t.silver:SetTexCoord(ua, ua + A.repeatA, A.vA, A.vA + A.vSpan)
    local f = 0.5 + 0.5 * math.sin(tm * A.sparkRate) * math.sin(tm * A.sparkRate * 0.61 + 1.3)
    t.spark:SetAlpha(A.sparkMin + (A.sparkMax - A.sparkMin) * f)
end
Style.AnimateThread = animateThread

--- Rahmen, Schild und Name des Fadens nach dem Layout ausrichten (nur bei Aenderung)
local function layoutThread(t, bar, CL)
    local key = tostring(CL.fh) .. "/" .. tostring(CL.slitH) .. "/" .. tostring(CL.cap)
    if t.layoutKey ~= key then
        t.layoutKey = key
        local b = t.box
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", bar, "TOPLEFT", -CL.padL, CL.padT)
        b:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", CL.padR, -CL.padB)
        b.left:SetWidth(CL.cap)
        b.right:SetWidth(CL.cap)
        t.shield:ClearAllPoints()
        t.shield:SetPoint("CENTER", b, "TOPLEFT", math.floor(CL.cap / 2 + 0.5), -CL.bandMid)
        t.shield:SetSize(CL.shield, CL.shield)
        t.name:ClearAllPoints()
        t.name:SetPoint("TOPLEFT", b, "BOTTOMLEFT", CL.padL, -1)
        t.sparkSize = math.floor(CL.fh * Style.CAST_ANIM.sparkSize + 0.5)
        anchorSpark(t)
    end
    local okL, lvl = call(t, "GetFrameLevel")
    lvl = okL and Compat.Num(lvl) or nil
    if lvl then
        t.clip:SetFrameLevel(lvl + 1)
        t.clipIn:SetFrameLevel(lvl + 1)
        t.silverFlow:SetFrameLevel(lvl + 2)
        t.box:SetFrameLevel(lvl + 3)
        t.silverFrame:SetFrameLevel(lvl + 4)
        t.fx:SetFrameLevel(lvl + 5)
    end
end

--- Clip an die (aktuelle) Fuellungs-Textur der Leiste, Lagen in fester Groesse ueber die ganze Leiste
local function anchorThread(t, bar, px)
    local ok, fill = call(bar, "GetStatusBarTexture")
    fill = (ok and type(fill) == "table") and fill or bar
    if t.fill == fill and t.px == px then return end
    t.fill, t.px = fill, px
    local hh = pxRound(Style.CAST.halo, px)
    t.clip:ClearAllPoints()
    t.clip:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, hh)
    t.clip:SetPoint("BOTTOMRIGHT", fill, "BOTTOMRIGHT", 0, -hh)
    t.clipIn:ClearAllPoints()
    t.clipIn:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, hh)
    t.clipIn:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, -hh)
    t.halo:ClearAllPoints()
    t.halo:SetAllPoints(t.clipIn)
    for _, x in ipairs({ t.core, t.flowA, t.flowB, t.silver }) do
        x:ClearAllPoints()
        x:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
        x:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    end
    anchorSpark(t)
end

--- Schrift des Zaubernamens (Lucid-Schrift, kleiner als der Name)
local function styleThreadName(t, c)
    local C = Style.CAST
    local face = c.font and c.font.face or "frizqt"
    local size = math.max(C.nameMin, (c.font and c.font.size or 12) + C.nameDelta)
    if t.face ~= face or t.size ~= size then
        t.face, t.size = face, size
        setFontSafe(t.name, face, size, Style.NAME.flags)
        local N = Style.NAME
        t.name:SetShadowColor(N.shadow[1], N.shadow[2], N.shadow[3], N.shadow[4])
        t.name:SetShadowOffset(N.shadowX, N.shadowY)
        local F = Style.FONT_COLOR
        t.name:SetTextColor(F[1], F[2], F[3])
    end
    t.name:SetShown(not (c.castThread and c.castThread.showName == false))
end

--- Zaubername und "nicht unterbrechbar" setzen (beides unveraendert durchgereicht, ggf. secret)
local function setCastInfo(t, name, notInterruptible)
    if Compat.IsSecret(name) or type(name) == "string" then pcall(t.name.SetText, t.name, name) end
    local ni = notInterruptible
    for _, sf in ipairs({ t.silverFrame, t.silverFlow }) do -- Schild und silberne Magie
        if Compat.IsSecret(ni) or type(ni) == "boolean" then
            if not (type(sf.SetAlphaFromBoolean) == "function" and pcall(sf.SetAlphaFromBoolean, sf, ni, 1, 0)) then
                -- ohne SetAlphaFromBoolean: nur lesbare Werte; ein Secret wird nicht verglichen (Glut)
                sf:SetAlpha((not Compat.IsSecret(ni) and ni == true) and 1 or 0)
            end
        else
            sf:SetAlpha(0)
        end
    end
end

Style.BuildThread, Style.AnchorThread, Style.LayoutThread = buildThread, anchorThread, layoutThread
Style.StyleThreadName, Style.SetCastInfo = styleThreadName, setCastInfo

--- Zauber der Einheit: Name, nicht unterbrechbar (Zauber oder Kanalisierung); nil, wenn keiner laeuft/nicht lesbar
local function isName(n) return Compat.IsSecret(n) or type(n) == "string" end

local function castInfo(unit)
    -- ohne Tabellen/Closures (laeuft alle CAST.tick s je zaubernder Plakette): Zauber (8. Rueckgabe = nicht unterbrechbar)
    -- bzw. Kanalisierung (7. Rueckgabe)
    if type(UnitCastingInfo) == "function" then
        local ok, n, _, _, _, _, _, _, ni = pcall(UnitCastingInfo, unit)
        if ok and isName(n) then return n, ni end
    end
    if type(UnitChannelInfo) == "function" then
        local ok, n, _, _, _, _, _, ni = pcall(UnitChannelInfo, unit)
        if ok and isName(n) then return n, ni end
    end
    return nil
end

-- Blizzards Leiste: Faden-Takt (laeuft nur, solange die Leiste sichtbar ist): Blizzards Regionen bleiben unsichtbar
-- (sie setzen Alpha/Animationen beim Zauberstart neu), Name/Unterbrechbarkeit alle CAST.tick s neu
Style.CAST_FRAME_DT = 0.033 -- Faden-Takt ~30 Hz (Animation, Blizzards Regionen unsichtbar halten)

local function threadTick(t, dt)
    local st = t.st
    if not (st and st.cast) then return end
    t.frameAcc = (t.frameAcc or 0) + dt
    if t.frameAcc < Style.CAST_FRAME_DT and t.seen then return end
    dt, t.frameAcc = t.frameAcc, 0
    animateThread(t, dt)
    -- Blizzard setzt Alpha/Animationen beim Zauberstart neu: nur auf 0 halten (die Originale merkt applyCast)
    local regs = st.castRegions
    if regs then
        for i = 1, #regs do
            local r = regs[i]
            pcall(r.SetAlpha, r, 0)
        end
    end
    t.acc = (t.acc or 0) + dt
    if t.acc < Style.CAST.tick and t.seen then return end
    t.acc, t.seen = 0, true
    anchorThread(t, t.bar, t.px)
    local unit = t.uf and field(t.uf, "unit")
    if type(unit) ~= "string" then return end
    setCastInfo(t, castInfo(unit))
end

local function applyCast(uf, st, c)
    local hb = healthBar(uf)
    local cb, path = nil, nil
    if hb and partOn(c, "castThread") then cb, path = findCastBar(uf) end
    if cb and Compat.QueryBool(cb, "IsForbidden") == true then cb = nil end
    st.castPath = path
    if cb then
        local R = ensureRoot(st, uf, hb)
        if not st.castOrig or st.castOrig.bar ~= cb then
            if st.castOrig and st.cast then -- andere Leiste (sollte nicht vorkommen): alte zurueck
                setPoints(st.castOrig.bar, st.castOrig.points or {})
            end
            local okH, h = call(cb, "GetHeight")
            st.castOrig = { bar = cb, points = readPoints(cb), height = okH and Compat.Num(h) or nil }
            st.castRegions = nil
        else
            -- Blizzard hat neu verankert (nicht an Lucids Container): das wird das neue Original
            local pts = readPoints(cb)
            if pts and pts[1] and pts[1][2] ~= R then
                st.castOrig.points = pts
                local okH, h = call(cb, "GetHeight")
                st.castOrig.height = okH and Compat.Num(h) or st.castOrig.height
            end
        end
        local px = Style.PixelUnit(hb)
        local height = layoutHeight(hb, c)
        local CL
        -- Original-Anker nicht lesbar: Blizzards Leiste wird nicht verschoben (sonst nicht wiederherstellbar); der Faden
        -- haengt dann an ihr, wo Blizzard sie hinlegt (style debug meldet es)
        local movable = st.castOrig.points ~= nil
        st.castFixed = not movable
        if movable then
            local key = tostring(R) .. "/" .. tostring(height) .. "/" .. tostring(px)
            local pts = readPoints(cb)
            local ours = pts and pts[1] and pts[1][2] == R
            if st.castKey ~= key or not ours then
                CL = placeCast(cb, R, height, px) -- nur bei geaendertem Layout oder wenn Blizzard neu verankert hat
                st.castKey, st.castLayout = key, CL
            else
                CL = st.castLayout
            end
        else
            CL = Style.CastLayout(height, px)
        end
        if not st.castRegions then
            local ok, regs = pcall(function() return { cb:GetRegions() } end)
            st.castRegions = {}
            for _, r in ipairs(ok and regs or {}) do
                if type(field(r, "SetAlpha")) == "function" then st.castRegions[#st.castRegions + 1] = r end
            end
        end
        hideRegions(st, "cast", st.castRegions)
        local t = st.castThread
        if not t or t.bar ~= cb then
            t = buildThread(cb)
            t.bar = cb
            t:SetScript("OnUpdate", function(self, dt)
                local ok, err = pcall(threadTick, self, dt)
                if not ok then recordError(err) end
            end)
            st.castThread = t
        end
        t.st, t.uf, t.px, t.seen = st, uf, px, nil
        anchorThread(t, cb, px)
        styleThreadName(t, c)
        local okL, lvl = call(cb, "GetFrameLevel")
        lvl = okL and Compat.Num(lvl) or nil
        if lvl then t:SetFrameLevel(lvl + 1) end
        layoutThread(t, cb, CL)
        t:Show()
        st.cast = true
    elseif st.cast then
        local o = st.castOrig
        if o and o.points then
            setPoints(o.bar, o.points)
            if o.height then call(o.bar, "SetHeight", o.height) end
        end
        st.castKey, st.castLayout = nil, nil
        restoreRegions(st, "cast")
        if st.castThread then st.castThread:Hide() end
        st.cast = false
    end
end

-- Zauber-Simulation (/lucid nameplates style cast): Lucid-eigene Leiste im Container an der Stelle des Fadens, mit
-- denselben Funktionen (placeCast, buildThread, anchorThread, styleThreadName, setCastInfo); Blizzards Zauberleiste
-- bekommt keine Fremdwerte
local sim = nil -- { bar, t0, dur }

--- Rang-Vorschau setzen ("off" = aus). Liefert true (an), false (aus) oder nil, Fehlerschluessel.
function Style.SetRankPreview(key)
    if key == "off" or key == "aus" then
        rankPreview = nil
        if active then Style.Refresh() end
        return false
    end
    if not Style.RANK_PREVIEW[key] then return nil, "NP_ST_RANK_USAGE" end
    if not engaged() then return nil, "NP_ST_RANK_NOSTYLE" end
    rankPreview = key
    Style.Refresh()
    return true
end

local function stopSim()
    if not sim then return end
    local s = sim
    sim = nil
    s.bar:SetScript("OnUpdate", nil)
    s.bar:Hide()
end
Style.StopCastSim = stopSim

-- Bausteine 4 und 5: Balken nur bei Bedarf, Friedlich nur Name -----------------------------------------
local inCombat = false -- Spieler im Kampf (lesbar; PLAYER_REGEN_DISABLED/ENABLED, beim Einschalten aus der API)

local function readCombat()
    return Compat.Bool(readFlag(UnitAffectingCombat, "player")) or Compat.Bool(readFlag(InCombatLockdown))
end

--- Friedlich: nicht angreifbarer NPC (UnitCanAttack lesbar false, kein Spieler, nicht von einem Spieler gesteuert).
--- Nicht lesbar = nicht friedlich (Balken bleibt).
function Style.IsPeaceful(unit)
    if type(unit) ~= "string" then return false end
    if readFlag(UnitCanAttack, "player", unit) ~= false then return false end
    if type(UnitIsPlayer) == "function" and readFlag(UnitIsPlayer, unit) ~= false then return false end
    if readFlag(UnitPlayerControlled, unit) == true then return false end
    return true
end

--- Zustand "friedlich" der Plakette neu bestimmen (ohne Einheit: zuletzt bestimmter)
local function updatePeaceful(uf, st, c)
    local unit = field(uf, "unit")
    if not partOn(c, "peaceful") then
        st.peaceful = false
    elseif type(unit) == "string" then
        st.peaceful = Style.IsPeaceful(unit)
    end
    return st.peaceful == true
end

-- Blizzards Balken (Container und Balken) bei friedlichen NPCs: Alpha 0, wiederherstellbar
local PEACEFUL_HIDE = { { "HealthBarsContainer" }, { "healthBar" } }

--- Alpha von "bars" aus der Blend-Stufe: 1 ohne Kurve, sonst Kurvenwert (secret); ohne Einheit bleibt der letzte Stand.
--- Scheitert die Kurve: Balken sichtbar (still).
function setDemandAlpha(uf, st)
    local bars = st.root and st.root.bars
    if not bars then return end
    local lvl = st.demandLevel or 1
    local k = math.floor(lvl * Style.DEMAND.steps + 0.5)
    if not st.demandOn or k >= Style.DEMAND.steps then
        bars:SetAlpha(1)
        st.demandMode = st.demandOn and "full" or "off"
        return
    end
    local unit = field(uf, "unit")
    if type(unit) ~= "string" then return end
    if setCurveAlpha(bars, healthValue(unit, demandCurve(k))) then
        st.demandMode = "curve"
    else
        bars:SetAlpha(1)
        st.demandMode = "fallback"
    end
end

--- Ziel-Alpha bei vollem Leben: 1 im Kampf oder (einstellbar) am Ziel, sonst 0 (nur Name)
local function demandGoal(c, isTarget)
    if inCombat then return 1 end
    if isTarget and c.barOnDemand.target ~= false then return 1 end
    return 0
end

local function applyMood(uf, st, c)
    local unit = field(uf, "unit")
    local hasUnit = type(unit) == "string"
    local peaceful = updatePeaceful(uf, st, c)
    local isTarget = st.moodTarget == true
    if hasUnit then isTarget = readFlag(UnitIsUnit, unit, "target") == true end
    st.moodTarget = isTarget
    -- Baustein 5: Blizzards Balken aus, Lucids Balken-Gruppe versteckt, Name blass (als Ziel voll deckend)
    if peaceful then
        if not st.peacefulRegions then st.peacefulRegions = regionsAt(uf, PEACEFUL_HIDE) end
        hideRegions(st, "peaceful", st.peacefulRegions)
    else
        restoreRegions(st, "peaceful")
    end
    if st.nameText then st.nameText:SetAlpha((peaceful and not isTarget) and Style.PEACEFUL.alpha or 1) end
    local bars = st.root and st.root.bars
    if bars then bars:SetShown(c ~= nil and not peaceful) end -- Stil aus: ganze Gruppe weg (Alpha unten zurueck auf 1)
    -- Baustein 4: nur mit Lucids Balken (Baustein 1), nicht bei friedlichen, nicht bei gestoertem Kurvenweg
    local demand = not peaceful and bars ~= nil and partOn(c, "barOnDemand") and partOn(c, "frame") and curveApi()
    if demand then
        if not hasUnit and st.demandOn then return end -- ohne Einheit: letzter Stand
        local goal = demandGoal(c, isTarget)
        if st.demandFresh or not st.demandOn or st.demandLevel == nil then
            st.demandLevel = goal -- neue Plakette/Einheit oder frisch eingeschaltet: sofort, ohne Blende
            fading[uf] = nil
        elseif st.demandLevel ~= goal then
            fading[uf] = true -- Kampfbeginn/-ende, Zielwechsel: weich ueber den Treiber
            wakeDriver()
        end
        st.demandFresh = nil
        st.demandGoal, st.demandOn = goal, true
    else
        st.demandOn, st.demandGoal, st.demandLevel, st.demandFresh = false, nil, 1, nil
        fading[uf] = nil
    end
    setDemandAlpha(uf, st)
end

-- Anwenden / Wiederherstellen -----------------------------------------------------------------------
local function applyAll(uf, st)
    local c = wantFor(uf)
    updatePeaceful(uf, st, c) -- vor dem Namen (Groesse/Lage)
    applyFrame(uf, st, c)
    -- Ohne Einheit (Plakette wird nach dem Abwaehlen ausgeblendet/entfernt; Blizzard ruft dabei UpdateAll mit unit=nil
    -- und faerbt z. B. grau) setzen Farbe/Name/Stufe den zuletzt gezeigten Stil erneut (Cache am Zustand). Die
    -- Originale kommen nur beim Ausschalten zurueck; ein wiederverwendeter Frame wird beim naechsten Hinzufuegen neu
    -- gestylt.
    applyColors(uf, st, c)
    applyFont(uf, st, c)
    applyLevel(uf, st, c)
    applyQuest(uf, st, c)
    applyRaidTarget(uf, st, c)
    applyCast(uf, st, c)
    applyMood(uf, st, c)
end

local function safeApply(uf, st)
    if Compat.QueryBool(uf, "IsForbidden") == true then return end -- auch bekannte Frames: forbidden nie anfassen
    local ok, err = pcall(applyAll, uf, st)
    if not ok then recordError(err) end
end

local function targetFrame()
    if not (UnitExists and Compat.Bool(readFlag(UnitExists, "target"))) then return nil end
    return frameOfUnit("target")
end

--- Zauber-Simulation an der Ziel-Plakette an/aus. sec (Sekunden), name (bereits bereinigt), nokick. Liefert true
--- (laeuft), false (beendet) oder nil, Fehlerschluessel.
function Style.CastSim(sec, name, nokick)
    if sim then
        stopSim()
        return false
    end
    local uf = targetFrame()
    if not uf then
        if not Compat.Bool(readFlag(UnitExists, "target")) then return nil, "NP_ST_TEST_NOTARGET" end
        return nil, "NP_ST_TEST_NOPLATE"
    end
    local st = stateFor(uf)
    local c = st and wantFor(uf)
    local hb = healthBar(uf)
    if not (c and hb) then return nil, "NP_ST_CAST_NOSTYLE" end
    local R = ensureRoot(st, uf, hb)
    local bar = st.simBar
    if not bar then
        bar = CreateFrame("StatusBar", nil, R)
        call(bar, "SetStatusBarTexture", Style.FILL_TEX)
        call(bar, "SetMinMaxValues", 0, 1)
        bar.thread = buildThread(bar)
        st.simBar = bar
    end
    local okT, fill = call(bar, "GetStatusBarTexture")
    if okT and type(fill) == "table" then call(fill, "SetAlpha", 0) end -- wie Blizzards Fuellung: nur der Faden zeigt
    local px = Style.PixelUnit(hb)
    local CL = placeCast(bar, R, layoutHeight(hb, c), px)
    local okL, lvl = call(hb, "GetFrameLevel")
    lvl = okL and Compat.Num(lvl) or nil
    if lvl then bar:SetFrameLevel(lvl + 3) end
    local t = bar.thread
    call(bar, "SetValue", 0)
    anchorThread(t, bar, px)
    if lvl then t:SetFrameLevel(lvl + 4) end
    layoutThread(t, bar, CL)
    styleThreadName(t, c)
    setCastInfo(t, name, nokick == true)
    local dur = sec
    sim = { bar = bar, t0 = 0, dur = dur }
    local elapsed = 0
    animateThread(t, 0)
    bar:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        animateThread(t, dt)
        call(self, "SetValue", math.min(1, elapsed / dur))
        if elapsed >= dur then stopSim() end
    end)
    bar:Show()
    t:Show()
    return true
end
function Style.CastSimActive() return sim ~= nil end

--- Vorschau der Ziel-Plakette nachziehen (Zielwechsel, Plakette neu/entfernt)
local function syncTest()
    local want = (active and testActive and not blocker) and targetFrame() or nil
    if not (active and testActive and not blocker) then
        -- Vorschau zu Ende: alle Vorschau-Plaketten zurueck
        local list = {}
        for uf in pairs(testSticky) do list[#list + 1] = uf end
        testSticky = setmetatable({}, { __mode = "k" })
        for _, uf in ipairs(list) do if states[uf] then safeApply(uf, states[uf]) end end
    end
    if want then testSticky[want] = true end
    if want == testFrame then return end
    local old = testFrame
    testFrame = want
    if old and states[old] then safeApply(old, states[old]) end -- bleibt ueber testSticky gestylt
    if want then
        local st = stateFor(want)
        if st then safeApply(want, st) end
    end
end

-- Hooks ----------------------------------------------------------------------------------------------
-- cuf = CompactUnitFrame_*-Hook: laeuft auch fuer jeden Raid-/Gruppenrahmen, deshalb vor dem pcall billig
-- verwerfen, was kein bekannter oder als Plakette benannter Frame ist (nur Tabellen-Lesen, keine Closure)
-- Spur (/lucid nameplates style trace): fuer TRACE_SECONDS alle Hook-Aufrufe und Plaketten-Ereignisse mit
-- Zeitstempel, Einheit und dem, was Lucid tat. Nur Plaketten-Frames (Raidrahmen werden nicht aufgezeichnet).
Style.TRACE_SECONDS, Style.TRACE_MAX = 5, 400
local trace = nil -- { t0, lines }

local function traceUnit(v)
    if v == nil then return "nil" end
    if Compat.IsSecret(v) then return "secret" end
    return tostring(v)
end

local function traceAdd(name, unit, action)
    if not trace or #trace.lines >= Style.TRACE_MAX then return end
    local now = type(GetTime) == "function" and GetTime() or 0
    trace.lines[#trace.lines + 1] = ("%6.3f  %-42s unit=%-12s %s"):format(now - trace.t0, name, traceUnit(unit), action)
end

local function traceHook(name, frame, isUnitArg, arg1)
    local unit, action
    if isUnitArg then
        unit = arg1
        action = engaged() and L.NP_ST_TR_APPLIED or L.NP_ST_TR_OFF
    else
        if type(frame) ~= "table" then return end
        unit = rawget(frame, "unit")
        local known = states[frame] ~= nil
        if not known and not (type(unit) == "string" and unit:find("^nameplate")) then return end -- kein Plakettenframe
        if not engaged() then
            action = L.NP_ST_TR_OFF
        elseif wantFor(frame) then
            action = type(unit) == "string" and L.NP_ST_TR_APPLIED or L.NP_ST_TR_CACHED
        else
            action = L.NP_ST_TR_RESTORED
        end
    end
    traceAdd(name, unit, action)
end

local function guarded(fn, cuf, name)
    return function(frame, ...)
        if trace then pcall(traceHook, name or "?", frame, not cuf, ...) end
        if not engaged() then return end
        if cuf then
            if type(frame) ~= "table" then return end
            if not states[frame] then
                local unit = rawget(frame, "unit")
                if type(unit) ~= "string" or not unit:find("^nameplate") then return end
            end
        end
        local ok, err = pcall(fn, frame, ...)
        if not ok then recordError(err) end
    end
end

-- CompactUnitFrame_*: nur Plaketten-UnitFrames, nur der betroffene Baustein
local function partHook(apply, unitBound)
    return function(frame)
        local st = stateFor(frame)
        if not st then return end
        local c = wantFor(frame)
        apply(frame, st, c)
    end
end

Style.HOOKS = { -- Reihenfolge = Ausgabe in style debug
    { name = "CompactUnitFrame_UpdateHealthColor", fn = partHook(applyColors, true) },
    { name = "CompactUnitFrame_UpdateName", fn = partHook(applyFont, true) },
    { name = "CompactUnitFrame_UpdateHealthBorder", fn = partHook(applyFrame) },
    { name = "CompactUnitFrame_UpdateSelectionHighlight", fn = partHook(applyFrame) }, -- gelber Ziel-Rand, Ziel-Glut
    { name = "CompactUnitFrame_UpdateAggroHighlight", fn = partHook(applyFrame) },
    { name = "CompactUnitFrame_UpdateLevel", fn = partHook(applyLevel, true) },
    { name = "CompactUnitFrame_UpdateAll", fn = function(frame)
        local st = stateFor(frame)
        if st then applyAll(frame, st) end
    end },
    { driver = true, name = "OnNamePlateAdded", fn = function(_, unit)
        if type(unit) ~= "string" then return end
        local uf = frameOfUnit(unit)
        local st = uf and stateFor(uf)
        if uf then testSticky[uf] = nil end -- wiederverwendeter Frame: Vorschau gilt nur, wenn er jetzt das Ziel ist
        if st then
            st.demandFresh = true -- neue Einheit: Balken-Bedarf ohne Blende
            st.lastQuest, st.lastQuestKind, st.questie = nil, nil, nil -- Pool-Frame: altes Ziel-Symbol nie uebernehmen
        end
        syncTest()
        if st then applyAll(uf, st) end
        -- Questie legt sein Plaketten-Symbol im selben Ereignis an (Reihenfolge offen): kurz danach erneut auswerten
        if st and C_Timer and C_Timer.After then
            C_Timer.After(Style.QUESTIE_RECHECK, function()
                if not engaged() or rawget(uf, "unit") ~= unit then return end
                local ok, err = pcall(applyQuest, uf, st, wantFor(uf))
                if not ok then recordError(err) end
            end)
        end
    end },
    { driver = true, name = "OnNamePlateRemoved", fn = function()
        syncTest()
        -- entfernte Plaketten (ohne Einheit oder unsichtbar): Fuellung/Schein vom Treiber abmelden
        for uf, st in pairs(states) do
            if st.overlay and (type(rawget(uf, "unit")) ~= "string" or Compat.QueryBool(uf, "IsVisible") == false) then
                stopAnimation(st.overlay)
            end
        end
    end },
    { driver = true, name = "OnTargetChanged", fn = function()
        syncTest()
        for uf, st in pairs(states) do -- Ziel-Glut wandert mit (nur sichtbare Plaketten mit Einheit)
            if Compat.QueryBool(uf, "IsForbidden") ~= true and type(rawget(uf, "unit")) == "string"
                and Compat.QueryBool(uf, "IsVisible") ~= false then
                local c = wantFor(uf)
                local ok, err = pcall(applyFrame, uf, st, c)
                if ok then ok, err = pcall(applyMood, uf, st, c) end -- Ziel: Balken blendet ein, Name voll
                if not ok then recordError(err) end
            end
        end
    end },
    { driver = true, name = "UpdateNamePlateOptions", fn = function()
        for uf, st in pairs(states) do safeApply(uf, st) end
    end },
}

-- Blizzards NamePlateUnitFrameMixin (12.x/Forever) setzt in UpdateAnchors die Anker von Balken und Name und die
-- Containerhoehe neu, in ApplyFrameOptions Schriftobjekt und -hoehe; beides laeuft auch nach dem Hinzufuegen (Ziel-,
-- Vereinfacht-, Nur-Name-Wechsel). Gehookt wird das Mixin selbst (hooksecurefunc auf die Blizzard-Tabelle, keine Felder
-- an Frames): Plaketten-Frames, die danach entstehen, erben den Nachher-Hook. Deshalb schon beim Laden installiert
-- (ohne Stil sofort beendet, s. guarded), sonst kaemen bereits erzeugte Plaketten nie dazu.
Style.MIXIN_HOOKS = { "UpdateAnchors", "ApplyFrameOptions" }
local mixinHooked = false
local function mixinHook(frame)
    local st = stateFor(frame)
    if st then applyAll(frame, st) end
end
local function installMixinHooks()
    if mixinHooked then return end
    local mx = _G.NamePlateUnitFrameMixin
    if type(mx) ~= "table" or type(hooksecurefunc) ~= "function" then
        for _, m in ipairs(Style.MIXIN_HOOKS) do hookStatus["NamePlateUnitFrameMixin." .. m] = "missing" end
        return
    end
    mixinHooked = true
    for _, m in ipairs(Style.MIXIN_HOOKS) do
        local key = "NamePlateUnitFrameMixin." .. m
        if type(field(mx, m)) ~= "function" then
            hookStatus[key] = "missing"
        else
            hookStatus[key] = pcall(hooksecurefunc, mx, m, guarded(mixinHook, true, "NamePlateUnitFrameMixin." .. m)) and "ok" or "failed"
        end
    end
end
installMixinHooks()
ns.On("ADDON_LOADED", function(_, name)
    if name == "Blizzard_NamePlates" then installMixinHooks() end
end)

local function installHooks()
    if hooksInstalled then return end
    hooksInstalled = true
    local driver = _G.NamePlateDriverFrame
    for _, h in ipairs(Style.HOOKS) do
        local key = h.driver and ("NamePlateDriverFrame." .. h.name) or h.name
        local target = h.driver and driver or _G
        if type(hooksecurefunc) ~= "function" or type(target) ~= "table" or type(field(target, h.name)) ~= "function" then
            hookStatus[key] = "missing" -- fehlt im Client: still uebergehen
        else
            local ok
            if h.driver then
                ok = pcall(hooksecurefunc, driver, h.name, guarded(h.fn, false, "NamePlateDriverFrame." .. h.name))
            else
                ok = pcall(hooksecurefunc, h.name, guarded(h.fn, true, h.name))
            end
            hookStatus[key] = ok and "ok" or "failed"
        end
    end
end

-- Baustein 10: Tiefe ueber Plaketten-CVars (eigene Instanz des CVar-Treibers: Sicherung, owned-Marker, Kampfpuffer) --
Style.DEPTH_CVARS = { "nameplateMinScale", "nameplateMaxScale", "nameplateMinScaleDistance", "nameplateMaxScaleDistance",
    "nameplateMinAlpha", "nameplateMaxAlpha", "nameplateMinAlphaDistance", "nameplateMaxAlphaDistance",
    "nameplateSelectedScale" }
local DepthCVars = ns.CVarDriver.New("nameplatestyle", Style.DEPTH_CVARS)
Style.DepthCVars = DepthCVars

local function num2(x) return (("%.2f"):format(x):gsub("0+$", ""):gsub("%.$", "")) end

--- Sollwerte der Tiefe (name -> String) oder leere Tabelle. Ferne Grenze hoechstens der B7-Radius (sonst wirkte die
--- Tiefe bei kleinem Radius kaum), nahe Grenze hoechstens die Haelfte der fernen.
function Style.DepthDesired(sc, npc)
    local d = {}
    if not (sc and sc.enabled and type(sc.depth) == "table" and sc.depth.enabled) then return d end
    local D = sc.depth
    local far, near = D.far, D.near
    if npc and npc.enabled and type(npc.radius) == "table" and npc.radius.enabled and type(npc.radius.yards) == "number" then
        far = math.min(far, npc.radius.yards)
    end
    near = math.min(near, far / 2)
    d.nameplateMinScale, d.nameplateMaxScale = num2(D.minScale), "1"
    d.nameplateMaxScaleDistance, d.nameplateMinScaleDistance = num2(near), num2(far)
    d.nameplateMinAlpha, d.nameplateMaxAlpha = num2(D.minAlpha), "1"
    d.nameplateMaxAlphaDistance, d.nameplateMinAlphaDistance = num2(near), num2(far)
    return d
end

--- Groessen-Sollwerte (Zielgroesse, "alle gleich gross"): Ziel-Plakette = nameplateSelectedScale (Blizzard sonst 1,2); gleich gross
--- = Entfernungs-Skalierung neutral (Min-/Max-Scale 1). Ist Tiefe (Baustein 10) an, bestimmt sie die Min-Scale (Vorrang): dann
--- wirkt "gleich gross" nicht (depth = true, der Reiter graut den Schalter aus).
function Style.SizeDesired(sc, depthOn)
    local d = {}
    if not (sc and sc.enabled) then return d end
    local ts = type(sc.targetScale) == "number" and sc.targetScale or 1
    d.nameplateSelectedScale = num2(ts)
    if sc.uniformSize ~= false and not depthOn then
        d.nameplateMinScale, d.nameplateMaxScale = "1", "1"
    end
    return d
end

--- Tiefe und Groessen herstellen: Stil an (nicht nur Vorschau), kein Fremd-Addon => Sollwerte; sonst Besitz zurueck
--- Quest-Fernsicht + B7-Radius: nameplateMaxDistance steht auf der Fernsicht-Reichweite, der Radius wirkt dann ueber Blizzards
--- Entfernungs-Alpha (ab Radius Alpha 0; laut Probe ist das Ziel ausgenommen, die Fern-Symbole ignorieren die Plaketten-Alpha).
--- Vorrang vor der Alpha-Haelfte der Tiefe (Baustein 10, Groesse bleibt). Liefert die Sollwerte oder nil.
function Style.RadiusAlphaDesired(npc)
    if not (npc and Nameplates.QuestFarOn(npc) and npc.radius and npc.radius.enabled) then return nil end
    local r = npc.radius.yards
    return { nameplateMinAlpha = "0", nameplateMaxAlpha = "1", nameplateMaxAlphaDistance = num2(math.max(0, r - 1)),
        nameplateMinAlphaDistance = num2(r) }
end

local function applyDepth()
    local want = active and not blocker and cfg and cfg.enabled
    local d = {}
    local npc = Nameplates.GetConfig()
    if want then
        local depthOn = partOn(cfg, "depth")
        if depthOn then d = Style.DepthDesired(cfg, npc) end
        for k, v in pairs(Style.SizeDesired(cfg, depthOn)) do d[k] = v end
    end
    local ra = active and Style.RadiusAlphaDesired(npc)
    if ra then for k, v in pairs(ra) do d[k] = v end end
    local ok, err = pcall(DepthCVars.Apply, d)
    if not ok then recordError(err) end
end

-- Steuerung ------------------------------------------------------------------------------------------
--- Einstellungen neu lesen und auf alle bekannten und sichtbaren Plaketten anwenden (bzw. zurueckstellen).
local refreshStyle
function Style.Refresh()
    refreshStyle()
    if ns.QuestFar then ns.QuestFar.Refresh() end
end
function refreshStyle()
    cfg = Nameplates.GetConfig().style
    blocker = Style.Conflict()
    if engaged() then installHooks() end
    updateListeners(engaged()) -- Stil aus: keine Leben-/Kampf-/Quest-Ereignisse
    applyDepth()
    if not engaged() then
        stopSim()
        restoreQuestieFrames()
    end
    fading = setmetatable({}, { __mode = "k" }) -- laufende Blenden enden (applyMood setzt den Stand neu)
    syncTest()
    for uf, st in pairs(states) do safeApply(uf, st) end
    if not engaged() then return end
    if not (C_NamePlate and type(C_NamePlate.GetNamePlates) == "function") then return end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok or type(plates) ~= "table" then return end
    for _, plate in ipairs(plates) do
        if Compat.QueryBool(plate, "IsForbidden") ~= true then
            local uf = field(plate, "UnitFrame")
            local st = stateFor(uf)
            if st then safeApply(uf, st) end
        end
    end
end

--- Anzahl der Plaketten mit mindestens einem angewendeten Baustein
function Style.StyledCount()
    local n = 0
    for _, st in pairs(states) do
        if st.frame or st.bar or st.colors or st.font or st.level or st.peaceful or st.quest or st.cast or st.raid then n = n + 1 end
    end
    return n
end

function Style.HookStatus() return hookStatus, hooksInstalled end
function Style.Errors() return errors, errorCount end
function Style.IsTestActive() return testActive end
function Style.Blocker() return blocker end
function Style.IsEngaged() return engaged() == true end

--- Vorschau an der Ziel-Plakette an/aus. Liefert true (an), false (aus) oder nil, Fehlerschluessel.
function Style.ToggleTest()
    if testActive then
        testActive = false
        Style.Refresh()
        return false
    end
    blocker = Style.Conflict()
    if blocker then return nil, "NP_ST_BLOCKED" end
    if not targetFrame() then
        if not Compat.Bool(readFlag(UnitExists, "target")) then return nil, "NP_ST_TEST_NOTARGET" end
        return nil, "NP_ST_TEST_NOPLATE"
    end
    testActive = true
    Style.Refresh()
    return true
end

ns.RegisterModule("nameplatestyle", {
    OnEnable = function()
        active = true
        inCombat = readCombat()
        Style.Refresh()
    end,
    OnDisable = function()
        active = false
        testActive = false
        Style.Refresh()
    end,
})

-- spaet geladene Fremd-Plaketten-Addons (Ladeanforderung) und ElvUI-Einstellung nach dem Login
ns.On("ADDON_LOADED", function(_, name)
    if not active then return end
    for _, n in ipairs(Style.CONFLICT_ADDONS) do
        if n == name then Style.Refresh() return end
    end
end)
ns.On("PLAYER_ENTERING_WORLD", function()
    if active and Style.Conflict() ~= blocker then Style.Refresh() return end
    if active then applyDepth() end -- Zonenwechsel: Blizzard setzt Plaketten-Einstellungen teils zurueck
end)
-- Tiefe: ausstehende CVar-Schreibzugriffe nach dem Kampf (auch wenn der Stil inzwischen aus ist: Rueckgabe)
ns.On("PLAYER_REGEN_ENABLED", function()
    if active then pcall(DepthCVars.Flush) end
end)
Compat.TryOn("PLAYER_LOGOUT", function()
    if active then pcall(DepthCVars.RestoreAll) end
end)

ns.Store.RegisterCallback(function()
    if active then Style.Refresh() end
end)

-- Bausteine 4/7: Leben einer Plakette geaendert -> Kurvenwerte neu (Raid-/Spielerrahmen-Einheiten sofort verworfen)
local function onHealth(_, unit)
    if not engaged() or type(unit) ~= "string" or Compat.IsSecret(unit) or not unit:find("^nameplate") then return end
    local uf = frameOfUnit(unit)
    local st = uf and states[uf]
    if not st or ns.Plates.IsHidden(uf) then return end -- versteckt: beim Sichtbarwerden nachgezogen (s. u.)
    local ok, err = pcall(function()
        if st.demandOn then setDemandAlpha(uf, st) end
        applyEmber(uf, st)
    end)
    if not ok then recordError(err) end
end

-- B7 blendet eine Plakette ein: Kurvenwerte (Leben kann sich im Versteck geaendert haben) nachziehen, Treiber wecken
ns.Plates.AddListener(function(uf, target)
    if not (engaged() and target and target > 0) then return end
    local st = states[uf]
    if not st then return end
    local ok, err = pcall(function()
        if st.demandOn then setDemandAlpha(uf, st) end
        applyEmber(uf, st)
    end)
    if not ok then recordError(err) end
    if st.overlay and animated[st.overlay] then wakeDriver(nil) end
end)

-- Baustein 4: Kampfbeginn/-ende (Events zuerst, die API hinkt beim Event nach) -> Balken blenden weich ein/aus
local function onCombat(on)
    inCombat = on
    if not engaged() then return end
    for uf, st in pairs(states) do
        if Compat.QueryBool(uf, "IsForbidden") ~= true and type(rawget(uf, "unit")) == "string" then
            local ok, err = pcall(applyMood, uf, st, wantFor(uf))
            if not ok then recordError(err) end
        end
    end
end
local function onRegenDisabled() onCombat(true) end
local function onRegenEnabled() onCombat(false) end

-- Baustein 9: Questlog geaendert -> Ziel-Symbole der sichtbaren Plaketten neu (gedrosselt auf QUEST_DELAY, dazu ein
-- zweiter Durchgang nach QUEST_LATE: Questie aktualisiert seine Ziel-Daten selbst erst nach dem Ereignis)
Style.QUEST_DELAY, Style.QUEST_LATE, Style.QUESTIE_RECHECK = 0.3, 1.0, 0.05
local questPending = false
local function questRefresh()
    questPending = false
    if not engaged() then return end
    for uf, st in pairs(states) do
        if Compat.QueryBool(uf, "IsForbidden") ~= true and type(rawget(uf, "unit")) == "string"
            and Compat.QueryBool(uf, "IsVisible") ~= false then
            local ok, err = pcall(applyQuest, uf, st, wantFor(uf))
            if not ok then recordError(err) end
        end
    end
end
-- Zielmarkierung gesetzt/geaendert: Blizzard verankert ihren Frame dabei teils neu -> erneut ueber den Namen legen
local function onRaidTarget()
    if not engaged() then return end
    for uf, st in pairs(states) do
        if Compat.QueryBool(uf, "IsForbidden") ~= true and type(rawget(uf, "unit")) == "string"
            and Compat.QueryBool(uf, "IsVisible") ~= false then
            local ok, err = pcall(applyRaidTarget, uf, st, wantFor(uf))
            if not ok then recordError(err) end
        end
    end
end
local function onQuest()
    if questPending or not engaged() then return end
    questPending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(Style.QUEST_DELAY, questRefresh)
        C_Timer.After(Style.QUEST_LATE, function() if not questPending then questRefresh() end end)
    else
        questRefresh()
    end
end

-- Nur angemeldet, solange der Stil wirkt (an oder Vorschau): sonst laeuft kein Raid-UNIT_HEALTH durch Lucids Bus.
-- Beim Anmelden wird der Kampfzustand aus der API gelesen (Ereignisse waren bis dahin nicht mitgezaehlt).
local LISTEN = { { "UNIT_HEALTH", onHealth }, { "UNIT_MAXHEALTH", onHealth },
    { "PLAYER_REGEN_DISABLED", onRegenDisabled }, { "PLAYER_REGEN_ENABLED", onRegenEnabled },
    { "QUEST_LOG_UPDATE", onQuest }, { "UNIT_QUEST_LOG_CHANGED", onQuest }, { "QUEST_ACCEPTED", onQuest },
    { "QUEST_TURNED_IN", onQuest }, { "QUEST_REMOVED", onQuest }, { "RAID_TARGET_UPDATE", onRaidTarget } }
local listening = false
function updateListeners(on)
    on = on and true or false
    if on == listening then return end
    listening = on
    if on then inCombat = readCombat() end
    for _, e in ipairs(LISTEN) do
        if on then Compat.TryOn(e[1], e[2]) else ns.Off(e[1], e[2]) end
    end
end
function Style.IsListening() return listening end

-- Slash: /lucid nameplates style on|off|test|debug ---------------------------------------------------
local function yn(b) return b and L.NP_YES or L.NP_NO end

local function partLists(c)
    local on, pending = {}, {}
    for _, name in ipairs(Nameplates.STYLE_PARTS) do
        local p = c[name]
        if type(p) == "table" and p.enabled then
            if Style.IMPLEMENTED[name] then on[#on + 1] = name else pending[#pending + 1] = name end
        end
    end
    return on, pending
end

local function list(t) return #t > 0 and table.concat(t, ", ") or L.NP_NONE end

local function printStatus()
    local c = Nameplates.GetConfig().style
    local on = partLists(c)
    ns.Print(L.NP_ST_STATUS, c.enabled and L.NP_ON or L.NP_OFF, c.preset, list(on))
    local b = Style.Conflict()
    if b then ns.Print(L.NP_ST_BLOCKED, b) end
end

-- Diagnose der Ziel-Plakette (style debug, landet im Kopierfenster): echte Anker, Masse, Farben, Schrift, Overlay,
-- Hervorhebungen. Rein lesend; Secret Values werden nur als "secret" gemeldet, nie verglichen.
local function v(x)
    if Compat.IsSecret(x) then return "secret" end
    if type(x) == "number" then return ("%.2f"):format(x) end
    if type(x) == "table" then
        local ok, n = pcall(function() return x:GetDebugName() end)
        if ok and type(n) == "string" and n ~= "" then return n end
        local okN, nm = pcall(function() return x:GetName() end)
        if okN and type(nm) == "string" then return nm end
        local okT, t = pcall(function() return x:GetObjectType() end)
        return okT and tostring(t) or "table"
    end
    return tostring(x)
end
local function pack(ok, ...)
    if not ok then -- Fehler der Abfrage mit ausgeben (z. B. GetPoint wirft im Client)
        local e = ...
        return e ~= nil and ("- (" .. string.sub(tostring(e), 1, 70) .. ")") or "-"
    end
    local out = {}
    for i = 1, select("#", ...) do out[#out + 1] = v((select(i, ...))) end
    return table.concat(out, "/")
end
local function diagRegion(label, r)
    if type(r) ~= "table" then
        ns.Print(L.NP_ST_DIAG_LINE, label, L.NP_STYLE_ABSENT)
        return
    end
    local items = { "size " .. pack(call(r, "GetWidth")) .. "x" .. pack(call(r, "GetHeight")),
        "shown " .. pack(call(r, "IsShown")), "alpha " .. pack(call(r, "GetAlpha")) }
    local okN, n = call(r, "GetNumPoints")
    n = okN and Compat.Num(n) or 0
    for i = 1, math.min(n, 4) do items[#items + 1] = "pt" .. i .. " " .. pack(call(r, "GetPoint", i)) end
    ns.Print(L.NP_ST_DIAG_LINE, label, (table.concat(items, "; "):gsub("|", "||")))
end

local function printTargetDiag()
    local uf = targetFrame()
    if not uf then
        ns.Print(L.NP_ST_DIAG_NOTARGET)
        return
    end
    local st = states[uf]
    ns.Print(L.NP_ST_DIAG_HEAD, v(field(uf, "unit")), st and yn(st.frame or st.bar or st.font) or L.NP_NO)
    local hb = healthBar(uf)
    diagRegion("HealthBarsContainer", field(uf, "HealthBarsContainer"))
    diagRegion("healthBar", hb)
    local fs = field(uf, "name")
    diagRegion("name", fs)
    diagRegion("RaidTargetFrame", field(uf, "RaidTargetFrame"))
    if type(fs) == "table" then
        ns.Print(L.NP_ST_DIAG_LINE, "name", ("font " .. pack(call(fs, "GetFont")) .. "; text " .. pack(call(fs, "GetTextColor"))
            .. "; vertex " .. pack(call(fs, "GetVertexColor")) .. "; wrap " .. pack(call(fs, "CanWordWrap"))
            .. "; truncated " .. pack(call(fs, "IsTruncated")) .. "; justify " .. pack(call(fs, "GetJustifyH"))
            .. "; stringWidth " .. pack(call(fs, "GetStringWidth"))):gsub("|", "||"))
    end
    if type(hb) == "table" then
        local okT, tex = call(hb, "GetStatusBarTexture")
        ns.Print(L.NP_ST_DIAG_LINE, "healthBar", ("color " .. pack(call(hb, "GetStatusBarColor")) .. "; texture "
            .. (okT and pack(call(tex, "GetTexture")) or "-") .. "; atlas " .. (okT and pack(call(tex, "GetAtlas")) or "-")
            .. "; level " .. pack(call(hb, "GetFrameLevel"))):gsub("|", "||"))
    end
    -- Messung (Runde 8): Hoehen in UI-Einheiten und Bildschirmpixeln (UI-Einheit * effektive Skalierung * Pixel/768)
    do
        local physH = type(GetPhysicalScreenSize) == "function" and select(2, GetPhysicalScreenSize()) or nil
        local okE, eff = call(hb, "GetEffectiveScale")
        eff = okE and Compat.Num(eff) or nil
        local px = (eff and Compat.Num(physH)) and (eff * physH / 768) or nil
        local function hpx(r)
            local okH, h = call(r, "GetHeight")
            h = okH and Compat.Num(h) or nil
            if not h then return "-" end
            return ("%.2f (%s px)"):format(h, px and ("%.1f"):format(h * px) or "?")
        end
        local ovm = st and st.overlay
        ns.Print(L.NP_ST_DIAG_LINE, "Messung", ("Balken " .. hpx(hb) .. "; Rahmen " .. (ovm and hpx(ovm) or "-")
            .. "; Schlitz " .. (ovm and hpx(ovm.slitBack) or "-") .. "; Skalierung " .. v(eff) .. "; Pixel/UI " .. v(px)):gsub("|", "||"))
    end
    local nt = st and st.nameText
    if nt then
        diagRegion("Lucid-Name", nt.text)
        ns.Print(L.NP_ST_DIAG_LINE, "Lucid-Name", ("text " .. pack(call(nt.text, "GetText")) .. "; color " .. pack(call(nt.text, "GetTextColor"))
            .. "; font " .. pack(call(nt.text, "GetFont")) .. "; shown " .. pack(call(nt, "IsShown"))
            .. "; truncated " .. pack(call(nt.text, "IsTruncated"))):gsub("|", "||"))
    end
    local ov = st and st.overlay
    ns.Print(L.NP_ST_DIAG_LINE, "Lucid-Overlay", ov and ("shown " .. pack(call(ov, "IsShown")) .. ", level "
        .. pack(call(ov, "GetFrameLevel")) .. ", Maske " .. tostring(ov.masked == true) .. ", Blizzard-Fuellung unsichtbar " .. tostring(st.fillHidden == true)
        .. ", glow " .. pack(call(ov.glow, "IsShown")) .. " alpha " .. pack(call(ov.glow, "GetAlpha"))
        .. ", flow " .. pack(call(ov.flow, "IsShown"))) or L.NP_STYLE_ABSENT)
    -- Etappe 3: Bedarf (Kurvenmodus), friedlich, Kampf, Glimmen der Ziel-Plakette
    if st then
        local mode = { off = "aus", full = "voll sichtbar", curve = "Kurve", fallback = "Rueckfall (Balken sichtbar)" }
        ns.Print(L.NP_ST_DIAG_LINE, "Lucid-Bausteine", ("Bedarf " .. (mode[st.demandMode] or "aus") .. ", Kurvenmodus "
            .. yn(st.demandMode == "curve") .. ", Stufe bei vollem Leben " .. v(st.demandOn and st.demandLevel or 1)
            .. ", Blende " .. yn(fading[uf] == true) .. "; friedlich " .. yn(st.peaceful == true) .. "; Kampf " .. yn(inCombat)
            .. "; Glimmen " .. yn(ov ~= nil and ov.emberOn == true) .. "; Kurvenweg "
            .. (curveBroken and "gestoert" or (curveApi() and "ok" or "fehlt"))):gsub("|", "||"))
        local u = field(uf, "unit")
        local cls = readFlag(UnitClassification, u)
        local cb, path = findCastBar(uf)
        local rk, bs = Style.Rank(u)
        ns.Print(L.NP_ST_DIAG_LINE, "Lucid-Etappe4", ("Rang " .. v(rk or "-") .. (bs and "+Boss" or "") .. " (" .. v(cls) .. "), Stufe "
            .. v(st.lastLevel == false and "aus (kein deutlicher Unterschied)" or st.lastLevel) .. ", Plaettchen "
            .. yn(st.levelPlate ~= nil and st.levelPlate:IsShown()) .. ", Medaille " .. yn(st.rankDecor ~= nil and st.rankDecor:IsShown())
            .. "; Quest " .. yn(st.quest == true) .. "; Zauberleiste " .. (cb and path or L.NP_STYLE_ABSENT)
            .. ", gestylt " .. yn(st.cast == true) .. (st.castFixed and " (Original-Anker nicht lesbar: Leiste nicht verschoben)" or "")
            .. ", Rahmen-Textur geladen "
            .. (st.castThread and (st.castThread.frameOk == "?" and "?" or yn(st.castThread.frameOk)) or "-")
            .. ", Simulation " .. yn(sim ~= nil)):gsub("|", "||"))
        ns.Print(L.NP_ST_DIAG_LINE, "Lucid-Markierung", ("verschoben " .. yn(st.raid) .. ", Original-Anker lesbar " .. yn(st.raidReadable)
            .. (st.raidOrig and st.raidOrig.points and " (gemerkt)" or " (Standard: RIGHT am Balken-Container)")):gsub("|", "||"))
        local q = st.questie or {}
        ns.Print(L.NP_ST_DIAG_LINE, "Lucid-Questie", ("Questie " .. (questieReady() and "bereit" or "nicht bereit/fehlt")
            .. ", Typ " .. v(q.kind or "-") .. ", Status " .. v(q.status or "-") .. ", Pfad " .. v(q.path or "-")
            .. ", Lucid-Symbol " .. v(st.quest and (st.lastQuestKind or "!") or "-")):gsub("|", "||"))
        local dd = {}
        for _, n in ipairs(Style.DEPTH_CVARS) do
            local info = DepthCVars.Info(n)
            dd[#dd + 1] = n:gsub("^nameplate", "") .. "=" .. (info.exists and tostring(info.value) or L.NP_STYLE_ABSENT)
        end
        ns.Print(L.NP_ST_DIAG_LINE, "Lucid-Tiefe", ("Lucid besitzt " .. #DepthCVars.OwnedNames() .. "; "
            .. table.concat(dd, ", ")):gsub("|", "||"))
    end
    local items = {}
    for _, p in ipairs(FRAME_HIDE) do
        local r = field(uf, p[1])
        if p[2] then r = field(r, p[2]) end
        local key = p[1] .. (p[2] and ("." .. p[2]) or "")
        if type(r) == "table" then
            items[#items + 1] = key .. " shown " .. pack(call(r, "IsShown")) .. " alpha " .. pack(call(r, "GetAlpha"))
        else
            items[#items + 1] = key .. " " .. L.NP_STYLE_ABSENT
        end
    end
    for _, p in ipairs(LEVEL_HIDE) do
        local r = field(uf, p[1])
        items[#items + 1] = p[1] .. (type(r) == "table" and (" shown " .. pack(call(r, "IsShown")) .. " alpha " .. pack(call(r, "GetAlpha"))) or (" " .. L.NP_STYLE_ABSENT))
    end
    for i = 1, #items, 3 do
        ns.Print(L.NP_ST_DIAG_LINE, "Blizzard", (table.concat(items, "; ", i, math.min(i + 2, #items)):gsub("|", "||")))
    end
end

local function printDebug()
    local c = Nameplates.GetConfig().style
    local on, pending = partLists(c)
    ns.Print(L.NP_ST_DEBUG_HEAD, c.enabled and L.NP_ON or L.NP_OFF, c.preset, yn(active), yn(testActive),
        Style.StyledCount())
    local b = Style.Conflict()
    if b then ns.Print(L.NP_ST_BLOCKED, b) end
    ns.Print(L.NP_ST_DEBUG_PARTS, list(on))
    if #pending > 0 then ns.Print(L.NP_ST_DEBUG_PENDING, list(pending)) end
    if not hooksInstalled then
        ns.Print(L.NP_ST_DEBUG_HOOKS, L.NP_ST_NOT_INSTALLED)
    else
        local items = {}
        for _, m in ipairs(Style.MIXIN_HOOKS) do
            local key = "NamePlateUnitFrameMixin." .. m
            local s = hookStatus[key]
            items[#items + 1] = key .. "=" .. (s == "ok" and L.NP_YES or s == "missing" and L.NP_STYLE_ABSENT or L.NP_NO)
        end
        for _, h in ipairs(Style.HOOKS) do
            local key = h.driver and ("NamePlateDriverFrame." .. h.name) or h.name
            local s = hookStatus[key]
            items[#items + 1] = key .. "=" .. (s == "ok" and L.NP_YES or s == "missing" and L.NP_STYLE_ABSENT or L.NP_NO)
        end
        ns.Print(L.NP_ST_DEBUG_HOOKS, table.concat(items, ", "))
    end
    if errorCount == 0 then
        ns.Print(L.NP_ST_DEBUG_NOERRORS)
    else
        ns.Print(L.NP_ST_DEBUG_ERRORS, errorCount)
        for _, e in ipairs(errors) do ns.Print(L.NP_ST_DEBUG_ERROR, (e:gsub("|", "||"))) end
    end
    local ok, err = pcall(printTargetDiag)
    if not ok then ns.Print(L.NP_ST_DEBUG_ERROR, (tostring(err):gsub("|", "||"))) end
end

-- Plaketten-Ereignisse fuer die Spur (nur waehrend einer Aufzeichnung wirksam)
for _, ev in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }) do
    Compat.TryOn(ev, function(_, unit)
        if not trace then return end
        local uf = type(unit) == "string" and frameOfUnit(unit) or nil
        local okA, a = uf and call(uf, "GetAlpha")
        traceAdd(ev, unit, L.NP_ST_TR_EVENT .. (uf and (" alpha " .. v(okA and a or nil)) or ""))
    end)
end
Compat.TryOn("PLAYER_TARGET_CHANGED", function()
    if trace then traceAdd("PLAYER_TARGET_CHANGED", nil, L.NP_ST_TR_EVENT) end
end)

local function finishTrace()
    if not trace then return end
    local t = trace
    trace = nil
    local text = table.concat(t.lines, "\n")
    if #t.lines == 0 then text = L.NP_ST_TRACE_EMPTY end
    ns.Print(L.NP_ST_TRACE_DONE, #t.lines)
    if ns.CopyBox then ns.CopyBox.Show("/lucid nameplates style trace", text) end
end

--- Spur starten (liefert false, wenn schon eine laeuft)
function Style.StartTrace()
    if trace then return false end
    installHooks() -- Hooks muessen fuer die Aufzeichnung stehen (ohne Stil wirken sie nicht)
    trace = { t0 = type(GetTime) == "function" and GetTime() or 0, lines = {} }
    C_Timer.After(Style.TRACE_SECONDS, finishTrace)
    return true
end

local function setEnabled(on)
    if not Nameplates.Set("style.enabled", on) then
        ns.Print(L.NP_VALUE_INVALID)
        return
    end
    ns.Print(on and L.NP_ST_ENABLED or L.NP_ST_DISABLED)
    local b = on and Style.Conflict()
    if b then ns.Print(L.NP_ST_BLOCKED, b) end
end

--- "cast [sek] [name] [nokick]": Argumente aus dem Rest der Zeile (Zahl = Sekunden, "nokick" = nicht unterbrechbar,
--- der Rest = Zaubername; "|" wird entschaerft, Laenge begrenzt)
function Style.ParseCastArgs(rest)
    local C = Style.CAST
    local sec, nokick, words = nil, false, {}
    for w in tostring(rest or ""):gmatch("%S+") do
        local n = tonumber(w)
        if n and not sec and n == n then
            sec = n
        elseif w:lower() == "nokick" then
            nokick = true
        else
            words[#words + 1] = w
        end
    end
    sec = math.max(C.simMin, math.min(C.simMax, sec or C.simDefault))
    local name = table.concat(words, " "):gsub("[%c]", ""):gsub("|", "||")
    if name == "" then name = L.NP_ST_CAST_DEFAULT end
    if #name > C.nameMax then name = name:sub(1, C.nameMax) end
    return sec, name, nokick
end

-- Aktionen (Slash, Testfenster /lucid nameplates style panel und spaeter der Reiter mit Live-Vorschau nutzen dieselben
-- Funktionen; jede meldet ihr Ergebnis im Chat wie der Slash-Befehl)
Style.Actions = {}
local Actions = Style.Actions

function Actions.SetEnabled(on) setEnabled(on and true or false) end

function Actions.Test()
    local res, why = Style.ToggleTest()
    if res == nil then
        if why == "NP_ST_BLOCKED" then ns.Print(L.NP_ST_BLOCKED, blocker or "?") else ns.Print(L[why]) end
    else
        ns.Print(res and L.NP_ST_TEST_ON or L.NP_ST_TEST_OFF)
    end
    return res
end

function Actions.Rank(key)
    local res, why = Style.SetRankPreview(key)
    if res == nil then
        ns.Print(L[why], table.concat(Style.RANK_PREVIEW_ORDER, "|"))
    else
        ns.Print(res and L.NP_ST_RANK_ON or L.NP_ST_RANK_OFF, key)
    end
    return res
end

--- Zauber-Simulation starten (eine laufende wird ersetzt); name ist bereits bereinigt (ParseCastArgs) oder nil
function Actions.Cast(sec, name, nokick)
    if sim then stopSim() end
    name = name or L.NP_ST_CAST_DEFAULT
    local res, why = Style.CastSim(sec, name, nokick)
    if res == nil then ns.Print(L[why]) elseif res then ns.Print(L.NP_ST_CAST_ON, ("%.1f"):format(sec), name) end
    return res
end

function Actions.CastStop()
    if not sim then return false end
    stopSim()
    ns.Print(L.NP_ST_CAST_OFF)
    return true
end

--- Baustein-Feld setzen (path relativ zu nameplates.style, z. B. "frame.glass"); wirkt sofort
function Actions.SetPart(path, value)
    local ok = Nameplates.Set("style." .. path, value)
    if not ok then ns.Print(L.NP_VALUE_INVALID) end
    return ok and true or false
end

--- Diagnose der Ziel-Plakette im Kopierfenster
function Actions.Debug()
    if ns.CopyBox and ns.CopyBox.Capture then ns.CopyBox.Capture("/lucid nameplates style debug", printDebug) else printDebug() end
end

function Actions.Trace()
    if Style.StartTrace() then ns.Print(L.NP_ST_TRACE_START, Style.TRACE_SECONDS) else ns.Print(L.NP_ST_TRACE_RUNNING) end
end

--- Zustand fuer Anzeigen (Testfenster): Stil an, Vorschau, Rang-Vorschau, Simulation laeuft
function Actions.State()
    local c = Nameplates.GetConfig().style
    return { enabled = c.enabled == true, test = testActive, rank = rankPreview, cast = sim ~= nil, style = c }
end

Nameplates.sub.style = function(arg)
    local a = tostring(arg or ""):lower():match("^(%S*)")
    if a == "on" or a == "an" then
        Actions.SetEnabled(true)
    elseif a == "off" or a == "aus" then
        Actions.SetEnabled(false)
    elseif a == "test" then
        Actions.Test()
    elseif a == "rank" then
        Actions.Rank(tostring(arg or ""):lower():match("^%S*%s*(%S*)"))
    elseif a == "cast" then
        local sec, name, nokick = Style.ParseCastArgs(tostring(arg or ""):match("^%S*%s*(.-)%s*$"))
        if sim then Actions.CastStop() else Actions.Cast(sec, name, nokick) end -- zweiter Aufruf beendet
    elseif a == "panel" then
        if ns.StylePanel then ns.StylePanel.Toggle() end
    elseif a == "debug" then
        printDebug()
    elseif a == "trace" then
        Actions.Trace()
    elseif a == "" or a == "status" then
        printStatus()
        ns.Print(L.HELP_NAMEPLATES_STYLE)
    else
        ns.Print(L.NP_ST_UNKNOWN, (a:gsub("|", "||")))
        ns.Print(L.HELP_NAMEPLATES_STYLE)
    end
end

ns.AddHelp("HELP_NAMEPLATES_STYLE")
