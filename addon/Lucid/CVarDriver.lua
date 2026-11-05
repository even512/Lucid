-- Gemeinsamer CVar-Treiber mit Sicherung (aus B7/N1 herausgeloest, B8: Kamera). Eine Instanz je Modul
-- (Driver.New(schluessel, katalog)); Daten in LucidDB[schluessel]. Lucid schreibt nur die verwalteten CVars und nur, wenn das
-- Modul im aktiven Profil an ist (Nameplates und Kamera sind Instanzen).
--
--  Existenz   Jede CVar wird vor Gebrauch mit GetCVarInfo geprueft; fehlende (anderer Client) werden uebersprungen.
--  Kampf      Secure oder im Kampf gesperrte CVars (isSecure / lockedWhileInCombat) gehen bei InCombatLockdown in eine
--             Warteschlange und werden bei PLAYER_REGEN_ENABLED geschrieben. Alle anderen gehen sofort.
--  Sicherung  Blizzard-Wert (String) + owned-Marker werden VOR dem ersten Schreiben in LucidDB[schluessel] gesetzt und
--             erst nach erfolgreichem Zurueckschreiben geloescht (soll einen Absturz/Logout im Kampf ueberleben, sofern
--             der Client die SavedVariables noch schreibt; die Login-Pruefung des Moduls stellt dann wieder her). Account-/lokal gespeicherte CVars liegen in
--             .baseline/.owned, pro Charakter gespeicherte in .char["Realm-Name"].baseline/.owned.
--  Schreiben  pcall + Rueckgabepruefung + Zuruecklesen. Nach einem Fehlschlag wird der vorherige Wert zurueckgeschrieben;
--             die Sicherung faellt nur weg, wenn der Wert wieder dem Ausgang entspricht, sonst bleibt owned stehen.
--  CVAR_UPDATE  eigene Schreibzugriffe tragen ein Selbstschreib-Flag; fremde Aenderungen an verwalteten CVars
--             (Taste V, Blizzard-Optionen) werden nur gezaehlt, Lucid gewinnt beim naechsten Apply.
local _, ns = ...
local Compat = ns.Compat

local Driver = {}
ns.CVarDriver = Driver

