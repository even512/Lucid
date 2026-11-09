-- Chat-Kontrast: Kontur und Schatten fuer die Schrift der Chat-Fenster (Profil-Abschnitt "chat", Felder outline/shadow,
-- geprueft in Glass.Validate). Unabhaengig von Glass und Fade, Standard: beides aus.
--
--  Kontur   outline = "none" | "thin" | "thick" => SetFont(datei, groesse, "" | "OUTLINE" | "THICKOUTLINE") je Fenster.
--           Schriftdatei und -groesse bleiben, wie sie gerade sind (jedes Mal neu per GetFont gelesen); weitere Flags
--           (z. B. MONOCHROME) bleiben erhalten.
--  Schatten shadow = true => SetShadowOffset(2, -2) (Blizzards Standard ist bereits 1,-1, daher doppelt so weit) und SetShadowColor(0, 0, 0, 1).
-- Vor der ersten Aenderung merkt sich Lucid je Fenster die Flags bzw. Schattenwerte und stellt sie bei "none"/aus (und wenn
-- das Chat-Modul abgeschaltet wird) exakt wieder her. Nicht lesbare Werte (Secret, Fehler, ungueltige Schrift) => das
-- Fenster bleibt unberuehrt, denn exakt wiederherstellen liesse es sich dann nicht.
--
-- Fenster: dieselbe Liste wie Glass (ChatFrame1..N und CHAT_FRAMES inkl. temporaerer Fenster). GMChatFrame und der
-- Gemeinschafts-Chat bleiben bewusst unberuehrt. Ausloeser: Glass.Apply (Modul an/aus, Profil, FCF_OpenTemporaryWindow,
-- UPDATE_CHAT_WINDOWS, ...) ruft ChatFont.Apply auf; zusaetzlich Nachher-Hooks (hooksecurefunc) auf FCF_OpenNewWindow und
-- FCF_SetChatWindowFontSize (neue Fenster starten mit ChatFontNormal ohne Kontur; Groessenaenderung). Der Hook ruft nur
-- SetFont am Fenster, nie FCF-Funktionen (keine Schleife). Keine Blizzard-Globals oder -Tabellenfelder geschrieben.
local _, ns = ...
local Glass, Compat = ns.Glass, ns.Compat

local ChatFont = {}
ns.ChatFont = ChatFont

ChatFont.FLAGS = { none = "", thin = "OUTLINE", thick = "THICKOUTLINE" }
ChatFont.SHADOW = { x = 2, y = -2, r = 0, g = 0, b = 0, a = 1 }

local savedFlags = {}  -- Message-Frame -> Flags vor Lucid
local savedShadow = {} -- Message-Frame -> { x, y, r, g, b, a } vor Lucid

-- Fenster darf aus diesem Kontext angefasst werden (12.1: FrameScriptObject:CanBeAccessedInContext; fehlt sie => ja)
local function accessible(f)
    if type(f.CanBeAccessedInContext) ~= "function" then return true end
    local ok, v = pcall(f.CanBeAccessedInContext, f)
    return ok and Compat.Bool(v) == true
end

local function plain(v) return v ~= nil and not Compat.IsSecret(v) end

-- Schriftdatei, Groesse, Flags (nil, wenn nicht eindeutig lesbar)
local function readFont(f)
    if type(f.GetFont) ~= "function" or type(f.SetFont) ~= "function" then return nil end
    local ok, file, size, flags = pcall(f.GetFont, f)
    if not ok or not plain(file) or not plain(size) or Compat.IsSecret(flags) then return nil end
    if type(file) ~= "string" or file == "" or type(size) ~= "number" or size <= 0 then return nil end
    return file, size, type(flags) == "string" and flags or ""
end

