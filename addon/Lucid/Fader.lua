-- Fader: Fade-Engine (Spec 3.2) gegen eine generische Element-Registrierung.
--
-- Element = id + Frame-Liste (+ Standardwerte). Die Einstellungen kommen aus dem aktiven Profil
-- (Abschnitt "elements", Store) ueber den Standardwerten des Elements und Fader.DEFAULTS:
--   enabled       Lucid steuert das Element (false = Element bleibt unberuehrt, Alpha 1)
--   baseAlpha     Grund-Alpha 0..1
--   conditions    { { state = <State-Name>, alpha = 0..1 }, ... }
--   fadeIn/fadeOut  Dauer einer vollen Ueberblendung 0 <-> 1 in Sekunden (Teilstrecken anteilig)
--   delay         Wartezeit vor dem Ausblenden in Sekunden
--   clickThrough  bei Alpha 0 Maus abschalten (nur ausserhalb des Kampfs)
-- Wirksames Alpha = max(baseAlpha, Alpha aller erfuellten Bedingungen).
--
-- Regeln: ausschliesslich SetAlpha (nie Show/Hide); Maus nur ausserhalb InCombatLockdown aendern, im Kampf
-- wird nach Kampfende nachgezogen; setzt Blizzard das Alpha zurueck, wird der Sollwert wiederhergestellt
-- (hooksecurefunc auf SetAlpha, nicht geschuetzt); Bearbeitungsmodus offen => alles voll sichtbar.
--
-- Kurvenmodus "Leben nicht voll" (hurt): Forever und Retail 12.x liefern UnitHealth("player") nur als Secret Value, der
-- Zustand ist dann fuer Lua nie lesbar. Hat ein Element die Bedingung hurt mit Alpha H und liegt das gerade anzuwendende
-- Alpha A darunter, setzt der Fader statt SetAlpha(A) das Ergebnis von UnitHealthPercent("player", false, Kurve) mit
-- der Kurve (0,H) (HURT_FULL,H) (1,A): der Client rechnet das Alpha aus dem geschuetzten Wert selbst aus (Secret, nur
-- an SetAlpha weitergereicht, nie verglichen). Neu gesetzt bei UNIT_HEALTH/UNIT_MAXHEALTH und jedem Blendenschritt.
-- Grenzen: der Wechsel beim Erreichen/Verlassen voller Lebenspunkte ist sofort (nicht animiert), und solange der
-- Kurvenmodus gilt, bleibt die Maus an (Lucid weiss nicht, ob der Rahmen gerade sichtbar ist).
local _, ns = ...
local State, Store, Compat = ns.State, ns.Store, ns.Compat

local Fader = {}
ns.Fader = Fader

Fader.DEFAULTS = {
    enabled = true, baseAlpha = 1, conditions = {}, fadeIn = 0.25, fadeOut = 0.6, delay = 1.5, clickThrough = false,
}
Fader.MAX_TIME = 10          -- Obergrenze fuer fadeIn/fadeOut/delay
-- Schema-Maxima: ein maximal volles Profil muss unter die Import-Grenzen des Store passen (Test prueft das)
Fader.MAX_CONDITIONS = #State.NAMES -- jede Bedingung hoechstens einmal sinnvoll
Fader.MAX_ELEMENTS = 64             -- Katalog (Spec 3.3) hat rund 25 Elemente
Fader.MOUSE_DEPTH = 3               -- Klicks durchlassen mit Kind-Frames: so tief wird abgestiegen
Fader.MOUSE_MAX = 256               -- und hoechstens so viele Frames je Element angefasst
Fader.VERIFY_INTERVAL = 0.5         -- opts.verify: so oft wird das Ist-Alpha gegen das Soll geprueft
Fader.HURT_FULL = 0.99999           -- Kurvenmodus: ab diesem Lebensanteil gilt das Leben als voll
local EPS = 0.001

local elements = {}   -- id -> Element
local owner = {}      -- frame -> Element (fuer den SetAlpha-Hook)
local hooked = {}     -- frame -> true (Hooks lassen sich nicht entfernen)
local hookedBool = {} -- frame -> true: SetAlphaFromBoolean-Hook haengt
local verifyTicker    -- C_Timer-Ticker fuer Elemente mit opts.verify
local editMode = false
local applying = false

local function clamp(v, lo, hi, def)
    if type(v) ~= "number" or v ~= v then return def end
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

