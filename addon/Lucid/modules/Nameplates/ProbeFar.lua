-- Plaketten-Stil, Nachtrag 2 (Quest-Fernsicht): Klaerungs-Probe /lucid nameplates probe far|click.
--
-- probe far   (1) liest Hit-Test-API und Plaketten (CanChangeHitTestPoints, Zahl der Hit-Test-Punkte, Alpha von Plakette und
--             UnitFrame, Ziel ja/nein) und die Entfernungs-Alpha-CVars; (2) ausserhalb des Kampfs: nameplateMaxDistance kurz auf
--             60/100/200 (je RANGE_WAIT s, Plaketten zaehlen), danach Originalwert zurueck; (3) Entfernungs-Alpha kurz extrem
--             (nameplateMinAlpha 0 ab 2 m), Alpha von Ziel und Nicht-Ziel lesen, nach ALPHA_HOLD s zurueck; (4) beim naechsten
--             Kampfbeginn CanChangeHitTestPoints im Ereignis selbst und kurz danach (Kopierfenster nach dem Kampf).
-- probe click gefuehrter Klicktest: CLICK_SECONDS lang stehen alle Gegner-Plaketten ausser dem Ziel auf UnitFrame-Alpha 0 (wie
--             B7 keepTarget); jeder Zielwechsel wird mit Zeit protokolliert und ob die Plakette des neuen Ziels unsichtbar war.
--             Danach bekommt jede Plakette ihr Alpha zurueck (B7-Stand aus Plates.lua, sonst der vorherige Wert).
--
-- Schreibt nur Testwerte, die sofort bzw. nach der Wartezeit zurueckgestellt werden (CVar-Treiber Guard: ein Absturz mitten im
-- Test wird beim naechsten Login zurueckgestellt). Keine Felder auf Blizzard-Frames, keine Hit-Test-Punkte veraendert, nichts
-- gehookt. Secret Values werden nie verglichen, nur als "secret" gemeldet.
local _, ns = ...
local Compat, Nameplates = ns.Compat, ns.Nameplates
local L = ns.L

local Far = {}
ns.NameplateProbeFar = Far

Far.RANGE_VALUES = { 60, 100, 200 }
Far.RANGE_WAIT = 2
Far.ALPHA_HOLD = 3
Far.CLICK_SECONDS = 15
Far.CLICK_TICK = 0.1
Far.MAX_PLATES = 10
Far.ALPHA_CVARS = { "nameplateMinAlpha", "nameplateMaxAlpha", "nameplateMinAlphaDistance", "nameplateMaxAlphaDistance",
    "nameplateSelectedAlpha", "nameplateNotSelectedAlpha", "nameplateOccludedAlphaMult", "nameplateTargetBehindMaxDistance",
    "nameplateMaxDistance" }
Far.ALPHA_TEST = { nameplateMinAlpha = "0", nameplateMaxAlphaDistance = "1", nameplateMinAlphaDistance = "2" }
Far.ALPHA_TEST_ORDER = { "nameplateMinAlpha", "nameplateMaxAlphaDistance", "nameplateMinAlphaDistance" }

local busy = false        -- Reichweiten-/Alpha-Test laeuft
local click = nil         -- laufender Klicktest
local combatArmed = false -- Kampfteil wartet auf den naechsten Kampfbeginn
local combatLines = nil

local function esc(s) return (tostring(s):gsub("|", "||")) end
local function yn(b) return b and L.NP_YES or L.NP_NO end
local function now() return type(GetTime) == "function" and GetTime() or 0 end

local function field(t, key)
    if type(t) ~= "table" then return nil end
    local ok, v = pcall(function() return t[key] end)
    if ok then return v end
    return nil
end

--- Wert fuer die Ausgabe: "secret", Zahl (2 Stellen), Text, "-"
local function show(v)
    if Compat.IsSecret(v) then return L.NP_STYLE_SECRET end
    if v == nil then return "-" end
    if type(v) == "boolean" then return yn(v) end
    if type(v) == "number" then return (("%.2f"):format(v):gsub("0+$", ""):gsub("%.$", "")) end
    return esc(v)
end

local function method(obj, name, ...)
    local fn = field(obj, name)
    if type(fn) ~= "function" then return false, nil, "missing" end
    local ok, v = pcall(fn, obj, ...)
    if not ok then return false, nil, v end
    return true, v