--- Neuen Treiber anlegen. key = Name des Datenabschnitts in LucidDB, catalog = Liste der verwalteten CVars.
function Driver.New(key, catalog)
    local CVars = { KEY = key }
    CVars.CATALOG = catalog
    local MANAGED = {}
    for _, n in ipairs(CVars.CATALOG) do MANAGED[n] = true end
    CVars.MANAGED = MANAGED

    local pending = {}      -- name -> Sollwert (String), wartet auf Ende der Kampfsperre
    local selfWrite = false -- true waehrend Lucid selbst schreibt (CVAR_UPDATE-Unterscheidung)
    local external = {}     -- name -> zuletzt gesehener Fremdwert (nur Diagnose)
    local externalCount = 0
    local failedFor = {}    -- name -> { want, was }: dauerhaft gescheiterter Schreibversuch (nicht bei jedem Wechsel wiederholen)
    local lastResult = {}   -- name -> "ok" | "queued" | "failed:<grund>" | "missing" | "readonly" (nur Diagnose)
    
    -- Zugriff auf die Client-API ---------------------------------------------------------------------
    local function api(name)
        local c = _G.C_CVar
        if type(c) == "table" and type(c[name]) == "function" then return c[name] end
        local g = _G[name]
        if type(g) == "function" then return g end
        return nil
    end
    
    local function str(v)
        if v == nil or Compat.IsSecret(v) then return nil end
        return tostring(v)
    end
    
    --- Zustand einer CVar: { exists, value, default, secure, locked, readOnly, account, character } (rein lesend).
    --- GetCVarInfo: value, default, isStoredServerAccount, isStoredServerCharacter, lockedWhileInCombat, isSecure, isReadOnly.
    --- exists=false, wenn die CVar im Client unbekannt ist oder die Abfrage fehlschlaegt.
    function CVars.Info(name)
        local info = { name = name, exists = false }
        local getInfo = api("GetCVarInfo")
        if getInfo then
            local ok, a, b, c, d, e, f, g = pcall(getInfo, name)
            if ok then
                if type(a) == "table" then -- Tabellenform (Client-Dokumentation)
                    info.value, info.default = str(a.value), str(a.defaultValue)
                    info.account, info.character = a.isStoredServerAccount, a.isStoredServerCharacter
                    info.locked = a.lockedWhileInCombat or a.isLockedWhileInCombat
                    info.secure, info.readOnly = a.isSecure, a.isReadOnly
                else
                    info.value, info.default = str(a), str(b)
                    info.account, info.character, info.locked, info.secure, info.readOnly = c, d, e, f, g
                end
            end
        end
        if info.value == nil then
            local get = api("GetCVar")
            if get then
                local ok, v = pcall(get, name)
                if ok then info.value = str(v) end
            end
        end
        if info.default == nil then
            local getDef = api("GetCVarDefault")
            if getDef then
                local ok, v = pcall(getDef, name)
                if ok then info.default = str(v) end
            end
        end
        info.exists = info.value ~= nil
        info.secure = info.secure == true
        info.locked = (not Compat.IsSecret(info.locked)) and info.locked == true
        info.readOnly = info.readOnly == true
        info.character = info.character == true
        return info
    end
    
    --- aktueller Wert als String oder nil
    function CVars.Get(name)
        local get = api("GetCVar")
        if not get then return nil end
        local ok, v = pcall(get, name)
        if ok then return str(v) end
        return nil
    end
    
    local function same(a, b)
        if a == nil or b == nil then return false end
        if a == b then return true end
        local x, y = tonumber(a), tonumber(b)
        return x ~= nil and y ~= nil and math.abs(x - y) < 1e-4
    end
    CVars.Same = same
    
    --- Wert normalisieren: Boolean/Zahl/Zahlen-String (endlich, |x| < 1e9) => String, sonst nil
    local function norm(v)
        if v == true then return "1" end
        if v == false then return "0" end
        if type(v) == "string" then v = tonumber(v) end
        if type(v) == "number" and v == v and v > -1e9 and v < 1e9 then
            local s = ("%.4f"):format(v):gsub("0+$", ""):gsub("%.$", "")
            return s
        end
        return nil
    end
    CVars.Normalize = norm
    
    -- LucidDB[key] ----------------------------------------------------------------------------
    local function data()
        local db = ns.db or LucidDB
        if type(db) ~= "table" then return nil end
        if type(db[key]) ~= "table" then db[key] = {} end
        local d = db[key]
        if type(d.baseline) ~= "table" then d.baseline = {} end
        if type(d.owned) ~= "table" then d.owned = {} end
        if type(d.char) ~= "table" then d.char = {} end
        return d
    end
    
    --- { baseline, owned } fuer Account-/lokale CVars (character=false) bzw. den aktuellen Charakter
    local function slots(d, character)
        local key = character and ns.Store and ns.Store.CharKey and ns.Store.CharKey()
        if not key then return d end
        local c = d.char[key]
        if type(c) ~= "table" then c = {}; d.char[key] = c end
        if type(c.baseline) ~= "table" then c.baseline = {} end
        if type(c.owned) ~= "table" then c.owned = {} end
        return c
    end
    
    --- Namen aller CVars, die Lucid noch nicht zurueckgestellt hat (Account-Teil + aktueller Charakter)
    function CVars.OwnedNames()
        local d = data()
        local out = {}
        if d then
            local c = slots(d, true)
            for _, n in ipairs(CVars.CATALOG) do
                if d.owned[n] or c.owned[n] then out[#out + 1] = n end
            end
        end
        return out
    end
    
    function CVars.Baseline(name)
        local d = data()
        if not d then return nil end
        local c = slots(d, true)
        if c.baseline[name] ~= nil then return c.baseline[name] end
        return d.baseline[name]
    end
    
    -- Schreiben --------------------------------------------------------------------------------------
    --- Schreibversuch mit pcall, Rueckgabepruefung und Zuruecklesen. Liefert true oder false, Grund.
    local function rawWrite(name, value)
        local set = api("SetCVar")
        if not set then return false, "api" end
        selfWrite = true
        local ok, ret = pcall(set, name, value)
        selfWrite = false
        if not ok then return false, "error" end
        if ret == false then return false, "rejected" end
        if not same(CVars.Get(name), value) then return false, "mismatch" end
        return true
    end
    
    local function canWriteNow(info)
        if InCombatLockdown and InCombatLockdown() then return not (info.secure or info.locked) end
        return true
    end
    
    --- Eine CVar auf value setzen. Sichert vorher den Blizzard-Wert. Liefert Status:
    --- "ok" | "queued" | "failed" | "missing" | "readonly" | "nodb"
    function CVars.Write(name, value)
        if not MANAGED[name] then return "failed" end
        value = norm(value)
        if not value then
            lastResult[name] = "failed:value"
            return "failed"
        end
        local d = data()
        if not d then
            lastResult[name] = "nodb"
            return "nodb"
        end
        local info = CVars.Info(name)
        if not info.exists then
            lastResult[name] = "missing"
            return "missing"
        end
        if info.readOnly then
            lastResult[name] = "readonly"
            return "readonly"
        end
        if not canWriteNow(info) then
            pending[name] = value
            lastResult[name] = "queued"
            return "queued"
        end
        pending[name] = nil
        local s = slots(d, info.character)
        if same(info.value, value) then
            lastResult[name] = "ok" -- steht schon richtig: nichts schreiben, nichts sichern (Besitz bleibt, wie er ist)
            return "ok"
        end
        local ff = failedFor[name]
        if ff and same(ff.want, value) and same(ff.was, info.value) then
            lastResult[name] = "failed:repeat" -- gleicher Sollwert, gleicher Ausgangswert: Client nimmt ihn nicht an
            return "failed"
        end
        local hadBaseline = s.baseline[name] ~= nil
        if not hadBaseline then s.baseline[name] = info.value end
        s.owned[name] = true
        local ok, why = rawWrite(name, value)
        if not ok then
            -- der Client kann den Wert trotzdem geaendert haben (z. B. geklemmt): vorherigen Wert zurueckschreiben
            local now = CVars.Get(name)
            local clean = same(now, info.value)
            if not clean then clean = rawWrite(name, info.value) end
            if clean and not hadBaseline then s.baseline[name], s.owned[name] = nil, nil end
            -- nur dauerhafte Gruende sperren (Client klemmt/nimmt den Wert nicht an); Fehler/Ablehnung duerfen es erneut versuchen
            if why == "mismatch" then failedFor[name] = { want = value, was = info.value } end
            lastResult[name] = "failed:" .. tostring(why)
            return "failed"
        end
        failedFor[name] = nil
        lastResult[name] = "ok"
        return "ok"
    end
    
    --- Eine CVar auf den gesicherten Blizzard-Wert zurueckstellen. Liefert "ok" | "queued" | "failed".
    function CVars.RestoreOne(name)
        local d = data()
        if not d then return "ok" end
        pending[name] = nil
        failedFor[name] = nil
        local info = CVars.Info(name)
        local s = slots(d, info.exists and info.character or false)
        if not s.owned[name] then
            local c = slots(d, true)
            if c.owned[name] then s = c else return "ok" end
        end
        if not info.exists then
            s.owned[name], s.baseline[name] = nil, nil
            return "ok"
        end
        -- gespeicherter Wert ist Fremddatei-Input (SavedVariables): nur Zahlen im Bereich, sonst Standard des Clients
        local base = norm(s.baseline[name]) or norm(info.default)
        if base == nil or same(info.value, base) then
            s.owned[name], s.baseline[name] = nil, nil
            return "ok"
        end
        if not canWriteNow(info) then
            pending[name] = base
            lastResult[name] = "queued"
            return "queued"
        end
        local ok, why = rawWrite(name, base)
        if not ok then
            lastResult[name] = "failed:" .. tostring(why)
            return "failed"
        end
        s.owned[name], s.baseline[name] = nil, nil
        lastResult[name] = "ok"
        return "ok"
    end
    
    --- Sollwerte (name -> Wert) schreiben; verwaltete CVars ohne Sollwert, die Lucid besitzt, werden zurueckgestellt.
    --- Liefert Tabelle name -> Status.
    function CVars.Apply(desired)
        local out = {}
        local owned = {}
        for _, n in ipairs(CVars.OwnedNames()) do owned[n] = true end
        for _, name in ipairs(CVars.CATALOG) do
            local v = desired and desired[name]
            if v ~= nil then
                out[name] = CVars.Write(name, v)
            else
                pending[name] = nil
                if owned[name] then out[name] = CVars.RestoreOne(name) end
            end
        end
        return out
    end
    
    --- Alles zurueckstellen, was Lucid besitzt. Liefert true, wenn nichts mehr offen ist.
    function CVars.RestoreAll()
        local clean = true
        for _, name in ipairs(CVars.OwnedNames()) do
            if CVars.RestoreOne(name) ~= "ok" then clean = false end
        end
        return clean
    end
    
    --- Warteschlange abarbeiten (nach Ende der Kampfsperre). Liefert Anzahl erledigter Eintraege.
    function CVars.Flush()
        if InCombatLockdown and InCombatLockdown() then return 0 end
        local names = {}
        for name in pairs(pending) do names[#names + 1] = name end
        table.sort(names)
        local done = 0
        local owned = {}
        for _, n in ipairs(CVars.OwnedNames()) do owned[n] = true end
        for _, name in ipairs(names) do
            local value = pending[name]
            pending[name] = nil
            if owned[name] and same(value, CVars.Baseline(name)) then
                if CVars.RestoreOne(name) == "ok" then done = done + 1 end
            elseif CVars.Write(name, value) == "ok" then
                done = done + 1
            end
        end
        return done
    end
    
    function CVars.Pending()
        local out = {}
        for _, n in ipairs(CVars.CATALOG) do
            if pending[n] ~= nil then out[n] = pending[n] end
        end
        return out
    end
    
    --- gemerkte Fehlschlaege vergessen (Login, Profilwechsel, Zurueckstellen)
    function CVars.ClearFailures() failedFor = {} end
    
    function CVars.LastResult(name) return lastResult[name] end
    
    --- Fremdaenderungen seit dem Laden: Anzahl, letzter Wert je CVar
    function CVars.External() return externalCount, external end
    
    --- fuer /lucid <modul> probe: Schreiben ohne Sicherung (der Aufrufer stellt sofort zurueck)
    function CVars.ProbeWrite(name, value) return rawWrite(name, value) end
    
    --- Probe-Schutz: sichert den Wert (Baseline + owned) fuer die Dauer eines Testlaufs, damit ein Absturz mittendrin
    --- beim naechsten Login zurueckgestellt wird. Liefert eine Freigabefunktion fuer den Erfolgsfall (wirft nie),
    --- oder nil, wenn die CVar fehlt oder Lucid sie ohnehin besitzt.
    function CVars.Guard(name)
        local d = data()
        if not d or not MANAGED[name] then return nil end
        local info = CVars.Info(name)
        if not info.exists then return nil end
        local s = slots(d, info.character)
        if s.owned[name] then return nil end
        s.baseline[name], s.owned[name] = info.value, true
        return function()
            if same(CVars.Get(name), info.value) then s.baseline[name], s.owned[name] = nil, nil end
        end
    end
    
    Compat.TryOn("CVAR_UPDATE", function(_, name)
        if selfWrite or type(name) ~= "string" then return end
        -- CVar-Namen sind unempfindlich gegen Gross-/Kleinschreibung
        for _, n in ipairs(CVars.CATALOG) do
            if n:lower() == name:lower() then
                external[n] = CVars.Get(n)
                externalCount = externalCount + 1
                if type(CVars.OnExternal) == "function" then pcall(CVars.OnExternal, n, CVars.Get(n)) end -- Haken fuer das Modul
                return
            end
        end
    end)

    return CVars
end