-- Konfiguration ------------------------------------------------------------------------------------
--- wirksame Einstellungen eines Elements (Profil > Element-Standard > Fader.DEFAULTS), immer gueltig.
--- fallback: Element-Standardwerte fuer ein (noch) nicht angemeldetes Element (z. B. aus dem Katalog)
--- stored: Einstellungen statt des Profil-Eintrags (Elemente mit eigener Config-Quelle, opts.config)
function Fader.GetConfig(id, fallback, stored)
    local el = elements[id]
    local defaults = (el and el.defaults) or (type(fallback) == "table" and fallback) or {}
    if stored == nil and Store.db then
        local p = Store.GetActive()
        stored = p and type(p.elements) == "table" and p.elements[id]
    end
    if type(stored) ~= "table" then stored = {} end
    local function pick(key)
        if stored[key] ~= nil then return stored[key] end
        if defaults[key] ~= nil then return defaults[key] end
        return Fader.DEFAULTS[key]
    end
    local D = Fader.DEFAULTS
    local cfg = {
        enabled = pick("enabled") ~= false,
        baseAlpha = clamp(pick("baseAlpha"), 0, 1, D.baseAlpha),
        fadeIn = clamp(pick("fadeIn"), 0, Fader.MAX_TIME, D.fadeIn),
        fadeOut = clamp(pick("fadeOut"), 0, Fader.MAX_TIME, D.fadeOut),
        delay = clamp(pick("delay"), 0, Fader.MAX_TIME, D.delay),
        clickThrough = pick("clickThrough") == true,
        conditions = {},
    }
    local conds = pick("conditions")
    if type(conds) == "table" then
        for _, c in ipairs(conds) do
            if type(c) == "table" and State.KNOWN[c.state] and type(c.alpha) == "number" then
                cfg.conditions[#cfg.conditions + 1] = { state = c.state, alpha = clamp(c.alpha, 0, 1, 1) }
            end
        end
    end
    return cfg
end

--- Soll-Alpha: max(Basis, erfuellte Bedingungen). get(state, id) ist standardmaessig State.Get.
function Fader.ComputeTarget(cfg, id, get)
    get = get or State.Get
    local a = cfg.baseAlpha
    for _, c in ipairs(cfg.conditions) do
        if c.alpha > a and get(c.state, id) then a = c.alpha end
    end
    return a
end

local function needsMouseover(cfg)
    for _, c in ipairs(cfg.conditions) do
        if c.state == "mouseover" then return true end
    end
    return false
end

-- Profil-Abschnitt "elements": Pruefung fuer den Import ------------------------------------------
local function isNum(v, lo, hi) return type(v) == "number" and v == v and v >= lo and v <= hi end

local function validateElement(e)
    if type(e) ~= "table" then return nil, "type" end
    local out = {}
    for k, v in pairs(e) do
        if k == "enabled" or k == "clickThrough" then
            if type(v) ~= "boolean" then return nil, k end
            out[k] = v
        elseif k == "baseAlpha" then
            if not isNum(v, 0, 1) then return nil, k end
            out[k] = v
        elseif k == "fadeIn" or k == "fadeOut" or k == "delay" then
            if not isNum(v, 0, Fader.MAX_TIME) then return nil, k end
            out[k] = v
        elseif k == "conditions" then
            if type(v) ~= "table" then return nil, k end
            local n = 0
            for _ in pairs(v) do n = n + 1 end
            if n > Fader.MAX_CONDITIONS or n ~= #v then return nil, k end
            local list = {}
            for i, c in ipairs(v) do
                if type(c) ~= "table" or not State.KNOWN[c.state] or not isNum(c.alpha, 0, 1) then
                    return nil, k .. "[" .. i .. "]"
                end
                list[i] = { state = c.state, alpha = c.alpha }
            end
            out[k] = list
        end
        -- unbekannte Felder fallen weg
    end
    return out
end

function Fader.ValidateElements(v)
    if type(v) ~= "table" then return nil, "type" end
    local out, n = {}, 0
    for id, e in pairs(v) do
        if type(id) ~= "string" or #id > 64 or not id:match("^[%w_%-%.]+$") then return nil, "id" end
        n = n + 1
        if n > Fader.MAX_ELEMENTS then return nil, "count" end
        local clean, detail = validateElement(e)
        if not clean then return nil, id .. "." .. detail end
        out[id] = clean
    end
    return out
end

Store.RegisterSection("elements", {
    default = function() return {} end,
    validate = Fader.ValidateElements,
})

-- Anwenden ---------------------------------------------------------------------------------------
-- SetAlpha mit gesetztem applying-Flag (damit der eigene Hook still bleibt). pcall: wirft SetAlpha, wird
-- das Flag trotzdem zurueckgesetzt (sonst waere jedes spaetere Re-Apply tot) und der Fehler gemeldet.
local function setAlphaGuarded(f, a, quiet)
    applying = true
    local ok, err = pcall(f.SetAlpha, f, a)
    applying = false
    if not ok and not quiet then geterrorhandler()(err) end
    return ok
end

-- Kurvenmodus (siehe Kopf) ------------------------------------------------------------------------
local curve               -- eine wiederverwendete Kurve: UnitHealthPercent wertet sie beim Aufruf aus, danach ist sie frei
local curveH, curveA      -- Punkte, mit denen die Kurve gerade belegt ist (gleiche Werte => nicht neu belegen)
local curveBroken = false -- Kurvenweg ist einmal gescheitert => fuer diese Sitzung aus (kein Fehler-Spam, alter Weg)

local function curveApi()
    return not curveBroken and type(UnitHealthPercent) == "function" and type(C_CurveUtil) == "table"
        and type(C_CurveUtil.CreateCurve) == "function"
end

--- true, wenn eine Bedingung nur ueber den Kurvenmodus wirken kann: "hurt" ist gerade nicht lesbar (Secret Value),
--- UnitHealthPercent mit Kurve steht aber zur Verfuegung. Lesbares hurt (alter Client) => false, alles wie bisher.
function Fader.IsCurveDriven(name)
    if name ~= "hurt" or not curveApi() then return false end
    local ok, reason = State.IsAvailable("hurt")
    return not ok and reason == "secret"
end

-- Secret-Alpha "h bei fehlendem Leben, sonst a" (oder nil, wenn der Weg nicht klappt). Nie verglichen oder gerechnet.
local function curveValue(h, a)
    if not curveApi() then return nil end
    local ok, v = pcall(function()
        if not curve then curve, curveH, curveA = C_CurveUtil.CreateCurve(), nil, nil end
        if curveH ~= h or curveA ~= a then
            curveH, curveA = nil, nil -- scheitert die Belegung, gilt die Kurve als leer
            if curve.ClearPoints then curve:ClearPoints() else curve = C_CurveUtil.CreateCurve() end
            curve:AddPoint(0, h)
            curve:AddPoint(Fader.HURT_FULL, h)
            curve:AddPoint(1, a)
            curveH, curveA = h, a
        end
        return UnitHealthPercent("player", false, curve)
    end)
    if ok and (Compat.IsSecret(v) or type(v) == "number") then return v end
    curve, curveH, curveA = nil, nil, nil
    return nil
end

-- Frame im Kurvenmodus setzen; klappt das nicht, Kurvenweg abschalten und normal SetAlpha(a). true = Kurve gesetzt.
local function setCurveAlpha(f, h, a)
    local v = curveValue(h, a)
    if v ~= nil and setAlphaGuarded(f, v, true) then return true end
    curveBroken = true
    setAlphaGuarded(f, a)
    return false
end

-- Verschachtelte Elemente (opts.parent): Alpha vererbt sich im Client multiplikativ. Ist das Eltern-Element
-- aktiv, bekommt das Kind Soll / Eltern-Alpha (auf 0..1 begrenzt), damit es sichtbar so wirkt wie eingestellt.
-- Grenze: ein Kind wird nie sichtbarer als sein Eltern-Frame; bei Eltern-Alpha 0 bleibt es unsichtbar.
-- el.cur ist immer das logische Soll, el.out der tatsaechlich gesetzte Wert.
local function outValue(el, v)
    local p = el.active and el.parentId and elements[el.parentId] -- inaktiv: Ausgangswert unveraendert
    if not (p and p.active) then return v end
    if p.cur <= EPS then return v > EPS and 1 or 0 end
    return clamp(v / p.cur, 0, 1, 1)
end
local function outAlpha(el) return outValue(el, el.cur) end

-- Werte setzen und Kind-Elemente nachziehen (nur abwaerts, Tiefe begrenzt => keine Schleife)
-- Wert fuer einen Frame: inaktiv => sein eigener Ausgangswert (Frames eines Elements koennen abweichen);
-- opts.relativeAlpha => logisches Alpha mal Ausgangswert (1 = "so wie vorher", 0 = unsichtbar)
local function frameAlpha(el, f, a)
    local o = el.origs[f] or 1
    if not el.active then return o end
    if el.relativeAlpha then return a * o end
    return a
end

-- logisches Alpha H der Bedingung hurt, wenn sie gerade nur ueber den Kurvenmodus wirken kann (sonst nil).
-- Simulation (Override) => State.Get("hurt") ist true und ComputeTarget rechnet H schon ein: kein Kurvenmodus.
local function hurtCurveAlpha(el)
    if not el.active or editMode or State.GetOverride("hurt") or not Fader.IsCurveDriven("hurt") then return nil end
    for _, c in ipairs(el.cfg.conditions) do
        if c.state == "hurt" then return c.alpha end
    end
    return nil
end

local updateMouse

-- el.curveAt[f] = H des Frames, solange er im Kurvenmodus steht; el.out bleibt das lesbare A.
-- Jeder Aufruf (Blendenschritt, Re-Apply, UNIT_HEALTH) wertet die Kurve neu aus.
local function push(el, depth)
    local a = outAlpha(el)
    el.out = a
    local h = hurtCurveAlpha(el)
    local hOut = h and h > el.cur + EPS and outValue(el, h) or nil
    local wasCurve = el.curveOn
    el.curveOn = false
    for _, f in ipairs(el.frames) do
        local fa = frameAlpha(el, f, a)
        local fh = hOut and frameAlpha(el, f, hOut)
        if fh and fh > fa + EPS and setCurveAlpha(f, fh, fa) then
            el.curveAt[f] = fh
            el.curveOn = true
        else
            el.curveAt[f] = nil
            setAlphaGuarded(f, fa)
        end
    end
    -- onAlpha bekommt im Kurvenmodus das hoechste moegliche Alpha (z. B. Minimap: nicht ganz verstecken)
    if el.onAlpha then xpcall(el.onAlpha, geterrorhandler(), el.curveOn and hOut or a) end
    if wasCurve ~= el.curveOn and updateMouse then updateMouse(el) end
    if depth >= 8 then return end
    for _, child in pairs(elements) do
        if child.parentId == el.id and child ~= el then push(child, depth + 1) end
    end
end

local function applyAlpha(el, a)
    el.cur = a
    push(el, 0)
end

local function lockdown() return InCombatLockdown and InCombatLockdown() end

-- Frames, deren Maus "Klicks durchlassen" abschaltet: die Element-Frames, mit opts.mouseChildren auch deren
-- Kind-Frames (Aktionsleisten: die Knoepfe tragen die Maus, nicht der Container). Nur lesend (GetChildren),
-- nur ausserhalb des Lockdowns aufgerufen; verbotene Frames (IsForbidden) bleiben unberuehrt, ebenso Frames, die
-- opts.mouseExclude(frame) ausschliesst (z. B. weil sie einem anderen Element gehoeren), samt Kindern.
-- Retail 12.x: jede Zustandsabfrage kann ein Secret Value liefern => nur ueber Compat.QueryBool (kein Wahrheitstest
-- auf dem Rohwert); ist IsForbidden nicht eindeutig false, bleibt der Frame samt Unterbaum unberuehrt.
local function mouseTargets(el)
    if not el.mouseChildren then return el.frames end
    local out, seen = {}, {}
    local function add(f, depth)
        if type(f) ~= "table" or seen[f] or #out >= Fader.MOUSE_MAX then return end
        seen[f] = true
        if f.IsForbidden and Compat.QueryBool(f, "IsForbidden") ~= false then return end
        if depth > 0 and el.mouseExclude and el.mouseExclude(f) then return end
        out[#out + 1] = f
        if depth < Fader.MOUSE_DEPTH and f.GetChildren then
            local ok, kids = pcall(function() return { f:GetChildren() } end)
            if ok then
                for i = 1, #kids do add(kids[i], depth + 1) end
            end
        end
    end
    for _, f in ipairs(el.frames) do add(f, 0) end
    return out
end
--- Frames, die "Klicks durchlassen" fuer dieses Element anfassen wuerde (Diagnose/Tests)
function Fader.MouseTargets(id) return elements[id] and mouseTargets(elements[id]) end

-- Maus: abschalten nur bei clickThrough, Alpha 0, keine laufende Blende, kein Bearbeitungsmodus, kein Kampf
-- (Zustand "combat": haengt so nicht davon ab, ob State oder Fader PLAYER_REGEN_DISABLED zuerst sieht).
-- Waehrend des Lockdowns wird nichts geaendert (pending), PLAYER_REGEN_ENABLED zieht nach.
-- Maus-Zustand eines Frames merken und genau so wiederherstellen (Klicks und Bewegung getrennt, wo der
-- Client das kennt; sonst EnableMouse mit dem gemerkten Wert). nil = Zustand nicht lesbar (Secret Value,
-- Fehler) => Frame wird nicht angefasst, sein Ausgangszustand bleibt.
local function mouseState(f)
    if f.IsMouseClickEnabled and f.IsMouseMotionEnabled then
        local clicks, motion = Compat.QueryBool(f, "IsMouseClickEnabled"), Compat.QueryBool(f, "IsMouseMotionEnabled")
        if clicks == nil or motion == nil then return nil end
        return { clicks = clicks, motion = motion }
    end
    local on = Compat.QueryBool(f, "IsMouseEnabled")
    if on == nil then return nil end
    return { enabled = on }
end

local function restoreMouse(f, st)
    if st.clicks ~= nil and f.EnableMouseClicks and f.EnableMouseMotion then
        f:EnableMouseClicks(st.clicks)
        f:EnableMouseMotion(st.motion)
    else
        f:EnableMouse(st.enabled ~= false)
    end
end

--- Maus-Zustand merken / wiederherstellen (auch fuer Mitlaeufer-Frames ausserhalb der Elemente, z. B. InkDock)
Fader.MouseState, Fader.RestoreMouse = mouseState, restoreMouse

-- el.mouseIsOff: "Klicks durchlassen" ist angewendet (auch wenn kein Frame abschaltbar war => kein erneuter Scan)
-- Kurvenmodus: der Rahmen ist evtl. sichtbar (Leben fehlt) => Maus bleibt an.
function updateMouse(el, forceOn)
    local want = not forceOn and el.active and el.cfg.clickThrough and el.cur <= EPS and not el.curveOn
        and not el.anim and not el.outAt and not editMode and not State.Get("combat")
    want = want and true or false
    if want == el.mouseIsOff then
        el.mousePending = false
        return
    end
    if lockdown() then
        el.mousePending = true
        return
    end
    el.mousePending = false
    -- Jeder Frame einzeln per pcall: wirft EnableMouse (z. B. geschuetzt/verboten), wird der Frame nicht gemerkt
    -- (Ausgangszustand bleibt), die uebrigen Frames werden weiter bearbeitet; Fehler einmal je Lauf gemeldet.
    -- mouseIsOff erst nach der Schleife setzen: mouseOff enthaelt genau die tatsaechlich abgeschalteten Frames.
    local firstErr
    if want then
        for _, f in ipairs(mouseTargets(el)) do
            if f.EnableMouse and Compat.QueryBool(f, "IsMouseEnabled") == true then
                local st = mouseState(f)
                if st then
                    local ok, err = pcall(f.EnableMouse, f, false)
                    if ok then el.mouseOff[f] = st else firstErr = firstErr or err end
                end
            end
        end
    else
        for f, st in pairs(el.mouseOff) do
            el.mouseOff[f] = nil
            local ok, err = pcall(restoreMouse, f, st)
            if not ok then firstErr = firstErr or err end
        end
    end
    el.mouseIsOff = want
    if firstErr then geterrorhandler()(firstErr) end
end

-- Treiber: OnUpdate nur, solange etwas laeuft (Blende oder Verzoegerung)
local driver = CreateFrame("Frame")
driver:Hide()

local function step(el, now)
    if el.outAt and now >= el.outAt then
        local startAt = el.outAt -- Blende beginnt am geplanten Zeitpunkt, nicht erst beim naechsten Frame
        el.outAt = nil
        local dist = el.cur - el.target
        if dist > EPS and el.cfg.fadeOut > 0 then
            el.anim = { from = el.cur, to = el.target, start = startAt, dur = el.cfg.fadeOut * dist }
        else
            applyAlpha(el, el.target)
            updateMouse(el)
        end
    end
    local an = el.anim
    if an then
        local p = (now - an.start) / an.dur
        if p >= 1 - 1e-6 then -- Gleitkomma: Rest unter einer Millionstel gilt als fertig
            el.anim = nil
            applyAlpha(el, an.to)
            updateMouse(el)
        else
            applyAlpha(el, an.from + (an.to - an.from) * p)
        end
    end
    return el.anim ~= nil or el.outAt ~= nil
end

local function wake()
    for _, el in pairs(elements) do
        if el.anim or el.outAt then
            driver:Show()
            return
        end
    end
    driver:Hide()
end

driver:SetScript("OnUpdate", function()
    local now = GetTime()
    local busy = false
    for _, el in pairs(elements) do
        if step(el, now) then busy = true end
    end
    if not busy then driver:Hide() end
end)

-- Neues Soll setzen. instant: ohne Blende (Anmeldung, Bearbeitungsmodus).
local function retarget(el, instant)
    local now = GetTime()
    if el.anim or el.outAt then step(el, now) end -- Ist-Wert auf jetzt bringen
    local target
    if not el.active then target = el.orig
    elseif editMode then target = 1
    else target = Fader.ComputeTarget(el.cfg, el.id) end
    el.target = target

    if instant or editMode or not el.active then
        el.anim, el.outAt = nil, nil
        applyAlpha(el, target)
    elseif target > el.cur + EPS then
        -- einblenden: sofort, ohne Verzoegerung; Maus vorher wieder an
        el.outAt = nil
        local dur = el.cfg.fadeIn * (target - el.cur)
        if dur > 0 then
            el.anim = { from = el.cur, to = target, start = now, dur = dur }
        else
            el.anim = nil
            applyAlpha(el, target)
        end
    elseif target < el.cur - EPS then
        -- ausblenden: nach Verzoegerung; laeuft schon eine Verzoegerung, bleibt deren Zeitpunkt
        if el.anim and el.anim.to < el.anim.from then
            el.anim.to = target
            el.anim.dur = el.cfg.fadeOut * (el.anim.from - target)
        else
            el.anim = nil
            if not el.outAt then el.outAt = now + el.cfg.delay end
            if el.cfg.delay <= 0 then step(el, now) end
        end
    else
        el.anim, el.outAt = nil, nil
        -- Kurvenmodus beteiligt (an, aus oder neues H, z. B. hurt wird gerade Secret): auch bei gleichem Soll neu setzen
        local h = hurtCurveAlpha(el)
        if math.abs(el.cur - target) > 0 or el.curveOn or (h and h > target + EPS) then applyAlpha(el, target) end
    end
    updateMouse(el)
    wake()
end

-- Registrierung ----------------------------------------------------------------------------------
local function onSetAlpha(f, a)
    if applying then return end
    local el = owner[f]
    if not el or not el.active or el.noReapply then return end
    -- Secret Value (Retail 12.x): nicht vergleichbar => als fremden Wert behandeln und Soll wiederherstellen
    local want = frameAlpha(el, f, el.out or el.cur)
    local fh = el.curveAt[f]
    if fh then
        -- Kurvenmodus: der eigene (Secret-)Aufruf laeuft mit applying; jeder fremde Wert => Kurve neu setzen
        if not setCurveAlpha(f, fh, want) then el.curveAt[f] = nil end
        return
    end
    if Compat.IsSecret(a) or type(a) ~= "number" or math.abs(a - want) > EPS then
        setAlphaGuarded(f, want)
    end
end

-- Ist-Alpha eines Frames gegen das Soll pruefen und ggf. wiederherstellen. Faengt Wege ab, die den SetAlpha-Hook
-- umgehen: SetAlphaFromBoolean (Retail 12.x), Alpha-Animationen mit Endwert, Aufrufe aus dem Client-Code.
-- Secret Value/unlesbar => als fremden Wert behandeln (wie onSetAlpha). Liefert true, wenn korrigiert wurde.
local function verifyFrame(el, f)
    if applying or not el.active or el.noReapply then return false end
    local want = frameAlpha(el, f, el.out or el.cur)
    local ok, a = pcall(f.GetAlpha, f)
    local fh = el.curveAt[f]
    if fh then
        -- Kurvenmodus: GetAlpha liefert nach dem eigenen SetAlpha ein Secret => nicht vergleichbar, gilt als eigener
        -- Wert. Nur eine lesbare Zahl, die weder H noch A ist, stammt sicher von fremder Hand => Kurve neu setzen.
        if not ok or Compat.IsSecret(a) then return false end
        a = Compat.Num(a)
        if a and (math.abs(a - want) <= EPS or math.abs(a - fh) <= EPS) then return false end
        if not setCurveAlpha(f, fh, want) then el.curveAt[f] = nil end
        return true
    end
    a = ok and Compat.Num(a) or nil
    if a and math.abs(a - want) <= EPS then return false end
    setAlphaGuarded(f, want)
    return true
end

--- Element jetzt pruefen (z. B. nach einem Blizzard-Update der Frames). Liefert die Zahl korrigierter Frames.
function Fader.Verify(id)
    local el = elements[id]
    if not el or not el.active then return 0 end
    local n = 0
    for _, f in ipairs(el.frames) do
        if verifyFrame(el, f) then n = n + 1 end
    end
    return n
end

local function onSetAlphaFromBoolean(f)
    local el = owner[f]
    if el then verifyFrame(el, f) end
end

-- Pruef-Ticker: laeuft nur, solange ein Element mit opts.verify angemeldet ist; laufende Blenden/Verzoegerungen
-- werden nicht angefasst (dort setzt der Fader ohnehin jeden Frame).
local function verifyTick()
    for id, el in pairs(elements) do
        if el.verify and el.active and not el.anim and not el.outAt then Fader.Verify(id) end
    end
end

local function updateVerifyTicker()
    local any = false
    for _, el in pairs(elements) do
        if el.verify then any = true break end
    end
    if verifyTicker and verifyTicker.IsCancelled and verifyTicker:IsCancelled() then verifyTicker = nil end
    if any and not verifyTicker and C_Timer and C_Timer.NewTicker then
        verifyTicker = C_Timer.NewTicker(Fader.VERIFY_INTERVAL, verifyTick)
    elseif not any and verifyTicker then
        verifyTicker:Cancel()
        verifyTicker = nil
    end
end
function Fader.IsVerifyTickerActive() return verifyTicker ~= nil end

local function configure(el)
    el.cfg = Fader.GetConfig(el.id, nil, el.config and el.config())
    local wasActive = el.active
    el.active = el.cfg.enabled
    if el.active and needsMouseover(el.cfg) then
        State.WatchMouseover(el.id, el.mouseFrames or el.frames)
    else
        State.UnwatchMouseover(el.id)
    end
    return wasActive
end

--- Element anmelden. frames: Frame oder Liste von Frames. defaults: Element-Standardwerte (siehe oben).
--- opts.noReapply: Alpha-Ruecksetzungen durch Blizzard nicht korrigieren (fuer Frames, die selbst blenden).
--- opts.mouseChildren: "Klicks durchlassen" erfasst auch Kind-Frames (Knoepfe einer Leiste).
--- opts.mouseExclude: function(frame) -> true, wenn ein Kind-Frame (samt Unterbaum) nicht angefasst werden darf.
--- opts.parent: id des Elements, in dessen Frame dieses Element steckt (Alpha-Ausgleich, siehe outAlpha).
--- opts.onAlpha: function(alpha) nach jedem gesetzten Alpha (tatsaechlich gesetzter Wert, auch beim Abmelden).
--- opts.config: function() -> Einstellungen; ersetzt den Profil-Eintrag elements[id] (eigene Config-Quelle).
--- opts.mouseFrames: Frames fuer die Mouseover-Bedingung statt der Element-Frames (Liste, Verweis wird gehalten).
--- opts.relativeAlpha: Alpha (Basis/Bedingungen) gilt relativ zum Ausgangswert je Frame (1 = Ausgangswert).
--- opts.verify: Ist-Alpha regelmaessig gegen das Soll pruefen (Frames, deren Alpha Blizzard ohne SetAlpha aendert).
function Fader.Register(id, frames, defaults, opts)
    assert(type(id) == "string" and id ~= "", "Lucid: Element-id fehlt")
    assert(type(frames) == "table", "Lucid: Element ohne Frames: " .. id)
    if frames.GetAlpha then frames = { frames } end
    if elements[id] then Fader.Unregister(id) end
    local el = {
        id = id, frames = {}, defaults = type(defaults) == "table" and defaults or {},
        noReapply = opts and opts.noReapply or false, mouseChildren = opts and opts.mouseChildren or false,
        mouseExclude = opts and type(opts.mouseExclude) == "function" and opts.mouseExclude or nil,
        parentId = opts and type(opts.parent) == "string" and opts.parent ~= id and opts.parent or nil,
        onAlpha = opts and type(opts.onAlpha) == "function" and opts.onAlpha or nil,
        config = opts and type(opts.config) == "function" and opts.config or nil,
        mouseFrames = opts and type(opts.mouseFrames) == "table" and opts.mouseFrames or nil,
        relativeAlpha = opts and opts.relativeAlpha == true or false,
        verify = opts and opts.verify == true or false,
        mouseOff = {}, mouseIsOff = false, cur = 1, orig = 1, origs = {},
        curveAt = {}, curveOn = false, -- Kurvenmodus: frame -> H; mindestens ein Frame im Kurvenmodus
    }
    for _, f in ipairs(frames) do
        if type(f) == "table" and f.SetAlpha and f.GetAlpha then
            el.frames[#el.frames + 1] = f
            local a = f:GetAlpha()
            el.origs[f] = Compat.IsSecret(a) and 1 or clamp(a, 0, 1, 1)
            owner[f] = el
            if not hooked[f] and hooksecurefunc then
                hooksecurefunc(f, "SetAlpha", onSetAlpha)
                hooked[f] = true
            end
            -- SetAlphaFromBoolean (Retail 12.x) laeuft am SetAlpha-Hook vorbei
            if not hookedBool[f] and hooksecurefunc and type(f.SetAlphaFromBoolean) == "function" then
                if pcall(hooksecurefunc, f, "SetAlphaFromBoolean", onSetAlphaFromBoolean) then hookedBool[f] = true end
            end
        end
    end
    assert(#el.frames > 0, "Lucid: Element ohne gueltige Frames: " .. id)
    local a0 = el.frames[1]:GetAlpha()
    el.orig = Compat.IsSecret(a0) and 1 or clamp(a0, 0, 1, 1) -- Secret: nicht vergleichbar, Ausgangswert 1
    el.cur = el.orig
    elements[id] = el
    configure(el)
    retarget(el, true)
    updateVerifyTicker()
    return el
end

--- Element abmelden: Alpha und Maus zurueck auf den Stand vor der Anmeldung (Maus ggf. nach Kampfende).
function Fader.Unregister(id)
    local el = elements[id]
    if not el then return end
    State.UnwatchMouseover(id)
    el.active = false
    el.anim, el.outAt = nil, nil
    applyAlpha(el, el.orig)
    updateMouse(el, true)
    if el.mousePending then Fader.orphans[#Fader.orphans + 1] = el end
    for _, f in ipairs(el.frames) do
        if owner[f] == el then owner[f] = nil end
    end
    elements[id] = nil
    wake()
    updateVerifyTicker()
end
Fader.orphans = {} -- abgemeldete Elemente, deren Maus erst nach Kampfende zurueck darf

--- Einstellungen eines Elements neu lesen (z. B. nach Aenderung im Profil) und weich anwenden
function Fader.Refresh(id)
    local el = elements[id]
    if not el then return end
    local wasActive = configure(el)
    if not el.active and wasActive then
        el.anim, el.outAt = nil, nil
        applyAlpha(el, el.orig)
        updateMouse(el, true)
        return
    end
    retarget(el, el.active and not wasActive)
end

function Fader.RefreshAll()
    for id in pairs(elements) do Fader.Refresh(id) end
end

--- Sollwert hart neu setzen (z. B. wenn Blizzard Frames beim Laden zurueckgesetzt hat)
function Fader.ReapplyAll()
    for _, el in pairs(elements) do
        if el.active then applyAlpha(el, el.cur) end
    end
end

function Fader.Get(id) return elements[id] end
--- id des Elements, dem der Frame gehoert, oder nil
function Fader.OwnerOf(f) return owner[f] and owner[f].id end
function Fader.GetAlpha(id) return elements[id] and elements[id].cur end
function Fader.IsEditMode() return editMode end
--- true, solange mindestens ein Frame des Elements im Kurvenmodus (hurt ueber geschuetzten Wert) steht
function Fader.IsCurveActive(id) return elements[id] ~= nil and elements[id].curveOn == true end
--- true, solange eine Blende oder Verzoegerung laeuft (nur dann laeuft OnUpdate)
function Fader.IsBusy() return driver:IsShown() == true end

-- Ereignisse ---------------------------------------------------------------------------------------
State.RegisterCallback(function(name, _, id)
    if name == "mouseover" then
        local el = elements[id]
        if el and el.active then retarget(el) end
        return
    end
    for _, el in pairs(elements) do
        if el.active then retarget(el) end
    end
end)

Store.RegisterCallback(function() Fader.RefreshAll() end)

-- Kampfbeginn: PLAYER_REGEN_DISABLED kommt vor dem Lockdown => letzte Gelegenheit, abgeschaltete Maus
-- wieder einzuschalten (im Kampf bleiben Leisten bedienbar).
-- Reihenfolge: State.lua steht in der TOC vor Fader.lua, also laeuft der State-Handler (combat = true,
-- Callback => retarget => updateMouse) zuerst. Weil updateMouse "combat" selbst beachtet, waere auch die
-- umgekehrte Reihenfolge korrekt; dieser Handler ist die Absicherung fuer Elemente ohne Zustandswechsel.
ns.On("PLAYER_REGEN_DISABLED", function()
    if lockdown() then return end
    for _, el in pairs(elements) do updateMouse(el, true) end
end)

-- Kampfende: aufgeschobene Maus-Aenderungen nachziehen
ns.On("PLAYER_REGEN_ENABLED", function()
    for _, el in pairs(elements) do updateMouse(el) end
    local orphans = Fader.orphans
    Fader.orphans = {}
    for _, el in ipairs(orphans) do
        updateMouse(el, true)
        if el.mousePending then Fader.orphans[#Fader.orphans + 1] = el end
    end
end)

ns.On("PLAYER_ENTERING_WORLD", function() Fader.ReapplyAll() end)

-- Kurvenmodus: Lebensaenderung => Kurve neu auswerten (der Zustand "hurt" selbst meldet sich nie, er bleibt Secret).
-- Der Sprung beim Erreichen/Verlassen voller Lebenspunkte ist sofort, nicht animiert (bewusst: der Wert ist nicht lesbar).
local function onHealth(_, unit)
    if Compat.IsSecret(unit) or unit ~= "player" then return end
    for _, el in pairs(elements) do
        if el.curveOn then push(el, 0) end
    end
end
Compat.TryOn("UNIT_HEALTH", onHealth)
Compat.TryOn("UNIT_MAXHEALTH", onHealth)

local function setEditMode(on)
    if editMode == on then return end
    editMode = on
    for _, el in pairs(elements) do
        if el.active then retarget(el, on) end
    end
    if not on then Fader.ReapplyAll() end
end
Fader.SetEditMode = setEditMode

Compat.OnEditMode(function() setEditMode(true) end, function() setEditMode(false) end)
ns.On("ADDON_LOADED", function(_, name)
    if name == ns.name and Compat.IsEditModeActive() then setEditMode(true) end
end)
