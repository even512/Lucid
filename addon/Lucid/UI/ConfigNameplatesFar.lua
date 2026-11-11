-- Reiter Plaketten, Ansicht "Quest-Fernsicht" (Nachtrag 2): Haken, Regler Groesse/Deckkraft/Reichweite, Atmen und Hof, dazu eine
-- Vorschau (dunkles Feld mit den vier Symbolen in der eingestellten Groesse/Deckkraft, atmet wie im Spiel) und Hinweise zum
-- Zusammenspiel mit Plaketten-Modul, Radius und Tiefe. Eigene Ansicht, weil "Aussehen" keinen Platz mehr hat.
-- Alles geht ueber Nameplates.SetMany (Tab.Apply, geprueft wie beim Import) und wirkt sofort; die Vorschau fasst keine echten
-- Plaketten an und nutzt dieselben Funktionen wie QuestFar.lua (BuildIcon/StyleIcon/Breath).
local _, ns = ...
local NP, W, L = ns.Nameplates, ns.Widgets, ns.L
local C = W.COLORS

local Far = {}
ns.NameplateFarView = Far

Far.PREVIEW_W, Far.PREVIEW_H = 300, 110
Far.KINDS = { "loot", "slay", "interact", false } -- false = "!"

local function qf() return NP.GetConfig().style.questFar end

