-- Minimap: Form (B6, M1). Profil-Abschnitt "minimap" (additiv, Schema bleibt 1):
--   shape (round | square | rect, Standard round = Blizzards runde Karte, es wird nichts angefasst),
--   rectRatio (3:2 | 4:3 | 16:9 | 2:3 | 3:4, Standard 3:2; nur bei rect), scale (50-200 %, Standard 100),
--   border (Stil aus modules/Minimap/Frames.lua oder "none", Standard schmal; nur bei eckiger Form sichtbar),
--   borderSize (50-200 %, Standard 100), northMarker (bool, Standard aus; Frame.lua),
--   elements (M6; Elements.lua): Sichtbarkeit je Element (always | hover | off) fuer zone, clock, calendar, mail, tracking,
--   difficulty, expansion, compartment, zoom, buttons, coords (Koordinaten unter der Karte, Blizzard ab 12.1.5);
--   zonePos/clockPos/coordsPos (blizzard | top | bottom: Lucids Text im Rahmen),
--   fontSize (8-24), bronze (bool: Schrift im Bronze-Ton).
--   button (bool, Standard an) und buttonAngle (Grad 0-360, Standard 225): Lucids eigener Minimap-Knopf (Button.lua).
--   ornament (bool, Standard aus), ornamentSize (50-200 %, Std 100), ornamentOffsetX/ornamentOffsetY (-40..40, Std 0;
--   positiv = rechts bzw. oben), ornamentAlpha (30-100 %, Std 85): Zonen-Ornament (Ornament.lua, nur rect 4:3). Alter
--   Bestand ohne die Felder bekommt die Standardwerte; das fruehere ornamentInset n (nach innen) wird zu offsetX = -n,
--   offsetY = -n und faellt danach weg. ornamentTop (bool, Standard an): Ornament auch ueber Sonne/Mond (GameTimeFrame).
-- Technik (Recherche zur Minimap):
--  - Der Minimap-Frame bleibt quadratisch; eine Masken-TGA (Media/minimap-*.tga, erzeugt von
--    scripts/gen-minimap-media.mjs) per Minimap:SetMaskTexture schneidet die Form aus. Rechteck = Maske schneidet ab,
--    SetHitRectInsets passt die Klickflaeche an.
--  - Forever setzt die Maske bei rotateMinimap selbst neu (Atlas); hooksecurefunc(Minimap, "SetMaskTexture") stellt
--    Lucids Maske wieder her (Rekursionsschutz per own-Flag).
--  - HybridMinimap und die Quest-/Archaeologie-Blob-Ringe nur per Existenzpruefung + pcall.
--  - GetMinimapShape wird nur definiert, wenn keine andere Funktion existiert, und beim Rueckweg zu "round" wieder entfernt.
--  - Groesse ueber Minimap:SetScale (nie an MinimapCluster/MinimapContainer: das gehoert dem Bearbeitungsmodus).
--  - Nichts im Kampf: Aenderungen warten auf PLAYER_REGEN_ENABLED. Bei "round" und Groesse 100 % ohne frueheren Eingriff
--    ruft Lucid nichts an der Minimap auf.
local ADDON_NAME, ns = ...
local Store, Compat, L = ns.Store, ns.Compat, ns.L

local MM = {}
ns.Minimap = MM

MM.SHAPES = { "round", "square", "rect" }
MM.RATIOS = { "3:2", "4:3", "16:9", "2:3", "3:4" }
MM.LIMITS = { scale = { 50, 200 }, borderSize = { 50, 200 }, fontSize = { 8, 24 },
    ornamentSize = { 50, 200 }, ornamentOffsetX = { -40, 40 }, ornamentOffsetY = { -40, 40 },
    ornamentAlpha = { 30, 100 } }
