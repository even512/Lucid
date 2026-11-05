# Changelog

## 1.0.1

Lucid now saves the key bindings of the map only when it actually changes one, and only once your bindings have been loaded.

## 1.0.0

First release. Lucid runs on WoW Forever (Interface 16001) and on Retail 12.1.5 (Interface 120105). After the installation
every part is off until you switch it on. Only Lucid's own minimap button is shown by default.

### Hide the interface
- 23 interface elements can fade out and come back on conditions: action bars, stance, pet and possess bars, micro menu,
  bag bar, player, target, focus and pet frames, minimap, quest tracker, buffs, debuffs, XP and reputation bar, and the
  Questie tracker when Questie is installed.
- Conditions: combat, target, focus, mouse over, resting, capital city, group, raid, instance, mounted, flying, casting,
  away, typing in chat, health not full, resource not at rest, talking to an NPC, indoors, swimming. Locked values count as
  not met.
- Base opacity, fade-in and fade-out times and a delay per element, a row "For all elements" and `/lucid delay <sec>` to set
  them together.
- Clicks can go through hidden elements, outside of combat.
- Presets: Immersion, Balanced, Combat, Off. "Simulate state" in the window shows the effect of a state without changing it.
- The to-do note that Ink & Embers docks to the quest tracker fades with the tracker.
- Profiles: a shared Default profile, an own profile per character, create, copy, rename, delete, reset, and export and
  import as text with a checksum.
- Settings window with `/lucid`, and an entry in Blizzard's AddOns options.

### Chat
- Glass look: background, tabs and buttons of the chat appear on mouseover or while typing.
- Chat messages can fade out one by one after a time you set.

### Zone text
- A card with zone name and subzone replaces Blizzard's zone text, with ornaments, glow, a light band, font, size, timing
  and a movable position. Newly discovered areas get a card as well. `/lucid zone test` plays a sample.

### Minimap
- Square and rectangular shapes (3:2, 4:3, 16:9, 2:3, 3:4) next to Blizzard's round map, with a choice of frames, frame
  strength, size and an N marker.
- Coordinates, location name, clock, calendar, mail, tracking, difficulty, expansion button, addon compartment, zoom buttons
  and addon icons can each stay, show on mouseover or be hidden.
- A Lucid minimap button: left-click opens the window, right-click opens a menu, dragging moves it along the edge.
- Questie pins on the minimap are no longer taken for addon icons.

### World map
- Lucid map mode: a slim map window in the same frame style, with optional hiding of the header and Blizzard's window
  frame, a quest list that is hidden, collapsible or always shown, opacity, and lower opacity while you move.
- The map key can open it, Blizzard's large map moves to Shift plus the key. Both keys are in the key bindings under Lucid.
- With Open Map installed, Lucid can place and scale the window through Open Map's settings or leave that to Open Map.

### Nameplates
- Nameplates only appear in the states you pick, optionally always for your target, with soft or hard fading and a limit for
  the view distance. Presets: Combat only, Combat and target.

### Camera
- Presets: Cinematic, Cinematic calm, Cinematic dynamic, Classic, Wide in combat.
- Action Cam values, zoom distances and rules per state, including combat, conversations, mounted, flying, swimming and
  indoors. Lucid turns Blizzard's motion sickness options off while it needs them and restores them afterwards.

### Commands
- `/lucid help` lists all commands. For troubleshooting there are `nameplates probe`, `camera probe`, `map probe`,
  `zone debug` and `minimap debug`. The map probe runs short write tests on the map and restores the values at once.

### Known limits
- With the rectangular minimap, pins that HereBeDragons draws at the map edge can sit about 16 pixels outside the rectangle
  at the top and bottom.
- Fading depends on what the game lets addons read. In combat and in instances some values are locked; Lucid then waits
  or marks the setting as not available.

### About this release
The code was written with Claude Code. Many of the images (minimap frames, zone ornaments, icon) were made with Google
Gemini and edited by the author.
