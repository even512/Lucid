-- Kamera (B8/K3): Zoom-Fahrer. Weicher Uebergang zu einer Ziel-Distanz ueber CameraZoomIn/Out und cameraZoomSpeed
-- (Prinzip von LibCamera.SetZoomUsingCVar, ohne Fremdbibliothek, ohne Eingriff in Blizzards Mausrad-Zoom):
--   1. cameraZoomSpeed sichern und auf |Delta|/Dauer setzen (1 bis 50),
--   2. im naechsten Frame EINMAL CameraZoomOut(Delta) bzw. CameraZoomIn(-Delta) ausloesen,
--   3. per OnUpdate GetCameraZoom() beobachten, bis das Ziel erreicht ist oder die Zeit um ist; dann cameraZoomSpeed zurueck.
-- Waehrend einer Fahrt geht KEIN weiterer Befehl ans Spiel (ob das Spiel Strecken aufs Fahrtziel addiert oder von der Kamera
-- aus rechnet, ist damit egal): Eine neue Vorgabe wird nur als naechstes Ziel gemerkt (pending, ein spaeteres ersetzt ein
-- frueheres). Erreicht die Kamera das Fahrtziel oder laeuft das Zeitlimit ab, faehrt Lucid von der echten Position zu pending.
-- Eine noch nicht abgesetzte Fahrt darf ihr Ziel direkt ersetzen.
-- Nach dem Zeitlimit startet die Folgefahrt erst, wenn die Position SETTLE Sekunden stillsteht (Kamera noch unterwegs, z. B.
-- Mausrad-Zoom oder gedrosseltes Tempo), spaetestens SETTLE_MAX Sekunden danach.
-- Die Distanz vor dem ersten Lucid-Zoom wird gemerkt; endet jede Ziel-Distanz, faehrt Lucid nach RETURN_DELAY dorthin
-- zurueck (Verzoegerung gegen Zucken beim Wechsel zwischen NPC-Fenstern). Beim Abmelden/Ausschalten geht es zurueck.
-- Ein Zoom des Nutzers waehrend der Fahrt wird nicht bekaempft: die Fahrt endet spaetestens nach dem Zeitlimit.
-- Diagnose: Ringpuffer der letzten TRACE_SIZE Ereignisse (Zoom.Trace), im Chat nur ueber /lucid camera debug.
local _, ns = ...
local Camera, Compat = ns.Camera, ns.Compat

local Zoom = {}
Camera.Zoom = Zoom

Zoom.RETURN_DELAY = 0.8
Zoom.MIN, Zoom.MAX = 1, Compat.isRetail and 39 or 50
Zoom.TOLERANCE = 0.05
Zoom.SPEED_CVAR = "cameraZoomSpeed"
Zoom.TRACE_SIZE = 20
Zoom.SETTLE = 0.2      -- nach dem Zeitlimit: so lange muss die Position stillstehen, bevor die Folgefahrt startet
Zoom.SETTLE_MAX = 3    -- harte Obergrenze (Sekunden nach dem Zeitlimit), damit eine ewig wandernde Position nichts haengen laesst

local saved = nil      -- Distanz vor dem ersten Lucid-Zoom (nil = Lucid hat nichts verschoben)
local target = nil     -- aktuelles Ziel (nil = keines)
local move = nil       -- laufende Fahrt { dest, called, elapsed, limit, speed (urspruenglicher Wert), set (gesetztes Tempo) }
local pending = nil    -- naechstes Ziel, solange eine abgesetzte Fahrt laeuft { dest, seconds, back (Rueckfahrt) }
local returnToken = 0  -- macht ausstehende Rueckkehr-Timer ungueltig
local frame
local trace, traceN = {}, 0

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

local function clamp(d) return math.max(Zoom.MIN, math.min(Zoom.MAX, d)) end

--- Ereignis in den Ringpuffer schreiben (Zeit, Ereignis, aktuelle Position, Ziel, Tempo)
local function log(event, dest)
    traceN = traceN + 1
    trace[(traceN - 1) % Zoom.TRACE_SIZE + 1] = {
        t = type(GetTime) == "function" and GetTime() or 0, ev = event, pos = current(), dest = dest, speed = getSpeed(),
    }
end

