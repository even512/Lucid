-- Chat-Glass (Spec 3.4): der Blizzard-Chat bleibt die Basis (kompatibel zu anderen Chat-Addons), Lucid nimmt
-- ihm nur die Optik und laesst Nachrichten einzeln ausblenden.
--
--  Glass-Optik  Hintergrund/Rahmen-Texturen, Tabs, Knopf-Leiste je Fenster (ButtonFrame), Scrollleiste, Groessen-
--               griff und die Chat-Knoepfe (Menue, Kanaele, Sprachchat, Schnellbeitritt/Sozial) aller Chat-Fenster
--               bilden ein Fader-Element (Glass.ID): Basis-Alpha 0, Maus ueber dem Chatbereich oder offene Eingabe
--               (State "typing") => jeder Teil zurueck auf seinen Ausgangswert (relativeAlpha, z. B. Hintergrund
--               mit der eingestellten Deckkraft), Ausblenden nach einstellbarer Verzoegerung.
--  Fade         natives Fading der Message-Frames: SetFading/SetTimeVisible/SetFadeDuration. Bei Maus darueber
--               oder offener Eingabe wird das Fading ausgesetzt (der Verlauf ist voll sichtbar), danach laufen die
--               Zeiten neu an. Abschalten stellt die vorherigen Werte je Fenster exakt wieder her.
-- Beide sind getrennt schaltbar (Profil-Abschnitt "chat"), Standard nach Installation: beides aus.
-- Kontrast  Kontur (outline none|thin|thick) und Schatten (shadow) der Chat-Schrift, unabhaengig von Glass und Fade, im
--           selben Profil-Abschnitt; umgesetzt in modules/Chat/Font.lua (Glass.Apply ruft ChatFont.Apply mit auf).
--
-- Taint: Chat-Frames sind nicht geschuetzt; trotzdem aendert Lucid nur Alpha (ueber den Fader) und die Fading-
-- Werte der Message-Frames. Achtung: SetFading/SetTimeVisible/SetFadeDuration auf Retail-Chatfenstern (Lua-Mixin)
-- schreiben Felder des Frames aus Addon-Code; uebliche Praxis vieler Chat-Addons, Chat-Frames sind nicht
-- geschuetzt - Taint-Log im Handtest pruefen. Blizzard blendet Tabs/Hintergrund selbst (FCF_FadeInChatFrame/FCF_FadeOutChatFrame,
-- UIFrameFade mit CHAT_FRAME_TAB_*_ALPHA). Lucid ueberschreibt diese Konstanten NICHT (globale Blizzard-Variablen
-- aus Addon-Code zu schreiben, macht sie tainted; jeder Blizzard-Pfad, der sie liest - auch der Chat-Eingabe-Pfad -
-- waere danach tainted). Stattdessen haelt der SetAlpha-Nachher-Hook des Faders (hooksecurefunc, je Frame) den
-- Lucid-Sollwert: Blizzard rechnet unveraendert, Lucid korrigiert nur das Ergebnis. Keine Hooks auf geschuetzte
-- Funktionen, keine Felder in Blizzard-Tabellen geschrieben. Das Eingabefeld (EditBox) selbst bleibt unberuehrt (Text,
-- Fokus, Skripte nur per HookScript beobachtet); nur seine Rahmen-/Kopf-Regionen (Left/Mid/Right, Header, ...) sind Teil
-- der Optik. Hintergrund: im Chat-Stil "classic" (Forever) bleibt die Eingabezeile dauerhaft sichtbar; mit Glass blenden
-- ihr Rahmen und Kopf aus und erscheinen bei Fokus (typing) bzw. Maus ueber dem Chatbereich. Die Fokus-Texturen
-- (FocusLeft/Mid/Right) steuert Blizzard selbst und bleiben ausgenommen.
-- Neue (temporaere) Fenster: Nachher-Hook auf FCF_OpenTemporaryWindow (hooksecurefunc) und Events.
local _, ns = ...
local Fader, State, Store, Compat = ns.Fader, ns.State, ns.Store, ns.Compat
local L = ns.L

local Glass = {}
ns.Glass = Glass

