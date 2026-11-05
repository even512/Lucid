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

-- Einstellungen -------------------------------------------------------------------------------------
local function isNum(v, lo, hi) return type(v) == "number" and v == v and v >= lo and v <= hi end

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

--- CVar-Ebene: soll die Gruppe existieren? (hart: = Sichtbarkeit; weich: auch waehrend des Ausblendens und fuer das Ziel)
function Nameplates.Exists(cfg, key)
    if Nameplates.GroupVisible(cfg[key]) then return true end
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
    if cfg.radius.enabled then d[CVars.MAX_DISTANCE] = cfg.radius.yards end
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
    p.nameplates = clean
    Nameplates.Apply()
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
    elseif Nameplates.sub[sub] then
        Nameplates.sub[sub]()
    else
        ns.Print(L.NP_UNKNOWN, (sub:gsub("|", "||")))
        ns.Print(L.HELP_NAMEPLATES)
    end
end

ns.AddHelp("HELP_NAMEPLATES")
