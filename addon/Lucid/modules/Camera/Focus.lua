-- Kamera: Zielfokus auf Gegner (test_cameraTargetFocusEnemy*) weich fuehren.
--
-- Der Wechsel in den Kampf soll nicht ruppig sein. Die wirksamen Staerken (Yaw/Pitch) gleiten deshalb in "focusSeconds"
-- (Profil, Standard 1,5 s, 0 = sofort) mit derselben Ease-Kurve wie der Schulterversatz (Offset.Ease):
--   Fokus geht an:  Enable wird sofort 1, die Staerken starten bei 0 und gleiten zum Sollwert.
--   Fokus geht aus: die Staerken gleiten auf 0; Enable bleibt solange 1. Erst danach gilt der Sollwert der Regel (Enable 0 oder
--                   keiner, Staerken Sollwert oder keiner => der Treiber stellt den Originalwert zurueck). Das uebernimmt ein
--                   normales Camera.Apply am Ende des Uebergangs.
--   Sollwert aendert sich bei aktivem Fokus: Gleiten vom aktuellen Zwischenwert, ein laufender Uebergang springt nicht.
--   Setzt eine Regel Enable, aber keine Staerke, gilt der Ausgangswert des Spiels (Sicherung im Treiber) als Sollwert.
-- Sofort gelten (wie beim Versatz): der erste Wert nach dem Einschalten, Restore, Logout, Ausschalten (Focus.Stop), kleine Spruenge.
-- Waehrend einer Pause (fremde Aenderung) schreibt der Uebergang nichts. Der Ticker laeuft nur waehrend eines Uebergangs.
-- Geschrieben wird ueber den gemeinsamen CVar-Treiber (Sicherung/Restore wie bei jedem Wert).
local _, ns = ...
local Camera, CVars = ns.Camera, ns.CameraCVars

local Focus = {}
Camera.Focus = Focus

Focus.ENABLE = "test_cameraTargetFocusEnemyEnable"
Focus.YAW = "test_cameraTargetFocusEnemyStrengthYaw"
Focus.PITCH = "test_cameraTargetFocusEnemyStrengthPitch"
Focus.FAST = 0.03          -- Ticker waehrend eines Uebergangs (Sekunden)
Focus.GLIDE_STEP = 0.004   -- kleinste Aenderung je Tick, die geschrieben wird
Focus.MIN_JUMP = 0.02      -- kleinere Sprungweiten gleiten nicht, sie gelten sofort

local CHANNELS = { { key = "yaw", id = Focus.YAW }, { key = "pitch", id = Focus.PITCH } }

local ticker
local have = false   -- Lucid fuehrt den Fokus gerade (nach dem ersten Plan)
local on = false     -- Fokus ist (bzw. wird) angeschaltet: Sollwert Enable = 1
local goals = nil    -- Sollwerte der Staerken bei aktivem Fokus { yaw, pitch }
local cur = nil      -- zuletzt vorgegebene Staerken { yaw, pitch } (aus: 0)
local glide = nil    -- { from, to, t0, dur, out } waehrend eines Uebergangs

local function round4(v) return tonumber(("%.4f"):format(v)) end
local function now() return (type(GetTime) == "function" and GetTime()) or 0 end
local function copy(t) return { yaw = t.yaw, pitch = t.pitch } end

function Focus.IsRunning() return ticker ~= nil end
function Focus.IsGliding() return glide ~= nil end
function Focus.IsOn() return have and on end
function Focus.Current() return cur and copy(cur) or nil end

--- Ausgangswert des Spiels fuer eine Staerke: gesicherter Blizzard-Wert, sonst der aktuelle Wert, sonst Standard
local function baseValue(id)
    local v = tonumber(CVars.Baseline(id))
    if v == nil then
        local info = CVars.Info(id)
        v = tonumber(info.value) or tonumber(info.default)
    end
    return v or 0
end

local function goalsOf(static)
    return { yaw = static[Focus.YAW] or baseValue(Focus.YAW), pitch = static[Focus.PITCH] or baseValue(Focus.PITCH) }
end

local function same(a, b) return math.abs(a.yaw - b.yaw) < 1e-4 and math.abs(a.pitch - b.pitch) < 1e-4 end
local function biggest(t) return math.max(math.abs(t.yaw), math.abs(t.pitch)) end