end

local function unitOf(plate)
    local u = field(plate, "namePlateUnitToken")
    if type(u) ~= "string" then u = field(plate, "unitToken") end
    if type(u) ~= "string" then u = field(field(plate, "UnitFrame"), "unit") end
    if Compat.IsSecret(u) or type(u) ~= "string" then return nil end
    return u
end

local function isTarget(unit)
    if not UnitIsUnit then return false end
    local ok, v = pcall(UnitIsUnit, unit, "target")
    return ok and Compat.Bool(v)
end

--- sichtbare, nicht forbidden Plaketten: { plate, uf, unit, group, target }; dazu Gesamtzahl und forbidden
local function plates()
    local out, total, forbidden = {}, 0, 0
    if not (C_NamePlate and type(C_NamePlate.GetNamePlates) == "function") then return out, 0, 0 end
    local ok, list = pcall(C_NamePlate.GetNamePlates)
    if not ok or type(list) ~= "table" then return out, 0, 0 end
    for _, plate in ipairs(list) do
        total = total + 1
        if Compat.QueryBool(plate, "IsForbidden") == true then
            forbidden = forbidden + 1
        else
            local uf = field(plate, "UnitFrame")
            local unit = unitOf(plate)
            if type(uf) == "table" and unit and Compat.QueryBool(uf, "IsForbidden") ~= true then
                out[#out + 1] = { plate = plate, uf = uf, unit = unit, group = ns.Plates.GroupOf(unit), target = isTarget(unit) }
            end
        end
    end
    return out, total, forbidden
end

local function enemyCount()
    local n = 0
    for _, p in ipairs((plates())) do if p.group == "enemies" then n = n + 1 end end
    return n
end

--- eine Zeile je Plakette (hoechstens MAX_PLATES): Ziel, Gruppe, Alpha Plakette/UnitFrame, Hit-Test
local function plateLines(out, label)
    local list, total, forbidden = plates()
    out[#out + 1] = L.NP_FAR_PLATES:format(label, total, forbidden, yn(InCombatLockdown()))
    for i, p in ipairs(list) do
        if i > Far.MAX_PLATES then break end
        local okC, can, errC = method(p.plate, "CanChangeHitTestPoints")
        local okH, pts, errH = method(p.plate, "GetHitTestPoints")
        local _, pa = method(p.plate, "GetAlpha")
        local _, ua = method(p.uf, "GetAlpha")
        local _, ea = method(p.plate, "GetEffectiveAlpha")
        out[#out + 1] = L.NP_FAR_PLATE_LINE:format(esc(p.unit), yn(p.target), esc(p.group or "?"), show(pa), show(ea), show(ua),
            okC and show(can) or (errC == "missing" and L.NP_STYLE_ABSENT or L.NP_STYLE_FAILED),
            okH and type(pts) == "table" and tostring(#pts) or (okH and (type(pts) .. " " .. show(pts))
                or (errH == "missing" and L.NP_FAR_NO_METHOD or (L.NP_STYLE_FAILED .. ": " .. esc(string.sub(tostring(errH), 1, 80))))))
    end
end

local function apiLines(out)
    local list = plates()
    local plate = list[1] and list[1].plate
    local items = {}
    for _, m in ipairs({ "CanChangeHitTestPoints", "ClearAllHitTestPoints", "GetHitTestPoints", "SetHitTestPoints" }) do
        items[#items + 1] = "plate:" .. m .. "=" .. (plate and type(field(plate, m)) or "-")
    end
    Far.probeFrame = Far.probeFrame or CreateFrame("Frame")
    local probe = Far.probeFrame
    items[#items + 1] = "Frame:SetIgnoreParentAlpha=" .. type(field(probe, "SetIgnoreParentAlpha"))
    items[#items + 1] = "C_NamePlate.SetNamePlateEnemyClickThrough=" .. type(field(C_NamePlate, "SetNamePlateEnemyClickThrough"))
    items[#items + 1] = "C_NamePlateManager.SetNamePlateHitTestInsets=" .. type(field(_G.C_NamePlateManager, "SetNamePlateHitTestInsets"))
    for i = 1, #items, 2 do out[#out + 1] = "  " .. table.concat(items, "; ", i, math.min(i + 1, #items)) end
    -- welche Hit-Test-Methoden die Plakette wirklich hat (Metatabelle, nur Namen lesen)
    if plate then
        local names = {}
        pcall(function()
            local mt = getmetatable(plate)
            local idx = mt and mt.__index
            for _, t in ipairs({ plate, type(idx) == "table" and idx or {} }) do
                for k, v in pairs(t) do
                    if type(k) == "string" and k:find("HitTest") and type(v) == "function" then names[#names + 1] = k end
                end
            end
        end)
        table.sort(names)
        out[#out + 1] = L.NP_FAR_HITTEST_METHODS:format(#names > 0 and esc(table.concat(names, ", ")) or L.NP_NONE)
    end
end

local function cvarLines(out)
    local items = {}
    for _, name in ipairs(Far.ALPHA_CVARS) do
        local info = ns.CVars.Info(name)
        items[#items + 1] = info.exists and (name .. "=" .. esc(info.value) .. " (" .. esc(info.default or "-") .. ", secure "
            .. yn(info.secure) .. ")") or (name .. ": " .. L.NP_STYLE_ABSENT)
    end
    for i = 1, #items, 2 do out[#out + 1] = "  " .. table.concat(items, "; ", i, math.min(i + 1, #items)) end
end

--- Zeilen ins Kopierfenster (mit Kopfzeile) bzw. in den Chat, wenn es das Fenster nicht gibt
local function publish(title, lines)
    local function emit() for _, l in ipairs(lines) do ns.Print(l) end end
    if ns.CopyBox and ns.CopyBox.Capture then ns.CopyBox.Capture(title, emit) else emit() end
end

-- Kampfbeginn ---------------------------------------------------------------------------------------------------
local onRegenDisabled, onRegenEnabled
-- Gegner-Plaketten muessen fuer die Messung existieren: nameplateShowEnemies/ShowAll (nicht secure, auch im Kampf
-- schreibbar) gehen im Ereignis kurz auf 1 und nach der letzten Messung zurueck; danach wendet B7 seine Sollwerte neu an.
Far.COMBAT_TIMES = { 0.5, 1.5 }
local function restoreCombatCVars(st)
    if not st then return end
    local ok = true
    for name, v in pairs(st.originals) do
        local okW, wrote = pcall(ns.CVars.ProbeWrite, name, v)
        if not (okW and wrote) then ok = false end
    end
    if ok then for _, r in ipairs(st.releases) do pcall(r) end end
    if ns.Nameplates and ns.Nameplates.Apply then pcall(ns.Nameplates.Apply) end
    return ok
end

function onRegenDisabled()
    ns.Off("PLAYER_REGEN_DISABLED", onRegenDisabled)
    combatArmed = false
    combatLines = { L.NP_FAR_COMBAT_HEAD }
    plateLines(combatLines, L.NP_FAR_AT_REGEN)
    local CVars = ns.CVars
    local st = { originals = {}, releases = {} }
    for _, name in ipairs({ CVars.ENEMIES, CVars.SHOW_ALL }) do
        local info = CVars.Info(name)
        if info.exists then
            st.originals[name] = info.value
            local r = CVars.Guard(name)
            if r then st.releases[#st.releases + 1] = r end
            pcall(CVars.ProbeWrite, name, "1")
        end
    end
    combatLines[#combatLines + 1] = L.NP_FAR_RANGE_SHOW:format(esc(st.originals[CVars.ENEMIES] or "-"),
        esc(st.originals[CVars.SHOW_ALL] or "-"))
    for i, t in ipairs(Far.COMBAT_TIMES) do
        C_Timer.After(t, function()
            if combatLines then
                local ok, err = pcall(plateLines, combatLines, L.NP_FAR_AFTER_REGEN:format(show(t)))
                if not ok then combatLines[#combatLines + 1] = L.NP_PROBE_ERROR:format(esc(err)) end
            end
            if i == #Far.COMBAT_TIMES then
                local restored = restoreCombatCVars(st)
                if combatLines then
                    combatLines[#combatLines + 1] = restored and L.NP_FAR_COMBAT_RESTORED or L.NP_FAR_COMBAT_RESTORE_FAILED
                end
            end
        end)
    end
    ns.On("PLAYER_REGEN_ENABLED", onRegenEnabled)
end
function onRegenEnabled()
    ns.Off("PLAYER_REGEN_ENABLED", onRegenEnabled)
    local lines = combatLines or {}
    combatLines = nil
    ns.Print(L.NP_FAR_COMBAT_DONE)
    publish("/lucid nameplates probe far (" .. L.NP_FAR_COMBAT_TITLE .. ")", lines)
end

local function armCombat()
    if combatArmed then return end
    combatArmed = true
    ns.On("PLAYER_REGEN_DISABLED", onRegenDisabled)
end

-- Reichweite + Entfernungs-Alpha (zeitversetzt, nur ausserhalb des Kampfs) --------------------------------------
local function restoreAll(driver, originals, releases)
    local ok = true
    for name, v in pairs(originals) do
        local okW, wrote = pcall(driver.ProbeWrite, name, v)
        if not (okW and wrote) then ok = false end
    end
    if ok then for _, r in ipairs(releases) do pcall(r) end end
    return ok
end

local function alphaTest(lines, done)
    local Style = ns.NameplateStyle
    local driver = Style and Style.DepthCVars
    if InCombatLockdown() or not driver then
        lines[#lines + 1] = L.NP_FAR_ALPHA_SKIPPED
        return done()
    end
    local originals, releases = {}, {}
    for _, name in ipairs(Far.ALPHA_TEST_ORDER) do
        local info = driver.Info(name)
        if not info.exists then
            lines[#lines + 1] = L.NP_FAR_ALPHA_MISSING:format(name)
            return done()
        end
        originals[name] = info.value
    end
    local ok, err = pcall(function()
        for _, name in ipairs(Far.ALPHA_TEST_ORDER) do
            local r = driver.Guard(name)
            if r then releases[#releases + 1] = r end
            driver.ProbeWrite(name, Far.ALPHA_TEST[name])
        end
    end)
    if not ok then
        lines[#lines + 1] = L.NP_PROBE_ERROR:format(esc(err))
        lines[#lines + 1] = restoreAll(driver, originals, releases) and L.NP_FAR_ALPHA_RESTORED or L.NP_FAR_ALPHA_RESTORE_FAILED
        return done()
    end
    ns.Print(L.NP_FAR_ALPHA_LOOK:format(show(Far.ALPHA_HOLD)))
    C_Timer.After(1, function()
        local okP, errP = pcall(plateLines, lines, L.NP_FAR_ALPHA_LABEL)
        if not okP then lines[#lines + 1] = L.NP_PROBE_ERROR:format(esc(errP)) end
    end)
    C_Timer.After(Far.ALPHA_HOLD, function()
        lines[#lines + 1] = restoreAll(driver, originals, releases) and L.NP_FAR_ALPHA_RESTORED or L.NP_FAR_ALPHA_RESTORE_FAILED
        done()
    end)
end

-- Plaketten-Ereignisse waehrend der Wartezeit einer Reichweiten-Stufe (Plaketten entstehen asynchron)
local addCount, removeCount = 0, 0
local function onAddCount() addCount = addCount + 1 end
local function onRemoveCount() removeCount = removeCount + 1 end

local function rangeTest(lines, done)
    local CVars = ns.CVars
    local name = CVars.MAX_DISTANCE
    local info = CVars.Info(name)
    if InCombatLockdown() then
        lines[#lines + 1] = L.NP_FAR_RANGE_SKIPPED
        return done()
    end
    if not info.exists then
        lines[#lines + 1] = L.NP_PROBE_MISSING:format(name)
        return done()
    end
    -- Ausgangswerte; Gegner-Plaketten muessen fuer die Zaehlung existieren (B7 haelt sie evtl. nur fuers Ziel an)
    local originals, order, releases = {}, { name }, {}
    originals[name] = info.value
    for _, n in ipairs({ CVars.ENEMIES, CVars.SHOW_ALL }) do
        local i2 = CVars.Info(n)
        if i2.exists then
            originals[n] = i2.value
            order[#order + 1] = n
        end
    end
    lines[#lines + 1] = L.NP_FAR_RANGE_HEAD:format(esc(originals[name]), enemyCount())
    lines[#lines + 1] = L.NP_FAR_RANGE_SHOW:format(esc(originals[CVars.ENEMIES] or "-"), esc(originals[CVars.SHOW_ALL] or "-"))
    for _, n in ipairs(order) do
        local r = CVars.Guard(n)
        if r then releases[#releases + 1] = r end
    end
    ns.On("NAME_PLATE_UNIT_ADDED", onAddCount)
    ns.On("NAME_PLATE_UNIT_REMOVED", onRemoveCount)
    local i = 0
    local function finish(failed)
        ns.Off("NAME_PLATE_UNIT_ADDED", onAddCount)
        ns.Off("NAME_PLATE_UNIT_REMOVED", onRemoveCount)
        local restored = true
        for _, n in ipairs(order) do
            local okR, wrote = pcall(CVars.ProbeWrite, n, originals[n])
            if not (okR and wrote) then restored = false end
        end
        if restored then for _, r in ipairs(releases) do pcall(r) end end
        if failed then lines[#lines + 1] = L.NP_PROBE_ERROR:format(esc(failed)) end
        if restored then
            lines[#lines + 1] = L.NP_FAR_RANGE_RESTORED:format(esc(originals[name]), esc(originals[CVars.ENEMIES] or "-"),
                esc(originals[CVars.SHOW_ALL] or "-"))
        else
            lines[#lines + 1] = L.NP_PROBE_RESTORE_FAILED:format(esc(originals[name]))
        end
        done()
    end
    local okS, errS = pcall(function()
        for _, n in ipairs(order) do if n ~= name then CVars.ProbeWrite(n, "1") end end
    end)
    if not okS then return finish(errS) end
    local function step()
        i = i + 1
        local v = Far.RANGE_VALUES[i]
        if not v then return finish() end
        if InCombatLockdown() then
            lines[#lines + 1] = L.NP_FAR_RANGE_SKIPPED
            return finish()
        end
        addCount, removeCount = 0, 0
        local ok, wrote = pcall(CVars.ProbeWrite, name, v)
        if not ok then return finish(wrote) end
        C_Timer.After(Far.RANGE_WAIT, function()
            local okC, n = pcall(enemyCount)
            local total = select(2, plates())
            lines[#lines + 1] = L.NP_FAR_RANGE_LINE:format(v, esc(CVars.Get(name) or "?"), wrote and L.NP_PROBE_OK or L.NP_NO,
                show(Far.RANGE_WAIT), okC and n or "?", total, addCount, removeCount)
            step()
        end)
    end
    step()
end

--- /lucid nameplates probe far
function Far.Run()
    local lines = {}
    lines[#lines + 1] = L.NP_FAR_HEAD:format(esc(Compat.flavor), esc(Compat.interface), yn(InCombatLockdown()))
    apiLines(lines)
    cvarLines(lines)
    plateLines(lines, L.NP_FAR_NOW)
    for _, l in ipairs(lines) do ns.Print(l) end -- landet ueber den Slash-Verteiler im ersten Kopierfenster
    armCombat()
    ns.Print(L.NP_FAR_COMBAT_ARMED)
    if busy then
        ns.Print(L.NP_FAR_BUSY)
        return
    end
    if InCombatLockdown() then
        ns.Print(L.NP_FAR_RANGE_SKIPPED)
        return
    end
    busy = true
    ns.Print(L.NP_FAR_STARTED:format(show(#Far.RANGE_VALUES * Far.RANGE_WAIT + Far.ALPHA_HOLD)))
    local later = { L.NP_FAR_LATER_HEAD }
    rangeTest(later, function()
        alphaTest(later, function()
            busy = false
            ns.Print(L.NP_FAR_DONE)
            publish("/lucid nameplates probe far", later)
        end)
    end)
end

-- Gefuehrter Klicktest -------------------------------------------------------------------------------------------
local function clickLog(fmt, ...)
    if not click then return end
    click.lines[#click.lines + 1] = ("%5.1f s  "):format(now() - click.t0) .. fmt:format(...)
end

--- Alpha 0 fuer alle Gegner-Plaketten ausser dem Ziel (Alpha 1); das vorherige Alpha wird fuer das Ende gemerkt
local function enforce()
    if not click then return end
    for _, p in ipairs((plates())) do
        if p.group == "enemies" then
            local uf = p.uf
            if click.saved[uf] == nil then
                local _, a = method(uf, "GetAlpha")
                click.saved[uf] = Compat.Num(a) or 1
            end
            click.unitOf[uf] = p.unit
            local want = p.target and 1 or 0 -- wie B7 keepTarget: Ziel sichtbar, alle anderen Gegner unsichtbar
            pcall(uf.SetAlpha, uf, want)
            click.hidden[uf] = (want == 0) or nil
            if want == 0 and not click.everSet[uf] then
                click.everSet[uf] = true
                click.ever = click.ever + 1
            end
        end
    end
end

--- Alpha nach dem Test: B7-Stand (Plates.lua verfolgt die Plakette), sonst das vorherige Alpha
local function giveBack(uf)
    local a = ns.Plates.CurrentAlpha and ns.Plates.CurrentAlpha(uf)
    if a == nil then a = click and click.saved[uf] or 1 end
    pcall(uf.SetAlpha, uf, a)
end

-- Klicktest: Plaketten muessen existieren (B7 haelt die Gegner-CVar evtl. nur fuers Ziel an). Fuer die Testdauer stehen
-- nameplateShowEnemies/ShowAll auf 1 und (ausserhalb des Kampfs) nameplateMaxDistance auf CLICK_DISTANCE; B7 kann sie bei
-- einem Zielwechsel neu schreiben, deshalb haelt der Ticker sie fest. Danach Originalwerte zurueck und B7 neu anwenden.
Far.CLICK_LEAD = 1.5
Far.CLICK_DISTANCE = 60
Far.CLICK_COUNTDOWN = { [10] = true, [5] = true }

local function clickCVars()
    local CVars = ns.CVars
    local want = { [CVars.ENEMIES] = "1", [CVars.SHOW_ALL] = "1" }
    if not InCombatLockdown() then want[CVars.MAX_DISTANCE] = tostring(Far.CLICK_DISTANCE) end
    return want
end

--- Sollwerte des Tests festhalten (nur schreiben, wenn der Wert abweicht)
local function holdCVars()
    if not click then return end
    local CVars = ns.CVars
    for name, v in pairs(clickCVars()) do
        if click.originals[name] ~= nil and tostring(CVars.Get(name)) ~= v and tonumber(CVars.Get(name)) ~= tonumber(v) then
            pcall(CVars.ProbeWrite, name, v)
        end
    end
end

local function hiddenCount()
    local n = 0
    for _ in pairs(click.hidden) do n = n + 1 end
    return n
end

local onClickTarget, onClickAdded, onClickRemoved
local function stopClick()
    if not click then return end
    local c = click
    if c.ticker then c.ticker:Cancel() end
    ns.Off("PLAYER_TARGET_CHANGED", onClickTarget)
    ns.Off("NAME_PLATE_UNIT_ADDED", onClickAdded)
    ns.Off("NAME_PLATE_UNIT_REMOVED", onClickRemoved)
    for uf in pairs(c.saved) do giveBack(uf) end
    click = nil
    -- CVars zurueck (secure Werte im Kampf: der Login-Schutz ueber Guard stellt sie spaeter zurueck)
    local CVars, restored = ns.CVars, true
    for name, v in pairs(c.originals) do
        local ok, wrote = pcall(CVars.ProbeWrite, name, v)
        if not (ok and wrote) then restored = false end
    end
    if restored then for _, r in ipairs(c.releases) do pcall(r) end end
    if ns.Nameplates and ns.Nameplates.Apply then pcall(ns.Nameplates.Apply) end -- B7-Sollwerte (Ziel kann gewechselt haben)
    local maxD = c.originals[CVars.MAX_DISTANCE]
    c.lines[#c.lines + 1] = (restored and L.NP_FAR_RANGE_RESTORED or L.NP_FAR_CLICK_RESTORE_FAILED):format(esc(maxD or "-"),
        esc(c.originals[CVars.ENEMIES] or "-"), esc(c.originals[CVars.SHOW_ALL] or "-"))
    c.lines[#c.lines + 1] = L.NP_FAR_CLICK_END:format(c.changes, c.toHidden, c.ever, c.max)
    ns.Print(L.NP_FAR_CLICK_DONE:format(c.changes, c.toHidden, c.ever))
    publish("/lucid nameplates probe click", c.lines)
end

--- unsichtbare Plaketten laufend mitzaehlen (aktuell, hoechstens, insgesamt)
local function countHidden()
    local n = hiddenCount()
    if n > click.max then click.max = n end
    if n ~= click.lastCount then
        click.lastCount = n
        clickLog(L.NP_FAR_CLICK_HIDDEN, n)
    end
    return n
end

function onClickTarget()
    if not (click and click.live) then return end
    click.changes = click.changes + 1
    local ok, exists = pcall(UnitExists, "target")
    if not (ok and Compat.Bool(exists)) then
        clickLog(L.NP_FAR_CLICK_CLEARED)
        enforce()
        countHidden()
        return
    end
    local hidden, found = false, false
    for uf in pairs(click.hidden) do
        local u = click.unitOf[uf]
        if u and isTarget(u) then hidden = true end
    end
    for _, p in ipairs((plates())) do if p.target then found = true end end
    if hidden then click.toHidden = click.toHidden + 1 end
    local okN, name = pcall(UnitName, "target")
    clickLog(L.NP_FAR_CLICK_TARGET, (okN and show(name)) or "?", yn(found), yn(hidden), yn(InCombatLockdown()))
    enforce()
    countHidden()
end
function onClickAdded()
    if not (click and click.live) then return end
    enforce()
    countHidden()
end
function onClickRemoved(_, unit)
    if not click then return end
    for uf, u in pairs(click.unitOf) do
        if u == unit then
            -- Pool-Frame: vor der Wiederverwendung zurueck (Plates.lua setzt ihn sonst selbst auf 1)
            pcall(uf.SetAlpha, uf, 1)
            click.saved[uf], click.hidden[uf], click.unitOf[uf] = nil, nil, nil
        end
    end
end

local function goLive()
    if not click then return end
    click.live = true
    click.t0 = now()
    enforce()
    local n = countHidden()
    ns.Print(L.NP_FAR_CLICK_GUIDE:format(Far.CLICK_SECONDS, n))
end

local function clickTick()
    if not click then return end
    holdCVars()
    if not click.live then return end
    local left = Far.CLICK_SECONDS - (now() - click.t0)
    if left <= 0 then return stopClick() end
    enforce()
    local n = countHidden()
    local sec = math.ceil(left - 1e-6)
    if Far.CLICK_COUNTDOWN[sec] and click.lastCountdown ~= sec then
        click.lastCountdown = sec
        ns.Print(L.NP_FAR_CLICK_COUNTDOWN:format(sec, n))
    end
end

--- /lucid nameplates probe click
function Far.Click()
    if click then
        ns.Print(L.NP_FAR_BUSY)
        return
    end
    click = { t0 = now(), saved = setmetatable({}, { __mode = "k" }), hidden = setmetatable({}, { __mode = "k" }),
        unitOf = setmetatable({}, { __mode = "k" }), ever = 0, everSet = setmetatable({}, { __mode = "k" }), max = 0,
        lastCount = nil, lines = {}, changes = 0, toHidden = 0, originals = {}, releases = {}, live = false }
    local CVars = ns.CVars
    local want = clickCVars()
    local before = {}
    for _, name in ipairs({ CVars.ENEMIES, CVars.SHOW_ALL, CVars.MAX_DISTANCE }) do
        local info = CVars.Info(name)
        if info.exists and want[name] then
            click.originals[name] = info.value
            local r = CVars.Guard(name)
            if r then click.releases[#click.releases + 1] = r end
        end
        before[#before + 1] = name .. "=" .. (info.exists and esc(info.value) or L.NP_STYLE_ABSENT)
    end
    click.lines[1] = L.NP_FAR_CLICK_HEAD:format(Far.CLICK_SECONDS, yn(InCombatLockdown()))
    click.lines[2] = L.NP_FAR_CLICK_CVARS:format(table.concat(before, ", "), want[CVars.MAX_DISTANCE] and Far.CLICK_DISTANCE
        or L.NP_FAR_CLICK_NODIST)
    holdCVars()
    ns.On("PLAYER_TARGET_CHANGED", onClickTarget)
    ns.On("NAME_PLATE_UNIT_ADDED", onClickAdded)
    ns.On("NAME_PLATE_UNIT_REMOVED", onClickRemoved)
    click.ticker = C_Timer.NewTicker(Far.CLICK_TICK, clickTick)
    C_Timer.After(Far.CLICK_LEAD, goLive)
    ns.Print(L.NP_FAR_CLICK_LEAD:format(show(Far.CLICK_LEAD)))
end

function Far.IsBusy() return busy or click ~= nil end

ns.AddHelp("HELP_NAMEPLATES_PROBE_FAR")
