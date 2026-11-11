-- Plaketten (B7): Namensplaketten zustandsabhaengig zeigen. Stufe N1 = Profilabschnitt "nameplates", CVar-Treiber
-- (CVars.lua) mit Sicherung/Wiederherstellung und Slash /lucid nameplates. Zustandsregeln, Radius-Oberflaeche und
-- weiches Ausblenden folgen in N2/N3.
--
-- Standard enabled=false: Lucid fasst dann keine CVar an (und stellt Reste einer frueheren Sitzung zurueck).
-- Lucid gewinnt gegen Taste V / Blizzard-Optionen, solange das Modul an ist: beim naechsten Apply (Zustandswechsel,
-- Profilwechsel, Befehl) wird der Sollwert erneut geschrieben.
local _, ns = ...
local Store, State, CVars = ns.Store, ns.State, ns.CVars
local L = ns.L

local Nameplates = {}
ns.Nameplates = Nameplates
local active = false -- Modul aktiv (nach PLAYER_LOGIN)
Nameplates.sub = {} -- Unterbefehle von /lucid nameplates (Probe.lua traegt "probe" ein)

Nameplates.RADIUS_MIN, Nameplates.RADIUS_MAX = 5, 100  -- Yards (Retail-Probe: 0 bis 500 werden exakt angenommen; Standard des Clients 60)
Nameplates.RADIUS_DEFAULT = 60
Nameplates.FADE_DURATION_MAX = 5
Nameplates.MAX_CONDITIONS = 32
Nameplates.FADE_MODES = { soft = true, hard = true }

Nameplates.DEFAULTS = {
    enabled = false,
    fade = "soft",
    fadeDuration = 0.3,
    radius = { enabled = false, yards = Nameplates.RADIUS_DEFAULT },
    -- keepTarget je Gruppe: Ziel-Plakette bleibt trotz "aus" sichtbar (Gegner: ja; Freunde: nein, sonst erscheinen
    -- befreundete Plaketten beim Anklicken, obwohl der Nutzer sie ausgeschaltet hat)
    enemies = { baseShow = true, keepTarget = true, conditions = {} },
    friends = { baseShow = false, keepTarget = false, conditions = {} },
}

-- Plaketten-Stil (Delta "Immersiver Plaketten-Stil"): Aussehen, unabhaengig von der Sichtbarkeit oben. Alle elf
-- Bausteine stehen schon im Schema (spaetere Etappen bauen sie ein; bis dahin duerfen sie im Profil stehen, wirken
-- aber nicht; welche wirken, steht in Style.IMPLEMENTED). Die Engine liegt in Style.lua.
Nameplates.STYLE_PRESETS = { subtle = true, immersive = true, cinematic = true, custom = true }
Nameplates.STYLE_PARTS = { -- Reihenfolge = Bausteine 1 bis 11 der Spec
    "frame", "colors", "font", "barOnDemand", "peaceful", "targetGlow", "lowHealth", "levelRank", "questSeal", "depth",
    "castThread",
}
Nameplates.STYLE_FONTS = { "marcellus", "cinzel", "cormorant", "frizqt", "morpheus" } -- feste Liste (Schluessel wie Zonentext)
Nameplates.STYLE_HEIGHT_MIN, Nameplates.STYLE_HEIGHT_MAX = 3, 14
Nameplates.STYLE_FONT_SIZE_MIN, Nameplates.STYLE_FONT_SIZE_MAX = 7, 18
Nameplates.STYLE_TARGET_MIN, Nameplates.STYLE_TARGET_MAX = 1.0, 1.3 -- Zielgroesse (Faktor, Blizzard-Standard 1,2)
Nameplates.STYLE_LOW_MIN, Nameplates.STYLE_LOW_MAX = 0.10, 0.35 -- Schwelle des Glimmens (Lebensanteil), Standard 0,20
-- Quest-Fernsicht (Nachtrag 2): Symbolgroesse (UI-Einheiten), Deckkraft, Reichweite (Meter = nameplateMaxDistance)
Nameplates.QF_SIZE_MIN, Nameplates.QF_SIZE_MAX = 12, 40
Nameplates.QF_ALPHA_MIN, Nameplates.QF_ALPHA_MAX = 0.3, 1
-- Reichweite je Client (Forever-Test 10.11.: dort ist bei ca. 45 m Schluss; Retail-Grenze 60 nur angenommen, wie Plater).
-- Aeltere Profilwerte ueber dem Client-Maximum werden geklemmt (bis QF_DISTANCE_ABS), nicht verworfen.
Nameplates.QF_DISTANCE_MIN = 20
Nameplates.QF_DISTANCE_MAX = ns.Compat.isRetail and 60 or 45
Nameplates.QF_DISTANCE_ABS = 100
Nameplates.QF_FIELDS = { enabled = { "bool" }, pulse = { "bool" }, halo = { "bool" },
    size = { "num", Nameplates.QF_SIZE_MIN, Nameplates.QF_SIZE_MAX },
    alpha = { "num", Nameplates.QF_ALPHA_MIN, Nameplates.QF_ALPHA_MAX },
    distance = { "clamp", Nameplates.QF_DISTANCE_MIN, Nameplates.QF_DISTANCE_ABS, Nameplates.QF_DISTANCE_MAX } }
