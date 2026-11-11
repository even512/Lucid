-- Zuordnung Zone -> Verzierungs-Motiv der grossen Zonenkarte (Spec lucid-change-zonen-ornamente). VON HAND gepflegt.
-- ns.ZoneMotifs.byMap[uiMapID] = "<motiv>"; das Motiv ist ein Vorlagen-Stil mit "auto": true in
-- docs/ornament-src/recipes.json (Textur Media/zone-<motiv>-*.tga, Stil in Ornaments.lua). Fehlt das Motiv dort
-- (noch nicht erzeugt) oder ist die Textur nicht ladbar, zeigt die Karte den festen Stil aus zone.ornament.
-- IDs: Forever (Classic 14xx + Neuzugaenge 2xxx) und Retail derselben Zonen (Quelle der Paare: Ink & Embers
-- journal/MapSpace.lua, Forever-Build 1.60.1.70170 / Retail 12.1.5.70575). Retail-ID 25 (Vorgebirge des Huegellands)
-- gehoert zu Huegelland: Retail hat kein eigenes Alteracgebirge. Weitere Retail-Zonen bekommen kein Motiv.
local _, ns = ...
local M = { byMap = {}, byName = {}, order = {}, dups = {}, ids = {} } -- ids[motiv] = IDs in Tabellenreihenfolge (erste = Hauptzone)
ns.ZoneMotifs = M

local function motif(name, ids)
    M.order[#M.order + 1] = name
    M.ids[name] = ids
    for _, id in ipairs(ids) do
        if M.byMap[id] ~= nil then M.dups[#M.dups + 1] = id end -- Pflegefehler; nur fuer den Test
        M.byMap[id] = name
    end
end

motif("royal", { 1453, 84 })                         -- Sturmwind
motif("shire", { 1429, 37 })                         -- Wald von Elwynn
motif("harvest", { 1436, 52 })                       -- Westfall
motif("frontier", { 1433, 49 })                      -- Rotkammgebirge
motif("dusk", { 1431, 47 })                          -- Daemmerwald
motif("orchard", { 1424, 25 })                       -- Vorgebirge des Huegellands
motif("alterac", { 1416 })                           -- Alteracgebirge (nur Forever)
motif("arathor", { 1417, 14 })                       -- Arathihochland
motif("menethil", { 1437, 56 })                      -- Sumpfland
motif("dwarf", { 1426, 27, 1455, 87, 1432, 48 })     -- Dun Morogh, Eisenschmiede, Loch Modan
motif("titan", { 1418, 15 })                         -- Oedland
motif("darkiron", { 1427, 32 })                      -- Sengende Schlucht
motif("blackrock", { 1428, 36 })                     -- Brennende Steppe
motif("wildhammer", { 1425, 26 })                    -- Hinterland
motif("gurubashi", { 1434, 224, 50, 210 })           -- Schlingendorntal (Retail: Tal, Nord, Kap)
motif("atalai", { 1435, 51 })                        -- Suempfe des Elends
motif("karazhan", { 1430, 42 })                      -- Gebirgspass der Totenwinde
motif("fel", { 1419, 17, 1448, 77 })                 -- Verwuestete Lande, Teufelswald
motif("forsaken", { 1420, 18, 1458, 90, 1421, 21 })  -- Tirisfal, Unterstadt, Silberwald
motif("scourge", { 1422, 22, 1423, 23 })             -- Westliche und Oestliche Pestlaender
motif("delta", { 2548 })                             -- Flusslande (nur Forever)
motif("horde", { 1411, 1, 1454, 85 })                -- Durotar, Orgrimmar
motif("tiki", { 2524 })                              -- Dunkelspeerinseln (nur Forever)
motif("savanna", { 1413, 10, 199 })                  -- Brachland (Retail: Nord, Sued)
motif("totem", { 1412, 7, 1456, 88 })                -- Mulgore, Donnerfels
motif("needles", { 1441, 64 })                       -- Tausend Nadeln
motif("kaldorei", { 1438, 57, 1457, 89 })            -- Teldrassil, Darnassus
motif("ashen", { 1440, 63 })                         -- Eschental
motif("shore", { 1439, 62 })                         -- Dunkelkueste
motif("moon", { 1450, 80 })                          -- Mondlichtung
motif("jungle", { 1444, 69 })                        -- Feralas
motif("frost", { 1452, 83 })                         -- Winterquell
motif("renewal", { 2482, 198 })                      -- Hyjal
motif("highborne", { 1447, 76 })                     -- Azshara
motif("centaur", { 1443, 66 })                       -- Desolace
motif("shendralas", { 2652 })                        -- Shen'dralas (nur Forever)
motif("goblin", { 1442, 65, 1446, 71 })              -- Steinkrallengebirge, Tanaris
motif("theramore", { 1445, 70 })                     -- Duestermarschen
motif("primal", { 1449, 78 })                        -- Krater von Un'Goro
motif("qiraji", { 1451, 81 })                        -- Silithus
motif("sky", { 2521, 2665 })                         -- Insel Zephras (nur Forever)

-- Gebiete ohne eigene Karte: Zuordnung ueber den angezeigten Namen (Zeile 1 oder 2 der Karte, exakt). Gilt vor byMap.
-- Namen, die in deDE und enUS gleich lauten; weitere Sprachen bei Bedarf ergaenzen.
local function named(name, names)
    M.order[#M.order + 1] = name
    M.ids[name] = {}
    for _, n in ipairs(names) do M.byName[n] = name end
end

named("dalaran", { "Dalaran" })                     -- Dalaran (Forever: Stadtgebiet im Alteracgebirge ohne eigene Karte)
