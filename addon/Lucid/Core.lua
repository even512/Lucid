-- Kern: Namespace, Locale, Event-Bus, Modul-Registry, Slash-Befehl /lucid.
local ADDON_NAME, ns = ...

ns.name = ADDON_NAME
do
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local v = getMeta and getMeta(ADDON_NAME, "Version")
    -- Aus dem Quellbaum (ohne Packager) bleibt der Platzhalter der TOC unersetzt: dann "dev".
    if type(v) ~= "string" or v == "" or v:find("@", 1, true) then v = "dev" end
    -- Der Packager setzt bei einem Tag v1.0.0 die Version mit fuehrendem "v" ein: fuer die Anzeige wegnehmen.
    v = v:gsub("^[vV](%d)", "%1")
    ns.version = v
end

-- Locale: Client-Sprache, fehlende Schluessel aus enUS, sonst der Schluessel selbst.
do
    local enUS = ns.Locales.enUS
    local active = ns.Locales[GetLocale()] or {}
    ns.L = setmetatable({}, {
        __index = function(_, key)
            local v = active[key]
            if v == nil then v = enUS[key] end
            if v == nil then v = key end
            return v
        end,
    })
end
local L = ns.L

-- ns.printSink: optionaler Mitschreiber (UI/CopyBox.lua); Print bleibt im Chat sichtbar und gibt die Zeile zusaetzlich weiter.
function ns.Print(fmt, ...)
    local msg = select("#", ...) > 0 and fmt:format(...) or fmt
    print("|cff9fd8ffLucid|r: " .. msg)
    local sink = ns.printSink
    if sink then pcall(sink, msg) end
end

-- Fehler eines Handlers stoppen nie die anderen; Meldung samt Stack geht an den Fehler-Handler des Clients.
-- Liefert true, wenn fn fehlerfrei lief.
local function safeCall(fn, ...)
    return (xpcall(fn, geterrorhandler(), ...))
end

-- Event-Bus: mehrere Handler pro Event, Reihenfolge = Anmeldereihenfolge.
-- Copy-on-write: On/Off ersetzen die Liste, die Verteilung laeuft ohne Kopie ueber die alte Liste.
-- active[fn] verhindert, dass ein waehrend der Verteilung abgemeldeter Handler noch aufgerufen wird.
local eventFrame = CreateFrame("Frame")
local handlers = {} -- event -> { list = {fn...}, active = {fn = true} }

function ns.On(event, fn)
    local entry = handlers[event]
    if not entry then
        eventFrame:RegisterEvent(event) -- wirft bei unbekanntem Event, bevor etwas gespeichert ist
        entry = { list = {}, active = {} }
        handlers[event] = entry
    end
    local list = { unpack(entry.list) }
    list[#list + 1] = fn
    entry.list = list
    entry.active[fn] = true
end

function ns.Off(event, fn)
    local entry = handlers[event]
    if not entry or not entry.active[fn] then return end
    local list = {}
    for _, f in ipairs(entry.list) do
        if f ~= fn then list[#list + 1] = f end
    end
    entry.list = list
    entry.active[fn] = nil
    if #list == 0 then
        handlers[event] = nil
        eventFrame:UnregisterEvent(event)
    end
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local entry = handlers[event]
    if not entry then return end
    local list, active = entry.list, entry.active
    for i = 1, #list do
        local fn = list[i]
        if active[fn] then safeCall(fn, event, ...) end
    end
end)

-- Modul-Registry: Module melden sich an, werden bei PLAYER_LOGIN in Anmeldereihenfolge aktiviert;
-- spaeter angemeldete Module sofort.
ns.modules = {}
local moduleOrder = {}
local loggedIn = false

function ns.EnableModule(id)
    local mod = ns.modules[id]
    if not mod or mod.enabled then return end
    mod.enabled = true
    -- Schlaegt OnEnable fehl, gilt das Modul als nicht aktiv (erneutes Aktivieren bleibt moeglich).
    if mod.OnEnable and not safeCall(mod.OnEnable, mod) then mod.enabled = false end
end

function ns.RegisterModule(id, mod)
    assert(type(id) == "string" and not ns.modules[id], "Lucid: Modul-id fehlt oder doppelt: " .. tostring(id))
    mod.id = id
    mod.enabled = false
    ns.modules[id] = mod
    moduleOrder[#moduleOrder + 1] = id
    if loggedIn then ns.EnableModule(id) end
    return mod
end

function ns.DisableModule(id)
    local mod = ns.modules[id]
    if not mod or not mod.enabled then return end
    mod.enabled = false
    if mod.OnDisable then safeCall(mod.OnDisable, mod) end
end

ns.On("ADDON_LOADED", function(_, name)
    if name ~= ADDON_NAME then return end
    LucidDB = LucidDB or {}
    ns.db = LucidDB
end)

ns.On("PLAYER_LOGIN", function()
    loggedIn = true
    for _, id in ipairs(moduleOrder) do ns.EnableModule(id) end
    ns.Print(L.LOADED, ns.version)
end)

-- Slash-Befehl. Module tragen eigene Befehle in ns.commands ein und ihre Hilfezeile per ns.AddHelp.
ns.helpLines = { "HELP_VERSION", "HELP_HELP" } -- Locale-Schluessel, Reihenfolge = Ausgabe

function ns.AddHelp(key) ns.helpLines[#ns.helpLines + 1] = key end

local commands = {
    version = function() ns.Print(L.VERSION, ns.version) end,
    help = function()
        ns.Print(L.HELP_HEADER)
        for _, key in ipairs(ns.helpLines) do ns.Print(L[key]) end
    end,
}
ns.commands = commands

SLASH_LUCID1 = "/lucid"
SlashCmdList.LUCID = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "" then cmd = "help" end
    local fn = commands[cmd]
    if not fn then
        ns.Print(L.UNKNOWN_COMMAND, cmd)
    elseif ns.CopyBox and ns.CopyBox.Wants(rest) then
        -- Probe-/Debug-Ausgaben zusaetzlich im Kopierfenster (Chat-Text laesst sich in WoW nicht kopieren)
        ns.CopyBox.Capture("/lucid " .. cmd .. (rest ~= "" and (" " .. rest) or ""), fn, rest)
    else
        fn(rest)
    end
end