-- Elemente (M6)
MM.ELEMENT_KEYS = { "zone", "clock", "coords", "calendar", "mail", "tracking", "difficulty", "expansion", "compartment", "zoom", "buttons" }
MM.TEXT_ELEMENTS = { "zone", "clock", "coords" } -- Elemente mit eigener Lage (Lucids Text im Rahmen)
MM.VIS = { "always", "hover", "off" }
MM.POS = { "blizzard", "top", "bottom" }
-- Rahmenstile aus dem erzeugten Frames.lua (Ladereihenfolge der .toc) plus "none"
MM.BORDERS = {}
for _, name in ipairs((ns.MinimapFrames or {}).order or {}) do MM.BORDERS[#MM.BORDERS + 1] = name end
MM.BORDERS[#MM.BORDERS + 1] = "none"

local function set(list)
    local s = {}
    for _, k in ipairs(list) do s[k] = true end
    return s
end
local SHAPE_SET, RATIO_SET, BORDER_SET = set(MM.SHAPES), set(MM.RATIOS), set(MM.BORDERS)

--- Standardwerte (frische Kopie bei jedem Aufruf)
function MM.ElementDefaults()
    local e = { zonePos = "blizzard", clockPos = "blizzard", coordsPos = "blizzard", fontSize = 12, bronze = true }
    for _, k in ipairs(MM.ELEMENT_KEYS) do e[k] = "always" end
    return e
end

function MM.Defaults()
    return { shape = "round", rectRatio = "3:2", scale = 100, border = "schmal", borderSize = 100, northMarker = false,
        elements = MM.ElementDefaults(), button = true, buttonAngle = 225,
        ornament = false, ornamentSize = 100, ornamentOffsetX = 0, ornamentOffsetY = 0, ornamentAlpha = 85,
        ornamentTop = true }
end

local VIS_SET, POS_SET, ELEMENT_SET = set(MM.VIS), set(MM.POS), set(MM.ELEMENT_KEYS)

--- Abschnitt "elements" pruefen: vollstaendige bereinigte Kopie oder nil, Feldname
local function validateElements(v)
    if type(v) ~= "table" then return nil, "type" end
    local out = {}
    for k, x in pairs(v) do
        if ELEMENT_SET[k] then
            if type(x) ~= "string" or not VIS_SET[x] then return nil, k end
            out[k] = x
        elseif k == "zonePos" or k == "clockPos" or k == "coordsPos" then
            if type(x) ~= "string" or not POS_SET[x] then return nil, k end
            out[k] = x
        elseif k == "fontSize" then
            if type(x) ~= "number" or x ~= x then return nil, k end
            local r = MM.LIMITS.fontSize
            out.fontSize = math.floor(math.min(r[2], math.max(r[1], x)) + 0.5)
        elseif k == "bronze" then
            if type(x) ~= "boolean" then return nil, k end
            out.bronze = x
        end -- unbekannte Felder fallen weg
    end
    for k, d in pairs(MM.ElementDefaults()) do
        if out[k] == nil then out[k] = d end
    end
    return out
end

--- true, wenn ein Element vom Standard abweicht (Sichtbarkeit oder Lage); Schrift/Ton wirken nur mit eigener Lage
function MM.ElementsCustom(cfg)
    local e = cfg and cfg.elements
    if type(e) ~= "table" then return false end
    for _, k in ipairs(MM.ELEMENT_KEYS) do
        if e[k] ~= "always" then return true end
    end
    return e.zonePos ~= "blizzard" or e.clockPos ~= "blizzard" or e.coordsPos ~= "blizzard"
end

--- Profil-Abschnitt "minimap" pruefen (Import und Aendern). Liefert eine vollstaendige bereinigte Kopie
--- oder nil, Feldname. Unbekannte Felder fallen weg, fehlende bekommen den Standard.
function MM.Validate(v)
    if type(v) ~= "table" then return nil, "type" end
    local def, out = MM.Defaults(), {}
    local legacyInset -- frueheres ornamentInset (Migration)
    for k, x in pairs(v) do
        if k == "shape" then
            if type(x) ~= "string" or not SHAPE_SET[x] then return nil, k end
            out.shape = x
        elseif k == "rectRatio" then
            if type(x) ~= "string" or not RATIO_SET[x] then return nil, k end
            out.rectRatio = x
        elseif k == "scale" or k == "borderSize" or k == "ornamentSize" or k == "ornamentOffsetX" or k == "ornamentOffsetY"
            or k == "ornamentAlpha" then
            -- Zahl Pflicht, auf die Grenzen aus MM.LIMITS geklemmt und auf ganze Werte gerundet
            if type(x) ~= "number" or x ~= x then return nil, k end
            local r = MM.LIMITS[k]
            out[k] = math.floor(math.min(r[2], math.max(r[1], x)) + 0.5)
        elseif k == "border" then
            if type(x) ~= "string" or not BORDER_SET[x] then return nil, k end
            out.border = x
        elseif k == "elements" then
            local e, d = validateElements(x)
            if not e then return nil, "elements." .. tostring(d) end
            out.elements = e
        elseif k == "ornamentInset" then
            -- Migration: frueher ein Versatz nach innen (links + unten); ungueltige Altwerte fallen still weg
            if type(x) == "number" and x == x then legacyInset = x end
        elseif k == "ornament" then
            if type(x) ~= "boolean" then return nil, k end
            out.ornament = x
        elseif k == "ornamentTop" then
            if type(x) ~= "boolean" then return nil, k end
            out.ornamentTop = x
        elseif k == "northMarker" then
            if type(x) ~= "boolean" then return nil, k end
            out.northMarker = x
        elseif k == "button" then
            if type(x) ~= "boolean" then return nil, k end
            out.button = x
        elseif k == "buttonAngle" then
            if type(x) ~= "number" or x ~= x or x == math.huge or x == -math.huge then return nil, k end
            out.buttonAngle = x % 360
        end
    end
    if legacyInset then
        local r = MM.LIMITS.ornamentOffsetX
        local n = math.floor(math.min(r[2], math.max(r[1], -legacyInset)) + 0.5)
        if out.ornamentOffsetX == nil then out.ornamentOffsetX = n end
        if out.ornamentOffsetY == nil then out.ornamentOffsetY = n end
    end
    for k, d in pairs(def) do
        if out[k] == nil then out[k] = d end
    end
    return out
end

Store.RegisterSection("minimap", { default = MM.Defaults, validate = MM.Validate })

--- wirksame Einstellungen des aktiven Profils (immer gueltig; ungueltiger Bestand => Standardwerte)
function MM.GetConfig()
    local stored
    if Store.db then
        local p = Store.GetActive()
        stored = p and p.minimap
    end
    return (type(stored) == "table" and MM.Validate(stored)) or MM.Defaults()
end

-- Masken ------------------------------------------------------------------------------------------
local MEDIA = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\"
-- Rueckfall fuer Blizzards eigene Maske, falls kein Aufruf mitgelesen wurde: Forever setzt einen Atlas
-- (Camelot/Skin.lua), Retail nutzt die Engine-Maske.
local FALLBACK_MASK_FOREVER = "ui-hud-minimap-frame-generic-mask"
local FALLBACK_MASK_RETAIL = "Textures\\MinimapMask"

local function ratioParts(ratio)
    local b, h = tostring(ratio):match("^(%d+):(%d+)$")
    return tonumber(b), tonumber(h)
end

--- Pfad der Masken-Textur (ohne Endung) zu Form und Seitenverhaeltnis; nil bei "round"
function MM.MaskPath(shape, ratio)
    if shape == "square" then return MEDIA .. "minimap-square" end
    if shape == "rect" then
        local b, h = ratioParts(ratio)
        if b and h then return MEDIA .. "minimap-rect-" .. b .. "x" .. h end
    end
    return nil
end

--- Anteile (Breite, Hoehe) des sichtbaren Rechtecks am quadratischen Frame
function MM.Fractions(shape, ratio)
    if shape ~= "rect" then return 1, 1 end
    local b, h = ratioParts(ratio)
    if not b or not h or b == 0 or h == 0 then return 1, 1 end
    if b >= h then return 1, h / b end
    return b / h, 1
end

--- Einzug der Klickflaeche (links, oben, rechts, unten) bei Frame-Seitenlaenge size
function MM.Insets(cfg, size)
    local wf, hf = MM.Fractions(cfg.shape, cfg.rectRatio)
    local x, y = size * (1 - wf) / 2, size * (1 - hf) / 2
    return x, y, x, y
end

-- Zustand -----------------------------------------------------------------------------------------
local modEnabled = false
local own = false            -- eigener SetMaskTexture-Aufruf laeuft (Hook still)
local hooked                 -- Minimap-Frame, an dem der Hook haengt
local pending = false        -- Aenderung wartet auf Kampfende
local blizzMask              -- zuletzt von fremdem Code gesetzte Maske (Blizzard)
local overrides = 0          -- wie oft fremder Code Lucids Maske ueberschrieben hat (und Lucid sie wiederherstellte)
local maskTouched = false    -- Lucid hat die Maske gesetzt
local scaleTouched = false
local insetsTouched = false
local hybridTouched, hybridOrig = false, nil
local blobTouched, blobOrig = false, nil
local shapeFn                -- Lucids GetMinimapShape (nur gesetzt, solange es unsere ist)
local last = { shape = "round", ratio = "3:2", scale = 100, mask = nil, insets = { 0, 0, 0, 0 }, hybrid = "-", blobs = "-" }

MM.listeners = {}
--- fn(active, cfg) nach jedem angewendeten Zustand (active = eckige Form). Cleanup.lua haengt sich hier an.
function MM.OnApply(fn) MM.listeners[#MM.listeners + 1] = fn end

local function lockdown() return InCombatLockdown ~= nil and Compat.Bool(InCombatLockdown()) end
local function inCombat() return lockdown() or (ns.State ~= nil and ns.State.Get("combat") == true) end
MM.InCombat = inCombat

local function frame()
    local m = _G.Minimap
    if type(m) == "table" and type(m.SetMaskTexture) == "function" then return m end
    return nil
end

local function effective()
    return modEnabled and MM.GetConfig() or MM.Defaults()
end

--- Seitenlaenge des (quadratischen) Minimap-Frames, Rueckfall 140 (Blizzards Standard)
function MM.FrameSize(m)
    if type(m.GetWidth) == "function" then
        local ok, w = pcall(m.GetWidth, m)
        w = ok and Compat.Num(w) or nil
        if w and w > 0 then return w end
    end
    return 140 -- Blizzards Standardgroesse
end

local function setMask(m, tex)
    own = true
    local ok = pcall(m.SetMaskTexture, m, tex)
    own = false
    return ok
end

local function blizzardMask()
    return blizzMask or (Compat.isForever and FALLBACK_MASK_FOREVER or FALLBACK_MASK_RETAIL)
end

local function ensureHook(m)
    if hooked == m then return end
    hooked = m
    hooksecurefunc(m, "SetMaskTexture", function(_, tex)
        if own then return end
        blizzMask = tex
        local cfg = effective()
        if cfg.shape == "round" or not maskTouched then return end
        overrides = overrides + 1
        if inCombat() then pending = true return end
        local want = MM.MaskPath(cfg.shape, cfg.rectRatio)
        if want then setMask(m, want) end
    end)
end

-- HybridMinimap (Retail/Forever-Struktur: MapCanvas + CircleMask), nur per Existenzpruefung + pcall
local function applyHybrid(path)
    local h = _G.HybridMinimap
    if type(h) ~= "table" then return "-" end
    if not path and not hybridTouched then return "-" end
    local ok = pcall(function()
        local canvas, circle = h.MapCanvas, h.CircleMask
        if type(circle) ~= "table" or type(circle.SetTexture) ~= "function" then error("CircleMask fehlt") end
        if type(canvas) == "table" and canvas.SetUseMaskTexture then canvas:SetUseMaskTexture(false) end
        if path then
            if hybridOrig == nil and circle.GetTexture then hybridOrig = circle:GetTexture() end
            circle:SetTexture(path)
        else
            circle:SetTexture(hybridOrig or blizzardMask())
        end
        if type(canvas) == "table" and canvas.SetUseMaskTexture then canvas:SetUseMaskTexture(true) end
    end)
    hybridTouched = path ~= nil
    return ok and (path and "angepasst" or "zurueck") or "Fehler"
end

-- Quest-/Archaeologie-Blob-Ringe ("Waffel"-Flaeche): ob das im Client wirkt, ist offen => Befund in der Diagnose
local BLOB_SETTERS = { "SetArchBlobRingScalar", "SetArchBlobRingAlpha", "SetQuestBlobRingScalar", "SetQuestBlobRingAlpha" }
local function applyBlobs(m, off)
    if not off and not blobTouched then return "-" end
    blobOrig = blobOrig or {}
    local done, total = 0, 0
    for _, name in ipairs(BLOB_SETTERS) do
        if type(m[name]) == "function" then
            total = total + 1
            local getter = m["Get" .. name:sub(4)]
            if off then
                if blobOrig[name] == nil then
                    local ok, v = false, nil
                    if type(getter) == "function" then ok, v = pcall(getter, m) end
                    blobOrig[name] = (ok and Compat.Num(v)) or 1
                end
                if pcall(m[name], m, 0) then done = done + 1 end
            elseif blobOrig[name] ~= nil then
                if pcall(m[name], m, blobOrig[name]) then done = done + 1 end
            end
        end
    end
    blobTouched = off
    return ("%d/%d"):format(done, total)
end

-- GetMinimapShape nur definieren, wenn keine existiert
local function applyShapeFn(active)
    if active then
        if type(_G.GetMinimapShape) ~= "function" then
            shapeFn = function() return "SQUARE" end
            _G.GetMinimapShape = shapeFn
        end
    elseif shapeFn then
        if _G.GetMinimapShape == shapeFn then _G.GetMinimapShape = nil end
        shapeFn = nil
    end
end

--- Zustand auf die Minimap anwenden. Im Kampf wartet die Aenderung bis PLAYER_REGEN_ENABLED.
--- Bei "round", Groesse 100 % und ohne frueheren Eingriff geschieht nichts.
function MM.Apply()
    local cfg = effective()
    local active = cfg.shape ~= "round"
    local wantScale = cfg.scale ~= 100
    local custom = MM.ElementsCustom(cfg) or (MM.ElementsTouched ~= nil and MM.ElementsTouched())
        or (MM.CleanupTouched ~= nil and MM.CleanupTouched())
    if not (active or wantScale or custom or maskTouched or scaleTouched or insetsTouched or hybridTouched or blobTouched) then
        last.shape, last.ratio, last.scale = cfg.shape, cfg.rectRatio, cfg.scale
        return false
    end
    local m = frame()
    if not m then return false end
    if inCombat() then pending = true return false end
    pending = false

    if active then ensureHook(m) end
    local mask = active and MM.MaskPath(cfg.shape, cfg.rectRatio) or nil
    if active then
        if setMask(m, mask) then maskTouched = true end
    elseif maskTouched then
        setMask(m, blizzardMask())
        maskTouched = false
    end
    last.mask = mask

    -- Klickflaeche: nur bei rect eingezogen
    if type(m.SetHitRectInsets) == "function" then
        if cfg.shape == "rect" then
            local l, t, r, b = MM.Insets(cfg, MM.FrameSize(m))
            pcall(m.SetHitRectInsets, m, l, r, t, b)
            last.insets, insetsTouched = { l, t, r, b }, true
        elseif insetsTouched then
            pcall(m.SetHitRectInsets, m, 0, 0, 0, 0)
            last.insets, insetsTouched = { 0, 0, 0, 0 }, false
        end
    end

    -- Groesse
    if type(m.SetScale) == "function" and (wantScale or scaleTouched) then
        pcall(m.SetScale, m, cfg.scale / 100)
        scaleTouched = wantScale
    end

    last.hybrid = applyHybrid(mask)
    last.blobs = applyBlobs(m, active)
    applyShapeFn(active)
    last.shape, last.ratio, last.scale = cfg.shape, cfg.rectRatio, cfg.scale

    for _, fn in ipairs(MM.listeners) do
        local ok, err = pcall(fn, active, cfg)
        if not ok then geterrorhandler()(err) end
    end
    return true
end

--- Aenderung am aktiven Profil (changes: Teilmenge von shape/rectRatio/scale), anwenden.
--- noApply: nur speichern, die Karte nicht neu anwenden (Minimap-Knopf: button/buttonAngle).
--- Liefert true (angewendet), "deferred" (wartet auf Kampfende) oder nil, Fehlercode.
function MM.Set(changes, noApply)
    local cfg = MM.GetConfig()
    for k, v in pairs(changes) do
        if k == "elements" and type(v) == "table" then
            for ek, ev in pairs(v) do cfg.elements[ek] = ev end -- Teilaenderung der Elemente
        else
            cfg[k] = v
        end
    end
    local clean = MM.Validate(cfg)
    if not clean then return nil, "invalid" end
    local p = Store.GetActive()
    if not p then return nil, "invalid" end
    p.minimap = clean
    if not noApply then MM.Apply() end
    if MM.Button then MM.Button.Refresh() end -- Button.lua laedt nach dieser Datei
    return pending and "deferred" or true
end

function MM.IsPending() return pending end

--- Zustand fuer Tests/Diagnose
function MM.State()
    return { shape = last.shape, ratio = last.ratio, scale = last.scale, mask = last.mask, maskTouched = maskTouched,
        scaleTouched = scaleTouched, insets = last.insets, hybrid = last.hybrid, blobs = last.blobs,
        pending = pending, overrides = overrides, shapeFn = shapeFn ~= nil }
end

ns.RegisterModule("minimap", {
    OnEnable = function()
        modEnabled = true
        MM.Apply()
    end,
    OnDisable = function()
        modEnabled = false
        MM.Apply() -- Standardwerte: alles zurueck, soweit Lucid etwas veraendert hat
    end,
})

Compat.TryOn("PLAYER_ENTERING_WORLD", function() if modEnabled then MM.Apply() end end)
Compat.TryOn("PLAYER_REGEN_ENABLED", function() if pending then MM.Apply() end end)
-- spaet ladende Blizzard-Teile (Uhr, Hybrid-Minimap) nachziehen
Compat.TryOn("ADDON_LOADED", function(_, name)
    if modEnabled and (name == "Blizzard_TimeManager" or name == "Blizzard_HybridMinimap") then MM.Apply() end
end)
Store.RegisterCallback(function() if modEnabled then MM.Apply() end end)
-- Bearbeitungsmodus verlassen: Blizzard legt die Minimap-Teile neu an => Lucids Anordnung erneuern.
-- Eigener Owner (Compat gehoert dem Fader; derselbe Owner darf ein Event nicht doppelt anmelden).
if EventRegistry and EventRegistry.RegisterCallback then
    pcall(EventRegistry.RegisterCallback, EventRegistry, "EditMode.Exit", function()
        if modEnabled then MM.Apply() end
    end, MM)
end

-- Slash-Befehl /lucid minimap ---------------------------------------------------------------------
-- Vorlaeufig zum Handtesten (der Reiter folgt in M4): minimap, minimap shape <round|square|rect> [ratio],
-- minimap scale <50-200>, minimap debug. Eingaben stehen nur nach Pruefung im Profil.
MM.commands = {}

local function ratioText(cfg) return cfg.shape == "rect" and (" (" .. cfg.rectRatio .. ")") or "" end

local function report(res, okText)
    if res == "deferred" then ns.Print(L.MINIMAP_DEFERRED) else ns.Print(okText) end
end

MM.commands[""] = function()
    local cfg = MM.GetConfig()
    ns.Print(L.MINIMAP_STATUS, cfg.shape, ratioText(cfg), tostring(cfg.scale))
    ns.Print(L.MINIMAP_STATUS_BORDER, cfg.border, tostring(cfg.borderSize), cfg.northMarker and L.MINIMAP_YES or L.MINIMAP_NO)
end

MM.commands.shape = function(arg)
    local shape, ratio = (arg or ""):match("^(%S*)%s*(%S*)$")
    shape = (shape or ""):lower()
    if not SHAPE_SET[shape] then
        ns.Print(L.MINIMAP_SHAPE_INVALID, (shape:gsub("[%c|]", "")):sub(1, 20))
        return
    end
    local changes = { shape = shape }
    if ratio and ratio ~= "" then
        if not RATIO_SET[ratio] then
            ns.Print(L.MINIMAP_RATIO_INVALID, (ratio:gsub("[%c|]", "")):sub(1, 20))
            return
        end
        changes.rectRatio = ratio
    end
    local res = MM.Set(changes)
    local cfg = MM.GetConfig()
    report(res, L.MINIMAP_SHAPE_SET:format(cfg.shape, ratioText(cfg)))
end

MM.commands.border = function(arg)
    local name = (arg or ""):match("^%s*(%S+)%s*$")
    name = name and name:lower()
    if not name or not BORDER_SET[name] then
        ns.Print(L.MINIMAP_BORDER_INVALID, ((arg or ""):gsub("[%c|]", "")):sub(1, 20), table.concat(MM.BORDERS, ", "))
        return
    end
    local res = MM.Set({ border = name })
    report(res, L.MINIMAP_BORDER_SET:format(name))
end

MM.commands.bordersize = function(arg)
    local n = tonumber((arg or ""):match("^%s*(%S+)%s*$"))
    local r = MM.LIMITS.borderSize
    if not n or n ~= n or n < r[1] or n > r[2] then
        ns.Print(L.MINIMAP_BORDERSIZE_INVALID, ((arg or ""):gsub("[%c|]", "")):sub(1, 20))
        return
    end
    local res = MM.Set({ borderSize = n })
    report(res, L.MINIMAP_BORDERSIZE_SET:format(tostring(MM.GetConfig().borderSize)))
end

MM.commands.north = function(arg)
    local v = ((arg or ""):match("^%s*(%S+)%s*$") or ""):lower()
    if v ~= "on" and v ~= "off" then
        ns.Print(L.MINIMAP_ONOFF_INVALID, (v:gsub("[%c|]", "")):sub(1, 20))
        return
    end
    local res = MM.Set({ northMarker = v == "on" })
    report(res, v == "on" and L.MINIMAP_NORTH_ON or L.MINIMAP_NORTH_OFF)
end

local function word(arg, n)
    local words = {}
    for w in (arg or ""):gmatch("%S+") do words[#words + 1] = w:lower() end
    return words[n]
end
local function clip(x) return ((x or ""):gsub("[%c|]", "")):sub(1, 20) end

--- /lucid minimap element <name> <always|hover|off>
MM.commands.element = function(arg)
    local key, vis = word(arg, 1), word(arg, 2)
    if not key or not ELEMENT_SET[key] then
        ns.Print(L.MINIMAP_ELEMENT_INVALID, clip(key), table.concat(MM.ELEMENT_KEYS, ", "))
        return
    end
    if not vis or not VIS_SET[vis] then
        ns.Print(L.MINIMAP_VIS_INVALID, clip(vis))
        return
    end
    report(MM.Set({ elements = { [key] = vis } }), L.MINIMAP_ELEMENT_SET:format(key, vis))
end

--- /lucid minimap pos <zone|clock|coords> <blizzard|top|bottom>
MM.commands.pos = function(arg)
    local which, pos = word(arg, 1), word(arg, 2)
    if which ~= "zone" and which ~= "clock" and which ~= "coords" then
        ns.Print(L.MINIMAP_POSKEY_INVALID, clip(which))
        return
    end
    if not pos or not POS_SET[pos] then
        ns.Print(L.MINIMAP_POS_INVALID, clip(pos))
        return
    end
    report(MM.Set({ elements = { [which .. "Pos"] = pos } }), L.MINIMAP_POS_SET:format(which, pos))
end

MM.commands.fontsize = function(arg)
    local n = tonumber(word(arg, 1))
    local r = MM.LIMITS.fontSize
    if not n or n ~= n or n < r[1] or n > r[2] then
        ns.Print(L.MINIMAP_FONTSIZE_INVALID, clip(word(arg, 1)))
        return
    end
    report(MM.Set({ elements = { fontSize = n } }), L.MINIMAP_FONTSIZE_SET:format(tostring(MM.GetConfig().elements.fontSize)))
end

MM.commands.bronze = function(arg)
    local v = word(arg, 1)
    if v ~= "on" and v ~= "off" then
        ns.Print(L.MINIMAP_ONOFF_INVALID, clip(v))
        return
    end
    report(MM.Set({ elements = { bronze = v == "on" } }), v == "on" and L.MINIMAP_BRONZE_ON or L.MINIMAP_BRONZE_OFF)
end

MM.commands.scale = function(arg)
    local n = tonumber((arg or ""):match("^%s*(%S+)%s*$"))
    local r = MM.LIMITS.scale
    if not n or n ~= n or n < r[1] or n > r[2] then
        ns.Print(L.MINIMAP_SCALE_INVALID, ((arg or ""):gsub("[%c|]", "")):sub(1, 20))
        return
    end
    local res = MM.Set({ scale = n })
    report(res, L.MINIMAP_SCALE_SET:format(tostring(MM.GetConfig().scale)))
end

--- Diagnosezeilen (Form, Maske, Klickflaeche, Hybrid/Ringe, Blizzard-Teile, GetMinimapShape, Client)
function MM.DebugLines()
    local cfg = MM.GetConfig()
    local yn = function(b) return b and L.MINIMAP_YES or L.MINIMAP_NO end
    local lines = {
        L.MINIMAP_DEBUG_HEAD:format(Compat.flavor, tostring(Compat.interface)),
        L.MINIMAP_DEBUG_SHAPE:format(cfg.shape, ratioText(cfg), tostring(cfg.scale), yn(pending)),
        L.MINIMAP_DEBUG_MASK:format(last.mask or L.MINIMAP_NONE, yn(maskTouched), tostring(overrides)),
    }
    local i = last.insets
    lines[#lines + 1] = L.MINIMAP_DEBUG_HIT:format(i[1], i[2], i[3], i[4])
    lines[#lines + 1] = L.MINIMAP_DEBUG_HYBRID:format(last.hybrid, last.blobs)
    local fn = type(_G.GetMinimapShape) == "function"
    local value = ""
    if fn then
        local okV, v = pcall(_G.GetMinimapShape)
        value = " (" .. ((okV and type(v) == "string" and not Compat.IsSecret(v)) and v:gsub("[%c|]", ""):sub(1, 20) or "?") .. ")"
    end
    lines[#lines + 1] = L.MINIMAP_DEBUG_SHAPEFN:format(
        (shapeFn and fn and L.MINIMAP_SHAPEFN_OURS or (fn and L.MINIMAP_SHAPEFN_OTHER or L.MINIMAP_SHAPEFN_NONE)) .. value)
    local e = cfg.elements
    local custom = {}
    for _, k in ipairs(MM.ELEMENT_KEYS) do
        if e[k] ~= "always" then custom[#custom + 1] = k .. "=" .. e[k] end
    end
    lines[#lines + 1] = L.MINIMAP_DEBUG_ELEMENTS:format(#custom > 0 and table.concat(custom, ", ") or L.MINIMAP_NONE,
        e.zonePos .. "/" .. e.clockPos .. "/" .. e.coordsPos, tostring(e.fontSize), e.bronze and L.MINIMAP_YES or L.MINIMAP_NO)
    if MM.ElementLines then
        for _, l in ipairs(MM.ElementLines()) do lines[#lines + 1] = l end
    end
    if MM.FrameLines then
        for _, l in ipairs(MM.FrameLines()) do lines[#lines + 1] = l end
    end
    if MM.CleanupLines then
        for _, l in ipairs(MM.CleanupLines()) do lines[#lines + 1] = l end
    end
    return lines
end

MM.commands.debug = function()
    for _, line in ipairs(MM.DebugLines()) do ns.Print(line) end
end

ns.commands.minimap = function(rest)
    local sub, arg = (rest or ""):match("^%s*(%S*)%s*(.-)%s*$")
    sub = sub:lower()
    local fn = MM.commands[sub]
    if fn then
        fn(arg)
    else
        ns.Print(L.MINIMAP_UNKNOWN, (sub:gsub("[%c|]", "")):sub(1, 20))
        ns.Print(L.HELP_MINIMAP)
    end
end
ns.AddHelp("HELP_MINIMAP")
ns.AddHelp("HELP_MINIMAP_DEBUG")