Glass.ID = "chat"              -- Fader-Element der Chat-Optik und Mouseover-Kennung des Chatbereichs
Glass.DEFAULTS = { glass = false, fade = false, time = 20, fadeDuration = 3, delay = 1, outline = "none", shadow = false }
Glass.OUTLINES = { none = true, thin = true, thick = true } -- erlaubte Werte fuer "outline" (Chat-Kontrast, Font.lua)
Glass.TIME_MIN, Glass.TIME_MAX = 1, 600      -- Sekunden, die eine Nachricht sichtbar bleibt
Glass.FADE_DURATION_MAX = 10                 -- Sekunden fuer das Ausblenden einer Nachricht
Glass.FADE_IN, Glass.FADE_OUT = 0.2, 0.5     -- Blende der Chat-Optik (volle Strecke)
Glass.MAX_WINDOWS = 64                       -- so viele Chat-Fenster werden hoechstens verwaltet

-- Texturen des Fensterrahmens (Name = Fenstername .. Suffix), zusaetzlich CHAT_FRAME_TEXTURES des Clients (nur gelesen)
Glass.FRAME_TEXTURES = {
    "Background", "TopLeftTexture", "BottomLeftTexture", "TopRightTexture", "BottomRightTexture",
    "LeftTexture", "RightTexture", "BottomTexture", "TopTexture",
}
-- weitere Teile je Fenster: per Name (Fenstername .. Suffix) bzw. per Feld des Fensters (nur gelesen)
Glass.FRAME_PARTS = { "Tab", "ButtonFrame", "ResizeButton" }
Glass.FRAME_KEYS = { "buttonFrame", "ScrollBar", "ScrollToBottomButton", "ResizeButton" }
-- Rahmen-/Kopf-Regionen der Eingabezeile (Name = Fenstername .. "EditBox" .. Suffix bzw. Feld der EditBox); fehlende
-- werden uebergangen. "Focus"-Teile (Blizzard blendet sie bei Fokus selbst) sind ausgenommen.
Glass.EDITBOX_PARTS = { "Left", "Mid", "Right", "Header", "HeaderSuffix", "Prompt" }
Glass.EDITBOX_KEYS = { "left", "mid", "right", "header", "headerSuffix", "prompt", "NineSlice", "Backdrop" }
-- Chat-Knoepfe ausserhalb der Fenster (Namen 12.x zuerst, aeltere als Fallback; fehlende werden uebergangen)
Glass.GLOBAL_CHROME = {
    "ChatFrameMenuButton", "ChatFrameChannelButton", "ChatFrameToggleVoiceDeafenButton",
    "ChatFrameToggleVoiceMuteButton", "QuickJoinToastButton", "FriendsMicroButton",
    "GeneralDockManagerOverflowButton", "CombatLogQuickButtonFrame_Custom",
}
-- zusaetzlich zum Mouseover-Bereich (Tabs der angedockten Fenster liegen dort)
Glass.GLOBAL_AREA = { "GeneralDockManager" }

local enabled = false   -- Modul aktiv (nach PLAYER_LOGIN)
local windows = {}      -- Message-Frames (ChatFrameN) in Fundreihenfolge
local chrome = {}       -- Frames/Texturen der Optik
local area = {}         -- Mouseover-Bereich; dieselbe Tabelle haelt der Fader (opts.mouseFrames), wird in place gefuellt
local chromeSet = {}    -- Frame -> true, wie beim Fader angemeldet
local registered = false
local saved = {}        -- Message-Frame -> { fading, time, duration } vor Lucid
local fadingOn = {}     -- Message-Frame -> zuletzt gesetztes SetFading

-- Einstellungen -------------------------------------------------------------------------------------
local function isNum(v, lo, hi) return type(v) == "number" and v == v and v >= lo and v <= hi end

--- Profil-Abschnitt "chat" pruefen (Import und Aendern). Liefert bereinigte Kopie oder nil, Detail.
function Glass.Validate(v)
    if type(v) ~= "table" then return nil, "type" end
    local out = {}
    for k, x in pairs(v) do
        if k == "glass" or k == "fade" or k == "shadow" then
            if type(x) ~= "boolean" then return nil, k end
        elseif k == "outline" then
            if type(x) ~= "string" or not Glass.OUTLINES[x] then return nil, k end
        elseif k == "time" then
            if not isNum(x, Glass.TIME_MIN, Glass.TIME_MAX) then return nil, k end
        elseif k == "fadeDuration" then
            if not isNum(x, 0, Glass.FADE_DURATION_MAX) then return nil, k end
        elseif k == "delay" then
            if not isNum(x, 0, Fader.MAX_TIME) then return nil, k end
        else
            x = nil -- unbekannte Felder fallen weg
        end
        if x ~= nil then out[k] = x end
    end
    return out
end

