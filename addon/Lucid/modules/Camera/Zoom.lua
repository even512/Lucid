-- Kamera (B8/K3): Zoom-Fahrer. Weicher Uebergang zu einer Ziel-Distanz ueber CameraZoomIn/Out und cameraZoomSpeed
-- (Prinzip von LibCamera.SetZoomUsingCVar, ohne Fremdbibliothek, ohne Eingriff in Blizzards Mausrad-Zoom):
--   1. cameraZoomSpeed sichern und auf |Delta|/Dauer setzen (1 bis 50),
--   2. im naechsten Frame EINMAL CameraZoomOut(Delta) bzw. CameraZoomIn(-Delta) ausloesen,
--   3. per OnUpdate GetCameraZoom() beobachten, bis das Ziel erreicht ist oder die Zeit um ist; dann cameraZoomSpeed zurueck.
-- Die Distanz vor dem ersten Lucid-Zoom wird gemerkt; endet jede Ziel-Distanz, faehrt Lucid nach RETURN_DELAY dorthin
-- zurueck (Verzoegerung gegen Zucken beim Wechsel zwischen NPC-Fenstern). Beim Abmelden/Ausschalten geht es zurueck.
-- Ein Zoom des Nutzers waehrend der Fahrt wird nicht bekaempft: die Fahrt endet spaetestens nach dem Zeitlimit.
local _, ns = ...
local Camera, Compat = ns.Camera, ns.Compat

local Zoom = {}
Camera.Zoom = Zoom

Zoom.RETURN_DELAY = 0.3
Zoom.MIN, Zoom.MAX = 1, Compat.isRetail and 39 or 50
Zoom.TOLERANCE = 0.05
Zoom.SPEED_CVAR = "cameraZoomSpeed"

local saved = nil      -- Distanz vor dem ersten Lucid-Zoom (nil = Lucid hat nichts verschoben)
local target = nil     -- aktuelles Ziel (nil = keines)
local move = nil       -- laufende Fahrt { dest, called, elapsed, limit, speed (urspruenglicher Wert) }
local returnToken = 0  -- macht ausstehende Rueckkehr-Timer ungueltig
local frame

local function current()
    if type(GetCameraZoom) ~= "function" then return nil end
    local ok, v = pcall(GetCameraZoom)
    return ok and Compat.Num(v) or nil
end

local function setSpeed(v)
    if v ~= nil and type(SetCVar) == "function" then pcall(SetCVar, Zoom.SPEED_CVAR, v) end
end

local function getSpeed()
    if type(GetCVar) ~= "function" then return nil end
    local ok, v = pcall(GetCVar, Zoom.SPEED_CVAR)
    return ok and tonumber(v) or nil
end

local function finish()
    if move then
        -- nur zurueckstellen, wenn niemand (z. B. CVars.Apply mit einem neuen Sollwert) das Tempo inzwischen geaendert hat
        local now = getSpeed()
        if now == nil or math.abs(now - move.set) < 1e-3 then setSpeed(move.speed) end
        move = nil
    end
    if frame then frame:SetScript("OnUpdate", nil) end
end

local function step(dt)
    if not move then return finish() end
    move.elapsed = move.elapsed + dt
    if not move.called then
        move.called = true
        local cur = current()
        if not cur then return finish() end
        local delta = move.dest - cur
        if math.abs(delta) < Zoom.TOLERANCE then return finish() end
        local fn = delta > 0 and CameraZoomOut or CameraZoomIn
        if type(fn) ~= "function" then return finish() end
        pcall(fn, math.abs(delta))
        return
    end
    local cur = current()
    if not cur or math.abs(cur - move.dest) < Zoom.TOLERANCE or move.elapsed > move.limit then finish() end
end

--- Sofort-Fahrt starten (Dauer in Sekunden, 0 = so schnell wie der Client es erlaubt)
local function goTo(dest, seconds)
    local cur = current()
    if not cur then return false end
    dest = math.max(Zoom.MIN, math.min(Zoom.MAX, dest))
    if math.abs(dest - cur) < Zoom.TOLERANCE then
        finish()
        return true
    end
    local original = move and move.speed or getSpeed()
    local speed = math.max(1, math.min(50, math.abs(dest - cur) / math.max(seconds or 0.6, 0.1)))
    setSpeed(speed)
    move = { dest = dest, called = false, elapsed = 0, limit = math.max(seconds or 0.6, 0.1) + 1.5, speed = original, set = speed }
    if not frame then frame = CreateFrame("Frame") end
    frame:SetScript("OnUpdate", function(_, dt) step(dt) end)
    return true
end

function Zoom.IsMoving() return move ~= nil end
function Zoom.Saved() return saved end
function Zoom.Target() return target end

--- Ziel-Distanz setzen (Yards) oder nil = keine Vorgabe mehr (Rueckkehr zur gemerkten Distanz)
function Zoom.Update(dest, seconds)
    returnToken = returnToken + 1
    if type(dest) == "number" then
        if saved == nil then saved = current() end
        if saved == nil then return end -- kein GetCameraZoom: nichts tun
        if target ~= dest then
            target = dest
            goTo(dest, seconds)
        end
        return
    end
    target = nil
    if saved == nil then return end
    local token = returnToken
    local function back()
        if token ~= returnToken or target ~= nil or saved == nil then return end
        local to = saved
        saved = nil
        goTo(to, seconds)
    end
    if C_Timer and C_Timer.After then C_Timer.After(Zoom.RETURN_DELAY, back) else back() end
end

--- sofort zurueck (Ausschalten, Abmelden): keine Verzoegerung, keine weiche Fahrt noetig
function Zoom.Release()
    returnToken = returnToken + 1
    target = nil
    local to = saved
    saved = nil
    if to == nil then return end -- eine laufende Rueckfahrt nicht abbrechen
    goTo(to, 0.1)
end

--- Abmelden: Distanz sofort zurueckschicken (best effort: der Client zoomt asynchron)
function Zoom.Logout()
    returnToken = returnToken + 1
    target = nil
    local to = saved or (move and move.dest) -- laufende Rueckfahrt zu Ende bringen
    saved = nil
    local original = move and move.speed or getSpeed()
    if original == nil and type(GetCVarDefault) == "function" then
        local ok, d = pcall(GetCVarDefault, Zoom.SPEED_CVAR)
        original = ok and tonumber(d) or nil
    end
    finish()
    if to == nil then return end
    local cur = current()
    if not cur or math.abs(cur - to) < Zoom.TOLERANCE then return end
    setSpeed(50)
    local fn = (to > cur) and CameraZoomOut or CameraZoomIn
    if type(fn) == "function" then pcall(fn, math.abs(to - cur)) end
    setSpeed(original)
end
