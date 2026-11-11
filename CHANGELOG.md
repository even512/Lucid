# Changelog

## 1.3.0

### Immersive nameplate style (opt-in)
- Lucid can now give Blizzard's nameplates a look that fits the world instead of an overlay: a slim bar in a dark bronze
  frame with a living liquid fill, ember colours by stance (hostile, neutral, friendly), a calm own name font with a soft ink
  veil, and a warm glow under your target. It is off by default; with it off the nameplates look exactly like Blizzard's.
- Level and rank: the level sits in a small bronze plaque, elite gets a bronze dragon, rare a silver dragon, bosses a skull.
- Quest objectives: enemies that belong to an active quest show a bag (collect), crossed swords (kill) or a gauntlet
  (interact) next to the bar. With Questie loaded Lucid asks its public API (read only) and hides Questie's own icon on the
  nameplate; without Questie it falls back to a golden "!".
- Bar on demand (only the name outside combat and at full health; your target always keeps its bar), peaceful creatures
  show only a small pale name, and a low-health glimmer for the execute range (default below 20 %, 10 to 35 % adjustable).
- Depth: distant nameplates get smaller and paler. New "All nameplates the same size" switch and "Target size" (100 to 130 %)
  replace Blizzard's 1.2x target enlargement and 80 % distance shrinking; depth takes precedence for the distance scaling.
  All of it goes through the same safe CVar handling as the rest (values are restored when you turn it off or log out).
- Styled cast bar: a thin glowing thread in its own bronze frame under the bar, with flowing magic, a spark at the leading
  edge and a shield for spells that cannot be interrupted.
- Three presets, "Subtle", "Immersive" and "Cinematic", switch the building blocks together (visibility and range are not
  touched); every block can also be turned on or off on its own.
- Nameplates tab: new view "Appearance" with a live preview (sample nameplate with sample states: stance, rank, quest, health,
  cast, target, combat; click the preview for a dark or light background), all building blocks with tooltips, bar height,
  font and size, ember threshold, depth values and the size options. The sample values change nothing in the game.
- If Plater, Kui Nameplates, TidyPlates, Threat Plates, Platynator or ElvUI nameplates are loaded, the style stays off and
  the tab says why; the visibility rules keep working.
- Commands: `/lucid nameplates style on|off|dezent|immersiv|filmisch` (also `subtle|immersive|cinematic`), `style test` (try it
  on your target), `style panel` (test window), `style rank|cast` (previews), `style debug|trace`.
- Raid target marker: with the style on, the marker (skull, cross, ...) sits centred above the nameplate name; with the style
  off Blizzard's position is restored.

### Quest far view (opt-in)
- Distant quest enemies whose nameplates would be invisible show only their quest symbol (bag, swords, gauntlet or "!"),
  using the same rule as the quest objectives above. Off by default; own view "Quest far view" in the Nameplates tab with a
  live preview (symbol size, opacity, pulse, halo) and `/lucid nameplates far on|off`.
- Range depends on the client: Forever 20 to 45 yards, Retail 20 to 60 yards. A view-distance limit (radius) is kept through
  Blizzard's distance opacity, so it still applies while the far view is on.
- Invisible nameplates do not catch clicks. It needs Lucid's nameplate control and stays off if another nameplate addon is
  loaded.
- Test mode `/lucid nameplates far test [loot|slay|interact|!|mix|off]` shows the far view on all hostile enemies nearby for
  the session (also a button in the tab and in the test window); `/lucid nameplates probe far|click` are diagnostic probes.

### Copy window for diagnostics
- The output of the probe and debug commands (for example `/lucid nameplates probe`, `style debug`) opens in a window with the
  text selected, so you can copy it with Ctrl+C instead of scrolling the chat.

### Minimap zone ornament
- A golden zone ornament in the style of the zone card wraps the top and right of the rectangular 4:3 minimap and changes
  with the zone: 43 zone motifs, with a ring around the sun/moon (day/night symbol). Zones without a motif stay plain.
  A thin dark edge keeps it readable on bright ground.