Store.RegisterSection("chat", {
    default = function() return {} end,
    validate = Glass.Validate,
})

--- wirksame Einstellungen (Profil > Glass.DEFAULTS), immer gueltig
function Glass.GetConfig()
    local stored
    if Store.db then
        local p = Store.GetActive()
        stored = p and p.chat
    end
    local clean = type(stored) == "table" and Glass.Validate(stored) or nil
    local cfg = {}
    for k, d in pairs(Glass.DEFAULTS) do
        local v = clean and clean[k]
        if v == nil then v = d end
        cfg[k] = v
    end
    return cfg
end

-- Fader-Einstellungen der Chat-Optik (eigene Config-Quelle, unabhaengig vom Abschnitt "elements")
local function chromeConfig()
    return {
        enabled = true, baseAlpha = 0, fadeIn = Glass.FADE_IN, fadeOut = Glass.FADE_OUT,
        delay = Glass.GetConfig().delay, clickThrough = false,
        conditions = { { state = "mouseover", alpha = 1 }, { state = "typing", alpha = 1 } },
    }
end

-- Fenster und Optik finden -------------------------------------------------------------------------
local function region(v)
    if type(v) == "table" and type(v.SetAlpha) == "function" and type(v.GetAlpha) == "function" then return v end
    return nil
end

local function walkUp(f, of)
    local p = f.GetParent and f:GetParent()
    for _ = 1, 32 do
        if p == nil then return false end
        if p == of then return true end
        p = p.GetParent and p:GetParent()
    end
    return false
end
-- Fehler (z. B. Secret Value in der Eltern-Kette) zaehlt konservativ als "Nachfahre": der Teil wird nicht angefasst
local function isDescendant(f, of)
    local ok, v = pcall(walkUp, f, of)
    return not ok or v == true
end

