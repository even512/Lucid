-- Presets fuer den Element-Katalog: "Immersion", "Ausgewogen", "Kampf", "Aus".
-- Uebernehmen schreibt fuer jedes Katalog-Element eine vollstaendige Einstellung ins aktive Profil
-- (vorherige Einstellungen dieser Elemente werden ersetzt, andere Abschnitte/Elemente bleiben). Danach ist
-- alles frei anpassbar; Lucid merkt sich kein "aktives Preset".
local _, ns = ...
local Elements, Fader, Store = ns.Elements, ns.Fader, ns.Store
local L = ns.L

local Presets = {}
ns.Presets = Presets

Presets.ORDER = { "immersion", "balanced", "combat", "off" }
-- Eingabe -> Preset (Englisch und Deutsch, ohne Gross-/Kleinschreibung)
Presets.ALIASES = {
    immersion = "immersion",
    balanced = "balanced", ausgewogen = "balanced",
    combat = "combat", kampf = "combat",
    off = "off", aus = "off",
}

local function conds(...)
    local list = {}
    for i = 1, select("#", ...) do list[i] = { state = (select(i, ...)), alpha = 1 } end
    return list
end

-- Einstellung: Basis-Alpha, Bedingungen, Zeiten (Ein, Aus, Verzoegerung), Klicks durchlassen
local function cfg(base, conditions, fadeIn, fadeOut, delay, clickThrough)
    return {
        enabled = true, baseAlpha = base, conditions = conditions,
        fadeIn = fadeIn, fadeOut = fadeOut, delay = delay, clickThrough = clickThrough,
    }
end

local OFF = function() return { enabled = false } end

-- Je Preset: Funktion(entry) -> Einstellung des Elements
Presets.BUILDERS = {
    -- ausserhalb des Kampfs ist alles unsichtbar; Kampf, Ziel und Maus darueber blenden weich ein,
    -- Ausblenden erst nach 2 s. Mikromenue/Taschen/Tracker/XP nur bei Bedarf.
    immersion = function(entry)
        local id, group = entry.id, entry.group
        if id == "micromenu" or id == "statusbars" then return cfg(0, conds("mouseover"), 0.3, 0.8, 2, true) end
        if id == "bags" or id == "tracker" or id == "questietracker" then return cfg(0, conds("mouseover", "npc"), 0.3, 0.8, 2, true) end
        if id == "buffs" or id == "debuffs" then return cfg(0, conds("combat", "mouseover"), 0.3, 0.8, 2, true) end
        -- Spielerrahmen bleibt zusaetzlich sichtbar, solange Leben fehlt (Bedingungen: Maximum)
        if id == "player" then return cfg(0, conds("combat", "target", "mouseover", "hurt"), 0.3, 0.8, 2, true) end
        if group == "bars" or group == "units" or id == "minimap" then
            return cfg(0, conds("combat", "target", "mouseover"), 0.3, 0.8, 2, true)
        end
        return OFF()
    end,
    -- alles bleibt angedeutet sichtbar (gedimmt), voll bei Bedarf; keine Klicks durchlassen
    balanced = function(entry)
        local id, group = entry.id, entry.group
        if id == "micromenu" or id == "statusbars" then return cfg(0.3, conds("mouseover"), 0.25, 0.6, 1.5, false) end
        if id == "bags" then return cfg(0.3, conds("mouseover", "npc"), 0.25, 0.6, 1.5, false) end
        if id == "tracker" or id == "questietracker" then return cfg(0.7, conds("mouseover", "npc"), 0.25, 0.6, 1.5, false) end
        if id == "minimap" then return cfg(0.6, conds("mouseover"), 0.25, 0.6, 1.5, false) end
        if id == "buffs" or id == "debuffs" then return cfg(0.5, conds("combat", "mouseover"), 0.25, 0.6, 1.5, false) end
        if group == "units" then
            return cfg(0.5, conds("combat", "target", "mouseover", "hurt"), 0.25, 0.6, 1.5, false)
        end
        if group == "bars" then
            return cfg(0.3, conds("combat", "target", "mouseover", "casting"), 0.25, 0.6, 1.5, false)
        end
        return OFF()
    end,
    -- Kampf-Fokus: Leisten, Einheitenfenster, Buffs/Debuffs bleiben unberuehrt (immer sichtbar);
    -- Minimap, Tracker, Mikromenue, Taschen, XP-Leiste nur bei Bedarf, schnelle Blenden
    combat = function(entry)
        local id = entry.id
        if id == "bags" or id == "tracker" or id == "questietracker" then return cfg(0, conds("mouseover", "npc"), 0.15, 0.5, 1, true) end
        if id == "minimap" or id == "micromenu" or id == "statusbars" then
            return cfg(0, conds("mouseover"), 0.15, 0.5, 1, true)
        end
        return OFF()
    end,
    -- Lucid fasst kein Element an
    off = OFF,
}

--- Name/Alias -> Preset-Schluessel oder nil
function Presets.Resolve(name)
    if type(name) ~= "string" then return nil end
    return Presets.ALIASES[name:lower():match("^%s*(.-)%s*$")]
end

--- Einstellungen aller Katalog-Elemente fuer ein Preset (frische Tabellen)
function Presets.Build(key)
    local build = Presets.BUILDERS[key]
    if not build then return nil end
    local out = {}
    for _, entry in ipairs(Elements.CATALOG) do out[entry.id] = build(entry) end
    return out
end

--- Preset ins aktive Profil uebernehmen und sofort anwenden.
--- Liefert den Preset-Schluessel oder nil, Code ("PRESET_UNKNOWN").
function Presets.Apply(name)
    local key = Presets.Resolve(name)
    if not key then return nil, "PRESET_UNKNOWN" end
    local clean = Fader.ValidateElements(Presets.Build(key)) -- Absicherung: Presets halten das Import-Schema ein
    assert(clean, "Lucid: Preset verletzt das Schema: " .. key)
    local p = Store.GetActive()
    if type(p.elements) ~= "table" then p.elements = {} end
    for id, c in pairs(clean) do p.elements[id] = c end
    Elements.SyncAll()
    return key
end

-- Slash: /lucid preset <name> --------------------------------------------------------------------
ns.commands.preset = function(rest)
    local key, code = Presets.Apply(rest or "")
    if not key then
        if (rest or "") ~= "" then ns.Print(L[code], (tostring(rest):gsub("|", "||"))) end
        ns.Print(L.PRESET_LIST)
        return
    end
    ns.Print(L.PRESET_APPLIED, L["PRESET_" .. key], (Store.GetActiveName():gsub("|", "||")))
end

ns.AddHelp("HELP_PRESET")