-- Flags aus den Ausgangs-Flags: Kontur-Anteil ersetzen, uebrige Flags behalten
local function composeFlags(orig, outline)
    local rest = {}
    for tok in orig:gmatch("[^,%s]+") do
        local up = tok:upper()
        if up ~= "OUTLINE" and up ~= "THICKOUTLINE" then rest[#rest + 1] = tok end
    end
    if outline ~= "" then table.insert(rest, 1, outline) end
    return table.concat(rest, ", ")
end

local function applyOutline(f, mode)
    local file, size, flags = readFont(f)
    if not file then return end
    if mode == "none" then
        local orig = savedFlags[f]
        if orig == nil then return end
        savedFlags[f] = nil
        if flags ~= orig then f:SetFont(file, size, orig) end
        return
    end
    if savedFlags[f] == nil then savedFlags[f] = flags end
    local want = composeFlags(savedFlags[f], ChatFont.FLAGS[mode] or "")
    if flags ~= want then f:SetFont(file, size, want) end
end

-- Schatten { x, y, r, g, b, a } oder nil
local function readShadow(f)
    if not (f.GetShadowOffset and f.GetShadowColor and f.SetShadowOffset and f.SetShadowColor) then return nil end
    local ok, x, y = pcall(f.GetShadowOffset, f)
    if not ok then return nil end
    local okC, r, g, b, a = pcall(f.GetShadowColor, f)
    if not okC then return nil end
    if a == nil then a = 1 end
    local v = { x, y, r, g, b, a }
    for i = 1, 6 do
        if not plain(v[i]) or type(v[i]) ~= "number" then return nil end
    end
    return v
end

local function applyShadow(f, on)
    if on then
        local cur = readShadow(f)
        if not cur then return end
        if not savedShadow[f] then savedShadow[f] = cur end
        local S = ChatFont.SHADOW
        if cur[1] ~= S.x or cur[2] ~= S.y then f:SetShadowOffset(S.x, S.y) end
        if cur[3] ~= S.r or cur[4] ~= S.g or cur[5] ~= S.b or cur[6] ~= S.a then f:SetShadowColor(S.r, S.g, S.b, S.a) end
        return
    end
    local s = savedShadow[f]
    if not s then return end
    savedShadow[f] = nil
    f:SetShadowOffset(s[1], s[2])
    f:SetShadowColor(s[3], s[4], s[5], s[6])
end

--- Kontur/Schatten an das aktive Profil angleichen. active = Chat-Modul aktiv (aus => alles zurueck).
function ChatFont.Apply(active)
    if active == nil then active = Glass.IsEnabled() end
    local cfg = Glass.GetConfig()
    local mode = active and cfg.outline or "none"
    local shadow = active and cfg.shadow == true
    local frames, seen = {}, {}
    local function add(f)
        if type(f) == "table" and not seen[f] then
            seen[f] = true
            frames[#frames + 1] = f
        end
    end
    for _, name in ipairs(Glass.WindowNames()) do add(_G[name]) end
    for f in pairs(savedFlags) do add(f) end
    for f in pairs(savedShadow) do add(f) end
    for _, f in ipairs(frames) do
        if accessible(f) then
            xpcall(applyOutline, geterrorhandler(), f, mode)
            xpcall(applyShadow, geterrorhandler(), f, shadow)
        end
    end
end

--- true, wenn Lucid an diesem Fenster gerade Kontur bzw. Schatten gesetzt hat (Diagnose/Tests)
function ChatFont.IsTouched(f) return savedFlags[f] ~= nil, savedShadow[f] ~= nil end

local function reapply()
    if Glass.IsEnabled() then ChatFont.Apply(true) end
end

-- neue Fenster und Groessenaenderung: Nachher-Hooks, die Blizzard-Funktionen bleiben unveraendert
-- (FCF_OpenTemporaryWindow und UPDATE_CHAT_WINDOWS laufen schon ueber Glass.Apply)
if hooksecurefunc then
    for _, fn in ipairs({ "FCF_OpenNewWindow", "FCF_SetChatWindowFontSize" }) do
        if type(_G[fn]) == "function" then pcall(hooksecurefunc, fn, reapply) end
    end
end
