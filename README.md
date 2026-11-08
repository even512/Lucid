# Lucid

An immersion UI suite for World of Warcraft. Lucid fades out parts of the interface while you do not need them and
brings them back when you do. It also replaces the zone text, reshapes the minimap, adds a slim world map, hides
nameplates outside of fights and adjusts the camera. I made it for WoW Forever (Interface 16001), and it runs on Retail
(12.1.5, Interface 120105) from the same download. Version 1.0.0 is the first release; the changes are in
`CHANGELOG.md`.

Every part is switched on or off on its own. After the installation all of them are off; only Lucid's own minimap button is
shown, and `/lucid minimap button off` hides it. Settings live in profiles.

## What it does

Hide the interface. Lucid can fade 23 elements: the action bars, stance, pet and possess bars, the micro menu, the bag
bar, the player, target, focus and pet frames, the minimap, the quest tracker, buffs, debuffs, the XP and reputation bar
and, when Questie is installed, its tracker. Each element has a base opacity and a list of
conditions that bring it back: in combat, has target, has focus, mouse over, resting, in a capital city, in a group,
in a raid, in an instance, mounted, flying, casting, away, typing in chat, health not full, resource not at rest, talking
to an NPC, indoors and swimming. Fade-in and fade-out times and a delay are set per element, and a row "For all elements" sets them together.
While an element is fully hidden, clicks can go through to the world (not in combat). The presets Immersion, Balanced,
Combat and Off fill in all elements; you can change everything afterwards. The to-do note that Ink & Embers docks to the
quest tracker fades together with the tracker.

Chat. An optional glass look hides the chat background, tabs and buttons until the mouse is over the chat or you type.
Chat messages can also fade out one by one after a time you set.

Zone text. A card with the zone name and subzone replaces Blizzard's zone text, with a choice of ornaments, glow, a light
band behind the text, font, size and timing. Every classic zone and the WoW Forever zones have their own ornament that
matches the zone (for example Ironforge, Tirisfal, Orgrimmar or Mount Hyjal); untick "Ornament adapts to the zone" to use
one fixed ornament everywhere. Newly discovered areas get their own card. You can move it, and `/lucid zone test` plays
a sample (`/lucid zone test all` shows every zone ornament).

Minimap. Besides Blizzard's round map there are a square and a rectangular shape (3:2, 4:3, 16:9, 2:3, 3:4) with a choice
of frames, a frame strength, a size and an optional N marker. Coordinates, location name, clock, calendar, mail, tracking,
difficulty, expansion button, addon compartment, zoom buttons and addon icons can each stay, show on mouseover or go.
Lucid has its own minimap button: left-click opens the window, right-click opens a menu for presets, camera, map and zone
text, and you can drag it along the edge.

World map. The Lucid map mode turns the world map into a slim window in the same frame style, with a choice of hiding the
header and Blizzard's window frame, a quest list that is hidden, collapsible or always shown, opacity, and a lower opacity
while you move. The map key can open it, and Blizzard's large map is on Shift plus the key if that combination is free.
Both are listed under Lucid in the key bindings. The map's content and its pins stay as they are. If Open Map is installed, Lucid can place
and scale the window through its settings or leave that to Open Map.

Nameplates. Lucid shows nameplates only in the states you pick, for example in combat or with a target, and can always show
your target's nameplate. Fading is soft or hard, and the view distance can be limited. Two presets, "Combat only" and
"Combat and target", set this up.

Camera. Presets set the Action Cam values and zoom distances per state: Cinematic, Cinematic calm, Cinematic dynamic, Classic
and Wide in combat. Shoulder offset, dynamic pitch, head movement, target focus and zoom can be set in the Camera tab, with
rules for states such as combat, conversations, mounted, flying, swimming and indoors.

Profiles. The Default profile is shared by the account, and each character can have its own. Profiles can be created,
copied, renamed, deleted and reset, and exported and imported as text that carries a checksum.

## Installation

From CurseForge: install Lucid with your usual addon manager.

By hand: copy the folder `addon/Lucid` to `Interface/AddOns/Lucid` in your game folder (`_forever_` or `_retail_`).
A new file such as a texture or font is only picked up after a full restart of the game; for changed Lua files `/reload`
is enough.

## Commands

`/lucid` opens and closes the settings window. The entry "Lucid" in the AddOns page of Blizzard's options opens it as
well. These commands are available in the game:

