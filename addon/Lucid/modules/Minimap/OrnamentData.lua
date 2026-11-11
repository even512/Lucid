-- ERZEUGT von scripts/gen-minimap-ornament.mjs aus docs/minimap-ornament-src/<motiv>-frei-v1.jpg. Nicht von Hand aendern.
-- Zonen-Ornament der Minimap (4:3). Fixpunkt ist die Sonnenmitte (GameTimeFrame): alle Stuecke liegen relativ zu ihr wie
-- im Referenzbild. Masse in Kartenbreiten (sichtbares Kartenrechteck in der Vorlage), x nach rechts, y nach unten.
-- pieces[i]: key (top | side | ring), file (Media/<file>.tga, ungedreht), tw/th = Texturgroesse, r = Rechteck in der
-- Textur, x/y = obere linke Ecke ab der Sonnenmitte, w/h = Groesse. sunX/sunY = Sonnenmitte ab der oberen rechten Ecke
-- des Kartenrechtecks (Rueckfall ohne Sonne), sunR = Sonnenradius, ringR = Aussenradius des Rings.
-- Einheitliche Geometrie (Vorbild dwarf): norm.k = Massstab (Innenradius des Rings), dxRing/dyRing = Ringmitte auf die
-- Sonne, dyTop = Leiste senkrecht, dxSide = Spalte waagrecht verschoben (Screenshot-Pixel) - so sitzen alle Motive bei
-- denselben Reglerwerten gleich am Rahmen.
local _, ns = ...
local D = { ratio = "4:3", ref = { mapW = 354, mapH = 265 }, order = {}, motifs = {} }
ns.MinimapOrnamentData = D
local function add(name, m)
    D.order[#D.order + 1] = name
    D.motifs[name] = m
end
-- dwarf: gemessen Ringmitte (422.9, 82.1), Innenradius 24.7, Leiste y 80.0 (Strecke 93), Spalte x 517.6 (Strecke 95) px
add("dwarf", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.11158, norm = { k = 1, dxRing = -0.875, dyRing = -1.125, dyTop = 0, dxSide = 0 }, pieces = {
    { key = "top", file = "mmorn-dwarf-top", tw = 1024, th = 128, r = { x = 2, y = 2, w = 796, h = 64 }, x = -0.83541, y = -0.04338, w = 1.12482, h = 0.09039 },
    { key = "side", file = "mmorn-dwarf-side", tw = 128, th = 1024, r = { x = 2, y = 2, w = 114, h = 612 }, x = 0.15492, y = 0.04274, w = 0.16047, h = 0.86404 },
    { key = "ring", file = "mmorn-dwarf-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 161, h = 165 }, x = -0.11559, y = -0.13093, w = 0.22772, h = 0.23274 },
} })
-- royal: gemessen Ringmitte (423.3, 83.8), Innenradius 24.5, Leiste y 80.2 (Strecke 244), Spalte x 509.0 (Strecke 143) px
add("royal", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.12414, norm = { k = 1.01021, dxRing = -1.25, dyRing = -2.75, dyTop = 1.40883, dxSide = 8.15576 }, pieces = {
    { key = "top", file = "mmorn-royal-top", tw = 1024, th = 128, r = { x = 2, y = 2, w = 520, h = 122 }, x = -0.8405, y = -0.17031, w = 1.23667, h = 0.28904 },
    { key = "side", file = "mmorn-royal-side", tw = 256, th = 512, r = { x = 2, y = 2, w = 156, h = 507 }, x = 0.14682, y = 0.11442, w = 0.24702, h = 0.80313 },
    { key = "ring", file = "mmorn-royal-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 177, h = 183 }, x = -0.12942, y = -0.15344, w = 0.25243, h = 0.26172 },
} })
-- shire: gemessen Ringmitte (423.3, 84.1), Innenradius 24.4, Leiste y 82.3 (Strecke 244), Spalte x 514.6 (Strecke 100) px
add("shire", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.13161, norm = { k = 1.0128, dxRing = -1.25, dyRing = -3.125, dyTop = -0.24374, dxSide = 2.1807 }, pieces = {
    { key = "top", file = "mmorn-shire-top", tw = 512, th = 128, r = { x = 2, y = 2, w = 492, h = 123 }, x = -0.86037, y = -0.18587, w = 1.22358, h = 0.30492 },
    { key = "side", file = "mmorn-shire-side", tw = 128, th = 1024, r = { x = 2, y = 2, w = 123, h = 548 }, x = 0.18676, y = 0.11472, w = 0.17568, h = 0.78428 },
    { key = "ring", file = "mmorn-shire-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 188, h = 192 }, x = -0.13749, y = -0.16716, w = 0.26855, h = 0.27536 },
} })
-- frontier: gemessen Ringmitte (423.5, 82.8), Innenradius 25.7, Leiste y 81.0 (Strecke 164), Spalte x 514.4 (Strecke 143) px
add("frontier", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.11946, norm = { k = 0.96113, dxRing = -1.5, dyRing = -1.75, dyTop = -0.45073, dxSide = 7.40348 }, pieces = {
    { key = "top", file = "mmorn-frontier-top", tw = 512, th = 128, r = { x = 2, y = 2, w = 488, h = 121 }, x = -0.80135, y = -0.19721, w = 1.15307, h = 0.28594 },
    { key = "side", file = "mmorn-frontier-side", tw = 128, th = 1024, r = { x = 2, y = 2, w = 81, h = 548 }, x = 0.2489, y = 0.08462, w = 0.10943, h = 0.74426 },
    { key = "ring", file = "mmorn-frontier-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 179, h = 198 }, x = -0.12528, y = -0.16447, w = 0.2431, h = 0.26815 },
} })
-- orchard: gemessen Ringmitte (423.1, 82.1), Innenradius 25.6, Leiste y 81.5 (Strecke 186), Spalte x 514.4 (Strecke 83) px
add("orchard", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.11595, norm = { k = 0.96582, dxRing = -1.125, dyRing = -1.125, dyTop = -1.53285, dxSide = 6.61484 }, pieces = {
    { key = "top", file = "mmorn-orchard-top", tw = 1024, th = 128, r = { x = 2, y = 2, w = 579, h = 124 }, x = -0.80804, y = -0.15965, w = 1.08933, h = 0.23372 },
    { key = "side", file = "mmorn-orchard-side", tw = 256, th = 512, r = { x = 2, y = 2, w = 129, h = 505 }, x = 0.16394, y = 0.06994, w = 0.20074, h = 0.78777 },
    { key = "ring", file = "mmorn-orchard-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 174, h = 173 }, x = -0.12118, y = -0.12851, w = 0.23691, h = 0.23647 },
} })
-- alterac: gemessen Ringmitte (423.4, 83.9), Innenradius 24.5, Leiste y 80.2 (Strecke 102), Spalte x 518.7 (Strecke 99) px
add("alterac", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.12984, norm = { k = 1.01021, dxRing = -1.375, dyRing = -2.875, dyTop = 1.5351, dxSide = -1.55572 }, pieces = {
    { key = "top", file = "mmorn-alterac-top", tw = 512, th = 256, r = { x = 2, y = 2, w = 492, h = 146 }, x = -0.86675, y = -0.2077, w = 1.22046, h = 0.3631 },
    { key = "side", file = "mmorn-alterac-side", tw = 128, th = 1024, r = { x = 2, y = 2, w = 104, h = 525 }, x = 0.18928, y = 0.15109, w = 0.14899, h = 0.7492 },
    { key = "ring", file = "mmorn-alterac-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 185, h = 190 }, x = -0.13595, y = -0.16458, w = 0.26401, h = 0.27178 },
} })
-- darkiron: gemessen Ringmitte (423.6, 82.3), Innenradius 25.4, Leiste y 80.2 (Strecke 108), Spalte x 513.6 (Strecke 89) px
add("darkiron", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.11543, norm = { k = 0.97295, dxRing = -1.625, dyRing = -1.25, dyTop = -0.18114, dxSide = 7.24066 }, pieces = {
    { key = "top", file = "mmorn-darkiron-top", tw = 1024, th = 128, r = { x = 2, y = 2, w = 607, h = 120 }, x = -0.81895, y = -0.17186, w = 1.19104, h = 0.23613 },
    { key = "side", file = "mmorn-darkiron-side", tw = 128, th = 1024, r = { x = 2, y = 2, w = 80, h = 599 }, x = 0.22563, y = 0.06011, w = 0.11003, h = 0.82336 },
    { key = "ring", file = "mmorn-darkiron-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 169, h = 204 }, x = -0.12196, y = -0.1762, w = 0.23271, h = 0.27976 },
} })
-- atalai: gemessen Ringmitte (423.3, 82.8), Innenradius 25.0, Leiste y 75.2 (Strecke 137), Spalte x 516.5 (Strecke 127) px
add("atalai", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.1608, norm = { k = 0.98999, dxRing = -1.25, dyRing = -1.75, dyTop = 5.33661, dxSide = 2.39081 }, pieces = {
    { key = "top", file = "mmorn-atalai-top", tw = 512, th = 256, r = { x = 2, y = 2, w = 492, h = 125 }, x = -0.84101, y = -0.14518, w = 1.19754, h = 0.30298 },
    { key = "side", file = "mmorn-atalai-side", tw = 128, th = 1024, r = { x = 2, y = 2, w = 115, h = 534 }, x = 0.18253, y = 0.15358, w = 0.16038, h = 0.74618 },
    { key = "ring", file = "mmorn-atalai-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 233, h = 225 }, x = -0.16616, y = -0.16659, w = 0.32605, h = 0.31496 },
} })
-- blackrock: gemessen Ringmitte (423.4, 82.3), Innenradius 25.2, Leiste y 78.5 (Strecke 123), Spalte x 514.1 (Strecke 143) px
add("blackrock", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.13185, norm = { k = 0.98261, dxRing = -1.375, dyRing = -1.25, dyTop = 1.57123, dxSide = 5.59404 }, pieces = {
    { key = "top", file = "mmorn-blackrock-top", tw = 512, th = 256, r = { x = 2, y = 2, w = 496, h = 146 }, x = -0.83726, y = -0.19729, w = 1.19762, h = 0.35318 },
    { key = "side", file = "mmorn-blackrock-side", tw = 256, th = 512, r = { x = 2, y = 2, w = 135, h = 498 }, x = 0.1719, y = 0.15169, w = 0.19748, h = 0.72803 },
    { key = "ring", file = "mmorn-blackrock-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 193, h = 168 }, x = -0.13749, y = -0.10592, w = 0.26806, h = 0.23289 },
} })
-- delta: gemessen Ringmitte (423.4, 82.5), Innenradius 25.8, Leiste y 80.5 (Strecke 86), Spalte x 514.1 (Strecke 50) px
add("delta", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.10834, norm = { k = 0.9588, dxRing = -1.375, dyRing = -1.5, dyTop = -0.21135, dxSide = 7.75467 }, pieces = {
    { key = "top", file = "mmorn-delta-top", tw = 1024, th = 128, r = { x = 2, y = 2, w = 574, h = 122 }, x = -0.79363, y = -0.16263, w = 1.11072, h = 0.23611 },
    { key = "side", file = "mmorn-delta-side", tw = 128, th = 1024, r = { x = 2, y = 2, w = 110, h = 579 }, x = 0.21232, y = 0.06939, w = 0.14873, h = 0.78477 },
    { key = "ring", file = "mmorn-delta-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 162, h = 191 }, x = -0.11218, y = -0.16135, w = 0.21907, h = 0.25931 },
} })
-- forsaken: gemessen Ringmitte (423.9, 83.3), Innenradius 26.8, Leiste y 82.8 (Strecke 157), Spalte x 512.2 (Strecke 143) px
add("forsaken", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.10951, norm = { k = 0.92301, dxRing = -1.875, dyRing = -2.25, dyTop = -1.6837, dxSide = 13.21123 }, pieces = {
    { key = "top", file = "mmorn-forsaken-top", tw = 512, th = 256, r = { x = 2, y = 2, w = 506, h = 178 }, x = -0.48529, y = -0.16401, w = 0.85061, h = 0.2989 },
    { key = "side", file = "mmorn-forsaken-side", tw = 128, th = 1024, r = { x = 2, y = 2, w = 102, h = 537 }, x = 0.21438, y = 0.13095, w = 0.1333, h = 0.70029 },
    { key = "ring", file = "mmorn-forsaken-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 172, h = 167 }, x = -0.11635, y = -0.12049, w = 0.22358, h = 0.21744 },
} })
-- gurubashi: gemessen Ringmitte (423.8, 84.4), Innenradius 23.7, Leiste y 77.2 (Strecke 246), Spalte x 510.9 (Strecke 143) px
add("gurubashi", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.12692, norm = { k = 1.0449, dxRing = -1.75, dyRing = -3.375, dyTop = 5.3426, dxSide = 3.72653 }, pieces = {
    { key = "top", file = "mmorn-gurubashi-top", tw = 512, th = 256, r = { x = 2, y = 2, w = 490, h = 126 }, x = -0.89053, y = -0.1819, w = 1.25757, h = 0.32276 },
    { key = "side", file = "mmorn-gurubashi-side", tw = 128, th = 1024, r = { x = 2, y = 2, w = 123, h = 529 }, x = 0.19298, y = 0.1364, w = 0.19163, h = 0.82178 },
    { key = "ring", file = "mmorn-gurubashi-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 173, h = 183 }, x = -0.13374, y = -0.16278, w = 0.25471, h = 0.2707 },
} })
-- horde: gemessen Ringmitte (423.6, 83.5), Innenradius 25.2, Leiste y 73.7 (Strecke 167), Spalte x 514.4 (Strecke 143) px
add("horde", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.13046, norm = { k = 0.98261, dxRing = -1.625, dyRing = -2.5, dyTop = 7.50337, dxSide = 5.57389 }, pieces = {
    { key = "top", file = "mmorn-horde-top", tw = 512, th = 256, r = { x = 2, y = 2, w = 507, h = 125 }, x = -0.82525, y = -0.20079, w = 1.17284, h = 0.28953 },
    { key = "side", file = "mmorn-horde-side", tw = 256, th = 512, r = { x = 2, y = 2, w = 141, h = 505 }, x = 0.13586, y = 0.08455, w = 0.22976, h = 0.82524 },
    { key = "ring", file = "mmorn-horde-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 191, h = 201 }, x = -0.13668, y = -0.16394, w = 0.26505, h = 0.27834 },
} })
-- kaldorei: gemessen Ringmitte (423.5, 82.6), Innenradius 26.0, Leiste y 83.0 (Strecke 146), Spalte x 514.4 (Strecke 68) px
add("kaldorei", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.10864, norm = { k = 0.94959, dxRing = -1.5, dyRing = -1.625, dyTop = -2.5036, dxSide = 8.45171 }, pieces = {
    { key = "top", file = "mmorn-kaldorei-top", tw = 512, th = 128, r = { x = 2, y = 2, w = 496, h = 123 }, x = -0.80158, y = -0.20235, w = 1.15665, h = 0.28724 },
    { key = "side", file = "mmorn-kaldorei-side", tw = 128, th = 1024, r = { x = 2, y = 2, w = 102, h = 565 }, x = 0.2143, y = 0.08083, w = 0.13714, h = 0.75763 },
    { key = "ring", file = "mmorn-kaldorei-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 164, h = 173 }, x = -0.11361, y = -0.1358, w = 0.21987, h = 0.23249 },
} })
-- karazhan: gemessen Ringmitte (423.6, 82.3), Innenradius 25.9, Leiste y 81.3 (Strecke 242), Spalte x 515.7 (Strecke 122) px
add("karazhan", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.11995, norm = { k = 0.95417, dxRing = -1.625, dyRing = -1.25, dyTop = -1.18037, dxSide = 6.86416 }, pieces = {
    { key = "top", file = "mmorn-karazhan-top", tw = 512, th = 256, r = { x = 2, y = 2, w = 504, h = 125 }, x = -0.79507, y = -0.2033, w = 1.13161, h = 0.2798 },
    { key = "side", file = "mmorn-karazhan-side", tw = 128, th = 1024, r = { x = 2, y = 2, w = 105, h = 587 }, x = 0.20383, y = 0.07242, w = 0.14218, h = 0.79117 },
    { key = "ring", file = "mmorn-karazhan-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 181, h = 185 }, x = -0.12617, y = -0.14088, w = 0.24426, h = 0.24991 },
} })
-- needles: gemessen Ringmitte (423.4, 82.3), Innenradius 25.5, Leiste y 80.2 (Strecke 242), Spalte x 516.0 (Strecke 98) px
add("needles", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.09162, norm = { k = 0.96818, dxRing = -1.375, dyRing = -1.25, dyTop = -0.19068, dxSide = 5.0698 }, pieces = {
    { key = "top", file = "mmorn-needles-top", tw = 512, th = 256, r = { x = 2, y = 2, w = 489, h = 131 }, x = -0.8129, y = -0.20895, w = 1.16376, h = 0.31147 },
    { key = "side", file = "mmorn-needles-side", tw = 128, th = 1024, r = { x = 2, y = 2, w = 86, h = 559 }, x = 0.22509, y = 0.09838, w = 0.11763, h = 0.76489 },
    { key = "ring", file = "mmorn-needles-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 135, h = 167 }, x = -0.097, y = -0.13882, w = 0.18422, h = 0.22878 },
} })
-- savanna: gemessen Ringmitte (423.6, 84.8), Innenradius 26.7, Leiste y 81.0 (Strecke 157), Spalte x 514.9 (Strecke 98) px
add("savanna", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.11395, norm = { k = 0.92733, dxRing = -1.625, dyRing = -3.75, dyTop = 1.3449, dxSide = 10.08866 }, pieces = {
    { key = "top", file = "mmorn-savanna-top", tw = 1024, th = 128, r = { x = 2, y = 2, w = 599, h = 120 }, x = -0.76234, y = -0.17135, w = 1.12174, h = 0.22506 },
    { key = "side", file = "mmorn-savanna-side", tw = 128, th = 1024, r = { x = 2, y = 2, w = 123, h = 548 }, x = 0.17374, y = 0.04975, w = 0.17432, h = 0.77551 },
    { key = "ring", file = "mmorn-savanna-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 176, h = 195 }, x = -0.11978, y = -0.16261, w = 0.23101, h = 0.25476 },
} })
-- tiki: gemessen Ringmitte (423.5, 82.1), Innenradius 25.8, Leiste y 83.5 (Strecke 109), Spalte x 523.6 (Strecke 34) px
add("tiki", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.10969, norm = { k = 0.9588, dxRing = -1.5, dyRing = -1.125, dyTop = -3.46977, dxSide = -1.20316 }, pieces = {
    { key = "top", file = "mmorn-tiki-top", tw = 1024, th = 128, r = { x = 2, y = 2, w = 581, h = 123 }, x = -0.82294, y = -0.18447, w = 1.1664, h = 0.24703 },
    { key = "side", file = "mmorn-tiki-side", tw = 128, th = 1024, r = { x = 2, y = 2, w = 123, h = 534 }, x = 0.13465, y = 0.05847, w = 0.18463, h = 0.80319 },
    { key = "ring", file = "mmorn-tiki-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 164, h = 179 }, x = -0.11545, y = -0.14737, w = 0.22273, h = 0.24294 },
} })
-- titan: gemessen Ringmitte (423.5, 83.4), Innenradius 25.2, Leiste y 80.5 (Strecke 243), Spalte x 515.7 (Strecke 69) px
add("titan", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.09021, norm = { k = 0.98261, dxRing = -1.5, dyRing = -2.375, dyTop = 0.69609, dxSide = 4.12204 }, pieces = {
    { key = "top", file = "mmorn-titan-top", tw = 1024, th = 128, r = { x = 2, y = 2, w = 561, h = 122 }, x = -0.82374, y = -0.15533, w = 1.19687, h = 0.26156 },
    { key = "side", file = "mmorn-titan-side", tw = 128, th = 1024, r = { x = 2, y = 2, w = 90, h = 560 }, x = 0.21395, y = 0.10203, w = 0.12539, h = 0.77769 },
    { key = "ring", file = "mmorn-titan-ring", tw = 128, th = 256, r = { x = 2, y = 2, w = 123, h = 164 }, x = -0.08528, y = -0.1517, w = 0.1712, h = 0.22799 },
} })
-- wildhammer: gemessen Ringmitte (423.6, 82.4), Innenradius 25.5, Leiste y 81.0 (Strecke 67), Spalte x 510.9 (Strecke 86) px
add("wildhammer", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.10967, norm = { k = 0.97056, dxRing = -1.625, dyRing = -1.375, dyTop = -0.79821, dxSide = 10.08077 }, pieces = {
    { key = "top", file = "mmorn-wildhammer-top", tw = 1024, th = 128, r = { x = 2, y = 2, w = 649, h = 122 }, x = -0.79997, y = -0.14383, w = 1.1859, h = 0.22243 },
    { key = "side", file = "mmorn-wildhammer-side", tw = 128, th = 1024, r = { x = 2, y = 2, w = 116, h = 587 }, x = 0.19384, y = 0.07446, w = 0.15945, h = 0.80476 },
    { key = "ring", file = "mmorn-wildhammer-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 161, h = 183 }, x = -0.11572, y = -0.15332, w = 0.22101, h = 0.25144 },
} })
-- ashen: gemessen Ringmitte (423.5, 82.3), Innenradius 25.7, Leiste y 81.0 (Strecke 174), Spalte x 514.9 (Strecke 100) px
add("ashen", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.12082, norm = { k = 0.96113, dxRing = -1.5, dyRing = -1.25, dyTop = -0.93129, dxSide = 6.88349 }, pieces = {
    { key = "top", file = "mmorn-ashen-top", tw = 512, th = 256, r = { x = 2, y = 2, w = 501, h = 127 }, x = -0.80208, y = -0.18216, w = 1.13324, h = 0.28731 },
    { key = "side", file = "mmorn-ashen-side", tw = 128, th = 1024, r = { x = 2, y = 2, w = 123, h = 555 }, x = 0.19088, y = 0.10104, w = 0.16672, h = 0.75384 },
    { key = "ring", file = "mmorn-ashen-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 181, h = 190 }, x = -0.12675, y = -0.14807, w = 0.24604, h = 0.25858 },
} })
-- shore: gemessen Ringmitte (423.4, 82.1), Innenradius 25.7, Leiste y 82.5 (Strecke 117), Spalte x 527.4 (Strecke 68) px
add("shore", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.10996, norm = { k = 0.96113, dxRing = -1.375, dyRing = -1.125, dyTop = -2.50438, dxSide = -5.1963 }, pieces = {
    { key = "top", file = "mmorn-shore-top", tw = 1024, th = 128, r = { x = 2, y = 2, w = 567, h = 122 }, x = -0.83513, y = -0.18764, w = 1.13985, h = 0.2449 },
    { key = "side", file = "mmorn-shore-side", tw = 128, th = 1024, r = { x = 2, y = 2, w = 87, h = 599 }, x = 0.1806, y = 0.05316, w = 0.11825, h = 0.81335 },
    { key = "ring", file = "mmorn-shore-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 165, h = 175 }, x = -0.11539, y = -0.13815, w = 0.224, h = 0.23737 },
} })
-- moon: gemessen Ringmitte (423.9, 82.5), Innenradius 30.3, Leiste y 80.2 (Strecke 172), Spalte x 515.5 (Strecke 80) px
add("moon", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.09916, norm = { k = 0.81634, dxRing = -1.875, dyRing = -1.5, dyTop = -0.29072, dxSide = 19.9829 }, pieces = {
    { key = "top", file = "mmorn-moon-top", tw = 1024, th = 128, r = { x = 2, y = 2, w = 521, h = 123 }, x = -0.63845, y = -0.15911, w = 0.96066, h = 0.22602 },
    { key = "side", file = "mmorn-moon-side", tw = 128, th = 1024, r = { x = 2, y = 2, w = 112, h = 573 }, x = 0.19808, y = 0.06341, w = 0.12913, h = 0.6612 },
    { key = "ring", file = "mmorn-moon-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 175, h = 188 }, x = -0.10477, y = -0.13099, w = 0.20149, h = 0.21672 },
} })
-- jungle: gemessen Ringmitte (423.0, 81.6), Innenradius 28.3, Leiste y 80.2 (Strecke 97), Spalte x 522.2 (Strecke 53) px
add("jungle", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.11111, norm = { k = 0.87406, dxRing = -1, dyRing = -0.625, dyTop = -0.92549, dxSide = 8.02145 }, pieces = {
    { key = "top", file = "mmorn-jungle-top", tw = 512, th = 256, r = { x = 2, y = 2, w = 506, h = 129 }, x = -0.72321, y = -0.18425, w = 1.0406, h = 0.26626 },
    { key = "side", file = "mmorn-jungle-side", tw = 128, th = 1024, r = { x = 2, y = 2, w = 99, h = 579 }, x = 0.18915, y = 0.07828, w = 0.12223, h = 0.71479 },
    { key = "ring", file = "mmorn-jungle-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 183, h = 170 }, x = -0.11537, y = -0.1132, w = 0.22575, h = 0.21027 },
} })
-- highborne: gemessen Ringmitte (423.4, 82.5), Innenradius 25.9, Leiste y 80.8 (Strecke 219), Spalte x 514.6 (Strecke 51) px
add("highborne", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.10916, norm = { k = 0.95417, dxRing = -1.375, dyRing = -1.5, dyTop = -0.46101, dxSide = 7.65807 }, pieces = {
    { key = "top", file = "mmorn-highborne-top", tw = 1024, th = 128, r = { x = 2, y = 2, w = 578, h = 124 }, x = -0.80965, y = -0.19311, w = 1.11338, h = 0.23837 },
    { key = "side", file = "mmorn-highborne-side", tw = 128, th = 1024, r = { x = 2, y = 2, w = 124, h = 560 }, x = 0.14915, y = 0.04118, w = 0.18009, h = 0.8163 },
    { key = "ring", file = "mmorn-highborne-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 163, h = 185 }, x = -0.11237, y = -0.15038, w = 0.2202, h = 0.24924 },
} })
-- centaur: gemessen Ringmitte (423.5, 83.0), Innenradius 25.1, Leiste y 71.7 (Strecke 192), Spalte x 513.0 (Strecke 143) px
add("centaur", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.11965, norm = { k = 0.98506, dxRing = -1.5, dyRing = -2, dyTop = 9.02034, dxSide = 6.56105 }, pieces = {
    { key = "top", file = "mmorn-centaur-top", tw = 1024, th = 128, r = { x = 2, y = 2, w = 512, h = 123 }, x = -0.82797, y = -0.18304, w = 1.18705, h = 0.28605 },
    { key = "side", file = "mmorn-centaur-side", tw = 128, th = 1024, r = { x = 2, y = 2, w = 97, h = 589 }, x = 0.19951, y = 0.0988, w = 0.13474, h = 0.81958 },
    { key = "ring", file = "mmorn-centaur-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 168, h = 179 }, x = -0.12539, y = -0.14893, w = 0.23335, h = 0.24889 },
} })
-- shendralas: gemessen Ringmitte (423.5, 82.5), Innenradius 25.8, Leiste y 80.5 (Strecke 118), Spalte x 514.6 (Strecke 80) px
add("shendralas", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.11348, norm = { k = 0.95648, dxRing = -1.5, dyRing = -1.5, dyTop = -0.21599, dxSide = 7.56708 }, pieces = {
    { key = "top", file = "mmorn-shendralas-top", tw = 512, th = 256, r = { x = 2, y = 2, w = 494, h = 152 }, x = -0.80714, y = -0.21058, w = 1.16065, h = 0.35672 },
    { key = "side", file = "mmorn-shendralas-side", tw = 128, th = 1024, r = { x = 2, y = 2, w = 103, h = 537 }, x = 0.19783, y = 0.14205, w = 0.13887, h = 0.72501 },
    { key = "ring", file = "mmorn-shendralas-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 171, h = 201 }, x = -0.11955, y = -0.16981, w = 0.23096, h = 0.27094 },
} })
-- goblin: gemessen Ringmitte (424.0, 81.6), Innenradius 25.3, Leiste y 80.2 (Strecke 243), Spalte x 515.5 (Strecke 71) px
add("goblin", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.11739, norm = { k = 0.97776, dxRing = -2, dyRing = -0.625, dyTop = -0.7826, dxSide = 5.32335 }, pieces = {
    { key = "top", file = "mmorn-goblin-top", tw = 1024, th = 128, r = { x = 2, y = 2, w = 597, h = 121 }, x = -0.81835, y = -0.12745, w = 1.13641, h = 0.23104 },
    { key = "side", file = "mmorn-goblin-side", tw = 128, th = 1024, r = { x = 2, y = 2, w = 91, h = 554 }, x = 0.20973, y = 0.09941, w = 0.12552, h = 0.76549 },
    { key = "ring", file = "mmorn-goblin-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 174, h = 170 }, x = -0.12509, y = -0.12733, w = 0.23983, h = 0.23452 },
} })
-- primal: gemessen Ringmitte (423.5, 82.3), Innenradius 25.7, Leiste y 82.5 (Strecke 160), Spalte x 517.1 (Strecke 107) px
add("primal", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.11539, norm = { k = 0.96113, dxRing = -1.5, dyRing = -1.25, dyTop = -2.38424, dxSide = 4.80355 }, pieces = {
    { key = "top", file = "mmorn-primal-top", tw = 1024, th = 128, r = { x = 2, y = 2, w = 550, h = 121 }, x = -0.80355, y = -0.17259, w = 1.1494, h = 0.25174 },
    { key = "side", file = "mmorn-primal-side", tw = 128, th = 1024, r = { x = 2, y = 2, w = 105, h = 571 }, x = 0.19602, y = 0.07505, w = 0.14322, h = 0.77505 },
    { key = "ring", file = "mmorn-primal-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 173, h = 180 }, x = -0.1216, y = -0.14601, w = 0.23429, h = 0.24421 },
} })
-- qiraji: gemessen Ringmitte (423.6, 82.6), Innenradius 25.7, Leiste y 85.3 (Strecke 127), Spalte x 514.1 (Strecke 77) px
add("qiraji", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.1181, norm = { k = 0.96113, dxRing = -1.625, dyRing = -1.625, dyTop = -4.68757, dxSide = 7.78361 }, pieces = {
    { key = "top", file = "mmorn-qiraji-top", tw = 1024, th = 128, r = { x = 2, y = 2, w = 684, h = 122 }, x = -0.91298, y = -0.16027, w = 1.28087, h = 0.22916 },
    { key = "side", file = "mmorn-qiraji-side", tw = 128, th = 1024, r = { x = 2, y = 2, w = 96, h = 585 }, x = 0.20557, y = 0.06478, w = 0.13073, h = 0.7942 },
    { key = "ring", file = "mmorn-qiraji-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 169, h = 181 }, x = -0.12415, y = -0.1484, w = 0.22988, h = 0.24626 },
} })
-- sky: gemessen Ringmitte (423.5, 82.3), Innenradius 25.7, Leiste y 82.0 (Strecke 136), Spalte x 515.7 (Strecke 63) px
add("sky", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.11675, norm = { k = 0.96113, dxRing = -1.5, dyRing = -1.25, dyTop = -1.89993, dxSide = 6.10352 }, pieces = {
    { key = "top", file = "mmorn-sky-top", tw = 1024, th = 128, r = { x = 2, y = 2, w = 527, h = 120 }, x = -0.80282, y = -0.19448, w = 1.14426, h = 0.26131 },
    { key = "side", file = "mmorn-sky-side", tw = 128, th = 1024, r = { x = 2, y = 2, w = 103, h = 581 }, x = 0.20337, y = 0.06273, w = 0.13954, h = 0.78873 },
    { key = "ring", file = "mmorn-sky-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 175, h = 183 }, x = -0.12234, y = -0.14943, w = 0.23722, h = 0.249 },
} })
-- arathor: gemessen Ringmitte (423.4, 82.4), Innenradius 25.7, Leiste y 80.2 (Strecke 242), Spalte x 503.0 (Strecke 115) px
add("arathor", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.1181, norm = { k = 0.96113, dxRing = -1.375, dyRing = -1.375, dyTop = -0.08467, dxSide = 18.20302 }, pieces = {
    { key = "top", file = "mmorn-arathor-top", tw = 1024, th = 128, r = { x = 2, y = 2, w = 515, h = 122 }, x = -0.76756, y = -0.17806, w = 1.16409, h = 0.27705 },
    { key = "side", file = "mmorn-arathor-side", tw = 128, th = 1024, r = { x = 2, y = 2, w = 118, h = 562 }, x = 0.23128, y = 0.09488, w = 0.16011, h = 0.76273 },
    { key = "ring", file = "mmorn-arathor-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 177, h = 195 }, x = -0.12347, y = -0.15661, w = 0.24016, h = 0.26405 },
} })
-- harvest: gemessen Ringmitte (423.5, 83.8), Innenradius 24.7, Leiste y 80.2 (Strecke 244), Spalte x 514.6 (Strecke 100) px
add("harvest", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.11723, norm = { k = 1, dxRing = -1.5, dyRing = -2.75, dyTop = 1.37305, dxSide = 3.60059 }, pieces = {
    { key = "top", file = "mmorn-harvest-top", tw = 1024, th = 128, r = { x = 2, y = 2, w = 522, h = 123 }, x = -0.84458, y = -0.16651, w = 1.17908, h = 0.27829 },
    { key = "side", file = "mmorn-harvest-side", tw = 128, th = 1024, r = { x = 2, y = 2, w = 123, h = 553 }, x = 0.18701, y = 0.1075, w = 0.17423, h = 0.78148 },
    { key = "ring", file = "mmorn-harvest-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 166, h = 184 }, x = -0.12347, y = -0.1647, w = 0.23383, h = 0.25978 },
} })
-- frost: gemessen Ringmitte (423.6, 82.6), Innenradius 25.7, Leiste y 80.2 (Strecke 242), Spalte x 514.4 (Strecke 143) px
add("frost", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.12489, norm = { k = 0.96113, dxRing = -1.625, dyRing = -1.625, dyTop = 0.15561, dxSide = 7.52362 }, pieces = {
    { key = "top", file = "mmorn-frost-top", tw = 1024, th = 128, r = { x = 2, y = 2, w = 593, h = 123 }, x = -0.80061, y = -0.13633, w = 1.15087, h = 0.23805 },
    { key = "side", file = "mmorn-frost-side", tw = 128, th = 1024, r = { x = 2, y = 2, w = 101, h = 555 }, x = 0.19309, y = 0.09762, w = 0.13661, h = 0.75384 },
    { key = "ring", file = "mmorn-frost-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 187, h = 195 }, x = -0.13076, y = -0.15045, w = 0.25412, h = 0.26473 },
} })
-- dalaran: gemessen Ringmitte (423.4, 82.4), Innenradius 25.8, Leiste y 82.8 (Strecke 166), Spalte x 515.5 (Strecke 138) px
add("dalaran", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.11888, norm = { k = 0.95648, dxRing = -1.375, dyRing = -1.375, dyTop = -2.50444, dxSide = 6.67131 }, pieces = {
    { key = "top", file = "mmorn-dalaran-top", tw = 1024, th = 128, r = { x = 2, y = 2, w = 558, h = 121 }, x = -0.79764, y = -0.20037, w = 1.11753, h = 0.24303 },
    { key = "side", file = "mmorn-dalaran-side", tw = 128, th = 1024, r = { x = 2, y = 2, w = 107, h = 570 }, x = 0.19418, y = 0.03857, w = 0.14399, h = 0.76994 },
    { key = "ring", file = "mmorn-dalaran-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 179, h = 196 }, x = -0.12433, y = -0.1579, w = 0.24192, h = 0.26481 },
} })
-- dusk: gemessen Ringmitte (423.4, 82.1), Innenradius 25.5, Leiste y 80.2 (Strecke 187), Spalte x 514.4 (Strecke 101) px
add("dusk", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.11104, norm = { k = 0.97056, dxRing = -1.375, dyRing = -1.125, dyTop = -0.30724, dxSide = 6.42506 }, pieces = {
    { key = "top", file = "mmorn-dusk-top", tw = 1024, th = 128, r = { x = 2, y = 2, w = 522, h = 121 }, x = -0.81184, y = -0.17284, w = 1.14511, h = 0.26457 },
    { key = "side", file = "mmorn-dusk-side", tw = 128, th = 1024, r = { x = 2, y = 2, w = 105, h = 570 }, x = 0.19013, y = 0.08758, w = 0.14388, h = 0.78127 },
    { key = "ring", file = "mmorn-dusk-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 164, h = 187 }, x = -0.11652, y = -0.15401, w = 0.22546, h = 0.25628 },
} })
-- menethil: gemessen Ringmitte (423.6, 83.8), Innenradius 23.9, Leiste y 77.5 (Strecke 167), Spalte x 512.5 (Strecke 143) px
add("menethil", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.1256, norm = { k = 1.03398, dxRing = -1.625, dyRing = -2.75, dyTop = 4.35772, dxSide = 2.87063 }, pieces = {
    { key = "top", file = "mmorn-menethil-top", tw = 1024, th = 128, r = { x = 2, y = 2, w = 549, h = 121 }, x = -0.88316, y = -0.17712, w = 1.23415, h = 0.27155 },
    { key = "side", file = "mmorn-menethil-side", tw = 128, th = 1024, r = { x = 2, y = 2, w = 64, h = 584 }, x = 0.23168, y = 0.09002, w = 0.09323, h = 0.85219 },
    { key = "ring", file = "mmorn-menethil-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 175, h = 192 }, x = -0.13198, y = -0.17176, w = 0.25521, h = 0.28112 },
} })
-- fel: gemessen Ringmitte (423.4, 83.6), Innenradius 25.2, Leiste y 83.8 (Strecke 243), Spalte x 514.4 (Strecke 143) px
add("fel", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.11629, norm = { k = 0.98018, dxRing = -1.375, dyRing = -2.625, dyTop = -2.27634, dxSide = 5.54977 }, pieces = {
    { key = "top", file = "mmorn-fel-top", tw = 1024, th = 128, r = { x = 2, y = 2, w = 565, h = 122 }, x = -0.82179, y = -0.201, w = 1.15795, h = 0.25045 },
    { key = "side", file = "mmorn-fel-side", tw = 128, th = 1024, r = { x = 2, y = 2, w = 88, h = 586 }, x = 0.21707, y = 0.04526, w = 0.12209, h = 0.81134 },
    { key = "ring", file = "mmorn-fel-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 172, h = 179 }, x = -0.12217, y = -0.14504, w = 0.23743, h = 0.24766 },
} })
-- legion: gemessen Ringmitte (423.5, 82.3), Innenradius 25.7, Leiste y 83.0 (Strecke 228), Spalte x 515.2 (Strecke 73) px
add("legion", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.13711, norm = { k = 0.96113, dxRing = -1.5, dyRing = -1.25, dyTop = -2.86856, dxSide = 6.6235 }, pieces = {
    { key = "top", file = "mmorn-legion-top", tw = 1024, th = 128, r = { x = 2, y = 2, w = 636, h = 124 }, x = -0.79694, y = -0.19106, w = 1.15087, h = 0.22506 },
    { key = "side", file = "mmorn-legion-side", tw = 128, th = 1024, r = { x = 2, y = 2, w = 97, h = 602 }, x = 0.20777, y = 0.0299, w = 0.1322, h = 0.81746 },
    { key = "ring", file = "mmorn-legion-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 205, h = 206 }, x = -0.14217, y = -0.14601, w = 0.27762, h = 0.2791 },
} })
-- totem: gemessen Ringmitte (423.5, 83.3), Innenradius 25.0, Leiste y 84.8 (Strecke 215), Spalte x 510.6 (Strecke 143) px
add("totem", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.11885, norm = { k = 0.98999, dxRing = -1.5, dyRing = -2.25, dyTop = -3.64677, dxSide = 8.52991 }, pieces = {
    { key = "top", file = "mmorn-totem-top", tw = 512, th = 128, r = { x = 2, y = 2, w = 502, h = 119 }, x = -0.83269, y = -0.19239, w = 1.22174, h = 0.2903 },
    { key = "side", file = "mmorn-totem-side", tw = 128, th = 1024, r = { x = 2, y = 2, w = 84, h = 567 }, x = 0.21127, y = 0.09369, w = 0.11801, h = 0.79268 },
    { key = "ring", file = "mmorn-totem-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 171, h = 208 }, x = -0.12526, y = -0.18561, w = 0.23905, h = 0.2903 },
} })
-- theramore: gemessen Ringmitte (423.6, 83.4), Innenradius 25.8, Leiste y 82.5 (Strecke 123), Spalte x 515.2 (Strecke 143) px
add("theramore", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.09322, norm = { k = 0.95648, dxRing = -1.625, dyRing = -2.375, dyTop = -1.30697, dxSide = 7.16916 }, pieces = {
    { key = "top", file = "mmorn-theramore-top", tw = 1024, th = 128, r = { x = 2, y = 2, w = 514, h = 121 }, x = -0.79691, y = -0.16089, w = 1.11168, h = 0.26141 },
    { key = "side", file = "mmorn-theramore-side", tw = 256, th = 512, r = { x = 2, y = 2, w = 125, h = 495 }, x = 0.16713, y = 0.09644, w = 0.18784, h = 0.74271 },
    { key = "ring", file = "mmorn-theramore-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 140, h = 175 }, x = -0.09943, y = -0.14699, w = 0.18857, h = 0.23622 },
} })
-- renewal: gemessen Ringmitte (423.4, 83.5), Innenradius 24.2, Leiste y 83.5 (Strecke 227), Spalte x 514.1 (Strecke 143) px
add("renewal", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.1532, norm = { k = 1.02328, dxRing = -1.375, dyRing = -2.5, dyTop = -2.15287, dxSide = 1.90453 }, pieces = {
    { key = "top", file = "mmorn-renewal-top", tw = 512, th = 256, r = { x = 2, y = 2, w = 508, h = 143 }, x = -0.87282, y = -0.20885, w = 1.17447, h = 0.33138 },
    { key = "side", file = "mmorn-renewal-side", tw = 128, th = 1024, r = { x = 2, y = 2, w = 115, h = 555 }, x = 0.18514, y = 0.11816, w = 0.16655, h = 0.80186 },
    { key = "ring", file = "mmorn-renewal-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 215, h = 213 }, x = -0.15882, y = -0.17218, w = 0.31043, h = 0.30734 },
} })
-- scourge: gemessen Ringmitte (423.4, 83.8), Innenradius 24.5, Leiste y 83.8 (Strecke 244), Spalte x 508.4 (Strecke 143) px
add("scourge", { sunX = -0.22034, sunY = -0.05932, sunR = 0.08757, ringR = 0.12097, norm = { k = 1.00764, dxRing = -1.375, dyRing = -2.75, dyTop = -2.15448, dxSide = 9.04741 }, pieces = {
    { key = "top", file = "mmorn-scourge-top", tw = 1024, th = 128, r = { x = 2, y = 2, w = 621, h = 122 }, x = -0.83537, y = -0.19499, w = 1.21966, h = 0.24025 },
    { key = "side", file = "mmorn-scourge-side", tw = 128, th = 1024, r = { x = 2, y = 2, w = 121, h = 516 }, x = 0.16715, y = 0.04096, w = 0.20251, h = 0.86419 },
    { key = "ring", file = "mmorn-scourge-ring", tw = 256, th = 256, r = { x = 2, y = 2, w = 169, h = 167 }, x = -0.12713, y = -0.1344, w = 0.24101, h = 0.2381 },
} })