local function windowNames()
    local names, seen = {}, {}
    local function add(n)
        if type(n) == "string" and not seen[n] and #names < Glass.MAX_WINDOWS then
            seen[n] = true
            names[#names + 1] = n
        end
    end
    for i = 1, (NUM_CHAT_WINDOWS or 10) do add("ChatFrame" .. i) end
    if type(CHAT_FRAMES) == "table" then -- enthaelt auch temporaere Fenster
        for _, n in ipairs(CHAT_FRAMES) do add(n) end
    end
    return names
end

--- Namen aller Chat-Fenster (ChatFrame1..N und CHAT_FRAMES inkl. temporaerer), auch fuer den Chat-Kontrast (Font.lua)
Glass.WindowNames = windowNames

local function editBoxOf(name, f)
    return region(f.editBox) or region(_G[name .. "EditBox"])
end

local function isFocusPart(r)
    local ok, n = pcall(function() return r.GetName and r:GetName() end)
    return ok and type(n) == "string" and n:find("Focus", 1, true) ~= nil
end

--- Rahmen-/Kopf-Regionen der Eingabezeile eines Fensters (ohne Fokus-Texturen und ohne bereits unsichtbare Teile)
local function editBoxParts(name, box)
    local out, seen = {}, {}
    local function add(r)
        r = region(r)
        if not r or seen[r] or isFocusPart(r) then return end
        -- schon voellig transparente Teile haben nichts auszublenden (und ihr Ausgangswert waere 0)
        local ok, a = pcall(r.GetAlpha, r)
        a = ok and Compat.Num(a) or nil
        if a ~= nil and a <= 0 and not chromeSet[r] then return end -- eigene (von Lucid ausgeblendete) bleiben
        seen[r] = true
        out[#out + 1] = r
    end
    for _, s in ipairs(Glass.EDITBOX_PARTS) do add(_G[name .. "EditBox" .. s]) end
    for _, k in ipairs(Glass.EDITBOX_KEYS) do
        local ok, v = pcall(function() return box[k] end)
        if ok then add(v) end
    end
    if type(box.GetRegions) == "function" then -- uebrige Rahmen-Texturen/Beschriftungen (Namen variieren je Client)
        local ok, t = pcall(function() return { box:GetRegions() } end)
        if ok and type(t) == "table" then
            for _, r in ipairs(t) do add(r) end
        end
    end
    return out
end

--- Chat-Fenster, Optik und Mouseover-Bereich neu ermitteln. Liefert true, wenn sich die Optik geaendert hat.
function Glass.Scan()
    local wins, parts, areaList, seen, boxes = {}, {}, {}, {}, {}
    local boxParts = {} -- Rahmen-/Kopf-Regionen der Eingabezeilen (Kinder der EditBox, aber Teil der Optik)
    local function addPart(r)
        r = region(r)
        if r and not seen[r] then seen[r] = true; parts[#parts + 1] = r end
    end
    local function addArea(r)
        r = region(r)
        if r then areaList[#areaList + 1] = r end
    end
    local textures = {}
    for _, s in ipairs(Glass.FRAME_TEXTURES) do textures[#textures + 1] = s end
    if type(CHAT_FRAME_TEXTURES) == "table" then
        for _, s in ipairs(CHAT_FRAME_TEXTURES) do
            if type(s) == "string" and not s:find("EditBox", 1, true) then textures[#textures + 1] = s end
        end
    end
    for _, name in ipairs(windowNames()) do
        local f = region(_G[name])
        if f then
            wins[#wins + 1] = f
            for _, s in ipairs(textures) do addPart(_G[name .. s]) end
            for _, s in ipairs(Glass.FRAME_PARTS) do addPart(_G[name .. s]) end
            for _, k in ipairs(Glass.FRAME_KEYS) do addPart(f[k]) end
            local box = editBoxOf(name, f)
            if box then
                boxes[#boxes + 1] = box
                State.WatchEditBox(box)
                for _, r in ipairs(editBoxParts(name, box)) do boxParts[r] = true; addPart(r) end
            end
            addArea(f)
            addArea(_G[name .. "Tab"])
            addArea(f.buttonFrame or _G[name .. "ButtonFrame"])
            addArea(box)
        end
    end
    for _, n in ipairs(Glass.GLOBAL_CHROME) do addPart(_G[n]); addArea(_G[n]) end
    for _, n in ipairs(Glass.GLOBAL_AREA) do addArea(_G[n]) end

    -- aussortieren: Eingabefelder samt Inhalt, verbotene Frames, Frames anderer Lucid-Elemente (z. B. Katalog),
    -- Kinder anderer Optik-Teile (Alpha vererbt sich, sonst wirkte es waehrend einer Blende doppelt)
    local list = {}
    for _, r in ipairs(parts) do
        -- Secret-sicher (Compat.QueryBool): ist IsForbidden nicht eindeutig false, bleibt der Frame unberuehrt
        local skip = r.IsForbidden ~= nil and Compat.QueryBool(r, "IsForbidden") ~= false
        local own = Fader.OwnerOf(r)
        if own ~= nil and own ~= Glass.ID then skip = true end
        for _, box in ipairs(boxes) do
            if r == box or (isDescendant(r, box) and not boxParts[r]) then skip = true end
        end
        if not skip then
            for _, other in ipairs(parts) do
                if other ~= r and isDescendant(r, other) then skip = true break end
            end
        end
        if not skip then list[#list + 1] = r end
    end

    windows = wins
    for i = #area, 1, -1 do area[i] = nil end
    for i, r in ipairs(areaList) do area[i] = r end
    local changed = #list ~= #chrome
    for _, r in ipairs(list) do
        if not chromeSet[r] then changed = true end
    end
    chrome = list
    return changed
end

-- Fading der Nachrichten -------------------------------------------------------------------------------
local function revealed()
    return State.Get("typing") or State.Get("mouseover", Glass.ID)
end

-- Zahl aus obj:method() ohne Vergleich auf einem Secret Value (nil = nicht lesbar)
local function queryNum(obj, method)
    if type(obj[method]) ~= "function" then return nil end
    local ok, v = pcall(obj[method], obj)
    return ok and Compat.Num(v) or nil
end

local function fadeWindow(f, cfg, show)
    if not (f.SetFading and f.GetFading and f.SetTimeVisible and f.GetTimeVisible) then return end
    if not saved[f] then
        -- Ausgangswerte nur ueber Compat lesen; ist einer nicht lesbar (Secret/Fehler), bleibt das Fenster
        -- unberuehrt, denn exakt wiederherstellen liesse es sich dann nicht
        local fading, time = Compat.QueryBool(f, "GetFading"), queryNum(f, "GetTimeVisible")
        local duration = queryNum(f, "GetFadeDuration")
        if fading == nil or time == nil or (f.GetFadeDuration and duration == nil) then return end
        saved[f] = { fading = fading, time = time, duration = duration }
    end
    if queryNum(f, "GetTimeVisible") ~= cfg.time then f:SetTimeVisible(cfg.time) end
    if f.SetFadeDuration and queryNum(f, "GetFadeDuration") ~= cfg.fadeDuration then f:SetFadeDuration(cfg.fadeDuration) end
    local want = not show
    if fadingOn[f] ~= want then
        fadingOn[f] = want
        f:SetFading(want)
        -- Verlauf war voll sichtbar: Zeiten neu starten, damit er nicht schlagartig verschwindet
        if want and f.ResetAllFadeTimes then f:ResetAllFadeTimes() end
    end
end

local function restoreFading()
    for f, s in pairs(saved) do
        xpcall(function()
            f:SetTimeVisible(s.time)
            if s.duration ~= nil and f.SetFadeDuration then f:SetFadeDuration(s.duration) end
            f:SetFading(s.fading)
        end, geterrorhandler())
        saved[f], fadingOn[f] = nil, nil
    end
end

local function updateFading()
    local cfg = Glass.GetConfig()
    if not (enabled and cfg.fade) then
        restoreFading()
        return
    end
    local show = revealed()
    for _, f in ipairs(windows) do
        xpcall(fadeWindow, geterrorhandler(), f, cfg, show)
    end
end

-- Anwenden -------------------------------------------------------------------------------------------
local function unregisterChrome()
    if not registered then return end
    registered = false
    chromeSet = {}
    Fader.Unregister(Glass.ID)
end

--- Zustand an das aktive Profil angleichen (nach Aenderung, Profilwechsel, neuem Fenster)
function Glass.Apply()
    local cfg = Glass.GetConfig()
    local wantGlass = enabled and cfg.glass
    local active = enabled and (cfg.glass or cfg.fade)
    local changed = active and Glass.Scan()

    if wantGlass and #chrome > 0 then
        if not registered or changed then
            unregisterChrome()
            local ok = xpcall(function()
                Fader.Register(Glass.ID, chrome, nil, { config = chromeConfig, mouseFrames = area, relativeAlpha = true })
            end, geterrorhandler())
            registered = ok
            if ok then for _, r in ipairs(chrome) do chromeSet[r] = true end end
        else
            Fader.Refresh(Glass.ID)
        end
    else
        unregisterChrome()
    end
    -- Mouseover des Chatbereichs: nach dem Fader, weil Fader.Unregister die Beobachtung beendet
    if active then State.WatchMouseover(Glass.ID, area) else State.UnwatchMouseover(Glass.ID) end
    updateFading()
    -- Chat-Kontrast (Kontur/Schatten) mit denselben Ausloesern (neue Fenster, Profilwechsel, Modul an/aus)
    if ns.ChatFont then xpcall(ns.ChatFont.Apply, geterrorhandler(), enabled) end
end

--- true, solange das Chat-Modul aktiv ist
function Glass.IsEnabled() return enabled end

--- true, wenn die Optik gerade ueber den Fader gesteuert wird
function Glass.IsGlassActive() return registered end
--- angemeldete Optik-Teile (Diagnose/Tests)
function Glass.Chrome() return chrome end
function Glass.Windows() return windows end

--- eine Einstellung im aktiven Profil setzen (geprueft wie beim Import) und sofort anwenden.
--- Liefert true oder nil, "CHAT_VALUE_INVALID".
function Glass.Set(key, value)
    local p = Store.GetActive()
    local candidate = type(p.chat) == "table" and Store.DeepCopy(p.chat) or {}
    candidate[key] = value
    local clean = Glass.Validate(candidate)
    if not clean or clean[key] == nil then return nil, "CHAT_VALUE_INVALID" end
    p.chat = clean
    Glass.Apply()
    return true
end

-- Modul + Ereignisse ------------------------------------------------------------------------------
ns.RegisterModule("chat", {
    OnEnable = function()
        enabled = true
        Glass.Apply()
    end,
    OnDisable = function()
        enabled = false
        Glass.Apply() -- Optik und Fading zurueck auf den vorherigen Stand
    end,
})

local function rescan()
    if enabled then Glass.Apply() end
end

-- neue temporaere Fenster (Fluesterfenster u. a.): Nachher-Hook, die Blizzard-Funktion bleibt unveraendert
if type(FCF_OpenTemporaryWindow) == "function" and hooksecurefunc then
    hooksecurefunc("FCF_OpenTemporaryWindow", rescan)
end
Compat.TryOn("UPDATE_CHAT_WINDOWS", rescan)
Compat.TryOn("UPDATE_FLOATING_CHAT_WINDOWS", rescan)
ns.On("ADDON_LOADED", rescan) -- z. B. Blizzard_CombatLog (Filterleiste des Kampflogs)
ns.On("PLAYER_ENTERING_WORLD", rescan)

-- Maus/Eingabe: Fading aussetzen bzw. wieder starten (die Optik blendet der Fader selbst)
State.RegisterCallback(function(name, _, id)
    if not enabled then return end
    if name == "typing" or (name == "mouseover" and id == Glass.ID) then updateFading() end
end)

Store.RegisterCallback(function() rescan() end)

-- Slash: /lucid chat glass|fade on|off, /lucid chat time <sek> ------------------------------------
local function safe(s) return (tostring(s):gsub("|", "||")) end
local function num(n) return ("%g"):format(n) end
local ON_OFF = { on = true, an = true, ["1"] = true, off = false, aus = false, ["0"] = false }

local function printStatus()
    local cfg = Glass.GetConfig()
    ns.Print(L.CHAT_STATUS, cfg.glass and L.CHAT_ON or L.CHAT_OFF, cfg.fade and L.CHAT_ON or L.CHAT_OFF, num(cfg.time))
    ns.Print(L.CHAT_FONT_STATUS, L["CHAT_OUTLINE_" .. cfg.outline], cfg.shadow and L.CHAT_ON or L.CHAT_OFF)
end

ns.commands.chat = function(rest)
    local sub, arg = (rest or ""):match("^%s*(%S*)%s*(.-)%s*$")
    sub = sub:lower()
    if sub == "" then
        printStatus()
        ns.Print(L.HELP_CHAT_GLASS)
        ns.Print(L.HELP_CHAT_FADE)
        ns.Print(L.HELP_CHAT_TIME)
        ns.Print(L.HELP_CHAT_OUTLINE)
        ns.Print(L.HELP_CHAT_SHADOW)
        return
    end
    if sub == "outline" then
        local mode = arg:lower()
        if not Glass.OUTLINES[mode] or not Glass.Set("outline", mode) then
            ns.Print(L.CHAT_OUTLINE_INVALID, safe(arg))
            return
        end
        ns.Print(L.CHAT_OUTLINE_SET, L["CHAT_OUTLINE_" .. mode])
        return
    end
    if sub == "shadow" then
        local on = ON_OFF[arg:lower()]
        if on == nil then
            ns.Print(L.CHAT_ONOFF_INVALID, safe(arg))
            return
        end
        if not Glass.Set("shadow", on) then
            ns.Print(L.CHAT_VALUE_INVALID)
            return
        end
        ns.Print(on and L.CHAT_SHADOW_ON or L.CHAT_SHADOW_OFF)
        return
    end
    if sub == "glass" or sub == "fade" then
        local on = ON_OFF[arg:lower()]
        if on == nil then
            ns.Print(L.CHAT_ONOFF_INVALID, safe(arg))
            return
        end
        if not Glass.Set(sub, on) then
            ns.Print(L.CHAT_VALUE_INVALID)
            return
        end
        if sub == "glass" then
            ns.Print(on and L.CHAT_GLASS_ON or L.CHAT_GLASS_OFF)
            if on and not registered then ns.Print(L.CHAT_NO_FRAMES) end
        else
            ns.Print(on and L.CHAT_FADE_ON or L.CHAT_FADE_OFF, num(Glass.GetConfig().time))
        end
    elseif sub == "time" then
        local n = (arg:match("^%d+$") or arg:match("^%d+%.%d+$")) and tonumber(arg)
        if not n or not Glass.Set("time", n) then
            ns.Print(L.CHAT_TIME_INVALID, safe(arg), Glass.TIME_MIN, Glass.TIME_MAX)
            return
        end
        ns.Print(L.CHAT_TIME_SET, num(n))
        if not Glass.GetConfig().fade then ns.Print(L.CHAT_TIME_FADE_HINT) end
    else
        ns.Print(L.CHAT_UNKNOWN, safe(sub))
        ns.Print(L.HELP_CHAT_GLASS)
        ns.Print(L.HELP_CHAT_FADE)
        ns.Print(L.HELP_CHAT_TIME)
        ns.Print(L.HELP_CHAT_OUTLINE)
        ns.Print(L.HELP_CHAT_SHADOW)
    end
end

ns.AddHelp("HELP_CHAT_GLASS")
ns.AddHelp("HELP_CHAT_FADE")
ns.AddHelp("HELP_CHAT_TIME")
ns.AddHelp("HELP_CHAT_OUTLINE")
ns.AddHelp("HELP_CHAT_SHADOW")
