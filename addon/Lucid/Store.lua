-- Store: LucidDB (SavedVariables) mit Profilen, Schema-Version + Migration, Export/Import-String.
--
-- Aufbau:  LucidDB.schema               Schema-Version der Datenbank
--          LucidDB.profiles[name]       Profilinhalt; Abschnitte (z. B. "elements") melden Module per RegisterSection an
--          LucidDB.charProfile["Realm-Char"] = name   abweichendes Profil je Charakter (fehlt => "Default")
--
-- Export-String:  LUCID:<format>:<base64(payload)>:<adler32 von base64 als 8 Hex-Ziffern>
-- payload ist eine eigene, typisierte Serialisierung (nur Tabellen/Strings/Zahlen/Booleans). Der Import
-- parst sie zeichenweise mit Grenzen (Laenge, Tiefe, Knoten) und prueft danach jeden Abschnitt gegen sein
-- Schema. Es wird NIE Code ausgefuehrt (kein loadstring).
local _, ns = ...
local L = ns.L

local Store = {}
ns.Store = Store

Store.SCHEMA = 1            -- aktuelle Schema-Version (DB und Profilinhalt)
Store.FORMAT = 1            -- Version des Export-Containers
Store.DEFAULT = "Default"
Store.PREFIX = "LUCID"
Store.MAX_IMPORT = 262144   -- Zeichen (ein maximal volles Profil passt hinein, siehe Fader-Maxima)
Store.NAME_MAX = 48         -- Bytes
local MAX_DEPTH = 16
local MAX_NODES = 20000
Store.MAX_NODES = MAX_NODES

-- Migrationen: migrations[n] hebt die DB von n-1 auf n, profileMigrations[n] einen Profilinhalt
-- (laeuft fuer jedes gespeicherte Profil und fuer importierte Profile aelterer Version).
Store.migrations = {
    [1] = function(db)
        if type(db.profiles) ~= "table" then db.profiles = {} end
        if type(db.charProfile) ~= "table" then db.charProfile = {} end
    end,
}
Store.profileMigrations = {}

-- Abschnitte ------------------------------------------------------------------------------------
local sections, sectionOrder = {}, {}

