# Third-party components / Fremdbestandteile

Everything below keeps its own license. The license texts lie next to the files.
Alle Folgenden behalten ihre eigene Lizenz; die Lizenztexte liegen bei den Dateien.

## Libraries

Lucid embeds no libraries: there is no `Libs` folder and no LibStub copy in the package.

HereBeDragons and Questie are not shipped either. If another addon has loaded them, Lucid only reads what they
expose at run time (for example to tell their minimap pins from addon buttons). For the nameplate style Lucid reads Questie's
public API (`Questie.API.GetQuestObjectiveIconForUnit`) and its icon tables, and sets only the transparency of Questie's own
icons on a nameplate (and puts it back); no file of Questie is included and nothing is written into Questie. Open Map and Ink & Embers are
treated the same way: Lucid reads their frames, it does not copy or redistribute any of their files.

## Fonts

Three fonts in `Fonts\`, all under the SIL Open Font License 1.1. They are not renamed or modified.
The license texts are `Fonts\OFL-*.txt`.

| Font | File | Copyright holder | Reserved Font Name (RFN) | Source |
|---|---|---|---|---|
| Cinzel | `Fonts\Cinzel-Regular.ttf` | The Cinzel Project Authors, Natanael Gama | "Cinzel Decorative" (not this font) | https://github.com/NDISCOVER/Cinzel |
| Cormorant Garamond Medium | `Fonts\CormorantGaramond-Medium.ttf` | Christian Thalmann and the Cormorant Project Authors | none declared | https://github.com/CatharsisFonts/Cormorant |
| Marcellus | `Fonts\Marcellus-Regular.ttf` | Brian J. Bonislawsky DBA Astigmatic (AOETI) | "Marcellus" | see `Fonts\OFL-Marcellus.txt` |

The Cormorant Garamond file is version 3.601, a static Medium cut. A single weight was chosen to keep the file below 1 MiB.

## Graphics and media

The files in `Media\` (minimap frames and masks, zone text ornaments, nameplate style textures, the addon icon) are not
covered by the MIT license, see `LICENSE`.

Made with Google Gemini and processed by the author: the seven minimap frames (rivets, crest, compass, patina, narrow,
cord, double line), the zone ornament styles vine, baroque, filigree2, gothic, arcane, celestial, thorns, blades and
waves, and the addon icon. Scripts of the development repository cut and converted those images to textures; the images
themselves are kept there and are not part of the package.

Nameplate style (`Media\np-*.tga`): made with Google Gemini and processed by the author are the bronze bar frame and the
cast bar frame (`np-frame`, `np-castframe`), the level plaque (`np-level`), the liquid fill (`np-liquid`, `np-liquid-mono`), the cast magic
(`np-castmagic`, `np-castmagic-mono`), the spark (`np-spark`), the shield (`np-shield`), the elite and rare dragons (`np-elite`,
`np-rare`), the skull (`np-skull`), the quest mark (`np-quest`) and the objective icons (`np-obj-loot`, `np-obj-slay`,
`np-obj-interact`). The source images are kept in `docs/nameplate-src` of the development repository and are not part of
the package. Drawn by script, with no third-party image: `np-fill`, `np-veil`, `np-mask-capsule`, `np-inset`, `np-glass`,
`np-endfade` and `np-glow`.

Drawn by script, with no third-party image: the zone ornaments swirl and filigree, the light band, the glow and the
minimap shape masks.

## Game content

World of Warcraft, its interface and the names of places, zones and spells are (c) Blizzard Entertainment, Inc.
Lucid is not affiliated with or endorsed by Blizzard. It contains no copied Blizzard textures; it only
changes how the game's own interface elements are shown.
