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

-- /lucid nameplates probe style (S0 des Plaketten-Stils): Aussehen der Ziel-Plakette -------------------------------------
-- Rein lesend, bis auf den Schreibtest auf der Ziel-Plakette: jeder Schreibzugriff laeuft per pcall, der Originalwert wird
-- vorher gelesen und sofort zurueckgeschrieben (im selben Funktionsaufruf, Blizzard kann dazwischen nichts aktualisieren).
-- Taint: keine Felder auf Blizzard-Frames, nichts gehookt, nichts dauerhaft veraendert. Secret Values werden nie
-- verglichen oder ausgegeben, nur als "secret" gemeldet.
local Compat = ns.Compat
local MAX_EXTRA = 25 -- Obergrenze fuer generisch aufgelistete Kinder/Regionen

local function secretFree(v) return v ~= nil and not Compat.IsSecret(v) end

local function field(t, key)
    if type(t) ~= "table" then return nil end
    local ok, v = pcall(function() return t[key] end)
    if ok then return v end
    return nil
end

--- Objekttyp (und Name) eines Frames/einer Region, "table"/Lua-Typ sonst; nil bei nil
local function describe(v)
    if Compat.IsSecret(v) then return L.NP_STYLE_SECRET end
    if v == nil then return nil end
    if type(v) ~= "table" then return type(v) end
    local ok, ot = pcall(function() return v:GetObjectType() end)
    if not ok or type(ot) ~= "string" then return "table" end
    local okN, nm = pcall(function() return v:GetName() end)
    if okN and type(nm) == "string" and nm ~= "" then return esc(ot .. " '" .. nm .. "'") end
    return esc(ot)
end