do
    local fonts = {}
    for _, k in ipairs(Nameplates.STYLE_FONTS) do fonts[k] = true end
    -- Zusatzfelder je Baustein (neben "enabled"): Art und Grenzen
    Nameplates.STYLE_FIELDS = {
        frame = { height = { "num", Nameplates.STYLE_HEIGHT_MIN, Nameplates.STYLE_HEIGHT_MAX }, living = { "bool" },
                  capsule = { "bool" }, inset = { "bool" }, meniscus = { "bool" }, glass = { "bool" } },
        font = { face = { "enum", fonts }, size = { "num", Nameplates.STYLE_FONT_SIZE_MIN, Nameplates.STYLE_FONT_SIZE_MAX },
                 veil = { "bool" } }, -- veil: Tinten-Schleier hinter dem Namen
        levelRank = { onlyDiff = { "bool" } },
        barOnDemand = { target = { "bool" } }, -- target: am Ziel immer Balken (auch ausserhalb des Kampfs, volles Leben)
        -- Tiefe: kleinste Groesse/Deckkraft in der Ferne, ab near (Meter) bis far wird verkleinert/verblasst
        depth = { minScale = { "num", 0.5, 1 }, minAlpha = { "num", 0.2, 1 }, near = { "num", 0, 30 }, far = { "num", 15, 80 } },
        castThread = { showName = { "bool" } }, -- Zaubername unter dem Faden
        lowHealth = { threshold = { "num", Nameplates.STYLE_LOW_MIN, Nameplates.STYLE_LOW_MAX } }, -- Glimmen unter diesem Lebensanteil
    }
end
-- Standard: Stil aus; eingeschaltet gilt das Preset "Immersiv" (Bausteine 1-6, 8-11; Glimmen 7 nur Filmisch); Balken 5 (Wahl R2), Name 12 mit Schleier (R7)
-- uniformSize: alle Plaketten gleich gross (keine Entfernungs-Skalierung), targetScale: Groesse der Ziel-Plakette (CVars ueber
-- Style.SizeDesired); beides gehoert nicht zu den Bausteinen, die Presets setzen es auf "gleich gross" und 100 %
Nameplates.DEFAULTS.style = {
    enabled = false,
    preset = "immersive",
    uniformSize = true,
    targetScale = 1.0,
    -- living: stroemende Fuellung; capsule: runde Enden (Maske); inset: innerer Schatten; meniscus: heller Saum an der
    -- Oberflaeche (Fuellungsende hart); glass: feiner Glasglanz (Runde 8, Wahl C)
    frame = { enabled = true, height = 5, living = true, capsule = true, inset = true, meniscus = true, glass = true },
    colors = { enabled = true },
    font = { enabled = true, face = "marcellus", size = 12, veil = true },
    barOnDemand = { enabled = true, target = true },
    peaceful = { enabled = true },
    targetGlow = { enabled = true },
    lowHealth = { enabled = false, threshold = 0.2 },
    levelRank = { enabled = true, onlyDiff = false },
    questSeal = { enabled = true },
    depth = { enabled = true, minScale = 0.75, minAlpha = 0.55, near = 10, far = 40 },
    castThread = { enabled = true, showName = true },
    -- Quest-Fernsicht (Nachtrag 2, kein Baustein: Presets lassen sie unberuehrt): unsichtbare Gegner-Plaketten (B7) zeigen nur
    -- ihr Quest-Symbol; wirkt nur mit eingeschaltetem Plaketten-Modul, unabhaengig vom Stil
    questFar = { enabled = false, size = 22, alpha = 0.85, pulse = true, halo = true, distance = Nameplates.QF_DISTANCE_MAX },
}

