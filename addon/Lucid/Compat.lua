-- Compat: Feature-Erkennung Forever vs. Retail. Lucid fragt Faehigkeiten ab, nicht Versionsnummern:
-- Forever (Interface 16001) und Retail (120105) teilen dieselbe Addon-API, Unterschiede werden zur
-- Laufzeit erkannt (API vorhanden? Event bekannt? Wert ein Secret Value?).
local _, ns = ...

local Compat = {}
ns.Compat = Compat

do
    local toc = GetBuildInfo and select(4, GetBuildInfo())
    Compat.interface = tonumber(toc) or 0
end
-- Retail zaehlt ab 10.0 sechsstellig; Forever meldet eine eigene, kleinere Nummer.
Compat.isRetail = Compat.interface >= 100000
Compat.isForever = Compat.interface > 0 and not Compat.isRetail
Compat.flavor = Compat.isRetail and "retail" or (Compat.isForever and "forever" or "unknown")

-- Secret Values (Retail 12.x): bestimmte Werte (u. a. Leben/Ressource im Kampf) sind fuer Addons
-- nicht lesbar; jeder Vergleich damit wirft. issecretvalue gibt es nur in Clients mit dieser Sperre.
Compat.hasSecrets = type(issecretvalue) == "function"

function Compat.IsSecret(v)
    return Compat.hasSecrets and issecretvalue(v) == true
end

--- Wahrheitswert eines API-Ergebnisses ohne Wahrheitstest auf einem Secret Value: Secret => false.
function Compat.Bool(v)
    if Compat.IsSecret(v) then return false end
    return v ~= nil and v ~= false
end

--- Boolesche Abfrage obj:method(...) (z. B. IsMouseEnabled, IsForbidden, IsVisible, IsMouseOver).
--- Liefert true/false, oder nil, wenn die Methode fehlt, wirft oder einen Secret Value liefert
--- (Retail 12.x: Frame-Zustaende tief in Einheitenfenstern koennen secret sein; jeder Test darauf wirft).
function Compat.QueryBool(obj, method, ...)
    local fn = type(obj) == "table" and obj[method]
    if type(fn) ~= "function" then return nil end
    local ok, v = pcall(fn, obj, ...)
    if not ok or Compat.IsSecret(v) then return nil end
    return v ~= nil and v ~= false
end

--- Zahl aus einem API-Ergebnis: nil bei Secret Value, Nicht-Zahl oder NaN.
function Compat.Num(v)
    if Compat.IsSecret(v) or type(v) ~= "number" or v ~= v then return nil end
    return v
end

--- true, wenn der Pfad (z. B. "C_Map.GetBestMapForUnit") eine Funktion ist.
function Compat.HasAPI(path)
    local cur = _G
    for part in path:gmatch("[^%.]+") do
        if type(cur) ~= "table" then return false end
        cur = cur[part]
    end
    return type(cur) == "function"
end

--- Event anmelden, ohne bei einem im Client unbekannten Event zu werfen. Liefert true bei Erfolg.
function Compat.TryOn(event, fn)
    return (pcall(ns.On, event, fn))
end

--- Aktuelles und maximales Leben ("health") bzw. Ressource ("power") des Spielers.
--- Liefert cur, max, powerType oder nil, Grund ("secret" | "api" | "invalid").
function Compat.PlayerValues(kind)
    local cur, max, ptype
    if kind == "health" then
        if not (UnitHealth and UnitHealthMax) then return nil, "api" end
        cur, max = UnitHealth("player"), UnitHealthMax("player")
    elseif kind == "power" then
        if not (UnitPower and UnitPowerMax and UnitPowerType) then return nil, "api" end
        ptype = UnitPowerType("player")
        if Compat.IsSecret(ptype) then return nil, "secret" end
        cur, max = UnitPower("player", ptype), UnitPowerMax("player", ptype)
    else
        return nil, "api"
    end
    -- Secret-Pruefung VOR jeder Rechnung/jedem Vergleich (sonst Lua-Fehler im Client)
    if Compat.IsSecret(cur) or Compat.IsSecret(max) then return nil, "secret" end
    if type(cur) ~= "number" or type(max) ~= "number" then return nil, "invalid" end
    return cur, max, ptype
end

--- Blizzard-Bearbeitungsmodus: aktuell offen?
function Compat.IsEditModeActive()
    local f = EditModeManagerFrame
    return Compat.QueryBool(f, "IsEditModeActive") == true
end

--- onEnter/onExit beim Oeffnen/Schliessen des Bearbeitungsmodus aufrufen.
--- Bevorzugt EventRegistry ("EditMode.Enter/Exit"), sonst OnShow/OnHide des Manager-Frames
--- (HookScript, kein Eingriff in geschuetzte Skripte). Liefert false, wenn es keinen Bearbeitungsmodus gibt.
function Compat.OnEditMode(onEnter, onExit)
    if EventRegistry and EventRegistry.RegisterCallback then
        EventRegistry:RegisterCallback("EditMode.Enter", function() onEnter() end, Compat)
        EventRegistry:RegisterCallback("EditMode.Exit", function() onExit() end, Compat)
        return true
    end
    local f = EditModeManagerFrame
    if f and f.HookScript then
        f:HookScript("OnShow", function() onEnter() end)
        f:HookScript("OnHide", function() onExit() end)
        return true
    end
    return false
end