local function printItems(items, perLine)
    for i = 1, #items, perLine do
        ns.Print(L.NP_STYLE_TEXT, table.concat(items, "; ", i, math.min(i + perLine - 1, #items)))
    end
end

local KNOWN_FIELDS = {
    "healthBar", "HealthBarsContainer", "name", "LevelFrame", "ClassificationFrame", "castBar", "CastBar",
    "selectionHighlight", "aggroHighlight", "border", "Border", "BuffFrame", "RaidTargetFrame", "softTargetFrame",
    "WidgetContainer",
}
local KNOWN_SUB = { -- {Elternfeld, Unterfeld}
    { "HealthBarsContainer", "healthBar" }, { "HealthBarsContainer", "border" }, { "LevelFrame", "levelText" },
    { "ClassificationFrame", "classificationIndicator" },
}

--- Kinder und Regionen, die weder bekannte Felder noch schon gesehen sind, generisch auflisten (begrenzt).
local function surveyExtra(obj, prefix, seen, out)
    if type(obj) ~= "table" then return end
    if type(seen) ~= "table" then seen = {} end
    local ok, keys = pcall(function()
        local list = {}
        for k, v in pairs(obj) do
            if type(k) == "string" and type(v) == "table" and not seen[v] then list[#list + 1] = k end
        end
        table.sort(list)
        return list
    end)
    if ok then
        for _, k in ipairs(keys) do
            local v = field(obj, k)
            if type(v) == "table" and #out < MAX_EXTRA then
                local d = describe(v)
                if d and d ~= "table" then
                    seen[v] = true
                    out[#out + 1] = esc(prefix .. k) .. "=" .. d
                end
            end
        end
    end
    for _, getter in ipairs({ "GetChildren", "GetRegions" }) do
        local okC, packed = pcall(function() return { n = select("#", obj[getter](obj)), obj[getter](obj) } end)
        if okC then
            for i = 1, packed.n do
                local c = packed[i]
                if type(c) == "table" and not seen[c] and #out < MAX_EXTRA then
                    seen[c] = true
                    out[#out + 1] = esc(prefix .. (getter == "GetChildren" and "child#" or "region#") .. i) .. "=" .. (describe(c) or "?")
                end
            end
        end
    end
end

local function printStructure(uf)
    ns.Print(L.NP_STYLE_FIELDS)
    local items, missing, seen = {}, {}, {}
    for _, key in ipairs(KNOWN_FIELDS) do
        local v = field(uf, key)
        local d = describe(v)
        if d then
            items[#items + 1] = key .. "=" .. d
            if type(v) == "table" then seen[v] = true end
        else
            missing[#missing + 1] = key
        end
    end
    for _, pair in ipairs(KNOWN_SUB) do
        local parent = field(uf, pair[1])
        local v = field(parent, pair[2])
        local d = describe(v)
        if d then
            items[#items + 1] = pair[1] .. "." .. pair[2] .. "=" .. d
            if type(v) == "table" then seen[v] = true end
        end
    end
    -- Statusbar-Textur: Objekttyp und (falls lesbar) Pfad/Atlas
    local hb = field(uf, "healthBar") or field(field(uf, "HealthBarsContainer"), "healthBar")
    if type(hb) == "table" then
        local ok, tex = pcall(function() return hb:GetStatusBarTexture() end)
        local d = ok and describe(tex) or nil
        if d then
            local okT, t = pcall(function() return tex:GetTexture() end)
            local okA, a = pcall(function() return tex:GetAtlas() end)
            items[#items + 1] = "healthBar:GetStatusBarTexture()=" .. d
                .. " (Textur " .. ((okT and secretFree(t)) and esc(t) or "-")
                .. ", Atlas " .. ((okA and secretFree(a) and a ~= "") and esc(a) or "-") .. ")"
        else
            missing[#missing + 1] = "healthBar:GetStatusBarTexture()"
        end
    end
    printItems(items, 2)
    if #missing > 0 then ns.Print(L.NP_STYLE_MISSING, table.concat(missing, ", ")) end
    local extra = {}
    for _, k in ipairs(KNOWN_FIELDS) do
        local v = field(uf, k)
        if type(v) == "table" then seen[v] = true end
    end
    surveyExtra(uf, "", seen, extra)
    local hbc = field(uf, "HealthBarsContainer")
    if type(hbc) == "table" then surveyExtra(hbc, "HBC.", seen, extra) end
    if #extra > 0 then
        ns.Print(L.NP_STYLE_EXTRA)
        printItems(extra, 3)
    end
end

--- "secret" | "lesbar (Wert/Typ)" | "Fehler: ..." aus dem Ergebnis eines pcall
local function classify(ok, v)
    if not ok then return L.NP_STYLE_FAILED .. ": " .. esc(string.sub(tostring(v), 1, 60)) end
    if Compat.IsSecret(v) then return L.NP_STYLE_SECRET end
    local t = type(v)
    if t == "number" or t == "boolean" or t == "string" then
        return L.NP_STYLE_READABLE .. " (" .. esc(string.sub(tostring(v), 1, 20)) .. ")"
    end
    return L.NP_STYLE_READABLE .. " (" .. t .. ")"
end

-- eigene Test-Textur (nie ein Blizzard-Frame) fuer "darf das Ergebnis in SetAlpha?"
local styleTex
local function testTexture()
    if styleTex == nil then
        local ok, t = pcall(function()
            local f = CreateFrame("Frame", nil, UIParent)
            f:Hide()
            return f:CreateTexture(nil, "ARTWORK")
        end)
        styleTex = ok and t or false
    end
    return styleTex or nil
end

local function alphaResult(v)
    local tex = testTexture()
    if not tex then return L.NP_STYLE_ABSENT end
    if not Compat.IsSecret(v) and type(v) ~= "number" then return L.NP_STYLE_SKIPPED:format("-") end
    local ok, err = pcall(tex.SetAlpha, tex, v)
    pcall(tex.SetAlpha, tex, 1)
    return ok and L.NP_PROBE_OK or (L.NP_STYLE_FAILED .. ": " .. esc(string.sub(tostring(err), 1, 60)))
end

local function printSecrets(unit)
    ns.Print(L.NP_STYLE_SECRET_HEAD)
    local items = {}
    local function add(label, fn, ...)
        if type(fn) ~= "function" then
            items[#items + 1] = label .. ": " .. L.NP_STYLE_ABSENT
            return
        end
        local ok, v = pcall(fn, ...)
        items[#items + 1] = label .. ": " .. classify(ok, v)
        return ok, v
    end
    add("UnitLevel", UnitLevel, unit)
    add("UnitEffectiveLevel", UnitEffectiveLevel, unit)
    add("UnitClassification", UnitClassification, unit)
    add("UnitReaction", UnitReaction, "player", unit)
    add("UnitCanAttack", UnitCanAttack, "player", unit)
    add("UnitIsQuestBoss", UnitIsQuestBoss, unit)
    add("C_QuestLog.UnitIsRelatedToActiveQuest", C_QuestLog and C_QuestLog.UnitIsRelatedToActiveQuest, unit)
    add("UnitCastingInfo", UnitCastingInfo, unit)
    add("UnitIsTapDenied", UnitIsTapDenied, unit)
    local _, pct = add("UnitHealthPercent", UnitHealthPercent, unit)
    items[#items + 1] = "SetAlpha(UnitHealthPercent): " .. (type(UnitHealthPercent) == "function" and alphaResult(pct) or L.NP_STYLE_ABSENT)
    -- Kurve: Existenz, Ergebnis, SetAlpha mit dem (ggf. secret) Ergebnis
    local curve
    local hasCurve = C_CurveUtil and type(C_CurveUtil.CreateCurve) == "function"
    if hasCurve then
        local ok, c = pcall(function()
            local cv = C_CurveUtil.CreateCurve()
            cv:AddPoint(0, 0)
            cv:AddPoint(1, 1)
            return cv
        end)
        if ok then curve = c end
    end
    items[#items + 1] = "C_CurveUtil.CreateCurve: " .. (hasCurve and (curve and L.NP_PROBE_OK or L.NP_STYLE_FAILED) or L.NP_STYLE_ABSENT)
    if curve and type(UnitHealthPercent) == "function" then
        local ok, v = pcall(UnitHealthPercent, unit, false, curve)
        items[#items + 1] = "UnitHealthPercent(Kurve): " .. classify(ok, v)
        items[#items + 1] = "SetAlpha(Kurven-Ergebnis): " .. (ok and alphaResult(v) or L.NP_STYLE_FAILED)
    end
    printItems(items, 2)
end

--- Zustand eines Statusbar-Texturobjekts: Atlas oder Pfad/ID, nil wenn nicht lesbar
local function readBarTexture(hb)
    local ok, tex = pcall(function() return hb:GetStatusBarTexture() end)
    if not ok or type(tex) ~= "table" then return nil, nil end
    local okA, atlas = pcall(function() return tex:GetAtlas() end)
    if okA and secretFree(atlas) and type(atlas) == "string" and atlas ~= "" then return atlas, tex, true end
    local okT, t = pcall(function() return tex:GetTexture() end)
    if okT and secretFree(t) and (type(t) == "string" or type(t) == "number") then return t, tex, false end
    return nil, tex
end

local function writeLine(label, result, reset)
    ns.Print(L.NP_STYLE_WRITE_LINE, label, result, reset, yn(InCombatLockdown()))
end
local function skipLine(label, why) writeLine(label, L.NP_STYLE_SKIPPED:format(why), "-") end
local function failText(err) return L.NP_STYLE_FAILED .. ": " .. esc(string.sub(tostring(err), 1, 60)) end

local function testBarTexture(hb)
    local label = "healthBar:SetStatusBarTexture"
    if type(hb) ~= "table" then return skipLine(label, L.NP_STYLE_NO_FIELD) end
    local orig, tex, isAtlas = readBarTexture(hb)
    if orig == nil then return skipLine(label, L.NP_STYLE_NO_ORIGINAL) end
    local okW, errW = pcall(hb.SetStatusBarTexture, hb, "Interface\\TargetingFrame\\UI-StatusBar")
    local okR = pcall(hb.SetStatusBarTexture, hb, orig) -- immer zurueck, auch nach Fehler
    local now = readBarTexture(hb)
    if now ~= orig and isAtlas and tex then pcall(function() tex:SetAtlas(orig) end) now = readBarTexture(hb) end
    writeLine(label, okW and L.NP_PROBE_OK or failText(errW), (okR and now == orig) and L.NP_YES or L.NP_NO)
end

local function testBarColor(hb)
    local label = "healthBar:SetStatusBarColor"
    if type(hb) ~= "table" then return skipLine(label, L.NP_STYLE_NO_FIELD) end
    local ok, r, g, b, a = pcall(function() return hb:GetStatusBarColor() end)
    if not ok or type(r) == "nil" or type(g) == "nil" or type(b) == "nil" then return skipLine(label, L.NP_STYLE_NO_ORIGINAL) end
    local okW, errW = pcall(hb.SetStatusBarColor, hb, 0.5, 0.5, 0.5, 1)
    local okR = pcall(hb.SetStatusBarColor, hb, r, g, b, a) -- Originalwerte (ggf. secret) unveraendert zurueckreichen
    local reset = L.NP_YES
    local ok2, r2, g2, b2 = pcall(function() return hb:GetStatusBarColor() end)
    if not okR or not ok2 then
        reset = L.NP_NO
    elseif secretFree(r) and secretFree(g) and secretFree(b) and secretFree(r2) and secretFree(g2) and secretFree(b2) then
        reset = (r == r2 and g == g2 and b == b2) and L.NP_YES or L.NP_NO
    end
    writeLine(label, okW and L.NP_PROBE_OK or failText(errW), reset)
end

local function testFont(fs)
    local label = "name:SetFont"
    if type(fs) ~= "table" then return skipLine(label, L.NP_STYLE_NO_FIELD) end
    local ok, f, s, fl = pcall(function() return fs:GetFont() end)
    if not ok or not secretFree(f) or type(f) ~= "string" or not secretFree(s) or type(s) ~= "number" then
        return skipLine(label, L.NP_STYLE_NO_ORIGINAL)
    end
    if not secretFree(fl) or type(fl) ~= "string" then fl = "" end
    local okW, errW = pcall(fs.SetFont, fs, "Fonts\\MORPHEUS.TTF", s, fl)
    local okR = pcall(fs.SetFont, fs, f, s, fl)
    local ok2, f2, s2 = pcall(function() return fs:GetFont() end)
    writeLine(label, okW and L.NP_PROBE_OK or failText(errW), (okR and ok2 and f2 == f and s2 == s) and L.NP_YES or L.NP_NO)
end

-- eigener Overlay-Frame, Elternteil kurz die Plakette (nur der erlaubte Weg wird gemeldet), danach zurueck an UIParent
local styleOverlay
local function testOverlay(plate)
    local label = "Overlay-Frame + Textur (Elternteil Plakette)"
    if styleOverlay == nil then
        local ok, o = pcall(function()
            local f = CreateFrame("Frame", nil, UIParent)
            f:Hide()
            return { frame = f, tex = f:CreateTexture(nil, "OVERLAY") }
        end)
        styleOverlay = ok and o or false
    end
    local o = styleOverlay
    if not o then return skipLine(label, L.NP_STYLE_FAILED) end
    local okW, errW = pcall(function()
        o.frame:SetParent(plate)
        o.frame:ClearAllPoints()
        o.frame:SetAllPoints(plate)
        o.tex:SetAllPoints(o.frame)
        o.tex:SetColorTexture(0, 0, 0, 0)
        o.frame:Show()
    end)
    local okR = pcall(function()
        o.frame:Hide()
        o.frame:ClearAllPoints()
        o.frame:SetParent(UIParent)
    end)
    local okP, parent = pcall(function() return o.frame:GetParent() end)
    writeLine(label, okW and L.NP_PROBE_OK or failText(errW), (okR and okP and parent == UIParent) and L.NP_YES or L.NP_NO)
end

local HOOK_FUNCS = {
    "CompactUnitFrame_UpdateHealthColor", "CompactUnitFrame_UpdateName", "CompactUnitFrame_UpdateHealthBorder",
    "CompactUnitFrame_UpdateAll", "CompactUnitFrame_UpdateHealth", "CompactUnitFrame_UpdateLevel",
    "CompactUnitFrame_UpdateClassificationIndicator", "CompactUnitFrame_UpdateSelectionHighlight",
    "CompactUnitFrame_UpdateAggroHighlight", "CompactUnitFrame_UpdateWidgetsOnlyMode",
}
local HOOK_DRIVER = { "OnNamePlateAdded", "OnNamePlateRemoved", "ApplyFrameOptions", "UpdateNamePlateOptions", "OnUnitFactionChanged" }
local HOOK_MIXINS = { "NameplateBuffContainerMixin", "NamePlateBaseMixin", "NamePlateUnitFrameMixin", "NamePlateDriverMixin" }
local UF_METHODS = { "UpdateName", "UpdateAll", "UpdateHealthColor", "UpdateHealthBorder", "UpdateAuras", "OnEvent" }
local FN_PREFIXES = { "On", "Update", "Apply", "Set", "Acquire", "Release", "Refresh" }

local function functionNames(t)
    local out = {}
    local ok = pcall(function()
        for k, v in pairs(t) do
            if type(k) == "string" and type(v) == "function" then
                for _, p in ipairs(FN_PREFIXES) do
                    if k:sub(1, #p) == p then out[#out + 1] = k break end
                end
            end
        end
    end)
    if not ok then return {} end
    table.sort(out)
    while #out > MAX_EXTRA do out[#out] = nil end
    return out
end

local function typeOf(v)
    if v == nil then return L.NP_STYLE_ABSENT end
    return type(v)
end

local function printHooks(uf)
    ns.Print(L.NP_STYLE_HOOKS_HEAD)
    local items = {}
    for _, n in ipairs(HOOK_FUNCS) do items[#items + 1] = n .. "=" .. typeOf(_G[n]) end
    local driver = _G.NamePlateDriverFrame
    items[#items + 1] = "NamePlateDriverFrame=" .. typeOf(driver)
    for _, m in ipairs(HOOK_DRIVER) do items[#items + 1] = "NamePlateDriverFrame." .. m .. "=" .. typeOf(field(driver, m)) end
    for _, n in ipairs(HOOK_MIXINS) do items[#items + 1] = n .. "=" .. typeOf(_G[n]) end
    for _, m in ipairs(UF_METHODS) do items[#items + 1] = "UnitFrame." .. m .. "=" .. typeOf(field(uf, m)) end
    printItems(items, 2)
    for _, pair in ipairs({ { "NamePlateDriverFrame", driver }, { "NameplateBuffContainerMixin", _G.NameplateBuffContainerMixin } }) do
        if type(pair[2]) == "table" then
            local names = functionNames(pair[2])
            if #names > 0 then ns.Print(L.NP_STYLE_TEXT, esc(pair[1]) .. ": " .. esc(table.concat(names, ", "))) end
        end
    end
end

local STYLE_CVARS = {
    "nameplateMinScale", "nameplateMaxScale", "nameplateMinScaleDistance", "nameplateMaxScaleDistance",
    "nameplateMinAlpha", "nameplateMaxAlpha", "nameplateMinAlphaDistance", "nameplateLargerScale",
    "nameplateGlobalScale", "nameplateSelectedScale",
}
local function printCVars()
    ns.Print(L.NP_STYLE_CVARS_HEAD)
    local items = {}
    for _, name in ipairs(STYLE_CVARS) do
        local info = CVars.Info(name)
        if info.exists then
            items[#items + 1] = name .. "=" .. esc(info.value) .. " (" .. esc(info.default or "-") .. ")"
        else
            items[#items + 1] = name .. ": " .. L.NP_STYLE_ABSENT
        end
    end
    printItems(items, 2)
end

local function plateStats()
    if not (C_NamePlate and type(C_NamePlate.GetNamePlates) == "function") then return "?", "?" end
    local ok, plates = pcall(C_NamePlate.GetNamePlates)
    if not ok or type(plates) ~= "table" then return "?", "?" end
    local n, forbidden = 0, 0
    for _, p in ipairs(plates) do
        n = n + 1
        if Compat.QueryBool(p, "IsForbidden") == true then forbidden = forbidden + 1 end
    end
    return n, forbidden
end

local function probeStyle()
    local n, forbiddenCount = plateStats()
    ns.Print(L.NP_STYLE_HEAD, Compat.flavor, Compat.interface, yn(InCombatLockdown()), n, forbiddenCount)
    local okT, hasTarget = pcall(UnitExists, "target")
    if not okT or not Compat.Bool(hasTarget) then
        ns.Print(L.NP_STYLE_NOTARGET)
        return
    end
    local plate
    if C_NamePlate and type(C_NamePlate.GetNamePlateForUnit) == "function" then
        local ok, p = pcall(C_NamePlate.GetNamePlateForUnit, "target")
        if ok and type(p) == "table" then plate = p end
    end
    if not plate then
        ns.Print(L.NP_STYLE_NOPLATE)
        return
    end
    local uf = field(plate, "UnitFrame")
    local fp = Compat.QueryBool(plate, "IsForbidden")
    local fu = Compat.QueryBool(uf, "IsForbidden")
    ns.Print(L.NP_STYLE_FORBIDDEN, fp == nil and "?" or yn(fp), fu == nil and "?" or yn(fu))
    if type(uf) ~= "table" then
        ns.Print(L.NP_STYLE_NOFRAME)
        return
    end
    printStructure(uf)
    printSecrets("target")
    if fp ~= true and fu ~= true then -- forbidden: nichts schreiben
        local hb = field(uf, "healthBar") or field(field(uf, "HealthBarsContainer"), "healthBar")
        ns.Print(L.NP_STYLE_WRITE_HEAD)
        testBarTexture(hb)
        testBarColor(hb)
        testFont(field(uf, "name"))
        testOverlay(plate)
    end
    printHooks(uf)
    printCVars()
end

Nameplates.sub.probe = function(arg)
    if type(arg) == "string" and arg:lower() == "style" then
        probeStyle()
        return
    end
    -- Quest-Fernsicht (Nachtrag 2): ProbeFar.lua
    local far = ns.NameplateProbeFar
    if far and type(arg) == "string" and arg:lower() == "far" then
        far.Run()
        return
    end
    if far and type(arg) == "string" and arg:lower() == "click" then
        far.Click()
        return
    end
    ns.Print(L.NP_PROBE_HEAD, ns.Compat.flavor, ns.Compat.interface, yn(InCombatLockdown()))
    for _, name in ipairs(CVars.CATALOG) do probeLine(name) end
    for _, name in ipairs(EXTRA) do probeLine(name) end
    rangeTest()
end

ns.AddHelp("HELP_NAMEPLATES_PROBE")
ns.AddHelp("HELP_NAMEPLATES_PROBE_STYLE")