--- Die letzten Ereignisse, aelteste zuerst: Liste von { t, ev, pos, dest, speed }
function Zoom.Trace()
    local out = {}
    local n = math.min(traceN, Zoom.TRACE_SIZE)
    for i = traceN - n + 1, traceN do out[#out + 1] = trace[(i - 1) % Zoom.TRACE_SIZE + 1] end
    return out
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

local step

--- Fahrt von der echten Position zu dest beginnen (der Befehl folgt im naechsten Frame)
local function startMove(dest, seconds)
    local cur = current()
    if not cur then
        finish()
        return false
    end
    dest = clamp(dest)
    local dist = math.abs(dest - cur)
    if dist < Zoom.TOLERANCE then
        finish()
        return true
    end
    local original = move and move.speed or getSpeed() -- eine noch nicht abgesetzte Fahrt hat das Tempo schon veraendert
    local speed = math.max(1, math.min(50, dist / math.max(seconds or 0.6, 0.1)))
    setSpeed(speed)
    -- Zeitlimit nach der tatsaechlichen Dauer (auch wenn das Tempo auf 1 oder 50 geklemmt ist)
    move = { dest = dest, called = false, elapsed = 0, limit = dist / speed + 1.5, speed = original, set = speed }
    if not frame then frame = CreateFrame("Frame") end
    frame:SetScript("OnUpdate", function(_, dt) step(dt) end)
    log("start", dest)
    return true
end

--- Fahrt beendet (Ziel erreicht oder Zeitlimit): Tempo zurueck, dann ggf. die gemerkte naechste Fahrt von der echten Position
local function endMove(reason)
    local p = pending
    pending = nil
    log(reason)
    finish()
    if p then startMove(p.dest, p.seconds) end
end

step = function(dt)
    if not move then return finish() end
    move.elapsed = move.elapsed + dt
    if not move.called then
        move.called = true
        local cur = current()
        if not cur then return endMove("nopos") end
        local delta = move.dest - cur
        if math.abs(delta) < Zoom.TOLERANCE then return endMove("reached") end
        local fn = delta > 0 and CameraZoomOut or CameraZoomIn
        if type(fn) ~= "function" then return endMove("nofn") end
        pcall(fn, math.abs(delta))
        move.anchor, move.still = cur, 0
        log(delta > 0 and "out" or "in", move.dest)
        return
    end
    local cur = current()
    if not cur then return endMove("nopos") end
    if math.abs(cur - move.dest) < Zoom.TOLERANCE then return endMove("reached") end
    -- Stillstand messen: gegen einen Ankerwert, damit auch eine langsame Bewegung (kleiner Schritt je Frame) zaehlt
    if math.abs(cur - move.anchor) >= Zoom.TOLERANCE then
        move.anchor, move.still = cur, 0
    else
        move.still = move.still + dt
    end
    if move.elapsed > move.limit and (move.still >= Zoom.SETTLE or move.elapsed > move.limit + Zoom.SETTLE_MAX) then
        return endMove("timeout")
    end
end

--- Fahrt zu dest anfordern (Dauer in Sekunden, 0 = so schnell wie der Client es erlaubt)
local function goTo(dest, seconds, back)
    if not current() then return false end
    if move and move.called then
        -- Befehl ist unterwegs: kein zweiter Befehl, nur als naechstes Ziel merken
        pending = { dest = dest, seconds = seconds, back = back }
        log("queue", dest)
        return true
    end
    return startMove(dest, seconds) -- ersetzt eine noch nicht abgesetzte Fahrt direkt
end

--- Nach einem fremden Schreiben von cameraZoomSpeed (CVars.Apply, Zuruecksetzen) waehrend einer Fahrt: Fahrt-Tempo erneut setzen,
--- der geschriebene Wert wird zum urspruenglichen Tempo, das finish() zurueckstellt
function Zoom.Resync()
    if not move then return end
    local now = getSpeed()
    if now ~= nil and math.abs(now - move.set) >= 1e-3 then
        move.speed = now
        setSpeed(move.set)
        log("resync", move.dest)
    end
end

function Zoom.IsMoving() return move ~= nil end
function Zoom.Saved() return saved end
function Zoom.Target() return target end

--- Ziel-Distanz setzen (Yards) oder nil = keine Vorgabe mehr (Rueckkehr zur gemerkten Distanz)
function Zoom.Update(dest, seconds)
    returnToken = returnToken + 1
    if type(dest) == "number" then
        if saved == nil then
            -- laeuft gerade eine Rueckfahrt, zaehlt ihr Ziel, nicht der Zwischenwert
            local ahead = (pending and pending.dest) or (move and move.dest)
            saved = ahead and clamp(ahead) or current()
        end
        if saved == nil then return end -- kein GetCameraZoom: nichts tun
        if target ~= dest then
            target = dest
            log("update", dest)
            goTo(dest, seconds)
        end
        return
    end
    target = nil
    if pending and not pending.back then pending = nil end -- gemerktes Ziel faellt weg: keine unnoetige Fahrt, Rueckfahrt folgt nach der Verzoegerung
    if saved == nil then return end
    local token = returnToken
    local function back()
        if token ~= returnToken or target ~= nil or saved == nil then return end
        local to = saved
        saved = nil
        log("return", to)
        goTo(to, seconds, true)
    end
    if C_Timer and C_Timer.After then C_Timer.After(Zoom.RETURN_DELAY, back) else back() end
end

--- sofort zurueck (Ausschalten): keine Verzoegerung; laeuft eine Fahrt, folgt die Rueckfahrt an ihrem Ende
function Zoom.Release()
    returnToken = returnToken + 1
    target = nil
    if pending and not pending.back then pending = nil end -- ein gemerktes Ziel loest nach dem Ausschalten nichts mehr aus
    local to = saved
    saved = nil
    if to == nil then return end -- eine laufende Rueckfahrt nicht abbrechen
    log("release", to)
    goTo(to, 0.1, true)
end

--- Abmelden: Distanz sofort zurueckschicken (best effort: der Client zoomt asynchron)
function Zoom.Logout()
    returnToken = returnToken + 1
    target = nil
    local to = saved or (pending and pending.dest) or (move and move.dest) -- laufende Rueckfahrt zu Ende bringen
    local called = move and move.called
    local flying = move and move.dest
    saved = nil
    pending = nil
    local original = move and move.speed or getSpeed()
    if original == nil and type(GetCVarDefault) == "function" then
        local ok, d = pcall(GetCVarDefault, Zoom.SPEED_CVAR)
        original = ok and tonumber(d) or nil
    end
    log("logout", to)
    finish()
    if to == nil then return end
    to = clamp(to)
    local cur = current()
    if not cur then return end
    local delta = to - cur
    -- Bei einer abgesetzten Fahrt nie so weit hinein befehlen, dass ein aufs Fahrtziel addierendes Spiel unter Zoom.MIN faellt
    if called and flying and delta < 0 then delta = math.max(delta, Zoom.MIN - flying) end
    if math.abs(delta) < Zoom.TOLERANCE then return end
    setSpeed(50)
    local fn = (delta > 0) and CameraZoomOut or CameraZoomIn
    if type(fn) == "function" then pcall(fn, math.abs(delta)) end
    setSpeed(original)
end