-- Stil-Presets (09.11.): setzen NUR die Stil-Bausteine (Schalter und Unteroptionen), nie Sichtbarkeit/Radius (B7),
-- Hoehe, Schrift oder Tiefe-Werte und nie das globale Lucid-Preset "Immersion". Dezent = Bausteine 1, 2, 3, 6; Immersiv =
-- 1-6, 8-11 (Glimmen 7 nur Filmisch); Filmisch = alle. Unteroptionen sind in allen Presets an (ausser "Stufe nur bei
-- Unterschied": die Stufe soll immer sichtbar sein).
Nameplates.STYLE_PRESET_ORDER = { "subtle", "immersive", "cinematic" }
Nameplates.STYLE_PRESET_PARTS = {
    subtle = { "frame", "colors", "font", "targetGlow" },
    immersive = { "frame", "colors", "font", "barOnDemand", "peaceful", "targetGlow", "levelRank", "questSeal", "depth", "castThread" },
    cinematic = Nameplates.STYLE_PARTS,
}
Nameplates.STYLE_PRESET_SUBS = { -- Pfad relativ zu nameplates.style -> Wert in jedem Preset
    ["frame.living"] = true, ["frame.capsule"] = true, ["frame.inset"] = true, ["frame.meniscus"] = true, ["frame.glass"] = true,
    ["font.veil"] = true, ["barOnDemand.target"] = true, ["levelRank.onlyDiff"] = false, ["castThread.showName"] = true,
}
Nameplates.STYLE_PRESET_SUB_ORDER = { "frame.living", "frame.capsule", "frame.inset", "frame.meniscus", "frame.glass", "font.veil",
    "barOnDemand.target", "levelRank.onlyDiff", "castThread.showName" }
-- Slash-Namen (deutsch und englisch) -> Preset
Nameplates.STYLE_PRESET_ALIASES = { dezent = "subtle", subtle = "subtle", immersiv = "immersive", immersive = "immersive",
    filmisch = "cinematic", cinematic = "cinematic" }

-- Einstellungen -------------------------------------------------------------------------------------
local function isNum(v, lo, hi) return type(v) == "number" and v == v and v >= lo and v <= hi end

local STYLE_PART_SET = {}
for _, k in ipairs(Nameplates.STYLE_PARTS) do STYLE_PART_SET[k] = true end

local function validateStylePart(name, v)
    if type(v) ~= "table" then return nil, "type" end
    local fields = Nameplates.STYLE_FIELDS[name] or {}
    local out = {}
    for k, x in pairs(v) do
        local spec = fields[k]
        if k == "enabled" then
            if type(x) ~= "boolean" then return nil, k end
            out[k] = x
        elseif spec then
            local ok
            if spec[1] == "num" then ok = isNum(x, spec[2], spec[3])
            elseif spec[1] == "enum" then ok = type(x) == "string" and spec[2][x] == true
            else ok = type(x) == "boolean" end
            if not ok then return nil, k end
            out[k] = x
        end -- unbekannte Felder fallen weg
    end
    return out
end

local function validateQuestFar(v)
    if type(v) ~= "table" then return nil, "type" end
    local out = {}
    for k, x in pairs(v) do
        local spec = Nameplates.QF_FIELDS[k]
        if spec then
            local ok
            if spec[1] == "num" or spec[1] == "clamp" then ok = isNum(x, spec[2], spec[3]) else ok = type(x) == "boolean" end
            if not ok then return nil, k end
            if spec[1] == "clamp" and x > spec[4] then x = spec[4] end -- ueber dem Client-Maximum: klemmen
            out[k] = x
        end -- unbekannte Felder fallen weg
    end
    return out
end

--- Unterabschnitt "style" pruefen. Liefert bereinigte Kopie oder nil, Detail.
function Nameplates.ValidateStyle(v)
    if type(v) ~= "table" then return nil, "type" end
    local out = {}
    for k, x in pairs(v) do
        if k == "enabled" then
            if type(x) ~= "boolean" then return nil, k end
            out[k] = x
        elseif k == "uniformSize" then
            if type(x) ~= "boolean" then return nil, k end
            out[k] = x
        elseif k == "targetScale" then
            if not isNum(x, Nameplates.STYLE_TARGET_MIN, Nameplates.STYLE_TARGET_MAX) then return nil, k end
            out[k] = x
        elseif k == "preset" then
            if type(x) ~= "string" or not Nameplates.STYLE_PRESETS[x] then return nil, k end
            out[k] = x
        elseif k == "questFar" then
            local q, detail = validateQuestFar(x)
            if not q then return nil, k .. "." .. tostring(detail) end
            out[k] = q
        elseif STYLE_PART_SET[k] then
            local p, detail = validateStylePart(k, x)
            if not p then return nil, k .. "." .. tostring(detail) end
            out[k] = p
        end -- unbekannte Felder fallen weg
    end
    return out
end

local function validateGroup(v)
    if type(v) ~= "table" then return nil, "type" end
    local out = {}
    for k, x in pairs(v) do
        if k == "baseShow" or k == "keepTarget" then
            if type(x) ~= "boolean" then return nil, k end
            out[k] = x
        elseif k == "conditions" then
            if type(x) ~= "table" then return nil, k end
            local list, seen = {}, {}
            for i = 1, #x do
                local name = x[i]
                if type(name) ~= "string" or not State.KNOWN[name] then return nil, k end
                if not seen[name] then
                    seen[name] = true
                    list[#list + 1] = name
                end
            end
            if #list > Nameplates.MAX_CONDITIONS then return nil, k end
            out[k] = list
        end -- unbekannte Felder fallen weg
    end
    return out
end

local function validateRadius(v)
    if type(v) ~= "table" then return nil, "type" end
    local out = {}
    for k, x in pairs(v) do
        if k == "enabled" then
            if type(x) ~= "boolean" then return nil, k end
            out[k] = x
        elseif k == "yards" then
            if not isNum(x, Nameplates.RADIUS_MIN, Nameplates.RADIUS_MAX) then return nil, k end
            out[k] = x
        end
    end
    return out
end

--- Profil-Abschnitt "nameplates" pruefen (Import und Aendern). Liefert bereinigte Kopie oder nil, Detail.
function Nameplates.Validate(v)
    if type(v) ~= "table" then return nil, "type" end
    local out = {}
    for k, x in pairs(v) do
        if k == "enabled" or k == "keepTarget" then
            if type(x) ~= "boolean" then return nil, k end
            out[k] = x
        elseif k == "fade" then
            if type(x) ~= "string" or not Nameplates.FADE_MODES[x] then return nil, k end
            out[k] = x
        elseif k == "fadeDuration" then
            if not isNum(x, 0, Nameplates.FADE_DURATION_MAX) then return nil, k end
            out[k] = x
        elseif k == "radius" then
            local r, detail = validateRadius(x)
            if not r then return nil, k .. "." .. tostring(detail) end
            out[k] = r
        elseif k == "enemies" or k == "friends" then
            local g, detail = validateGroup(x)
            if not g then return nil, k .. "." .. tostring(detail) end
            out[k] = g
        elseif k == "style" then
            local s, detail = Nameplates.ValidateStyle(x)
            if not s then return nil, k .. "." .. tostring(detail) end
            out[k] = s
        end -- unbekannte Felder fallen weg
    end
    return out
end

Store.RegisterSection("nameplates", {
    default = function() return {} end,
    validate = Nameplates.Validate,
})

local function merged(defaults, stored)
    local out = {}
    for k, d in pairs(defaults) do
        local v = nil
        if type(stored) == "table" then v = stored[k] end -- false ist ein gueltiger Wert
        if type(d) == "table" and not (#d > 0) and next(d) ~= nil then
            out[k] = merged(d, v)
        elseif type(d) == "table" then
            out[k] = Store.DeepCopy(type(v) == "table" and v or d)
        elseif v ~= nil then
            out[k] = v
        else
            out[k] = d
        end
    end
    return out
end

--- wirksame Einstellungen (Profil > Nameplates.DEFAULTS), immer gueltig
function Nameplates.GetConfig()
    local stored
    if Store.db then
        local p = Store.GetActive()
        stored = p and p.nameplates
    end
    local clean = type(stored) == "table" and Nameplates.Validate(stored) or nil
    local cfg = merged(Nameplates.DEFAULTS, clean)
    -- aeltere Profile: ein gespeichertes keepTarget=false (Gesamtschalter) gilt fuer die Gegner
    if clean and clean.keepTarget == false and not (clean.enemies and clean.enemies.keepTarget ~= nil) then
        cfg.enemies.keepTarget = false
    end
    cfg.keepTarget = cfg.enemies.keepTarget or cfg.friends.keepTarget -- abgeleitet: mindestens eine Gruppe
    -- ohne gespeicherte Sichtweite gilt der aktuelle Wert des Clients (Blizzard-Wert, falls Lucid ihn schon gesetzt hat), sonst 60
    if not (clean and clean.radius and clean.radius.yards ~= nil) then
        local cur = tonumber(CVars.Baseline(CVars.MAX_DISTANCE) or CVars.Get(CVars.MAX_DISTANCE))
        if cur and cur == cur then
            cfg.radius.yards = math.max(Nameplates.RADIUS_MIN, math.min(Nameplates.RADIUS_MAX, math.floor(cur + 0.5)))
        end
    end
    return cfg
end

-- Stil-Presets: Aenderungsliste, Erkennung ----------------------------------------------------------
--- Aenderungen (Pfad -> Wert, fuer SetMany) fuer ein Stil-Preset oder nil bei unbekannter Kennung. Enthaelt style.preset.
function Nameplates.StylePresetChanges(id)
    local parts = Nameplates.STYLE_PRESET_PARTS[id]
    if not parts then return nil end
    local on = {}
    for _, name in ipairs(parts) do on[name] = true end
    local changes = { ["style.preset"] = id, ["style.uniformSize"] = true, ["style.targetScale"] = 1.0 }
    for _, name in ipairs(Nameplates.STYLE_PARTS) do changes["style." .. name .. ".enabled"] = on[name] == true end
    for path, value in pairs(Nameplates.STYLE_PRESET_SUBS) do changes["style." .. path] = value end
    return changes
end

--- Welches Preset die Schalter der Stil-Einstellungen (zusammengefuehrt, wie GetConfig().style) genau abbilden; sonst "custom"
function Nameplates.StylePresetOf(style)
    if type(style) ~= "table" then return "custom" end
    for _, id in ipairs(Nameplates.STYLE_PRESET_ORDER) do
        local on = {}
        for _, name in ipairs(Nameplates.STYLE_PRESET_PARTS[id]) do on[name] = true end
        local same = true
        for _, name in ipairs(Nameplates.STYLE_PARTS) do
            local part = style[name]
            if type(part) ~= "table" or (part.enabled == true) ~= (on[name] == true) then same = false break end
        end
        if same then
            for path, value in pairs(Nameplates.STYLE_PRESET_SUBS) do
                local part, key = path:match("^([^%.]+)%.(.+)$")
                if type(style[part]) ~= "table" or style[part][key] ~= value then same = false break end
            end
        end
        if same then return id end
    end
    return "custom"
end

--- Kennung (englisch oder deutsch, beliebige Schreibweise) -> Preset-Kennung oder nil
function Nameplates.StylePresetByName(name)
    if type(name) ~= "string" then return nil end
    return Nameplates.STYLE_PRESET_ALIASES[name:lower()]
end

-- Sollwerte -----------------------------------------------------------------------------------------
local function flag(b) return b and "1" or "0" end

--- Gruppe (Gegner/Freunde) sichtbar? Semantik wie beim Fader: sichtbar, sobald die Basis oder eine Bedingung zutrifft.
function Nameplates.GroupVisible(group)
    if group.baseShow then return true end
    for _, name in ipairs(group.conditions) do
        if State.Get(name) then return true end
    end
    return false
end

-- Weiches Ausblenden (N3): wird eine Gruppe unsichtbar, bleibt ihre CVar noch die Dauer des Ausblendens an, damit die
-- Plaketten per Alpha ausblenden koennen (Plates.lua); danach schaltet die CVar sie ab.
local lastVisible = {}  -- "enemies"/"friends" -> Sichtbarkeit nach Regeln beim letzten Apply
local holdUntil = {}    -- "enemies"/"friends" -> GetTime(), bis die CVar fuer das Ausblenden an bleibt
local GROUPS = { "enemies", "friends" }

local function softOn(cfg) return cfg.enabled and cfg.fade == "soft" end

--- true, wenn die Plakette des Ziels in dieser Gruppe liegt (keepTarget haelt die CVar dann an)
local function targetIn(key)
    if not (UnitExists and UnitExists("target")) then return false end
    local g = ns.Plates.GroupOf("target")
    return g == key
end

--- Quest-Fernsicht wirksam? (Plaketten-Modul an, Fernsicht an, kein Fremd-Plaketten-Addon). Ohne sie bleibt B7 exakt wie vorher.
--- Testmodus (QuestFar.lua, /lucid nameplates far test): schaltet die Fernsicht fuer die Sitzung zu, ohne das Profil zu aendern
Nameplates.questFarTest = false
function Nameplates.QuestFarOn(cfg)
    cfg = cfg or Nameplates.GetConfig()
    local qf = cfg.style and cfg.style.questFar
    if not (cfg.enabled and type(qf) == "table" and (qf.enabled or Nameplates.questFarTest)) then return false end
    local S = Nameplates.Style
    if S and S.Conflict and S.Conflict() then return false end
    return true
end

--- CVar-Ebene: soll die Gruppe existieren? (hart: = Sichtbarkeit; weich: auch waehrend des Ausblendens und fuer das Ziel)
function Nameplates.Exists(cfg, key)
    if Nameplates.GroupVisible(cfg[key]) then return true end
    -- Quest-Fernsicht: Gegner-Plaketten existieren immer (unsichtbar per Alpha, Plates.lua), damit ihr Quest-Symbol zeigen kann
    if key == "enemies" and Nameplates.QuestFarOn(cfg) then return true end
    if not softOn(cfg) then return false end
    if holdUntil[key] and GetTime() < holdUntil[key] then return true end
    return cfg[key].keepTarget and targetIn(key) or false
end

local function resetHold()
    lastVisible, holdUntil = {}, {}
end

--- Uebergaenge sichtbar -> unsichtbar merken und die Haltezeit starten
local function trackTransitions(cfg)
    for _, key in ipairs(GROUPS) do
        local vis = Nameplates.GroupVisible(cfg[key])
        if softOn(cfg) and lastVisible[key] and not vis and cfg.fadeDuration > 0 then
            holdUntil[key] = GetTime() + cfg.fadeDuration
            C_Timer.After(cfg.fadeDuration + 0.05, function()
                if active then Nameplates.Apply() end
            end)
        end
        if vis then holdUntil[key] = nil end
        lastVisible[key] = vis
    end
end

--- Sollwerte der CVars (name -> Wert) aus der Konfiguration und den aktuellen Zustaenden.
function Nameplates.Desired(cfg)
    cfg = cfg or Nameplates.GetConfig()
    local d = {}
    if not cfg.enabled then return d end
    local enemies, friends = Nameplates.Exists(cfg, "enemies"), Nameplates.Exists(cfg, "friends")
    d[CVars.ENEMIES] = flag(enemies)
    d[CVars.FRIEND_PLAYERS] = flag(friends)
    d[CVars.FRIEND_NPCS] = flag(friends)
    if enemies or friends then d[CVars.SHOW_ALL] = "1" end -- sonst zeigt Blizzard Plaketten nur im Kampf
    if Nameplates.QuestFarOn(cfg) then
        -- Fernsicht: Reichweite der Symbole; der B7-Radius gilt dann ueber die Entfernungs-Alpha (Style.lua, applyDepth)
        d[CVars.MAX_DISTANCE] = cfg.style.questFar.distance
    elseif cfg.radius.enabled then
        d[CVars.MAX_DISTANCE] = cfg.radius.yards
    end
    return d
end


--- Sollzustand herstellen: an => Sollwerte schreiben, aus (oder Modul nicht aktiv) => Besitz zurueckstellen.
--- Liefert Tabelle name -> Status.
function Nameplates.Apply()
    local cfg = Nameplates.GetConfig()
    if not (active and cfg.enabled) then
        resetHold()
        ns.Plates.Update(nil) -- Alpha aller Plaketten zurueck auf 1
        local owned = CVars.OwnedNames()
        local res = {}
        for _, name in ipairs(owned) do res[name] = CVars.RestoreOne(name) end
        return res
    end
    trackTransitions(cfg)
    local res = CVars.Apply(Nameplates.Desired(cfg))
    if cfg.fade == "soft" then
        ns.Plates.Update({
            vis = { enemies = Nameplates.GroupVisible(cfg.enemies), friends = Nameplates.GroupVisible(cfg.friends) },
            keep = { enemies = cfg.enemies.keepTarget, friends = cfg.friends.keepTarget }, duration = cfg.fadeDuration,
        })
    elseif Nameplates.QuestFarOn(cfg) then
        -- hart + Fernsicht: Gegner-Plaketten existieren, unsichtbare stehen sofort auf Alpha 0 (wie hart: kein keepTarget)
        resetHold()
        ns.Plates.Update({
            vis = { enemies = Nameplates.GroupVisible(cfg.enemies), friends = Nameplates.GroupVisible(cfg.friends) },
            keep = { enemies = false, friends = false }, duration = 0,
        })
    else
        resetHold() -- hart: keine Haltezeit, kein Alpha
        ns.Plates.Update(nil)
    end
    return res
end

--- Mehrere Einstellungen im aktiven Profil setzen (changes: Pfad wie "enabled", "enemies.baseShow" -> Wert; geprueft
--- wie beim Import, alles oder nichts) und anwenden. Liefert true oder nil, "NP_VALUE_INVALID".
function Nameplates.SetMany(changes)
    local p = Store.GetActive()
    local candidate = type(p.nameplates) == "table" and Store.DeepCopy(p.nameplates) or {}
    local paths = {}
    for path in pairs(changes) do paths[#paths + 1] = path end
    table.sort(paths)
    local split = {}
    for _, path in ipairs(paths) do
        local parts = {}
        for part in path:gmatch("[^%.]+") do parts[#parts + 1] = part end
        split[path] = parts
        local node = candidate
        for i = 1, #parts - 1 do
            if type(node[parts[i]]) ~= "table" then node[parts[i]] = {} end
            node = node[parts[i]]
        end
        node[parts[#parts]] = Store.DeepCopy(changes[path])
    end
    local clean = Nameplates.Validate(candidate)
    if not clean then return nil, "NP_VALUE_INVALID" end
    for _, path in ipairs(paths) do
        local chk = clean
        for _, part in ipairs(split[path]) do
            if type(chk) ~= "table" then chk = nil; break end
            chk = chk[part]
        end
        if chk == nil then return nil, "NP_VALUE_INVALID" end
    end
    -- Handaenderung an einem Stil-Schalter: "preset" folgt den Schaltern (passen sie zu keinem Preset: "custom")
    if changes["style.preset"] == nil then
        for _, path in ipairs(paths) do
            local part, rest = path:match("^style%.([^%.]+)%.?(.*)$")
            if part and STYLE_PART_SET[part] and (rest == "enabled" or Nameplates.STYLE_PRESET_SUBS[part .. "." .. rest] ~= nil) then
                clean.style = clean.style or {}
                clean.style.preset = Nameplates.StylePresetOf(merged(Nameplates.DEFAULTS, clean).style)
                break
            end
        end
    end
    p.nameplates = clean
    Nameplates.Apply()
    if Nameplates.Style then Nameplates.Style.Refresh() end -- Plaketten-Stil (Style.lua) liest seine Einstellungen neu
    return true
end

function Nameplates.Set(path, value) return Nameplates.SetMany({ [path] = value }) end

-- Voreinstellungen (nur die Plaketten; Radius und Ein-/Ausblende-Art bleiben, die globalen Presets bleiben unveraendert)
Nameplates.PRESET_ORDER = { "combat", "combattarget", "off" }
Nameplates.PRESETS = {
    combat = { ["enabled"] = true, ["enemies.baseShow"] = false, ["enemies.conditions"] = { "combat" },
               ["friends.baseShow"] = false, ["friends.conditions"] = { "combat" } },
    combattarget = { ["enabled"] = true, ["enemies.baseShow"] = false, ["enemies.conditions"] = { "combat", "target" },
                     ["friends.baseShow"] = false, ["friends.conditions"] = { "combat", "target" } },
    off = { ["enabled"] = false },
}

--- Voreinstellung uebernehmen. Liefert true oder nil, Fehlerschluessel.
function Nameplates.ApplyPreset(id)
    local preset = Nameplates.PRESETS[id]
    if not preset then return nil, "NP_PRESET_UNKNOWN" end
    return Nameplates.SetMany(preset)
end

--- Stil-Preset uebernehmen (nur Stil-Bausteine). Liefert true oder nil, Fehlerschluessel.
function Nameplates.ApplyStylePreset(id)
    local changes = Nameplates.StylePresetChanges(id)
    if not changes then return nil, "NP_PRESET_UNKNOWN" end
    return Nameplates.SetMany(changes)
end

-- Modul + Ereignisse ------------------------------------------------------------------------------
ns.RegisterModule("nameplates", {
    OnEnable = function()
        active = true
        CVars.ClearFailures()
        -- Login-Pruefung: Reste einer frueheren Sitzung (Absturz, anderer Charakter, Profil jetzt aus) werden hier
        -- ueber den owned-Marker zurueckgestellt, wenn das Modul im aktiven Profil nicht an ist.
        local wasOwned = #CVars.OwnedNames() > 0
        local res = Nameplates.Apply()
        if wasOwned and not Nameplates.GetConfig().enabled then
            local n = 0
            for _, st in pairs(res) do if st == "ok" then n = n + 1 end end
            if n > 0 then ns.Print(L.NP_LOGIN_RESTORED, n) end
        end
    end,
    OnDisable = function()
        active = false
        resetHold()
        ns.Plates.Update(nil)
        CVars.RestoreAll()
    end,
})

Store.RegisterCallback(function()
    CVars.ClearFailures()
    if active then Nameplates.Apply() end
end)

-- Zielwechsel (auch A -> B ohne dass "Ziel vorhanden" wechselt, Gegner -> Freund): keepTarget braucht die CVar der
-- Gruppe des neuen Ziels und das neue Ziel-Alpha
ns.On("PLAYER_TARGET_CHANGED", function()
    if not active then return end
    local cfg = Nameplates.GetConfig()
    if cfg.enabled and cfg.fade == "soft" and cfg.keepTarget then Nameplates.Apply() end
end)

-- Zustandswechsel: nur wenn der Zustand in einer Bedingungsliste steht, werden die CVars neu berechnet
State.RegisterCallback(function(name)
    if not active then return end
    local cfg = Nameplates.GetConfig()
    if not cfg.enabled then return end
    if name == "target" and cfg.fade == "soft" and cfg.keepTarget then
        Nameplates.Apply()
        return
    end
    for _, group in ipairs({ cfg.enemies, cfg.friends }) do
        for _, c in ipairs(group.conditions) do
            if c == name then
                Nameplates.Apply()
                return
            end
        end
    end
end)

-- Zonen-/Instanzwechsel: Blizzard setzt Plaketten-Einstellungen teils zurueck, Lucid gewinnt
ns.On("PLAYER_ENTERING_WORLD", function()
    if active and Nameplates.GetConfig().enabled then Nameplates.Apply() end
end)

-- Ende der Kampfsperre: ausstehende Schreibzugriffe nachholen
ns.On("PLAYER_REGEN_ENABLED", function()
    if active then CVars.Flush() end
end)

-- Abmelden/Neuladen: Blizzard-Werte zurueck (account-weite CVars gelten fuer alle Charaktere)
ns.Compat.TryOn("PLAYER_LOGOUT", function()
    if active then CVars.RestoreAll() end
end)

-- Slash: /lucid nameplates on|off|status|debug (|probe) --------------------------------------------
local function esc(s) return (tostring(s):gsub("|", "||")) end
local function yesNo(b) return b and L.NP_YES or L.NP_NO end
local function condList(g)
    if #g.conditions == 0 then return L.NP_NONE end
    return table.concat(g.conditions, ", ")
end

local function printStatus()
    local cfg = Nameplates.GetConfig()
    ns.Print(L.NP_STATUS, cfg.enabled and L.NP_ON or L.NP_OFF)
    if not cfg.enabled then return end
    ns.Print(L.NP_STATUS_GROUP, L.NP_ENEMIES, yesNo(cfg.enemies.baseShow), condList(cfg.enemies))
    ns.Print(L.NP_STATUS_GROUP, L.NP_FRIENDS, yesNo(cfg.friends.baseShow), condList(cfg.friends))
    if cfg.radius.enabled then ns.Print(L.NP_STATUS_RADIUS, ("%g"):format(cfg.radius.yards)) end
    local n = 0
    for _ in pairs(CVars.Pending()) do n = n + 1 end
    if n > 0 then ns.Print(L.NP_STATUS_PENDING, n) end
end

local function printDebug()
    local cfg = Nameplates.GetConfig()
    local desired = Nameplates.Desired(cfg)
    local pend = CVars.Pending()
    local owned = {}
    for _, n in ipairs(CVars.OwnedNames()) do owned[n] = true end
    ns.Print(L.NP_DEBUG_HEAD, cfg.enabled and L.NP_ON or L.NP_OFF, active and L.NP_YES or L.NP_NO,
        InCombatLockdown() and L.NP_YES or L.NP_NO)
    for _, name in ipairs(CVars.CATALOG) do
        local info = CVars.Info(name)
        if not info.exists then
            ns.Print(L.NP_DEBUG_MISSING, name)
        else
            ns.Print(L.NP_DEBUG_LINE, name, esc(info.value), esc(desired[name] or "-"), esc(CVars.Baseline(name) or "-"),
                yesNo(info.secure), yesNo(owned[name]), esc(pend[name] or "-"), esc(CVars.LastResult(name) or "-"))
        end
    end
    local tracked, moving = ns.Plates.Counts()
    ns.Print(L.NP_DEBUG_PLATES, tracked, moving)
    local count = CVars.External()
    ns.Print(L.NP_DEBUG_EXTERNAL, count)
end

local function setEnabled(on)
    local ok = Nameplates.Set("enabled", on)
    if not ok then
        ns.Print(L.NP_VALUE_INVALID)
        return
    end
    ns.Print(on and L.NP_ENABLED or L.NP_DISABLED)
    if on then ns.Print(L.NP_KEY_V_HINT) end
    local n = 0
    for _ in pairs(CVars.Pending()) do n = n + 1 end
    if n > 0 then ns.Print(L.NP_STATUS_PENDING, n) end
end

ns.commands.nameplates = function(rest)
    local sub = (rest or ""):match("^%s*(%S*)"):lower()
    if sub == "" or sub == "status" then
        printStatus()
        if sub == "" then ns.Print(L.HELP_NAMEPLATES) end
    elseif sub == "on" or sub == "an" then
        setEnabled(true)
    elseif sub == "off" or sub == "aus" then
        setEnabled(false)
    elseif sub == "debug" then
        printDebug()
    elseif sub == "preset" then
        local id = (rest or ""):match("^%s*%S+%s+(%S+)")
        local ok = id and Nameplates.ApplyPreset(id:lower())
        if ok then
            ns.Print(L.NP_PRESET_APPLIED, id:lower())
            printStatus()
        else
            ns.Print(L.NP_PRESET_INVALID, esc(id or ""))
        end
    elseif sub == "style" and Nameplates.StylePresetByName((rest or ""):match("^%s*%S+%s+(%S+)")) then
        local id = Nameplates.StylePresetByName((rest or ""):match("^%s*%S+%s+(%S+)"))
        if Nameplates.ApplyStylePreset(id) then
            ns.Print(L.NP_ST_PRESET_APPLIED, L["UI_NP_STYLE_PRESET_" .. id])
            if not Nameplates.GetConfig().style.enabled then ns.Print(L.NP_ST_PRESET_HINT_OFF) end
        else
            ns.Print(L.NP_VALUE_INVALID)
        end
    elseif Nameplates.sub[sub] then
        Nameplates.sub[sub]((rest or ""):match("^%s*%S+%s*(.-)%s*$")) -- Rest nach dem Unterbefehl (z. B. "probe style")
    else
        ns.Print(L.NP_UNKNOWN, (sub:gsub("|", "||")))
        ns.Print(L.HELP_NAMEPLATES)
    end
end

ns.AddHelp("HELP_NAMEPLATES")