| Command | What it does |
|---|---|
| `/lucid help` | list all commands |
| `/lucid version` | show the version |
| `/lucid status` | show which elements were found and are active |
| `/lucid toggle <element>` | switch an element on or off; without a name it lists them |
| `/lucid delay <sec>` | set the delay for all elements of the active profile |
| `/lucid preset <name>` | apply a preset: `immersion`, `balanced`, `combat`, `off` |
| `/lucid chat glass on\|off` | chat look: background, tabs and buttons only on mouseover or while typing |
| `/lucid chat fade on\|off` | fade out chat messages one by one |
| `/lucid chat time <sec>` | how long a message stays visible (1 to 600 seconds) |
| `/lucid zone` | status of the zone text; `zone on\|off`, `zone test [zone\|subzone\|discovery\|<motif>\|all\|stop]`, `zone move`, `zone seed` |
| `/lucid minimap` | `minimap shape <round\|square\|rect> [ratio]`, `minimap scale`, `minimap border`, `minimap bordersize`, `minimap north on\|off`, `minimap button [on\|off]` |
| `/lucid nameplates` | `on`, `off`, `status`, `preset <combat\|combattarget\|off>` |
| `/lucid camera` | `on`, `off`, `status`, `preset <cinematic\|cinematicCalm\|cinematicDynamic\|classic\|combatwide>` |
| `/lucid map [on\|off\|status]` | Lucid map mode for the world map |

For troubleshooting there are `/lucid nameplates probe`, `/lucid camera probe`, `/lucid map probe`, `/lucid zone debug`
and `/lucid minimap debug`, as well as `debug` for nameplates and camera. They print what the addon found. The map probe
also runs short write tests on the map and puts the values back right away. You do not need them in normal play.

## Compatibility

The addon is written for WoW Forever and Retail 12.1.5. In combat and in instances Blizzard locks some values and
frames for addons. Where that matters, Lucid waits until combat ends or marks the setting as not available, and it does not
raise errors for locked values.

Optional addons are only read, never changed or copied: Questie (its tracker can be faded as an element, and its minimap
pins are not treated as addon icons), Open Map (placement of the Lucid map) and Ink & Embers (its to-do note fades with
the tracker). None of them is required.

Known limit: with the rectangular minimap, pins that HereBeDragons draws at the edge of the map can sit about 16 pixels
outside the rectangle at the top and bottom.

## Data and privacy

Everything stays on your computer. Lucid uses no network and sends no addon messages. The settings are saved in the
account-wide SavedVariables file `WTF/Account/<ACCOUNT>/SavedVariables/Lucid.lua`, in the variable `LucidDB`. WoW writes
that file on logout and on reload. Lucid sets some game settings (CVars) for nameplates and camera. When you switch the part off, the previous values come
back. The option "Take over the map key" uses a temporary override and does not change your saved key bindings. Only if an
earlier version of Lucid put its map action on a key does Lucid restore that key, once.

## Feedback

Bugs, wishes and questions go to https://github.com/even512/Lucid/issues. For an error please include the exact message
(`/console scriptErrors 1` shows Lua errors in the game), the Lucid version from `/lucid version` and your client
(WoW Forever or Retail, and the build). A template for bug reports is in `.github/ISSUE_TEMPLATE`.

## Building from the source

You need Node 20 or newer, and only for the helper scripts. The addon itself needs nothing.

1. `npm install`
2. Copy `.env.example` to `.env` and set `WOW_DIR`, for example `WOW_DIR=D:\World of Warcraft`. The file stays local.
3. `npm run install-addon` copies the addon to `_forever_`. Add `-- --retail` for `_retail_`, or `-- --dry-run` to only
   list what would change.

`npm run check` parses all Lua files with luaparse (Lua 5.1). Releases are built by the BigWigs packager from a tag `v*`
(`.pkgmeta`, `.github/workflows/release.yml`). The test suite stays in a private development repository.

## Licenses

- The code is under the MIT license, (c) 2026 EveN. The graphics and media (the files in `Media`: minimap frames, zone
  ornaments, the icon) are not covered by it: all rights reserved, as far as protection exists. See `LICENSE`.
- The three fonts in `Fonts` (Cinzel, Cormorant Garamond, Marcellus) are under the SIL Open Font License 1.1. Details are in
  `addon/Lucid/THIRD-PARTY.md`. Lucid contains no libraries.
- World of Warcraft and its game content are (c) Blizzard Entertainment. This addon is not affiliated with or endorsed
  by Blizzard.

## AI notice

I wrote the code with Claude Code, and many of the images were made with Google Gemini and then edited by me. I plan,
test and maintain the addon myself.

## Support

If you want to support the development, you can do so on Ko-fi: https://ko-fi.com/even512