local function cancel()
    if ticker then
        ticker:Cancel()
        ticker = nil
    end
end

--- Staerken beim Uebergang fertigstellen; danach stellt ein normales Camera.Apply die Sollwerte her (Enable zuletzt)
local function finish()
    local g = glide
    glide = nil
    cancel()
    if g.out then
        for _, c in ipairs(CHANNELS) do
            if cur[c.key] ~= 0 then
                cur[c.key] = 0
                CVars.Write(c.id, 0)
            end
        end
    else
        cur = copy(g.to)
    end
    Camera.Apply()
end

local function tick()
    if not glide then return end
    if Camera.IsPaused() then return end -- fremde Aenderung: Lucid schreibt die Action Cam nicht, bis der Nutzer etwas aendert
    local p = glide.dur > 0 and (now() - glide.t0) / glide.dur or 1
    if p >= 1 then return finish() end
    local e = Camera.Offset.Ease(p)
    for _, c in ipairs(CHANNELS) do
        local from, to = glide.from[c.key], glide.to[c.key]
        local value = round4(from + (to - from) * e)
        if math.abs(value - cur[c.key]) >= Focus.GLIDE_STEP then
            cur[c.key] = value
            CVars.Write(c.id, value)
        end
    end
end

local function ensureTicker()
    if not glide then return cancel() end
    if ticker then return end
    if C_Timer and C_Timer.NewTicker then ticker = C_Timer.NewTicker(Focus.FAST, tick) end
end

--- Fuehrung beenden (Ausschalten, Restore, Logout, Pause): kein Ticker, der naechste Plan gilt wieder sofort
function Focus.Stop()
    cancel()
    have, on, goals, cur, glide = false, false, nil, nil, nil
end

--- Werte, die waehrend eines Uebergangs anstelle der Sollwerte gelten (nil = die Sollwerte gelten)
local function overrides()
    if not glide then return nil end
    return { [Focus.ENABLE] = 1, [Focus.YAW] = cur.yaw, [Focus.PITCH] = cur.pitch }
end

local function startGlide(to, seconds, out)
    glide = { from = copy(cur), to = copy(to), t0 = now(), dur = seconds, out = out }
    ensureTicker()
end

--- Von Camera.Apply: Sollwerte ohne Uebergang (static, ohne Pause-Filter) und Dauer in Sekunden. Liefert eine Tabelle
--- name -> Wert, die waehrend eines Uebergangs die Sollwerte ersetzt (Enable 1 + Zwischenstaerken), sonst nil.
function Focus.Plan(static, seconds)
    if not CVars.Info(Focus.ENABLE).exists then -- nichts zu fuehren
        Focus.Stop()
        return nil
    end
    seconds = seconds or 0
    local newOn = static[Focus.ENABLE] == 1
    local newGoals = newOn and goalsOf(static) or nil

    local function immediate()
        if glide then glide = nil; cancel() end
        on, goals = newOn, newGoals
        cur = newOn and copy(newGoals) or { yaw = 0, pitch = 0 }
        return nil
    end

    if not have then -- erster Wert: gilt sofort
        have = true
        return immediate()
    end
    if seconds <= 0 then return immediate() end

    if newOn == on then
        if not newOn then return overrides() end -- aus: ein laufendes Ausblenden geht weiter
        if same(newGoals, goals) then return overrides() end
        -- Sollwert aendert sich bei aktivem Fokus: vom aktuellen Zwischenwert gleiten
        local far = math.abs(newGoals.yaw - cur.yaw) >= Focus.MIN_JUMP or math.abs(newGoals.pitch - cur.pitch) >= Focus.MIN_JUMP
        if glide or far then
            goals = newGoals
            startGlide(newGoals, seconds, false)
            return overrides()
        end
        return immediate()
    end

    if newOn then -- Fokus geht an (auch: ein laufendes Ausblenden kehrt um)
        if not glide and biggest(newGoals) < Focus.MIN_JUMP then return immediate() end
        on, goals = true, newGoals
        startGlide(newGoals, seconds, false)
    else -- Fokus geht aus
        if not glide and biggest(cur) < Focus.MIN_JUMP then return immediate() end
        on, goals = false, nil
        startGlide({ yaw = 0, pitch = 0 }, seconds, true)
    end
    return overrides()
end
