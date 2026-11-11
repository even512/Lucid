-- Plaketten, Nachtrag 2 (Quest-Fernsicht): Gegner-Plaketten, die nach den B7-Regeln gerade unsichtbar sind (Plates.lua, UnitFrame-
-- Alpha 0), zeigen von weitem nur ihr Quest-Symbol (Beutel/Schwerter/Handschuh/"!", Regel wie Baustein 9: Style.QuestSymbol).
--
-- Zusammenspiel (Nameplates.lua): mit Fernsicht bleibt die Gegner-CVar an und nameplateMaxDistance steht auf der Fernsicht-
-- Reichweite; ein B7-Radius wirkt dann ueber Blizzards Entfernungs-Alpha (Style.RadiusAlphaDesired). Ohne Fernsicht bleibt B7
-- exakt wie vorher. Probe (Forever, 09./10.11.): Plaketten mit Alpha 0 fangen keine Klicks ab; die Entfernungs-Alpha liegt auf der
-- Plakette selbst, das Ziel ist davon ausgenommen.
--
-- Das Symbol ist ein eigener Frame mit Elternteil Plakette (Geschwister des UnitFrame, bleibt bei UnitFrame-Alpha 0 sichtbar) und
-- ignoriert die Plaketten-Alpha (SetIgnoreParentAlpha). Ausgewertet wird nur beim Hinzufuegen (plus kurzer Nachpruefung fuer
-- Questie) und bei Questlog-Ereignissen (gedrosselt, nur angemeldet solange die Fernsicht wirkt); sichtbar/unsichtbar folgt dem
-- Zuhoerer von Plates.lua, waehrend B7 ein-/ausblendet blendet das Symbol gegengleich. Pro Bild laeuft nur das Atmen bzw. die
-- Gegenblende am gemeinsamen Treiber von Style.lua. Questies eigenes Plaketten-Symbol wird an diesen Plaketten ausgeblendet, wenn
-- der Stil das nicht schon selbst tut (zurueck beim Ausschalten).
--
-- Taint: nur eigene Frames, Alpha und Anker, keine Felder auf Blizzard-Frames, forbidden Plaketten werden uebersprungen.
local _, ns = ...
local Compat, Nameplates = ns.Compat, ns.Nameplates
local L = ns.L

local QuestFar = {}
ns.QuestFar = QuestFar

-- Atmen: Deckkraft zwischen breathMin und 1 (Anteil der eingestellten Deckkraft), Periode in s; Hof: Groesse x Symbol, Alpha
QuestFar.ANIM = { breathMin = 0.55, period = 2.4 }
QuestFar.HALO = { scale = 2.1, alpha = 0.75, color = { 0.03, 0.02, 0.01 } }
QuestFar.RECHECK = 0.05
QuestFar.QUEST_DELAY, QuestFar.QUEST_LATE = 0.3, 1.0
QuestFar.LEVEL = 30 -- ueber dem UnitFrame

local entries = setmetatable({}, { __mode = "k" }) -- Plakette -> { f, unit, uf, want, kind, shown }
local byUnit = {}                                   -- unit -> Plakette
local active = false                                -- Modul aktiv (nach PLAYER_LOGIN)
local on = false                                    -- Fernsicht wirksam (Refresh)
local qcfg = nil                                    -- zwischengespeicherte Einstellungen
local replaced = setmetatable({}, { __mode = "k" }) -- Plakette -> true, solange hier Questies Symbol ausgeblendet ist
local updateListeners -- Ereignisse an/ab (weiter unten), aus Refresh gerufen
-- Testmodus (10.11.): alle feindlichen Plaketten gelten als Quest-Gegner, sonst exakt der echte Pfad. kind: "loot"|"slay"|
-- "interact"|"!"|"mix" (abwechselnd, fest je Einheit); nur fuer die Sitzung (Nameplates.questFarTest), Profil bleibt unveraendert
QuestFar.TEST_KINDS = { loot = true, slay = true, interact = true, ["!"] = true, mix = true }
QuestFar.MIX = { "loot", "slay", "interact", false }
local testKind = nil

local function field(t, key)
    if type(t) ~= "table" then return nil end
    local ok, v = pcall(function() return t[key] end)
    if ok then return v end
    return nil
end