function Far.Build(page, far)
    local Tab = ns.Config.Nameplates
    local x, y = 0, -4
    far.on = W.Check(far, L.UI_NPF_ON, function(v) Tab.Apply(page, { ["style.questFar.enabled"] = v }) end)
    far.on:SetPoint("TOPLEFT", x, y)
    W.Tooltip(far.on, function() return L.UI_NPF_ON, L.UI_NPF_ON_TIP end)
    far.intro = W.Text(far, "GameFontHighlightSmall", C.muted)
    far.intro:SetPoint("TOPLEFT", x + 4, y - 26)
    far.intro:SetWidth(400)
    far.intro:SetJustifyH("LEFT")
    far.intro:SetText(L.UI_NPF_INTRO)

    local function pct(v) return ("%d %%"):format(math.floor(v * 100 + 0.5)) end
    far.size = W.Slider(far, L.UI_NPF_SIZE, NP.QF_SIZE_MIN, NP.QF_SIZE_MAX, 1, 190,
        function(v) return ("%g"):format(v) end, function(v) Tab.Apply(page, { ["style.questFar.size"] = v }) end)
    far.size:SetPoint("TOPLEFT", x, -96)
    W.Tooltip(far.size.slider, function() return L.UI_NPF_SIZE, L.UI_NPF_SIZE_TIP end)
    far.alpha = W.Slider(far, L.UI_NPF_ALPHA, NP.QF_ALPHA_MIN, NP.QF_ALPHA_MAX, 0.05, 190, pct,
        function(v) Tab.Apply(page, { ["style.questFar.alpha"] = v }) end)
    far.alpha:SetPoint("TOPLEFT", x + 210, -96)
    W.Tooltip(far.alpha.slider, function() return L.UI_NPF_ALPHA, L.UI_NPF_ALPHA_TIP end)
    far.distance = W.Slider(far, L.UI_NPF_DISTANCE, NP.QF_DISTANCE_MIN, NP.QF_DISTANCE_MAX, 1, 400,
        function(v) return ("%g m"):format(v) end, function(v) Tab.Apply(page, { ["style.questFar.distance"] = v }) end)
    far.distance:SetPoint("TOPLEFT", x, -142)
    W.Tooltip(far.distance.slider, function()
        local limit = ns.Compat.isRetail and L.UI_NPF_DISTANCE_LIMIT_RETAIL or L.UI_NPF_DISTANCE_LIMIT_FOREVER
        return L.UI_NPF_DISTANCE, L.UI_NPF_DISTANCE_TIP .. "\n" .. limit
    end)
    far.pulse = W.Check(far, L.UI_NPF_PULSE, function(v) Tab.Apply(page, { ["style.questFar.pulse"] = v }) end)
    far.pulse:SetPoint("TOPLEFT", x, -190)
    W.Tooltip(far.pulse, function() return L.UI_NPF_PULSE, L.UI_NPF_PULSE_TIP end)
    far.halo = W.Check(far, L.UI_NPF_HALO, function(v) Tab.Apply(page, { ["style.questFar.halo"] = v }) end)
    far.halo:SetPoint("TOPLEFT", x + 210, -190)
    W.Tooltip(far.halo, function() return L.UI_NPF_HALO, L.UI_NPF_HALO_TIP end)
    -- Testmodus: alle Gegner in der Naehe gelten als Quest-Gegner (nur fuer die Sitzung)
    far.test = W.Button(far, L.UI_NPF_TEST, 180, function()
        ns.QuestFar.SetTest(ns.QuestFar.TestKind() and "off" or "mix")
        ns.Config.Refresh()
    end)
    far.test:SetPoint("TOPLEFT", x + 210, -4)
    W.Tooltip(far.test, function() return L.UI_NPF_TEST, L.UI_NPF_TEST_TIP end)

    -- Vorschau rechts: dunkles Feld (Spielwelt-Ersatz) mit den vier Symbolen
    local box = CreateFrame("Frame", nil, far)
    box:SetPoint("TOPLEFT", 440, -4)
    box:SetSize(Far.PREVIEW_W, Far.PREVIEW_H + 22)
    W.Fill(box, C.panel)
    W.Border(box, { C.line[1], C.line[2], C.line[3], 0.5 })
    local title = W.Text(box, "GameFontNormal", C.accent)
    title:SetPoint("TOPLEFT", 8, -5)
    title:SetText(L.UI_NPF_PREVIEW)
    local field = CreateFrame("Frame", nil, box)
    field:SetPoint("TOPLEFT", 6, -22)
    field:SetSize(Far.PREVIEW_W - 12, Far.PREVIEW_H - 6)
    W.Fill(field, { 0.30, 0.34, 0.26, 1 }) -- heller Waldboden: Kontrast wie draussen bei Tag
    far.icons = {}
    for i, kind in ipairs(Far.KINDS) do
        local f = ns.QuestFar.BuildIcon(field)
        f:SetPoint("CENTER", field, "LEFT", (Far.PREVIEW_W - 12) * (i - 0.5) / #Far.KINDS, 0)
        f.kind = kind or nil
        far.icons[i] = f
    end
    far.box = box
    -- Atmen in der Vorschau: eigenes OnUpdate nur solange die Ansicht sichtbar ist
    local t = 0
    box:SetScript("OnUpdate", function(_, dt)
        t = t + dt
        local c = qf()
        local b = c.pulse and ns.QuestFar.Breath(t) or 1
        for _, f in ipairs(far.icons) do f:SetAlpha((f.baseAlpha or 1) * b) end
    end)

    far.notes = W.Text(far, "GameFontHighlightSmall", C.muted)
    far.notes:SetPoint("TOPLEFT", x + 4, -230)
    far.notes:SetWidth(740)
    far.notes:SetJustifyH("LEFT")
end

--- Hinweise: was die Fernsicht gerade braucht bzw. veraendert (Modul, Fremd-Addon, Radius, Tiefe, Gegner ohnehin sichtbar)
function Far.Notes(npc, blocker)
    local out = {}
    local c = npc.style.questFar
    if blocker then out[#out + 1] = "|cffff9966" .. L.UI_NPF_BLOCKED:format(W.Plain(blocker)) .. "|r" end
    if not npc.enabled then out[#out + 1] = "|cffff9966" .. L.UI_NPF_NEEDS_MODULE .. "|r" end
    if npc.enemies.baseShow then out[#out + 1] = L.UI_NPF_BASESHOW end
    if npc.radius.enabled then
        out[#out + 1] = L.UI_NPF_RADIUS:format(("%g"):format(npc.radius.yards), ("%g"):format(c.distance))
        if npc.style.enabled and npc.style.depth.enabled then out[#out + 1] = L.UI_NPF_DEPTH end
    else
        out[#out + 1] = L.UI_NPF_NORADIUS:format(("%g"):format(c.distance))
    end
    out[#out + 1] = L.UI_NPF_CLICKS
    return table.concat(out, "\n")
end

function Far.Refresh(page, far)
    local npc = NP.GetConfig()
    local c = npc.style.questFar
    far.on:SetValue(c.enabled)
    far.on:SetActive(true)
    far.size:SetValue(c.size)
    far.alpha:SetValue(c.alpha)
    far.distance:SetValue(c.distance)
    far.pulse:SetValue(c.pulse)
    far.halo:SetValue(c.halo)
    local testing = ns.QuestFar.TestKind() ~= nil
    for _, w in ipairs({ far.size, far.alpha, far.distance, far.pulse, far.halo }) do w:SetActive(c.enabled or testing) end
    far.test.active = testing
    if testing then pcall(far.test.LockHighlight, far.test) else pcall(far.test.UnlockHighlight, far.test) end
    far.test:SetText(testing and L.UI_NPF_TEST_STOP or L.UI_NPF_TEST)
    for _, f in ipairs(far.icons) do
        ns.QuestFar.StyleIcon(f, f.kind, c)
        f:Show()
    end
    far.notes:SetText(Far.Notes(npc, ns.NameplateStyle.Conflict()))
end
