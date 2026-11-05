-- Kamera (B8): Schulterversatz (test_cameraOverShoulder) weich fuehren.
--
-- 1. Uebergang: wechselt der Sollwert des Versatzes (Regel/Zustand, z. B. Gebaeude betreten, Aufsitzen), springt die Kamera nicht
--    zur Mitte, sondern gleitet in "offsetSeconds" (Profil, Standard 0,6 s, 0 = sofort) mit Ease-in-out (smoothstep) zum neuen Wert.
--    Der erste Wert nach dem Einschalten, Restore, Logout und Ausschalten gelten sofort.
-- 2. Versatz nach Abstand (Option "offsetByDistance", wie DynamicCam): wirksamer Versatz = Sollwert x Faktor(Kameradistanz),
--    Faktor 0 bis NEAR (2 yd), 1 ab FAR (7 yd), dazwischen linear. Die Distanz kommt aus GetCameraZoom(). Das Ziel eines Uebergangs
--    ist der jeweils aktuelle Wert (Regelwert x Abstandsfaktor), die Kamera gleitet also auch dorthin.
-- Ein Ticker laeuft nur waehrend eines Uebergangs (schnell, FAST) oder solange der Abstandsversatz aktiv ist und der Sollwert
-- ungleich 0 ist (langsam, SLOW). Geschrieben wird ueber den gemeinsamen CVar-Treiber (Sicherung/Restore wie bei jedem Wert),
-- im Abstandsmodus nur bei merklicher Aenderung (STEP). Fehlt GetCameraZoom, gilt der volle Sollwert (Faktor 1).
local _, ns = ...
local Camera, CVars, Compat = ns.Camera, ns.CameraCVars, ns.Compat

local Offset = {}
Camera.Offset = Offset

Offset.CVAR = "test_cameraOverShoulder"
Offset.NEAR, Offset.FAR = 2, 7  -- Yards: darunter kein Versatz, ab hier voller Versatz
Offset.FAST = 0.03              -- Ticker waehrend eines Uebergangs (Sekunden)
Offset.SLOW = 0.1               -- Ticker im reinen Abstandsmodus
Offset.STEP = 0.03              -- Abstandsmodus: kleinste Aenderung, die geschrieben wird
Offset.GLIDE_STEP = 0.004       -- Uebergang: kleinste Aenderung je Tick
Offset.DIST_STEP = 0.02         -- Abstandsmodus: kleinste Distanzaenderung, die ueberhaupt neu gerechnet wird
Offset.MIN_JUMP = 0.02          -- kleinere Sprungweiten gleiten nicht, sie gelten sofort

local ticker, tickerEvery
local have = false       -- Lucid fuehrt den Versatz gerade (nach dem ersten Plan)
local target = nil       -- Sollwert der Regel (ohne Abstandsfaktor)
local useDist = false    -- Abstandsfaktor anwenden
local cur = nil          -- zuletzt vorgegebener wirksamer Versatz
local glide = nil        -- { from, t0, dur } waehrend eines Uebergangs
local lastDist = nil     -- Distanz der letzten Rechnung (Abstandsmodus)

--- aktuelle Kameradistanz in Yards oder nil (API fehlt, wirft, Secret Value, nicht endlich)
function Offset.Distance()
    if type(GetCameraZoom) ~= "function" then return nil end
    local ok, v = pcall(GetCameraZoom)
    if not ok then return nil end
    v = Compat.Num(v)
    if v == nil or v ~= v or v < 0 or v > 1e6 then return nil end
    return v
end

--- Faktor 0..1 zur Distanz; ohne Distanz 1
function Offset.Factor(dist)
    if dist == nil then return 1 end
    if dist <= Offset.NEAR then return 0 end
    if dist >= Offset.FAR then return 1 end
    return (dist - Offset.NEAR) / (Offset.FAR - Offset.NEAR)
end

local function round4(v) return tonumber(("%.4f"):format(v)) end

--- wirksamer Versatz zum Sollwert und zur Distanz (auf vier Stellen gerundet)
function Offset.Scale(value, dist) return round4(value * Offset.Factor(dist)) end

--- Ease-in-out (smoothstep), p in 0..1
function Offset.Ease(p)
    if p <= 0 then return 0 end
    if p >= 1 then return 1 end
    return p * p * (3 - 2 * p)