local function plateFor(unit)
    if not (C_NamePlate and type(C_NamePlate.GetNamePlateForUnit) == "function") then return nil end
    local ok, plate = pcall(C_NamePlate.GetNamePlateForUnit, unit)
    if not ok or type(plate) ~= "table" or Compat.QueryBool(plate, "IsForbidden") == true then return nil end
    local uf = field(plate, "UnitFrame")
    if type(uf) ~= "table" or Compat.QueryBool(uf, "IsForbidden") == true then return nil end
    return plate, uf
end

--- Symbol-Frame (Hof + Symbol) als Kind von parent; auch fuer die Vorschau im Reiter
function QuestFar.BuildIcon(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.halo = f:CreateTexture(nil, "BACKGROUND")
    f.halo:SetPoint("CENTER", f, "CENTER", 0, 0)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetPoint("CENTER", f, "CENTER", 0, 0)
    if f.SetIgnoreParentAlpha then pcall(f.SetIgnoreParentAlpha, f, true) end
    f:Hide()
    return f
end

--- Symbol gestalten: kind (loot/slay/interact oder nil fuer "!"), c = Einstellungen questFar
function QuestFar.StyleIcon(f, kind, c)
    local S = ns.NameplateStyle
    local path = kind and S.OBJ_TEX[kind] or S.QUEST_TEX
    if f.path ~= path then
        f.path = path
        f.tex:SetTexture(path)
    end
    local size = c.size
    local w = kind and size or size / 2 -- "!" halb so breit wie hoch (wie Baustein 9)
    f:SetSize(size, size)
    f.tex:SetSize(w, size)
    local H = QuestFar.HALO
    f.halo:SetTexture(S.VEIL_TEX)
    f.halo:SetVertexColor(H.color[1], H.color[2], H.color[3])
    f.halo:SetSize(size * H.scale, size * H.scale)
    f.halo:SetAlpha(H.alpha)
    f.halo:SetShown(c.halo == true)
    f.baseAlpha = c.alpha
    f:SetAlpha(c.alpha)
end

--- Deckkraft beim Atmen zum Zeitpunkt t (Anteil 0..1 der eingestellten Deckkraft)
function QuestFar.Breath(t)
    local A = QuestFar.ANIM
    return A.breathMin + (1 - A.breathMin) * (0.5 + 0.5 * math.sin(t * 2 * math.pi / A.period))
end

--- Anteil, zu dem B7 die Plakette gerade ausblendet (1 = ganz unsichtbar, 0 = sichtbar); nil = Plakette ist nicht von B7
--- verfolgt oder voll sichtbar mit Ziel 1. Das Fern-Symbol blendet gegengleich (Alpha x Anteil), springt also nicht.
local function hiddenShare(e)
    local cur, target = ns.Plates.CurrentAlpha(e.uf), ns.Plates.TargetAlpha(e.uf)
    if cur == nil or target == nil then return nil end
    if target ~= 0 and cur >= 1 then return nil end
    return 1 - cur
end

--- Questies Symbol an der Plakette: nur anfassen, wenn der Stil es nicht selbst verwaltet
local function syncQuestie(plate, replace)
    local S = ns.NameplateStyle
    if S.IsEngaged() then
        replaced[plate] = nil
        return
    end
    if replace then
        replaced[plate] = true
        S.SyncQuestie(plate, true)
    elseif replaced[plate] then
        replaced[plate] = nil
        S.SyncQuestie(plate, false)
    end
end



--- Sichtbarkeit eines Eintrags herstellen (Symbol nur an unsichtbaren Gegner-Plaketten mit Quest-Bezug)
local function show(plate, e)
    local share = (on and e.want and e.unit ~= nil) and hiddenShare(e) or nil
    local want = share ~= nil
    if want then
        if not e.f then e.f = QuestFar.BuildIcon(plate) end
        local f = e.f
        f:ClearAllPoints()
        f:SetPoint("CENTER", plate, "CENTER", 0, 0)
        local okL, lvl = pcall(e.uf.GetFrameLevel, e.uf)
        lvl = okL and Compat.Num(lvl) or 0
        f:SetFrameLevel(lvl + QuestFar.LEVEL)
        QuestFar.StyleIcon(f, e.kind, qcfg)
        f:SetAlpha(qcfg.alpha * share)
        f:Show()
        e.shown = true
        if qcfg.pulse or share < 1 or ns.Plates.TargetAlpha(e.uf) ~= 0 then ns.NameplateStyle.WakeDriver() end
    elseif e.f then
        e.f:Hide()
        e.shown = false
    else
        e.shown = false
    end
    syncQuestie(plate, want and e.kind ~= nil)
end

--- Quest-Bezug einer Einheit neu auswerten (Hinzufuegen, Questlog)
local function evaluate(unit)
    local plate, uf = plateFor(unit)
    if not plate then return end
    local e = entries[plate]
    if not e then
        e = {}
        entries[plate] = e
    end
    e.unit, e.uf = unit, uf
    byUnit[unit] = plate
    local group = ns.Plates.GroupOf(unit)
    if on and group == "enemies" and testKind then
        local kind = testKind
        if kind == "mix" then
            local n = tonumber(unit:match("(%d+)$")) or 0
            kind = QuestFar.MIX[n % #QuestFar.MIX + 1]
        end
        e.want, e.kind = true, (kind ~= "!" and kind) or nil
    elseif on and group == "enemies" then
        local okQ, want, kind = pcall(ns.NameplateStyle.QuestSymbol, unit)
        e.want, e.kind = okQ and want == true, okQ and kind or nil
    else
        e.want, e.kind = false, nil
    end
    show(plate, e)
end

local function drop(unit)
    local plate = byUnit[unit]
    byUnit[unit] = nil
    local e = plate and entries[plate]
    if not e then return end
    e.unit, e.want, e.kind = nil, false, nil
    show(plate, e)
end

local function scan()
    if not (C_NamePlate and type(C_NamePlate.GetNamePlates) == "function") then return end
    local ok, list = pcall(C_NamePlate.GetNamePlates)
    if not ok or type(list) ~= "table" then return end
    for _, plate in ipairs(list) do
        local unit = field(plate, "namePlateUnitToken") or field(plate, "unitToken")
        if type(unit) == "string" and not Compat.IsSecret(unit) then evaluate(unit) end
    end
end

local function hideAll()
    for plate, e in pairs(entries) do
        if e.f then e.f:Hide() end
        e.shown = false
        if replaced[plate] then syncQuestie(plate, false) end
    end
end

--- Einstellungen neu lesen und anwenden (aus Style.Refresh, also nach jeder Profil-/Plaketten-Aenderung)
function QuestFar.Refresh()
    local npc = Nameplates.GetConfig()
    qcfg = npc.style.questFar
    local was = on
    on = active and Nameplates.QuestFarOn(npc)
    updateListeners(on)
    if not on then
        if was or next(replaced) then hideAll() end
        return
    end
    scan()
end

function QuestFar.IsOn() return on end

--- Testmodus: kind (siehe TEST_KINDS) oder nil/"off" beendet. Liefert true (laeuft), false (beendet) oder nil, Fehlerschluessel.
function QuestFar.SetTest(kind)
    if kind == nil or kind == "off" then
        if not testKind then return false end
        testKind = nil
        Nameplates.questFarTest = false
        Nameplates.Apply()
        ns.NameplateStyle.Refresh() -- Entfernungs-Alpha, QuestFar.Refresh
        ns.Print(L.NP_QF_TEST_OFF)
        return false
    end
    if not QuestFar.TEST_KINDS[kind] then return nil, "NP_QF_TEST_UNKNOWN" end
    testKind = kind
    Nameplates.questFarTest = true
    Nameplates.Apply()
    ns.NameplateStyle.Refresh()
    if not on then
        local npc = Nameplates.GetConfig()
        local reason = (not npc.enabled) and L.NP_QF_NEEDS_MODULE or L.NP_QF_TEST_BLOCKED
        testKind = nil
        Nameplates.questFarTest = false
        Nameplates.Apply()
        ns.NameplateStyle.Refresh()
        ns.Print(reason)
        return nil, "NP_QF_TEST_FAILED"
    end
    ns.Print(L.NP_QF_TEST_ON, L["NP_QF_TEST_KIND_" .. (kind == "!" and "excl" or kind)])
    return true
end
function QuestFar.TestKind() return testKind end

--- sichtbares Fern-Symbol einer Plakette oder nil (Diagnose/Tests)
function QuestFar.IconOf(plate)
    local e = entries[plate]
    return e and e.shown and e.f or nil
end

--- Diagnose: verfolgte Plaketten, davon mit Quest-Bezug, davon gerade mit Symbol
function QuestFar.Counts()
    local n, quest, shown = 0, 0, 0
    for _, e in pairs(entries) do
        if e.unit then
            n = n + 1
            if e.want then quest = quest + 1 end
            if e.shown then shown = shown + 1 end
        end
    end
    return n, quest, shown
end

-- Am gemeinsamen Treiber (Style.lua): Atmen und Gegenblende waehrend B7 eine Plakette ein-/ausblendet; ruht sonst
ns.NameplateStyle.AddStepper(function(t)
    if not (on and qcfg) then return false end
    local busy = false
    local b = qcfg.pulse and QuestFar.Breath(t) or 1
    for plate, e in pairs(entries) do
        if e.shown and e.f then
            local share = hiddenShare(e)
            if share == nil then
                show(plate, e) -- Plakette ganz eingeblendet: Symbol weg
            else
                e.f:SetAlpha((e.f.baseAlpha or 1) * b * share)
                if qcfg.pulse or share < 1 or ns.Plates.TargetAlpha(e.uf) ~= 0 then busy = true end
            end
        end
    end
    return busy
end)

-- Sichtbarkeit folgt Plates.lua (B7: Ziel, Bedingungen, Ein-/Ausblenden)
ns.Plates.AddListener(function(uf)
    if not on then return end
    for plate, e in pairs(entries) do
        if e.uf == uf then show(plate, e) end
    end
end)

-- Ereignisse (nur angemeldet, solange die Fernsicht wirkt; Muster updateListeners in Style.lua) -----------------------
local function onAdded(_, unit)
    if not on or type(unit) ~= "string" then return end
    evaluate(unit)
    -- Questie legt seine Ziel-Daten im selben Ereignis an (Reihenfolge offen): kurz danach erneut
    C_Timer.After(QuestFar.RECHECK, function() if on and byUnit[unit] then evaluate(unit) end end)
end
local function onRemoved(_, unit)
    if type(unit) == "string" then drop(unit) end
end

local questPending = false
local function questRefresh()
    questPending = false
    if on then scan() end
end
local function onQuest()
    if not on or questPending then return end
    questPending = true
    C_Timer.After(QuestFar.QUEST_DELAY, questRefresh)
    C_Timer.After(QuestFar.QUEST_LATE, function() if not questPending and on then scan() end end)
end
local LISTEN = { { "NAME_PLATE_UNIT_ADDED", onAdded }, { "NAME_PLATE_UNIT_REMOVED", onRemoved },
    { "QUEST_LOG_UPDATE", onQuest }, { "UNIT_QUEST_LOG_CHANGED", onQuest }, { "QUEST_ACCEPTED", onQuest },
    { "QUEST_TURNED_IN", onQuest }, { "QUEST_REMOVED", onQuest } }
local listening = false
function updateListeners(want)
    want = want and true or false
    if want == listening then return end
    listening = want
    for _, e in ipairs(LISTEN) do
        if want then Compat.TryOn(e[1], e[2]) else ns.Off(e[1], e[2]) end
    end
end
function QuestFar.IsListening() return listening end

ns.RegisterModule("nameplatequestfar", {
    OnEnable = function()
        active = true
        QuestFar.Refresh()
    end,
    OnDisable = function()
        active = false
        QuestFar.Refresh()
    end,
})

-- Slash: /lucid nameplates far on|off|debug ------------------------------------------------------------------------
Nameplates.sub.far = function(arg)
    local a = type(arg) == "string" and arg:lower() or ""
    local t = a:match("^test%s*(%S*)")
    if t then
        if t == "" then t = testKind and "off" or "mix" end
        local _, code = QuestFar.SetTest(t)
        if code == "NP_QF_TEST_UNKNOWN" then ns.Print(L.NP_QF_TEST_USAGE) end
        return
    end
    if a == "on" or a == "an" or a == "off" or a == "aus" then
        local want = (a == "on" or a == "an")
        if not Nameplates.Set("style.questFar.enabled", want) then
            ns.Print(L.NP_VALUE_INVALID)
            return
        end
        ns.Print(want and L.NP_QF_ENABLED or L.NP_QF_DISABLED)
        if want and not Nameplates.GetConfig().enabled then ns.Print(L.NP_QF_NEEDS_MODULE) end
        return
    end
    local npc = Nameplates.GetConfig()
    local n, quest, shown = QuestFar.Counts()
    local blocker = ns.NameplateStyle.Conflict()
    ns.Print(L.NP_QF_STATUS, npc.style.questFar.enabled and L.NP_ON or L.NP_OFF, on and L.NP_YES or L.NP_NO,
        npc.enabled and L.NP_YES or L.NP_NO, blocker and blocker:gsub("|", "||") or "-", n, quest, shown,
        tostring(npc.style.questFar.distance), (npc.radius.enabled and ("%g"):format(npc.radius.yards)) or "-")
end

ns.AddHelp("HELP_NAMEPLATES_FAR")
