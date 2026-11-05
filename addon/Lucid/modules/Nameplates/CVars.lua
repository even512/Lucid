-- Plaketten (B7/N1): Katalog der verwalteten Plaketten-CVars. Der Treiber selbst (Existenz-Pruefung, Sicherung,
-- Kampf-Warteschlange, Wiederherstellung, CVAR_UPDATE) liegt in CVarDriver.lua und wird auch von der Kamera genutzt.
local _, ns = ...

local NAMES = {
    ENEMIES = "nameplateShowEnemies",
    FRIEND_PLAYERS = "nameplateShowFriendlyPlayers",
    FRIEND_NPCS = "nameplateShowFriendlyNpcs",
    SHOW_ALL = "nameplateShowAll",
    MAX_DISTANCE = "nameplateMaxDistance",
}

-- verwaltete CVars (Reihenfolge = Ausgabe)
local CVars = ns.CVarDriver.New("nameplates", {
    NAMES.ENEMIES, NAMES.FRIEND_PLAYERS, NAMES.FRIEND_NPCS, NAMES.SHOW_ALL, NAMES.MAX_DISTANCE,
})
for k, v in pairs(NAMES) do CVars[k] = v end
ns.CVars = CVars
