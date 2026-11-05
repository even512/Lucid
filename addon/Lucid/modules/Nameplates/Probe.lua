-- Plaketten (B7/N0): Diagnose-Probe /lucid nameplates probe. Beantwortet im Client, was die Recherche offen liess:
-- Existenz, Wert, Standard und isSecure der Plaketten-CVars, Grenzen von nameplateMaxDistance.
-- Rein lesend; nur der Min/Max-Test schreibt nameplateMaxDistance - ausserhalb des Kampfs, jeder Testwert wird
-- zurueckgelesen und der Originalwert danach sofort wiederhergestellt (auch bei Fehlern).
local _, ns = ...
local CVars, Nameplates = ns.CVars, ns.Nameplates
local L = ns.L

-- zusaetzlich zu den verwalteten CVars (nur lesen): fuer N3/Radius-Entscheidungen
local EXTRA = {
    "nameplateShowEnemyMinions", "nameplateShowFriendlyPlayerMinions", "nameplateShowOnlyNameForFriendlyPlayerUnits",
    "nameplateCheckDistanceForTarget", "nameplateMinAlpha", "nameplateMinAlphaDistance",
    "nameplateSelectedAlpha", "nameplateNotSelectedAlpha", "nameplateShowOffscreen",
}
local TEST_VALUES = { 0, 1, 5, 10, 60, 100, 500 }

local function esc(s) return (tostring(s):gsub("|", "||")) end
local function yn(b) return b and L.NP_YES or L.NP_NO end
local function where(info)
    if info.character then return L.NP_PROBE_CHARACTER end
    if info.account then return L.NP_PROBE_ACCOUNT end
    return L.NP_PROBE_LOCAL
end

local function probeLine(name)
    local info = CVars.Info(name)
    if not info.exists then
        ns.Print(L.NP_PROBE_MISSING, name)
        return
    end
    ns.Print(L.NP_PROBE_LINE, name, esc(info.value), esc(info.default or "-"), yn(info.secure), yn(info.readOnly), where(info))
end

--- Min/Max-Test fuer nameplateMaxDistance. Setzt Testwerte, liest zurueck und stellt den Originalwert wieder her.
local function rangeTest()
    local name = CVars.MAX_DISTANCE
    if InCombatLockdown() then
        ns.Print(L.NP_PROBE_RANGE_COMBAT)
        return
    end
    local info = CVars.Info(name)
    if not info.exists then
        ns.Print(L.NP_PROBE_MISSING, name)
        return
    end
    local original = info.value
    local release = CVars.Guard(name) -- Absturz mitten im Test: der Login stellt den Originalwert wieder her
    local results = {}
    local ok, err = pcall(function()
        for _, v in ipairs(TEST_VALUES) do
            local wrote, why = CVars.ProbeWrite(name, v)
            results[#results + 1] = { v, CVars.Get(name) or "?", wrote, why }
        end
    end)
    -- Originalwert sofort zurueck (immer, auch nach einem Fehler)
    local okRestore, restored = pcall(CVars.ProbeWrite, name, original)
    restored = okRestore and restored
    if restored and release then release() end
    ns.Print(L.NP_PROBE_RANGE_HEAD, name, esc(original))
    for _, r in ipairs(results) do
        ns.Print(L.NP_PROBE_RANGE_LINE, r[1], esc(r[2]), r[3] and L.NP_PROBE_OK or esc(r[4]))
    end
    if not ok then ns.Print(L.NP_PROBE_ERROR, (tostring(err):gsub("|", "||"))) end
    ns.Print(restored and L.NP_PROBE_RESTORED or L.NP_PROBE_RESTORE_FAILED, esc(original))
end

Nameplates.sub.probe = function()
    ns.Print(L.NP_PROBE_HEAD, ns.Compat.flavor, ns.Compat.interface, yn(InCombatLockdown()))
    for _, name in ipairs(CVars.CATALOG) do probeLine(name) end
    for _, name in ipairs(EXTRA) do probeLine(name) end
    rangeTest()
end

ns.AddHelp("HELP_NAMEPLATES_PROBE")
