-- Karte (B9/W0): Diagnose-Probe /lucid map probe. Prueft im Client gefahrlos, ob Weg A (Blizzards WorldMapFrame selbst im
-- Lucid-Kartenmodus) tragfaehig ist: Struktur der Frames, CVars, Schreibtests (Skala, Deckkraft, Position, Ausblenden von
-- Kopfzeile/Questliste/Rahmen) mit Rueckstellung, danach eine Taint-Pruefung (issecurevariable). Nichts im Kampf; jeder
-- Schritt laeuft unter pcall, der Ursprungszustand wird sofort wiederhergestellt (auch nach Fehlern).
local _, ns = ...
local Map, L = ns.Map, ns.L

local CVARS = { "mapFade", "miniWorldMap", "questLogOpen" }
-- Kinder des WorldMapFrame, die der Kartenmodus beruehrt oder die fuer die Struktur wichtig sind
local PARTS = { "BorderFrame", "NavBar", "ScrollContainer", "BlackoutFrame", "TitleCanvasSpacerFrame", "overlayFrames" }

local function esc(s) return (tostring(s):gsub("|", "||")) end
local function yn(b) return b and L.NP_YES or L.NP_NO end
local function wmf() return _G.WorldMapFrame end

local function call(obj, method, ...)
    if type(obj) ~= "table" or type(obj[method]) ~= "function" then return false, "n/a" end
    local ok, a, b, c, d = pcall(obj[method], obj, ...)
    if not ok then return false, tostring(a) end
    return true, a, b, c, d
end

local function secure(tbl, key)
    if type(_G.issecurevariable) ~= "function" then return "?" end
    local ok, res = pcall(_G.issecurevariable, tbl, key)
    if not ok then return "?" end
    return res and L.NP_YES or L.NP_NO
end

local function size(f)
    local _, w = call(f, "GetWidth")
    local _, h = call(f, "GetHeight")
    return ("%s x %s"):format(tostring(w and math.floor(w + 0.5)), tostring(h and math.floor(h + 0.5)))
end