end

function Offset.IsRunning() return ticker ~= nil end
function Offset.IsGliding() return glide ~= nil end
function Offset.Target() return target end
function Offset.Current() return cur end

local function now() return (type(GetTime) == "function" and GetTime()) or 0 end

local function goalNow()
    if target == nil then return nil end
    if useDist then return Offset.Scale(target, Offset.Distance()) end
    return round4(target)
end

local ensureTicker

local function tick()
    if not have or target == nil then return end
    if Camera.IsPaused() then return end -- fremde Aenderung: Lucid schreibt die Action Cam nicht, bis der Nutzer etwas aendert
    local goal = goalNow()
    local value
    if glide then
        local p = glide.dur > 0 and (now() - glide.t0) / glide.dur or 1
        if p >= 1 then
            value = goal
            glide = nil
        else
            value = round4(glide.from + (goal - glide.from) * Offset.Ease(p))
        end
        if value ~= cur and (glide == nil or math.abs(value - cur) >= Offset.GLIDE_STEP) then
            cur = value
            CVars.Write(Offset.CVAR, value)
        end
        if glide == nil then ensureTicker() end
        return
    end
    if not useDist then return ensureTicker() end
    local dist = Offset.Distance()
    if dist == nil then return end
    if lastDist ~= nil and math.abs(dist - lastDist) < Offset.DIST_STEP then return end
    lastDist = dist
    value = goal
    if cur ~= nil then
        local small = math.abs(value - cur) < Offset.STEP
        -- die Endpunkte (kein Versatz / voller Versatz) werden immer erreicht
        if small and (value == cur or (value ~= 0 and value ~= target)) then return end
    end
    cur = value
    CVars.Write(Offset.CVAR, value)
end

local function cancel()
    if ticker then
        ticker:Cancel()
        ticker, tickerEvery = nil, nil
    end
end

--- Ticker nach Bedarf: waehrend eines Uebergangs schnell, im Abstandsmodus (Sollwert <> 0) langsam, sonst keiner
function ensureTicker()
    local want = nil
    if have and target ~= nil and CVars.Info(Offset.CVAR).exists then
        if glide then want = Offset.FAST
        elseif useDist and target ~= 0 and type(GetCameraZoom) == "function" then want = Offset.SLOW end
    end
    if want == nil then return cancel() end
    if ticker and tickerEvery == want then return end
    cancel()
    if C_Timer and C_Timer.NewTicker then
        ticker, tickerEvery = C_Timer.NewTicker(want, tick), want
    end
end

--- Fuehrung beenden (Ausschalten, Restore, Logout): kein Ticker, der naechste Plan gilt wieder sofort
function Offset.Stop()
    cancel()
    have, target, useDist, cur, glide, lastDist = false, nil, false, nil, nil, nil
end
Offset.Sync = function(value)
    if value == nil then return Offset.Stop() end
end

--- Von Camera.Apply: Sollwert der Regel (target, ohne Abstandsfaktor; nil = Lucid setzt keinen Versatz) und der zum jetzigen
--- Abstand passende Zielwert (goal). Liefert den Wert, der JETZT geschrieben werden soll (bei einem Uebergang der aktuelle
--- Zwischenwert, sonst goal), oder nil.
function Offset.Plan(newTarget, goal, distanceMode, seconds)
    if newTarget == nil or goal == nil then
        Offset.Stop()
        return goal
    end
    local changed = (not have) or newTarget ~= target
    local was = cur
    target, useDist, have = newTarget, distanceMode and true or false, true
    if not CVars.Info(Offset.CVAR).exists then -- nichts zu fuehren
        cur, glide = goal, nil
        return goal
    end
    lastDist = Offset.Distance()
    if glide then
        -- laufender Uebergang: neues Ziel, gleiche Zwischenstelle als Start (kein Sprung)
        if changed then glide = { from = cur, t0 = now(), dur = seconds or 0 } end
        if (seconds or 0) <= 0 then glide, cur = nil, goal end
    elseif changed and was ~= nil and (seconds or 0) > 0 and math.abs(goal - was) >= Offset.MIN_JUMP then
        glide = { from = was, t0 = now(), dur = seconds }
    else
        cur = goal
    end
    ensureTicker()
    return cur
end