--- Abschnitt im Profil anmelden. def.default() liefert den Startwert,
--- def.validate(v) liefert eine bereinigte Kopie oder nil, Detail (fuer den Import).
function Store.RegisterSection(key, def)
    assert(type(key) == "string" and not sections[key], "Lucid: Abschnitt fehlt oder doppelt: " .. tostring(key))
    assert(type(def) == "table" and type(def.default) == "function" and type(def.validate) == "function",
        "Lucid: Abschnitt braucht default und validate: " .. key)
    sections[key] = def
    sectionOrder[#sectionOrder + 1] = key
end

local function deepCopy(v)
    if type(v) ~= "table" then return v end
    local t = {}
    for k, x in pairs(v) do t[k] = deepCopy(x) end
    return t
end
Store.DeepCopy = deepCopy

--- neues Profil mit den Startwerten aller Abschnitte
function Store.NewProfile()
    local p = {}
    for _, key in ipairs(sectionOrder) do p[key] = sections[key].default() end
    return p
end

--- Profilinhalt gegen alle Abschnitte pruefen. Unbekannte Abschnitte fallen weg, fehlende bekommen
--- den Startwert. Liefert bereinigte Kopie oder nil, "IMPORT_INVALID", Detail.
function Store.SanitizeProfile(data)
    if type(data) ~= "table" then return nil, "IMPORT_INVALID", "profile" end
    local clean = {}
    for _, key in ipairs(sectionOrder) do
        local v = data[key]
        if v == nil then
            clean[key] = sections[key].default()
        else
            local ok, res, detail = pcall(sections[key].validate, v)
            if not ok or res == nil then return nil, "IMPORT_INVALID", key .. (detail and ("." .. detail) or "") end
            clean[key] = res
        end
    end
    return clean
end

-- Fehlertexte ------------------------------------------------------------------------------------
--- Fehlercode (+ optionales Argument, z. B. Profilname) als Text in Client-Sprache
function Store.ErrorText(code, arg)
    return (L[code]):format(tostring(arg or ""))
end

local function fail(code, arg) return nil, code, arg end

-- Namen ------------------------------------------------------------------------------------------
--- gueltiger Profilname (getrimmt) oder nil. Keine Steuerzeichen, kein "|" (Escape-Zeichen im Chat).
function Store.ValidName(name)
    if type(name) ~= "string" then return nil end
    name = name:match("^%s*(.-)%s*$")
    if name == "" or #name > Store.NAME_MAX or name:find("[%c|]") then return nil end
    return name
end

local function charKey()
    local n, r = UnitName and UnitName("player"), GetRealmName and GetRealmName()
    if type(n) ~= "string" or type(r) ~= "string" then return nil end
    return r .. "-" .. n
end
Store.CharKey = charKey

-- Callbacks: fn(reason) bei Wechsel oder Neuinhalt des aktiven Profils ------------------------
local callbacks = {}
function Store.RegisterCallback(fn) callbacks[#callbacks + 1] = fn end
local function notify(reason)
    for _, fn in ipairs(callbacks) do xpcall(function() fn(reason) end, geterrorhandler()) end
end

-- Entdeckungsliste (B5) --------------------------------------------------------------------------
-- LucidDB.discovered["Realm-Char"] = { seeded = bool, zones = { [uiMapID] = true }, areas = { [Gebietsname] = true } }
-- Charakter-Datum, kein Profilinhalt: wird nie exportiert und nie in ein Profil kopiert.
Store.DISCOVERED_MAX = 8000     -- Eintraege (zones + areas) je Charakter; darueber: nichts mehr eintragen, nichts loeschen
Store.DISCOVERED_KEY_MAX = 80   -- Bytes je Gebietsname

--- gueltiger Gebietsname: String, nicht leer, hoechstens 80 Bytes, keine Steuerzeichen
function Store.ValidAreaName(name)
    return type(name) == "string" and name ~= "" and #name <= Store.DISCOVERED_KEY_MAX and not name:find("%c")
end

--- gueltige Karten-ID: positive ganze Zahl
function Store.ValidMapId(id)
    return type(id) == "number" and id == id and id >= 1 and id % 1 == 0 and id < 2 ^ 31
end

--- Anzahl der Eintraege (zones + areas) eines Entdeckungs-Datensatzes
function Store.DiscoveredCount(entry)
    local n = 0
    if type(entry) == "table" then
        if type(entry.zones) == "table" then for _ in pairs(entry.zones) do n = n + 1 end end
        if type(entry.areas) == "table" then for _ in pairs(entry.areas) do n = n + 1 end end
    end
    return n
end

--- Struktur von LucidDB.discovered reparieren: Datensatz je Charakter muss eine Tabelle mit seeded (bool),
--- zones, areas sein; ungueltige Schluessel/Werte fallen weg, Fremdes (weitere Felder) bleibt unberuehrt.
--- Ueberzaehliges ueber DISCOVERED_MAX wird nicht geloescht, sondern nur nicht mehr erweitert (siehe DiscoveredCount).
function Store.RepairDiscovered(d)
    if type(d.discovered) ~= "table" then d.discovered = {} end
    for key, entry in pairs(d.discovered) do
        if type(key) == "string" then
            if type(entry) ~= "table" then
                d.discovered[key] = { seeded = false, zones = {}, areas = {} }
            else
                if type(entry.seeded) ~= "boolean" then entry.seeded = false end
                if type(entry.zones) ~= "table" then entry.zones = {} end
                if type(entry.areas) ~= "table" then entry.areas = {} end
                for id, v in pairs(entry.zones) do
                    if v ~= true or not Store.ValidMapId(id) then entry.zones[id] = nil end
                end
                for name, v in pairs(entry.areas) do
                    if v ~= true or not Store.ValidAreaName(name) then entry.areas[name] = nil end
                end
            end
        end
    end
end

--- Entdeckungs-Datensatz des aktuellen Charakters (wird angelegt) oder nil, wenn der Charakter unbekannt ist
function Store.GetDiscovered()
    local d = Store.db
    assert(d, "Lucid: Store vor ADDON_LOADED benutzt")
    local key = charKey()
    if not key then return nil end
    local entry = d.discovered[key]
    if type(entry) ~= "table" then
        entry = { seeded = false, zones = {}, areas = {} }
        d.discovered[key] = entry
    end
    return entry
end

-- Laden + Migration ------------------------------------------------------------------------------
local db

--- DB vorbereiten (bei ADDON_LOADED): migrieren und Struktur reparieren, ohne Fremdes zu loeschen.
function Store.Init(raw)
    db = raw
    local from = tonumber(db.schema) or 0
    if from > Store.SCHEMA then
        -- von einer neueren Lucid-Version gespeichert: nichts umbauen, nur das Noetigste sicherstellen
        ns.Print(L.DB_NEWER)
    else
        for n = from + 1, Store.SCHEMA do
            if Store.migrations[n] then Store.migrations[n](db) end
            if Store.profileMigrations[n] and type(db.profiles) == "table" then
                for _, p in pairs(db.profiles) do
                    if type(p) == "table" then Store.profileMigrations[n](p) end
                end
            end
        end
        db.schema = Store.SCHEMA
    end
    if type(db.profiles) ~= "table" then db.profiles = {} end
    if type(db.charProfile) ~= "table" then db.charProfile = {} end
    for name, p in pairs(db.profiles) do
        if type(name) ~= "string" or type(p) ~= "table" or Store.ValidName(name) ~= name then
            db.profiles[name] = nil   -- unzulaessiger Name (Steuerzeichen, "|", zu lang, unsauber getrimmt): verwerfen
        end
    end
    if not db.profiles[Store.DEFAULT] then db.profiles[Store.DEFAULT] = Store.NewProfile() end
    for _, p in pairs(db.profiles) do
        for _, key in ipairs(sectionOrder) do
            if p[key] == nil then p[key] = sections[key].default() end
        end
    end
    for key, name in pairs(db.charProfile) do
        if type(name) ~= "string" or not db.profiles[name] then db.charProfile[key] = nil end
    end
    Store.RepairDiscovered(db)
    Store.db = db
    return db
end

ns.On("ADDON_LOADED", function(_, name)
    if name ~= ns.name then return end
    Store.Init(ns.db or LucidDB)
end)

local function requireDb()
    assert(db, "Lucid: Store vor ADDON_LOADED benutzt")
    return db
end

-- Profile ----------------------------------------------------------------------------------------
function Store.GetActiveName()
    local d = requireDb()
    local key = charKey()
    local name = key and d.charProfile[key]
    if name and d.profiles[name] then return name end
    return Store.DEFAULT
end

function Store.GetActive()
    return requireDb().profiles[Store.GetActiveName()]
end

function Store.GetProfile(name)
    return requireDb().profiles[name]
end

function Store.ListProfiles()
    local out = {}
    for name in pairs(requireDb().profiles) do out[#out + 1] = name end
    table.sort(out)
    return out
end

--- Profil fuer den aktuellen Charakter waehlen ("Default" = keine eigene Zuordnung)
function Store.SetActive(name)
    local d = requireDb()
    if not d.profiles[name] then return fail("PROFILE_NOT_FOUND", Store.ValidName(name)) end
    local key = charKey()
    if not key then return fail("PROFILE_NO_CHAR") end
    local before = Store.GetActiveName()
    d.charProfile[key] = (name ~= Store.DEFAULT) and name or nil
    if before ~= name then notify("active") end
    return true
end

local function newName(name)
    local clean = Store.ValidName(name)
    if not clean then return fail("PROFILE_NAME_INVALID") end
    if requireDb().profiles[clean] then return fail("PROFILE_EXISTS", clean) end
    return clean
end

function Store.CreateProfile(name)
    local clean, code, arg = newName(name)
    if not clean then return nil, code, arg end
    requireDb().profiles[clean] = Store.NewProfile()
    return clean
end

--- Kopie von src unter neuem Namen dst
function Store.CopyProfile(src, dst)
    local d = requireDb()
    if not d.profiles[src] then return fail("PROFILE_NOT_FOUND", Store.ValidName(src)) end
    local clean, code, arg = newName(dst)
    if not clean then return nil, code, arg end
    d.profiles[clean] = deepCopy(d.profiles[src])
    return clean
end

function Store.RenameProfile(old, new)
    local d = requireDb()
    if old == Store.DEFAULT then return fail("PROFILE_DEFAULT_PROTECTED") end
    if not d.profiles[old] then return fail("PROFILE_NOT_FOUND", Store.ValidName(old)) end
    local clean, code, arg = newName(new)
    if not clean then return nil, code, arg end
    d.profiles[clean], d.profiles[old] = d.profiles[old], nil
    for key, name in pairs(d.charProfile) do
        if name == old then d.charProfile[key] = clean end
    end
    return clean
end

--- Profil loeschen; Charaktere, die es nutzen, fallen auf "Default" zurueck
function Store.DeleteProfile(name)
    local d = requireDb()
    if name == Store.DEFAULT then return fail("PROFILE_DEFAULT_PROTECTED") end
    if not d.profiles[name] then return fail("PROFILE_NOT_FOUND", Store.ValidName(name)) end
    local wasActive = Store.GetActiveName() == name
    d.profiles[name] = nil
    for key, n in pairs(d.charProfile) do
        if n == name then d.charProfile[key] = nil end
    end
    if wasActive then notify("active") end
    return true
end

--- Profil auf die Startwerte zuruecksetzen (Tabelle bleibt dieselbe, Verweise bleiben gueltig)
function Store.ResetProfile(name)
    local d = requireDb()
    local p = d.profiles[name]
    if not p then return fail("PROFILE_NOT_FOUND", Store.ValidName(name)) end
    for k in pairs(p) do p[k] = nil end
    for k, v in pairs(Store.NewProfile()) do p[k] = v end
    if Store.GetActiveName() == name then notify("reset") end
    return true
end

-- Serialisierung ---------------------------------------------------------------------------------
-- Wert   := "T" { Schluessel Wert } "E" | "S" <laenge> ":" <bytes> | "N" <zahl> ";" | "B0" | "B1"
-- Schluessel sind Strings oder Zahlen; Ausgabe ist sortiert (gleiche Daten => gleicher String).
local function numToStr(v)
    -- %d nur im 32-Bit-Bereich (Lua 5.1 im Client formatiert %d als long)
    if v == math.floor(v) and v > -2 ^ 31 and v < 2 ^ 31 then return string.format("%d", v) end
    return string.format("%.17g", v)
end

local function keyLess(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then return ta == "number" end
    return a < b
end

-- state.nodes zaehlt wie Deserialize jeden Wert/Schluessel; mehr als MAX_NODES waere nicht importierbar.
local function serialize(v, out, depth, seen, state)
    state.nodes = state.nodes + 1
    if state.nodes > MAX_NODES then error("zu viele Knoten") end
    local tv = type(v)
    if tv == "boolean" then
        out[#out + 1] = v and "B1" or "B0"
    elseif tv == "number" then
        if v ~= v or v == math.huge or v == -math.huge then error("Zahl nicht endlich") end
        out[#out + 1] = "N" .. numToStr(v) .. ";"
    elseif tv == "string" then
        out[#out + 1] = "S" .. #v .. ":" .. v
    elseif tv == "table" then
        if seen[v] or depth >= MAX_DEPTH then error("Zyklus oder zu tief") end
        seen[v] = true
        local keys = {}
        for k in pairs(v) do
            local tk = type(k)
            if tk ~= "string" and tk ~= "number" then error("Schluesseltyp " .. tk) end
            keys[#keys + 1] = k
        end
        table.sort(keys, keyLess)
        out[#out + 1] = "T"
        for _, k in ipairs(keys) do
            serialize(k, out, depth + 1, seen, state)
            serialize(v[k], out, depth + 1, seen, state)
        end
        out[#out + 1] = "E"
        seen[v] = nil
    else
        error("Typ " .. tv)
    end
end

--- Wert -> String (wirft bei nicht serialisierbaren Werten)
function Store.Serialize(v)
    local out = {}
    serialize(v, out, 0, {}, { nodes = 0 })
    return table.concat(out)
end

local CORRUPT = {}

--- String -> Wert oder nil (bei jedem Formfehler). Fuehrt keinen Code aus.
function Store.Deserialize(s)
    if type(s) ~= "string" then return nil end
    local pos, nodes, len = 1, 0, #s
    local function bad() error(CORRUPT, 0) end
    local readValue
    readValue = function(depth)
        nodes = nodes + 1
        if nodes > MAX_NODES or depth > MAX_DEPTH then bad() end
        local tag = s:sub(pos, pos)
        pos = pos + 1
        if tag == "B" then
            local c = s:sub(pos, pos)
            pos = pos + 1
            if c == "1" then return true elseif c == "0" then return false end
            bad()
        elseif tag == "N" then
            local e = s:find(";", pos, true)
            if not e or e - pos > 32 then bad() end
            local str = s:sub(pos, e - 1)
            pos = e + 1
            if not (str:match("^%-?%d+%.?%d*$") or str:match("^%-?%d+%.?%d*[eE][%-+]?%d+$")) then bad() end
            local n = tonumber(str)
            if not n or n ~= n or n == math.huge or n == -math.huge then bad() end
            return n
        elseif tag == "S" then
            local digits = s:match("^(%d+):", pos)
            if not digits or #digits > 7 then bad() end
            pos = pos + #digits + 1
            local n = tonumber(digits)
            if pos + n - 1 > len then bad() end
            local v = s:sub(pos, pos + n - 1)
            pos = pos + n
            return v
        elseif tag == "T" then
            local t = {}
            while true do
                if pos > len then bad() end
                if s:sub(pos, pos) == "E" then
                    pos = pos + 1
                    return t
                end
                local k = readValue(depth + 1)
                local tk = type(k)
                if (tk ~= "string" and tk ~= "number") or t[k] ~= nil then bad() end
                t[k] = readValue(depth + 1)
            end
        end
        bad()
    end
    local ok, v = pcall(function()
        local v = readValue(0)
        if pos ~= len + 1 then bad() end
        return v
    end)
    if not ok then return nil end
    return v
end

-- Base64 + Pruefsumme (nur Arithmetik, laeuft in Lua 5.1 ohne bit-Bibliothek) ------------------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_INDEX = {}
for i = 1, 64 do B64_INDEX[B64:byte(i)] = i - 1 end

function Store.Base64Encode(s)
    local out = {}
    for i = 1, #s, 3 do
        local a, b, c = s:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64
        out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
            .. (b and B64:sub(c3 + 1, c3 + 1) or "=") .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
    end
    return table.concat(out)
end

--- Base64 -> Bytes oder nil bei ungueltiger Eingabe
function Store.Base64Decode(s)
    if #s % 4 ~= 0 or not s:match("^[A-Za-z0-9+/]*=?=?$") then return nil end
    local out = {}
    for i = 1, #s, 4 do
        local q = { s:byte(i, i + 3) }
        local pad = 0
        local n = 0
        for j = 1, 4 do
            local idx = B64_INDEX[q[j]]
            if q[j] == 61 then -- "="
                if i + 3 ~= #s then return nil end
                pad = pad + 1
                idx = 0
            elseif pad > 0 then
                return nil
            end
            n = n * 64 + idx
        end
        local a, b, c = math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256
        if pad == 0 then out[#out + 1] = string.char(a, b, c)
        elseif pad == 1 then out[#out + 1] = string.char(a, b)
        elseif pad == 2 then out[#out + 1] = string.char(a)
        else return nil end
    end
    return table.concat(out)
end

--- Adler-32 als 8 Hex-Ziffern (Schutz gegen Abschneiden/Tippfehler, keine Authentisierung)
function Store.Checksum(s)
    local a, b = 1, 0
    for i = 1, #s do
        a = (a + s:byte(i)) % 65521
        b = (b + a) % 65521
    end
    return string.format("%04x%04x", b, a) -- zwei Haelften: %x ist im Client nur 32 Bit mit Vorzeichen
end

-- Export/Import ----------------------------------------------------------------------------------
--- Profil als Export-String oder nil, Code
function Store.ExportProfile(name)
    local p = requireDb().profiles[name]
    if not p then return fail("PROFILE_NOT_FOUND", Store.ValidName(name)) end
    local ok, payload = pcall(Store.Serialize, { kind = "profile", v = Store.SCHEMA, name = name, data = p })
    if not ok then return fail("EXPORT_FAILED") end
    local body = Store.Base64Encode(payload)
    local str = Store.PREFIX .. ":" .. Store.FORMAT .. ":" .. body .. ":" .. Store.Checksum(body)
    -- nie einen String ausgeben, den der eigene Import ablehnen wuerde
    if #str > Store.MAX_IMPORT then return fail("EXPORT_FAILED") end
    return str
end

--- Export-String pruefen und entpacken. Liefert { name = vorgeschlagener Name|nil, data = bereinigtes Profil }
--- oder nil, Code, Detail.
function Store.DecodeImport(str)
    if type(str) ~= "string" then return fail("IMPORT_EMPTY") end
    if #str > Store.MAX_IMPORT then return fail("IMPORT_TOO_LONG") end
    str = str:gsub("%s+", "")
    if str == "" then return fail("IMPORT_EMPTY") end
    local prefix, format, body, sum = str:match("^(%a+):(%d+):([A-Za-z0-9+/=]+):(%x+)$")
    if prefix ~= Store.PREFIX or #sum ~= 8 then return fail("IMPORT_FORMAT") end
    if tonumber(format) ~= Store.FORMAT then
        return fail(tonumber(format) > Store.FORMAT and "IMPORT_NEWER" or "IMPORT_FORMAT")
    end
    if Store.Checksum(body) ~= sum:lower() then return fail("IMPORT_CHECKSUM") end
    local payload = Store.Base64Decode(body)
    if not payload then return fail("IMPORT_CORRUPT") end
    local env = Store.Deserialize(payload)
    if type(env) ~= "table" or env.kind ~= "profile" or type(env.data) ~= "table"
        or type(env.v) ~= "number" or env.v < 1 or env.v % 1 ~= 0 then
        return fail("IMPORT_CORRUPT")
    end
    if env.v > Store.SCHEMA then return fail("IMPORT_NEWER") end
    local data = env.data
    for n = env.v + 1, Store.SCHEMA do
        if Store.profileMigrations[n] then
            if not pcall(Store.profileMigrations[n], data) then return fail("IMPORT_CORRUPT") end
        end
    end
    local clean, code, detail = Store.SanitizeProfile(data)
    if not clean then return nil, code, detail end
    return { name = Store.ValidName(env.name), data = clean }
end

--- Export-String als Profil uebernehmen. name: Zielname (Standard: Name aus dem String, sonst "Import").
--- overwrite: vorhandenes Profil ersetzen. Liefert den Profilnamen oder nil, Code, Detail.
function Store.ImportProfile(str, name, overwrite)
    local d = requireDb()
    local res, code, detail = Store.DecodeImport(str)
    if not res then return nil, code, detail end
    local target
    if name ~= nil then
        target = Store.ValidName(name)
        if not target then return fail("PROFILE_NAME_INVALID") end
    else
        target = res.name or "Import"
    end
    local existing = d.profiles[target]
    if existing and not overwrite then return fail("PROFILE_EXISTS", target) end
    if existing then
        for k in pairs(existing) do existing[k] = nil end
        for k, v in pairs(res.data) do existing[k] = v end
        if Store.GetActiveName() == target then notify("import") end
    else
        d.profiles[target] = res.data
    end
    return target
end