local function partLine(m, key)
    local part = m[key]
    if type(part) ~= "table" then
        ns.Print(L.MAP_PROBE_PART_MISSING, key)
        return
    end
    if key == "overlayFrames" then
        ns.Print(L.MAP_PROBE_PART_COUNT, key, #part, secure(m, key))
        return
    end
    local _, shown = call(part, "IsShown")
    local _, prot = call(part, "IsProtected")
    ns.Print(L.MAP_PROBE_PART, key, yn(shown), yn(prot), size(part), secure(m, key))
end

local function snapshot(m)
    local pts = {}
    local okN, n = call(m, "GetNumPoints")
    n = okN and tonumber(n) or 0
    for i = 1, n do
        local ok, p, rel, rp, x, y = call(m, "GetPoint", i)
        if ok then pts[#pts + 1] = { p, rel, rp, x, y } end
    end
    return { scale = select(2, call(m, "GetScale")), alpha = select(2, call(m, "GetAlpha")), points = pts }
end

local function restore(m, snap)
    if snap.scale then call(m, "SetScale", snap.scale) end
    if snap.alpha then call(m, "SetAlpha", snap.alpha) end
    if #snap.points > 0 then
        call(m, "ClearAllPoints")
        for _, p in ipairs(snap.points) do call(m, "SetPoint", p[1], p[2], p[3], p[4], p[5]) end
    end
end

local function report(name, ok, err)
    ns.Print(L.MAP_PROBE_TEST, name, ok and L.MAP_PROBE_OK or esc(err))
end

--- ein Schreibtest: fn() aendert, check() liest zurueck (true/false), danach Rueckstellung ueber restoreFn
local function writeTest(name, fn, check, restoreFn)
    local ok, err = pcall(fn)
    local readOk = true
    if ok and check then
        local okC, res = pcall(check)
        readOk = okC and res ~= false
        if not readOk then err = L.MAP_PROBE_NOREAD end
    end
    local okR = pcall(restoreFn)
    report(name, ok and readOk, err)
    if not okR then ns.Print(L.MAP_PROBE_RESTORE_FAILED, name) end
end

local function partWriteTest(m, key, name)
    local part = m[key]
    if type(part) ~= "table" or type(part.SetAlpha) ~= "function" then
        ns.Print(L.MAP_PROBE_TEST, name, L.MAP_PROBE_SKIPPED)
        return
    end
    local _, oldAlpha = call(part, "GetAlpha")
    local _, wasShown = call(part, "IsShown")
    writeTest(name .. " (Hide)", function()
        local ok, err = call(part, "Hide")
        if not ok then error(err) end
    end, function() return select(2, call(part, "IsShown")) == false end, function()
        if wasShown then call(part, "Show") end
        if oldAlpha then call(part, "SetAlpha", oldAlpha) end
    end)
end

Map.sub.probe = function()
    local m = wmf()
    ns.Print(L.MAP_PROBE_HEAD, ns.Compat.flavor, ns.Compat.interface, yn(InCombatLockdown()))
    if type(m) ~= "table" then
        ns.Print(L.MAP_PROBE_NO_MAP)
        return
    end
    for _, name in ipairs(CVARS) do
        local ok, v = pcall(GetCVar, name)
        ns.Print(L.MAP_PROBE_CVAR, name, ok and v ~= nil and esc(v) or "-")
    end
    local _, maxed = call(m, "IsMaximized")
    local _, shown = call(m, "IsShown")
    local _, prot = call(m, "IsProtected")
    local _, movable = call(m, "IsMovable")
    local snap = snapshot(m)
    ns.Print(L.MAP_PROBE_FRAME, yn(shown), yn(maxed), yn(prot), yn(movable), size(m), tostring(snap.scale), tostring(snap.alpha),
        #snap.points)
    for _, key in ipairs(PARTS) do partLine(m, key) end
    local qm = _G.QuestMapFrame
    if type(qm) == "table" then
        local _, qs = call(qm, "IsShown")
        local _, qp = call(qm, "IsProtected")
        ns.Print(L.MAP_PROBE_PART, "QuestMapFrame", yn(qs), yn(qp), size(qm), secure(_G, "QuestMapFrame"))
    else
        ns.Print(L.MAP_PROBE_PART_MISSING, "QuestMapFrame")
    end
    ns.Print(L.MAP_PROBE_ADDONS, yn(Map.OpenMapLoaded()), yn(Map.AddonLoaded("Mapster")), yn(Map.AddonLoaded("Leatrix_Maps")))

    if InCombatLockdown() then
        ns.Print(L.MAP_PROBE_COMBAT)
        return
    end
    -- Schreibtests, jeweils mit sofortiger Rueckstellung
    writeTest("SetScale 0.9", function() local ok, e = call(m, "SetScale", 0.9) if not ok then error(e) end end,
        function() return math.abs((select(2, call(m, "GetScale")) or 0) - 0.9) < 0.001 end, function() restore(m, snap) end)
    writeTest("SetAlpha 0.5", function() local ok, e = call(m, "SetAlpha", 0.5) if not ok then error(e) end end,
        function() return math.abs((select(2, call(m, "GetAlpha")) or 0) - 0.5) < 0.001 end, function() restore(m, snap) end)
    writeTest("ClearAllPoints/SetPoint", function()
        local ok, e = call(m, "ClearAllPoints")
        if not ok then error(e) end
        ok, e = call(m, "SetPoint", "CENTER", UIParent, "CENTER", 40, 40)
        if not ok then error(e) end
    end, function() return select(2, call(m, "GetNumPoints")) == 1 end, function() restore(m, snap) end)
    partWriteTest(m, "NavBar", "NavBar")
    partWriteTest(m, "BorderFrame", "BorderFrame")
    if type(_G.QuestMapFrame) == "table" then partWriteTest({ QuestMapFrame = _G.QuestMapFrame }, "QuestMapFrame", "QuestMapFrame") end
    -- Taint-Pruefung: sind die Blizzard-Felder noch Blizzards?
    local bad = {}
    for _, key in ipairs({ "ScrollContainer", "BorderFrame", "NavBar", "overlayFrames", "SetScale", "SetPoint", "SetAlpha" }) do
        if secure(m, key) == L.NP_NO then bad[#bad + 1] = key end
    end
    if secure(_G, "WorldMapFrame") == L.NP_NO then bad[#bad + 1] = "WorldMapFrame" end
    ns.Print(L.MAP_PROBE_TAINT, #bad == 0 and L.MAP_PROBE_TAINT_NONE or esc(table.concat(bad, ", ")))
    ns.Print(L.MAP_PROBE_DONE)
end

-- /lucid map debug: alle sichtbaren Kinder und Regionen des WorldMapFrame (Name / Schluessel, Typ, Groesse, Ebene), damit eine
-- unerwartete Flaeche benannt werden kann; dazu der Zustand des Kartenmodus und der letzte Tasten-Umschalter.
local function keyOf(parent, child)
    if type(child.GetName) == "function" then
        local ok, n = pcall(child.GetName, child)
        if ok and type(n) == "string" and n ~= "" then return n end
    end
    for k, v in pairs(parent) do
        if v == child and type(k) == "string" then return "." .. k end
    end
    return "?"
end

local function describe(parent, child, kind)
    local _, shown = call(child, "IsShown")
    if not shown then return nil end
    local _, a = call(child, "GetAlpha")
    local _, lvl = call(child, "GetFrameLevel")
    local _, layer = call(child, "GetDrawLayer")
    local _, strata = call(child, "GetFrameStrata")
    local tex = ""
    if kind == "Region" then
        local _, t = call(child, "GetTexture")
        local _, at = call(child, "GetAtlas")
        tex = esc(at or (type(t) == "string" and t) or (type(t) == "number" and t) or "")
        local _, par = call(child, "GetParent")
        local pk = type(par) == "table" and keyOf(type(parent) == "table" and parent or {}, par) or "?"
        if pk == "?" and type(par) == "table" and par == parent then pk = "(parent)" end
        tex = ("%s parent=%s layer=%s"):format(tex, esc(pk), esc(layer or "-"))
    end
    local _, ot = call(child, "GetObjectType")
    return L.MAP_DEBUG_LINE:format(kind, esc(keyOf(parent, child)), esc(ot or "?"), size(child), esc(lvl or layer or "-"),
        esc(strata or "-"), esc(a and ("%.2f"):format(a) or "-"), tex)
end

Map.sub.debug = function()
    local m = wmf()
    if type(m) ~= "table" then
        ns.Print(L.MAP_PROBE_NO_MAP)
        return
    end
    local st = Map.State()
    ns.Print(L.MAP_DEBUG_STATE, yn(st.engaged), yn(st.external), yn(st.bypass), esc(table.concat(st.hidden or {}, ",")),
        st.lastToggle and (yn(st.lastToggle.wasOpen) .. "/" .. st.lastToggle.steps .. "/" .. yn(st.lastToggle.nowOpen)) or "-")
    ns.Print(L.MAP_DEBUG_HEAD, size(m))
    local n = 0
    local function out(line)
        if line and n < 60 then
            n = n + 1
            ns.Print("%s", line)
        end
    end
    local kids = { m:GetChildren() }
    for _, c in ipairs(kids) do if type(c) == "table" then out(describe(m, c, "Frame")) end end
    if type(m.GetRegions) == "function" then
        for _, r in ipairs({ m:GetRegions() }) do if type(r) == "table" then out(describe(m, r, "Region")) end end
    end
    for _, key in ipairs({ "BorderFrame", "QuestLog" }) do
        local part = m[key]
        if type(part) == "table" and type(part.GetChildren) == "function" then
            for _, c in ipairs({ part:GetChildren() }) do
                if type(c) == "table" then out(describe(part, c, "Frame")) end
            end
            if type(part.GetRegions) == "function" then
                for _, r in ipairs({ part:GetRegions() }) do if type(r) == "table" then out(describe(part, r, "Region")) end end
            end
        end
    end
    ns.Print(L.MAP_DEBUG_DONE, n)
end

ns.AddHelp("HELP_MAP_PROBE")
