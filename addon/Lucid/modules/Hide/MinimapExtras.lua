-- Minimap-Extras: Spielerpfeil, Questgebiete (Blobs) und POI-Pfeile zeichnet die Minimap-Engine selbst; sie folgen
-- dem Alpha des Minimap-Elements nicht und blieben bei Alpha 0 sichtbar. Seit 12.0.7 gibt es die Setter fuer
-- Pfeil-/Blip-Texturen nicht mehr (Forever ebenso), Blob-Ring-/Flaechen-Alpha wirkt im Client nicht.
-- Loesung (Vorgabe, im Client bestaetigt: Minimap:Hide() blendet Pfeil und Zonen sauber aus):
--  - Ist das Ausblenden wirklich bei (nahezu) 0 angekommen, versteckt Lucid die Minimap ganz (Minimap:Hide()).
--  - Beim Einblenden zuerst Minimap:Show() (bei Alpha ~0), danach blendet der Fader normal aufwaerts.
--  - Gezeigt wird nur, was Lucid selbst versteckt hat (weHid). War die Minimap schon versteckt (vom Spieler
--    ausgeschaltet), bleibt sie es; versteckt sie jemand, waehrend Lucid sie versteckt haelt, gilt das als
--    Wunsch des Spielers (kein Show mehr).
--  - Die Minimap ist kein geschuetzter Frame (Blizzard ruft in ToggleMinimap selbst Hide/Show); trotzdem: im
--    Kampf nie Hide, bei PLAYER_REGEN_DISABLED (vor dem Lockdown) sofort Show, nach Kampfende nachziehen.
--  - Zeigt Blizzard die Minimap selbst (Show, SetShown, Ladebildschirm), versteckt Lucid sie wieder, solange
--    ausgeblendet sein soll und kein Kampf ist (eigene Aufrufe laufen mit own-Flag => keine Rekursion).
--  - Mouseover einer versteckten Minimap: vor dem Hide merkt sich State das Rechteck (State.RememberRect).
--  Alles per Existenzpruefung und pcall; Zustandsabfragen ueber Compat (Secret Values).
local _, ns = ...
local Compat = ns.Compat

local MinimapExtras = {}
ns.MinimapExtras = MinimapExtras

-- Alpha, ab dem das Ausblenden als angekommen gilt (Fader-Genauigkeit EPS = 0.001)
MinimapExtras.HIDE_AT = 0.001

local alpha = 1         -- zuletzt gemeldetes Alpha des Minimap-Elements
local weHid = false     -- Lucid hat die Minimap versteckt (nur dann zeigt Lucid sie wieder)
local own = false       -- eigener Show/Hide-Aufruf laeuft (Hooks still)
local hookedMap         -- Minimap-Frame, an dem die Hooks haengen
local reported = false  -- Fehler schon einmal gemeldet

local function lockdown() return InCombatLockdown and Compat.Bool(InCombatLockdown()) end
local function inCombat() return (ns.State and ns.State.Get("combat")) or lockdown() end

local function minimap()
    local m = Minimap
    if type(m) == "table" and type(m.Show) == "function" and type(m.Hide) == "function" then return m end
    return nil
end

local function call(m, method)
    own = true
    local ok, err = pcall(m[method], m)
    own = false
    if not ok and not reported then
        reported = true
        geterrorhandler()(err)
    end
    return ok
end

-- soll die Minimap gerade versteckt sein? (Fade bei 0 angekommen, kein Kampf, kein Bearbeitungsmodus)
local function wantHidden()
    if alpha > MinimapExtras.HIDE_AT then return false end
    if inCombat() then return false end
    if ns.Fader and ns.Fader.IsEditMode() then return false end
    return true
end

local function show()
    local m = minimap()
    weHid = false
    if ns.State and ns.State.ForgetRect and m then ns.State.ForgetRect(m) end
    if m then call(m, "Show") end
end

local function hide()
    local m = minimap()
    if not m or lockdown() then return end
    -- nur eine sichtbar geschaltete Minimap verstecken: war sie schon aus (Spieler), bleibt Lucid draussen
    if Compat.QueryBool(m, "IsShown") ~= true then return end
    if ns.State and ns.State.RememberRect then ns.State.RememberRect(m) end
    if call(m, "Hide") then
        weHid = true
    elseif ns.State and ns.State.ForgetRect then
        ns.State.ForgetRect(m)
    end
end

-- fremdes Zeigen (Blizzard: Show/SetShown/OnShow, Ladebildschirm, ToggleMinimap): solange ausgeblendet sein soll
-- und kein Kampf ist, wieder verstecken
local function onForeignShow()
    if own then return end
    local m = minimap()
    -- doppelte Meldung (OnShow und Show-Hook desselben Aufrufs, schon wieder versteckt): nichts zu tun
    if not m or Compat.QueryBool(m, "IsShown") ~= true then return end
    weHid = false
    if wantHidden() then
        hide()
    elseif ns.State and ns.State.ForgetRect then
        ns.State.ForgetRect(m)
    end
end

-- fremdes Verstecken, waehrend Lucid sie versteckt haelt: Wunsch des Spielers => Lucid zeigt sie nie wieder
local function onForeignHide()
    if own or not weHid then return end
    weHid = false
    if ns.State and ns.State.ForgetRect then ns.State.ForgetRect(minimap()) end
end

--- Hooks anbringen (einmal je Minimap-Frame); beim Laden und vor jedem Schalten
function MinimapExtras.Hook()
    local m = minimap()
    if not m or hookedMap == m or not hooksecurefunc then return end
    hookedMap = m
    pcall(hooksecurefunc, m, "Show", onForeignShow)
    pcall(hooksecurefunc, m, "Hide", onForeignHide)
    if type(m.SetShown) == "function" then
        pcall(hooksecurefunc, m, "SetShown", function(_, on)
            if Compat.IsSecret(on) then return end
            if on then onForeignShow() else onForeignHide() end
        end)
    end
    -- Zeigen ueber C-Pfade, die die Lua-Methode nicht aufrufen
    if type(m.HookScript) == "function" then pcall(m.HookScript, m, "OnShow", onForeignShow) end
end

--- Alpha des Minimap-Elements melden (Fader opts.onAlpha, auch beim Abmelden mit dem Ausgangswert).
function MinimapExtras.Update(a)
    a = Compat.Num(a)
    if a then alpha = a end
    MinimapExtras.Hook()
    if wantHidden() then
        -- auch wenn Lucid sie versteckt glaubt, sie aber (ohne gemeldeten Pfad) wieder sichtbar ist
        local m = minimap()
        if not weHid or (m and Compat.QueryBool(m, "IsShown") == true) then
            weHid = false
            hide()
        end
    elseif weHid then
        show()
    end
end

--- true, solange Lucid die Minimap versteckt haelt
function MinimapExtras.IsHidden() return weHid end

MinimapExtras.Hook()

-- Kampfbeginn (vor dem Lockdown): sofort zeigen; Kampfende: nachziehen
ns.On("PLAYER_REGEN_DISABLED", function()
    if weHid then show() end
end)
ns.On("PLAYER_REGEN_ENABLED", function() MinimapExtras.Update(alpha) end)
ns.On("PLAYER_ENTERING_WORLD", function() MinimapExtras.Update(alpha) end)