- Minimap tab, group "Zone ornament": switch, size, opacity, horizontal and vertical offset, and "Place over sun and moon".
  The ornament fades with the minimap. `/lucid minimap ornament on|off|probe` (the probe shows motif, zone and sizes).

## 1.2.0

### Chat readability
- New "Readability" options in the Chat tab: text outline (none, thin, thick) and a stronger text shadow. They work on every chat
  window, including new and whisper windows and after changing the font size, independent of the glass look and message
  fading. Font and size stay as they are; turning them off restores the previous text exactly.
- `/lucid chat outline none|thin|thick`, `/lucid chat shadow on|off`.

### Hide other addons
- New group "Addons" in the Hide tab: RestedXP guide and RestedXP arrow, Details! meter (all windows, also ones you open
  later), VuhDo (also panels that appear when your group changes), Grid2, Cell and HealBot. Lucid only changes their
  opacity (and lets clicks through outside combat), never shows, hides or moves them. Rows of addons you do not use are
  greyed out ("... missing"). They are off by default and presets leave them alone.

### Cooldown Manager
- Blizzard's Cooldown Manager can be hidden like the action bars: four separate entries (essential, utility, buff icons,
  buff bars) in the Action bars group. Lucid keeps its value when Blizzard applies the Edit Mode opacity. The Immersion and
  Balanced presets treat them like the action bars.

### Debuff condition
- New condition "Debuff on you": shows a frame while a harmful effect is on you, also out of combat (for example a Faerie
  Fire). Deserter, Resurrection Sickness and Exhaustion do not count. While the game locks aura data in combat, the last
  value is kept. The Immersion and Balanced presets now show the debuff bar with it (apply the preset again).

### Hide tab
- The element list got longer and now has a scroll bar (the mouse wheel works too).
- Row labels stay on one line; long names are cut off instead of running into the next row. The Cooldown Manager rows use
  short names, the tooltip shows the full name.

## 1.1.0

### Zone ornaments that match the zone
- The large zone card now shows an ornament that fits the zone you enter: 41 new hand-picked motifs for every classic zone
  and city and the WoW Forever zones (Zephras Isle, Darkspear Islands, Riverglades, Shen'dralas, Mount Hyjal). Examples:
  the Bronzebeard hammer in Ironforge and Dun Morogh, the Forsaken crest in Tirisfal and the Undercity, the Horde crest in
  Durotar and Orgrimmar, the World Tree with Archimonde's remains on Mount Hyjal.
- New option "Ornament adapts to the zone" in the Zone text tab (on by default). The ornament you pick ("Ornament (fixed)")
  is used in zones without a motif of their own, and everywhere when the option is off. "None" always turns the ornament
  off. All zone motifs can also be picked as a fixed ornament.
- `/lucid zone auto [on|off]`; `/lucid zone test <motif>` shows one motif, `/lucid zone test all` plays all of them,
  `/lucid zone test stop` ends it. `/lucid zone debug` shows the map and the chosen motif.
- Ornaments keep their distance from a long subzone name or the "Discovered" line instead of overlapping it.
- The download is larger than before because of the new artwork.

### Camera
- The target focus on enemies now fades in and out (new setting "Target focus transition time", default 1.5 s) instead of
  snapping to the target; the cinematic presets zoom over 1.5 s.
- Smoother zoom when several camera rules change quickly one after another.

## 1.0.3

The map key no longer changes your saved key bindings; it uses a temporary override. If an earlier version put Lucid's map action on a key, Lucid restores that key once, a few seconds after you enter the world. Shift plus the map key opens Blizzard's large map only if that combination is free. A key that has another action, such as the default Shift+M for the battlefield map, keeps it; you can bind the large map to a key of your own under Key Bindings > AddOns.

## 1.0.2

In map mode the map filter button with its red reset X now sits inside the map frame, left of Lucid's quest list button, instead of floating above the frame on WoW Forever, and it stays there when another addon moves it.

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
