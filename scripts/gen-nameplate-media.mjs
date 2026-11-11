// Erzeugt die Texturen des Plaketten-Stils (Delta "Immersiver Plaketten-Stil") als unkomprimierte 32-bit-TGA
// (Format wie scripts/gen-minimap-media.mjs, tgaRgba).
//
// Aus den freigegebenen Gemini-Vorlagen (docs/nameplate-src/, schwarzer Grund):
//   np-frame.tga  256 x 32   Bronze-Balkenrahmen mit Blatt-Enden aus np-frame-v1.jpg. Schwarz -> Alpha (weicher
//                            Uebergang, Innen-Schlitz durchsichtig). Drei Teile nach Spalten: linke Kappe 0..32,
//                            dehnbare Mitte 32..224 (Ausschnitt aus der Mitte der Vorlage), rechte Kappe 224..256.
//   np-level.tga   64 x 32   Stufen-Plaettchen aus np-level-v1.jpg (Hintergrund von aussen her freigestellt, die dunkle
//                            Innenflaeche bleibt deckend).
// Prozedural (deterministisch):
//   np-fill.tga   128 x 16   Fuellung matt (Wahl Runde 2): flacher dunkler Koerper (Rost/Kohle), glimmende
//                            Oberkante, feine Maserung; Grauwert, per SetStatusBarColor nach Haltung eingefaerbt.
//   np-mask-capsule.tga 256 x 16  Kapsel-Maske (runde Enden) fuer Lucids Fuellungs-Lagen im Schlitz (MaskTexture).
//   np-glass.tga    64 x 4   Glasglanz, an beiden Enden weich auslaufend.
//   np-endfade.tga  64 x 4   Endblende (MaskTexture ueber dem Schlitz): Alpha waagrecht zu beiden Roehrenenden weich auf 0,
//                            senkrecht gleich; laesst Meniskus und Glasglanz vor den Kappen auslaufen.
//   np-inset.tga   256 x 16  innerer Schatten im Schlitz (Alpha dunkel an den Kanten, per Vertexfarbe schwarz).
//   np-veil.tga    64 x 32   Tinten-Schleier hinter dem Namen (weiche Ellipse, weiss, per Vertexfarbe dunkel getoent).
//   np-glow.tga    64 x 32   Ziel-Schein: weicher Rand um den Rahmen (3-teilig), weiss, per Vertexfarbe getoent.
// Aus der Vorlage np-liquid-v1.jpg (rote Stroemung, waagrecht nahtlos):
//   np-liquid.tga       256 x 64   lebendige Fuellung (Lebensfluessigkeit): zwei flache, ruhige Ausschnitte ueber die
//                                  volle Breite (oben Lage A, unten Lage B), leicht weichgezeichnet; fliesst im Spiel
//                                  in zwei Lagen per TexCoord (REPEAT).
//   np-liquid-mono.tga  256 x 64   dieselbe, entsaettigt (Helligkeit), fuer neutral/freundlich per Vertexfarbe getoent.
// Zauberleiste (Etappe 4a, freigegeben): np-castframe.tga 256 x 32 aus np-castframe-v1.jpg, 3-teilig wie np-frame
//   (Laschen oben an den Kappen docken am Lebensbalken-Rahmen an); np-shield.tga 32 x 32 aus np-shield-v1.jpg;
//   np-castmagic(-mono).tga 256 x 64 aus np-castmagic-v1.jpg (zwei Lagen, orange-gold bzw. grau); np-spark.tga 64 x 64
//   aus np-spark-v1.jpg (Funken-Flash an der fuellenden Kante, additiv).
// Zier (Etappe 4a, freigegeben): np-elite/np-rare 64 x 64 (Bronze-/Silber-Drache um eine Scheibe, Stufenzahl in
//   der Scheibe), np-skull 32 x 32 (Bronze-Totenkopf), np-quest 16 x 32 (goldenes Ausrufezeichen) - aus den Vorlagen in
//   DECOR[name].src (Schwarz -> Alpha, Zuschnitt, mittig eingepasst); fehlt eine Vorlage: prozeduraler Platzhalter.
// Weitere Kandidaten nur fuer Vorschau/Tests: fillImage (Glanzverlauf), flowImage (prozedurale Adern).
//
// FRAME_GEOMETRY (Schlitz-Lage in Textur-Pixeln) steht gleich in modules/Nameplates/Style.lua; der Test misst die
// Datei im Repo nach. Aufruf: node scripts/gen-nameplate-media.mjs  (JPG -> PNG ueber Headless-Chrome, Zwischenablage
// im Temp-Ordner, wie gen-minimap-media.mjs).
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { resample, tgaRgba } from "./gen-minimap-media.mjs";
import { decodePng, jpgToPng } from "./gen-zone-media.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const MEDIA = path.join(ROOT, "addon", "Lucid", "Media");
const SRC = path.join(ROOT, "docs", "nameplate-src");

export const FRAME = { w: 256, h: 32, cap: 32, seam: 28 }; // seam: Ueberblendung an der Naht Mitte/Kappe (Pixel)
export const LEVEL = { w: 64, h: 32 };
export const FILL = { w: 128, h: 16 };
export const GLOW = { w: 64, h: 32, cap: 16, inner: 9, radius: 6 }; // inner wie Style.GLOW.inner
export const FLOW = { w: 128, h: 16, cells: 8 };
// Zwei flache, ruhige Ausschnitte (Quell-y, Hoehe in Quellpixeln) uebereinander: A oben, B unten (je h/2 Zeilen).
// Flach, weil im Spiel 0,55-0,75 Texturbreiten auf ~272 x 5 px gezeigt werden (dann wirkt das Bild nicht gestreift).
export const LIQUID = { w: 256, h: 64, cuts: [{ y: 245, h: 44 }, { y: 1380, h: 44 }], gain: 1.05, blur: 1 };
// Zauber-Magie (Freigabe np-castmagic-v1, 2752 x 1536, waagrecht kachelbar): zwei Baender mit Runenfaeden (oben Lage
// A, unten Lage B), auf Orange-Gold umgefaerbt (hebt sich vom roten Lebensbalken ab) und entsaettigt (silbrig getoent)
export const CASTMAGIC = { w: 256, h: 64, cuts: [{ y: 330, h: 120 }, { y: 690, h: 120 }], gain: 1.1, blur: 0 };
// Orange-Gold-Verlauf nach Helligkeit (dunkel -> hell). Runde 3 (R2 "zu wild", R1 "einfarbig"): Mittelweg - die
// gespreizte, per S-Kurve verstaerkte Helligkeit wird zur Haelfte (mix) mit der urspruenglichen gemischt, die hellsten
// Runenfaeden enden warm-gold statt fast weiss
export const CASTMAGIC_RAMP = [[0, [32, 10, 3]], [0.35, [135, 52, 10]], [0.7, [236, 144, 36]], [0.9, [250, 196, 88]],
  [1, [255, 222, 140]]];
export const CASTMAGIC_CONTRAST = { lo: 0.02, hi: 0.98, s: 0.7, mix: 0.5 };
// Funken-Flash (np-spark-v1, schwarzer Grund): additiv, 64 x 64; streak = Lage des hellen Streifens (Anteil der Breite)
export const SPARK = { w: 64, h: 64 };

/** deterministisches Rauschen [0, 1) aus zwei ganzen Zahlen (Hash, kein Zufall) */
export function noise(x, y, seed = 1) {
  let h = (x * 374761393 + y * 668265263 + seed * 2246822519) >>> 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177) >>> 0;
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
}

const clamp = (v, lo = 0, hi = 255) => Math.max(lo, Math.min(hi, v));
const smooth = (x, a, b) => {
  const t = Math.min(1, Math.max(0, (x - a) / (b - a)));
  return t * t * (3 - 2 * t);
};
const maxc = (rgba, i) => Math.max(rgba[i * 4], rgba[i * 4 + 1], rgba[i * 4 + 2]);

/** Alpha je Pixel setzen und Farben entmultiplizieren (Vorlage = Farbe x Alpha ueber Schwarz) */
function applyAlpha({ w, h, rgba }, alphaOf) {
  const out = new Uint8Array(w * h * 4);
  for (let i = 0; i < w * h; i++) {
    const a = alphaOf(i);
    if (a <= 0) continue;
    for (let k = 0; k < 3; k++) out[i * 4 + k] = clamp(Math.round(rgba[i * 4 + k] / Math.max(a, 0.25)));
    out[i * 4 + 3] = Math.round(a * 255);
  }
  return { w, h, rgba: out };
}

/** Luminanz-Schluessel: alles Schwarze (aussen und im Schlitz) wird durchsichtig */
export function keyLuma(img, lo = 6, hi = 24) {
  return applyAlpha(img, (i) => smooth(maxc(img.rgba, i), lo, hi));
}

/** Von aussen freistellen: nur der mit dem Bildrand verbundene dunkle Grund wird durchsichtig (Innenflaeche bleibt) */
export function keyOutside(img, thr = 30, lo = 4) {
  const { w, h, rgba } = img;
  const bg = new Uint8Array(w * h), stack = [];
  const push = (x, y) => {
    const i = y * w + x;
    if (!bg[i] && maxc(rgba, i) <= thr) { bg[i] = 1; stack.push(i); }
  };
  for (let x = 0; x < w; x++) { push(x, 0); push(x, h - 1); }
  for (let y = 0; y < h; y++) { push(0, y); push(w - 1, y); }
  while (stack.length) {
    const i = stack.pop(), x = i % w, y = (i / w) | 0;
    if (x > 0) push(x - 1, y);
    if (x < w - 1) push(x + 1, y);
    if (y > 0) push(x, y - 1);
    if (y < h - 1) push(x, y + 1);
  }
  return applyAlpha(img, (i) => (bg[i] ? smooth(maxc(rgba, i), lo, thr) : 1));
}

/** Begrenzungsrechteck der deckenden Pixel (Alpha > 0.5) */
export function alphaBox({ w, h, rgba }) {
  let x0 = w, y0 = h, x1 = -1, y1 = -1;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      if (rgba[(y * w + x) * 4 + 3] > 127) {
        if (x < x0) x0 = x;
        if (x > x1) x1 = x;
        if (y < y0) y0 = y;
        if (y > y1) y1 = y;
      }
    }
  }
  if (x1 < 0) throw new Error("Vorlage leer");
  return { x0, y0, x1: x1 + 1, y1: y1 + 1 };
}

function blit(dst, src, dx) {
  for (let y = 0; y < src.h; y++) {
    for (let x = 0; x < src.w; x++) {
      for (let k = 0; k < 4; k++) dst.rgba[((y * dst.w) + dx + x) * 4 + k] = src.rgba[(y * src.w + x) * 4 + k];
    }
  }
}

/** Rahmen: Zuschnitt (Kappen quadratisch zur Rahmenhoehe), Mitte aus der Bildmitte, auf FRAME.w x FRAME.h */
export function frameFromTemplate(keyed) {
  const b = alphaBox(keyed);
  const pad = 2, y0 = b.y0 - pad, ch = b.y1 - b.y0 + 2 * pad;
  const capSrc = ch * (FRAME.cap / FRAME.h);               // Kappen in Vorlagen-Pixeln (Seitenverhaeltnis wie im Ziel)
  const midW = FRAME.w - 2 * FRAME.cap, midSrc = ch * (midW / FRAME.h);
  const cx = (b.x0 + b.x1) / 2;
  const out = { w: FRAME.w, h: FRAME.h, rgba: new Uint8Array(FRAME.w * FRAME.h * 4) };
  blit(out, resample(keyed, b.x0 - pad, y0, capSrc, ch, FRAME.cap, FRAME.h), 0);
  blit(out, resample(keyed, cx - midSrc / 2, y0, midSrc, ch, midW, FRAME.h), FRAME.cap);
  blit(out, resample(keyed, b.x1 + pad - capSrc, y0, capSrc, ch, FRAME.cap, FRAME.h), FRAME.w - FRAME.cap);
  blendSeams(out);
  return out;
}

/** Naht Mittelteil/Kappe (Etappe 3): das Mittelteil kommt aus der Bildmitte der Vorlage (heller Lichtstreifen im
 *  oberen Band), die Kappen vom Rand (dunkleres Band) - an x = cap bzw. w - cap sprang die Helligkeit des Bands hart.
 *  Die Bandpixel des Mittelteils laufen deshalb auf FRAME.seam Pixeln weich in die angrenzende Kappenspalte ueber (nur
 *  wo beide deckend sind; Schlitz und Rand aussen bleiben unberuehrt). */
export function blendSeams(out) {
  const { w, h, rgba } = out, B = FRAME.seam;
  for (const [edge, dir] of [[FRAME.cap - 1, 1], [w - FRAME.cap, -1]]) {
    for (let y = 0; y < h; y++) {
      const e = (y * w + edge) * 4;
      if (rgba[e + 3] <= 127) continue;
      for (let j = 0; j < B; j++) {
        const i = (y * w + edge + dir * (j + 1)) * 4;
        if (rgba[i + 3] <= 127) continue;
        const t = 1 - (j + 0.5) / B, k = t * t * (3 - 2 * t); // Anteil der Kappenfarbe, an der Naht ~1
        for (let c = 0; c < 4; c++) rgba[i + c] = Math.round(rgba[i + c] * (1 - k) + rgba[e + c] * k);
      }
    }
  }
  return out;
}

/** Zauber-Magie: Flussbaender wie die Lebensfluessigkeit, Farbe per Orange-Gold-Verlauf aus der Helligkeit */
export function castMagicFromTemplate(img) {
  const { mono } = liquidFromTemplate(img, CASTMAGIC);
  // Kontrast: Perzentile spreizen, S-Kurve (s = Anteil der Smoothstep-Kurve)
  const n = mono.w * mono.h, sorted = [];
  for (let i = 0; i < n; i++) sorted.push(mono.rgba[i * 4]);
  sorted.sort((a, b) => a - b);
  const C = CASTMAGIC_CONTRAST, lo = sorted[Math.floor(n * C.lo)], hi = sorted[Math.floor(n * C.hi)];
  for (let i = 0; i < n; i++) {
    const orig = mono.rgba[i * 4] / 255;
    const x = Math.min(1, Math.max(0, (mono.rgba[i * 4] - lo) / Math.max(1, hi - lo)));
    const v = Math.round((orig * (1 - C.mix) + (x * (1 - C.s) + x * x * (3 - 2 * x) * C.s) * C.mix) * 255);
    mono.rgba.set([v, v, v, 255], i * 4);
  }
  const color = { w: mono.w, h: mono.h, rgba: new Uint8Array(mono.rgba.length) };
  for (let i = 0; i < mono.w * mono.h; i++) {
    const v = mono.rgba[i * 4] / 255;
    let k = 0;
    while (k < CASTMAGIC_RAMP.length - 2 && v > CASTMAGIC_RAMP[k + 1][0]) k++;
    const [a, ca] = CASTMAGIC_RAMP[k], [b, cb] = CASTMAGIC_RAMP[k + 1], t = Math.min(1, Math.max(0, (v - a) / (b - a)));
    for (let c = 0; c < 3; c++) color.rgba[i * 4 + c] = Math.round(ca[c] + (cb[c] - ca[c]) * t);
    color.rgba[i * 4 + 3] = 255;
  }
  return { color, mono };
}

/** Funken-Flash: auf die helle Flaeche zugeschnitten, quadratisch eingepasst; Farbe normiert, Alpha = Helligkeit (additiv
 *  gemischt ergibt das wieder die Vorlage); streak = Spalte des hellsten Streifens als Anteil der Breite */
export function sparkFromTemplate(img) {
  const keyed = keyLuma(img, 6, 24);
  const b = alphaBox(keyed);
  const bw = b.x1 - b.x0, bh = b.y1 - b.y0, side = Math.max(bw, bh);
  const x0 = b.x0 - (side - bw) / 2, y0 = b.y0 - (side - bh) / 2;
  const opaque = { w: img.w, h: img.h, rgba: Uint8Array.from(img.rgba, (v, i) => (i % 4 === 3 ? 255 : v)) };
  const s = resample(opaque, x0, y0, side, side, SPARK.w, SPARK.h);
  const out = { w: SPARK.w, h: SPARK.h, rgba: new Uint8Array(SPARK.w * SPARK.h * 4) };
  const col = new Float64Array(SPARK.w);
  for (let i = 0; i < SPARK.w * SPARK.h; i++) {
    const m = Math.max(s.rgba[i * 4], s.rgba[i * 4 + 1], s.rgba[i * 4 + 2]);
    col[i % SPARK.w] += m;
    if (m < 3) continue;
    for (let k = 0; k < 3; k++) out.rgba[i * 4 + k] = Math.round(s.rgba[i * 4 + k] * 255 / m);
    out.rgba[i * 4 + 3] = m;
  }
  let best = 0;
  for (let x = 1; x < SPARK.w; x++) if (col[x] > col[best]) best = x;
  out.streak = (best + 0.5) / SPARK.w;
  return out;
}

/** Zauberleisten-Rahmen (Freigabe, np-castframe-v1): schmaler Bronze-Rahmen mit Rundkappen und zwei Laschen oben,
 *  zugeschnitten und 3-teilig wie np-frame (gleiche Masse, Naehte verblendet) */
export function castFrameFromTemplate(keyed) {
  return frameFromTemplate(keyed); // frameFromTemplate verblendet die Naehte (blendSeams)
}

/** Lage im Zauberleisten-Rahmen (Textur-Pixel): bandTop = Oberkante des Bands in der Mitte (darueber nur die Laschen an
 *  den Kappen), top/bottom = Schlitz-Ober-/-Unterkante von oben bzw. unten, left/right = Schlitz-Einzug in Schlitzmitte */
export function measureCastSlit({ w, h, rgba }) {
  const a = (x, y) => rgba[(y * w + x) * 4 + 3];
  const cx = w >> 1;
  let y = 0;
  while (y < h && a(cx, y) <= 127) y++;
  const bandTop = y;
  while (y < h && a(cx, y) > 127) y++;
  const top = y;
  while (y < h && a(cx, y) <= 127) y++;
  const bottom = h - y;
  const cy = Math.floor((top + y) / 2);
  let x = 0;
  while (x < cx && a(x, cy) <= 127) x++;
  while (x < cx && a(x, cy) > 127) x++;
  const left = x;
  x = w - 1;
  while (x > cx && a(x, cy) <= 127) x--;
  while (x > cx && a(x, cy) > 127) x--;
  return { bandTop, top, bottom, left, right: w - 1 - x };
}

/** Lage des durchsichtigen Schlitzes (Textur-Pixel): Bandstaerke oben/unten in der Mitte, Einzug links/rechts */
export function measureSlit({ w, h, rgba }) {
  const a = (x, y) => rgba[(y * w + x) * 4 + 3];
  const cx = w >> 1, cy = h >> 1;
  let top = 0, bottom = 0, left = 0, right = 0;
  while (top < cy && a(cx, top) > 127) top++;
  while (bottom < cy && a(cx, h - 1 - bottom) > 127) bottom++;
  // Rand aussen (durchsichtig) ueberspringen, dann das Band bis zum Schlitz
  let x = 0;
  while (x < cx && a(x, cy) <= 127) x++;
  while (x < cx && a(x, cy) > 127) x++;
  left = x;
  x = w - 1;
  while (x > cx && a(x, cy) <= 127) x--;
  while (x > cx && a(x, cy) > 127) x--;
  right = w - 1 - x;
  return { top, bottom, left, right };
}

export function levelFromTemplate(keyed) {
  const b = alphaBox(keyed), pad = 3;
  return resample(keyed, b.x0 - pad, b.y0 - pad, b.x1 - b.x0 + 2 * pad, b.y1 - b.y0 + 2 * pad, LEVEL.w, LEVEL.h);
}

/** Fuellung: warmer Verlauf (Farbe x Haltungsfarbe): oben hell-warm mit Glanzkante, unten dunkel-rot, Maserung */
export function fillImage() {
  const { w, h } = FILL;
  const rgba = new Uint8Array(w * h * 4);
  const TOP = [1.0, 0.93, 0.80], BOTTOM = [0.52, 0.30, 0.24];
  for (let y = 0; y < h; y++) {
    const v = y / (h - 1);
    let c = TOP.map((t, i) => t + (BOTTOM[i] - t) * Math.pow(v, 0.8));
    if (y === 1) c = c.map((x) => Math.min(1, x * 1.08)); // feine Glanzkante
    if (y === 0) c = c.map((x) => x * 0.85);
    const row = (noise(0, y, 7) - 0.5) * 0.06;
    for (let x = 0; x < w; x++) {
      const fine = (noise(x >> 2, y, 11) - 0.5) * 0.05;
      rgba.set([...c.map((k) => clamp(Math.round((k + row + fine) * 255))), 255], (y * w + x) * 4);
    }
  }
  return { w, h, rgba };
}

/** Fuellung matt (Runde 2, Variante): kein Glanzverlauf; Koerper flach dunkel (Rost/Kohle), oberste Zeile glimmt,
 *  feine unruhige Maserung. Grauwert, wird mit der Haltungsfarbe multipliziert (Standard seit Runde 2). */
export function fillMattImage() {
  const { w, h } = FILL;
  const rgba = new Uint8Array(w * h * 4);
  for (let y = 0; y < h; y++) {
    const base = y <= 1 ? 1.0 : y <= 3 ? 0.74 : 0.62 - 0.08 * (y / (h - 1));
    for (let x = 0; x < w; x++) {
      const grain = (noise(x >> 1, y, 21) - 0.5) * 0.08 + (noise(x >> 4, 0, 23) - 0.5) * 0.06;
      const g = clamp(Math.round((base + (y <= 1 ? grain * 0.3 : grain)) * 255));
      rgba.set([g, g, g, 255], (y * w + x) * 4);
    }
  }
  return { w, h, rgba };
}

/** Schein: weiss, Alpha als weiche Ellipse (Vertexfarbe toent im Spiel) */
export function glowImage() {
  // Ziel-Schein (Runde 4): weisser Rand um ein abgerundetes Innen-Rechteck (= Rahmen), Alpha faellt ueber GLOW.inner
  // Pixel nach aussen weich auf 0; innen deckend (liegt ohnehin unter Rahmen/Schlitz). 3-teilig nutzbar: die Mitte
  // (cap .. w - cap) ist waagrecht gleichfoermig.
  const { w, h, inner, radius } = GLOW;
  const rgba = new Uint8Array(w * h * 4);
  const cx = w / 2, cy = h / 2, hx = w / 2 - inner, hy = h / 2 - inner;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const qx = Math.abs(x + 0.5 - cx) - (hx - radius), qy = Math.abs(y + 0.5 - cy) - (hy - radius);
      const d = Math.hypot(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) - radius;
      const a = d <= 0 ? 1 : Math.pow(Math.max(0, 1 - d / inner), 2);
      rgba.set([255, 255, 255, clamp(Math.round(a * 255))], (y * w + x) * 4);
    }
  }
  return { w, h, rgba };
}

/** periodisches Wertrauschen (waagrecht kachelbar mit Periode p Zellen), weich interpoliert */
function valueNoise(x, y, p, seed) {
  const x0 = Math.floor(x), y0 = Math.floor(y), fx = x - x0, fy = y - y0;
  const sx = fx * fx * (3 - 2 * fx), sy = fy * fy * (3 - 2 * fy);
  const n = (i, j) => noise(((i % p) + p) % p, j, seed);
  const a = n(x0, y0) + (n(x0 + 1, y0) - n(x0, y0)) * sx;
  const b = n(x0, y0 + 1) + (n(x0 + 1, y0 + 1) - n(x0, y0 + 1)) * sx;
  return a + (b - a) * sy;
}

/** Platzhalter der lebendigen Fuellung: fbm-Adern (weiss, Alpha = Aderstaerke), waagrecht kachelbar (REPEAT) */
export function flowImage() {
  const { w, h, cells } = FLOW;
  const rgba = new Uint8Array(w * h * 4);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      let v = 0, amp = 0.55, freq = 1;
      for (let o = 0; o < 4; o++) {
        v += amp * valueNoise((x / w) * cells * freq, (y / h) * 2.5 * freq, cells * freq, 31 + o);
        amp *= 0.5;
        freq *= 2;
      }
      const vein = Math.pow(1 - Math.abs(v - 0.5) * 2, 6); // schmale helle Adern entlang der Mittelwerte
      rgba.set([255, 255, 255, clamp(Math.round(vein * 0.9 * 255))], (y * w + x) * 4);
    }
  }
  return { w, h, rgba };
}

/** Lebensfluessigkeit aus der Vorlage (np-liquid-v1.jpg, waagrecht nahtlos): Streifen mit Wirbeln/Lichtfaeden ueber
 *  die volle Breite (bleibt nahtlos), isotrop auf LIQUID.w x LIQUID.h (im Spiel wird die halbe Hoehe gezeigt, der
 *  Rest dient dem senkrechten Wogen). Liefert die farbige und eine entsaettigte Fassung (zum Toenen per Vertexfarbe). */
export function liquidFromTemplate(img, cfg = LIQUID) {
  const { w, h, cuts, gain, blur } = cfg;
  const opaque = { w: img.w, h: img.h, rgba: Uint8Array.from(img.rgba, (v, i) => (i % 4 === 3 ? 255 : v)) };
  const color = { w, h, rgba: new Uint8Array(w * h * 4) };
  const half = h / cuts.length;
  cuts.forEach((c, k) => {
    const part = resample(opaque, 0, c.y, img.w, c.h, w, half);
    color.rgba.set(part.rgba, k * half * w * 4);
  });
  // leicht weichzeichnen (waagrecht, wrap = nahtlos), damit markante Boegen ruhiger werden
  for (let pass = 0; pass < blur; pass++) {
    const src = Uint8Array.from(color.rgba);
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        for (let k = 0; k < 3; k++) {
          const at = (xx) => src[(y * w + ((xx + w) % w)) * 4 + k];
          color.rgba[(y * w + x) * 4 + k] = Math.round((at(x - 1) + 2 * at(x) + at(x + 1)) / 4);
        }
      }
    }
  }
  const mono = { w, h, rgba: new Uint8Array(w * h * 4) };
  let maxL = 1;
  const lum = new Float64Array(w * h);
  for (let i = 0; i < w * h; i++) {
    lum[i] = Math.max(color.rgba[i * 4], color.rgba[i * 4 + 1], color.rgba[i * 4 + 2]);
    if (lum[i] > maxL) maxL = lum[i];
    for (let k = 0; k < 3; k++) color.rgba[i * 4 + k] = clamp(Math.round(color.rgba[i * 4 + k] * gain));
    color.rgba[i * 4 + 3] = 255;
  }
  for (let i = 0; i < w * h; i++) {
    const v = clamp(Math.round(Math.pow(lum[i] / maxL, 1.2) * 255));
    mono.rgba.set([v, v, v, 255], i * 4);
  }
  return { color, mono };
}

/** Vorlage (JPG) -> dekodiertes Bild; PNG-Zwischenablage im Temp-Ordner */
export function loadTemplate(name) {
  const cache = path.join(os.tmpdir(), "lucid-nameplate-src");
  mkdirSync(cache, { recursive: true });
  const png = path.join(cache, name + ".png");
  if (!existsSync(png)) jpgToPng(path.join(SRC, name + ".jpg"), png);
  return decodePng(readFileSync(png));
}

export const VEIL = { w: 64, h: 32 };
export const MASK = { w: 256, h: 16, rx: 6 };
export const INSET = { w: 256, h: 16 };
export const GLASS = { w: 64, h: 4, fade: 0.18 };
export const ENDFADE = { w: 64, h: 4, fade: 0.12 };

/** Endblende: weiss, Alpha waagrecht an beiden Enden weich (je ENDFADE.fade der Breite) auf 0, senkrecht konstant */
export function endFadeImage() {
  const { w, h, fade } = ENDFADE;
  const rgba = new Uint8Array(w * h * 4);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const u = (x + 0.5) / w, e = Math.min(u, 1 - u) / fade;
      rgba.set([255, 255, 255, clamp(Math.round(smooth(Math.min(1, e), 0, 1) * 255))], (y * w + x) * 4);
    }
  }
  return { w, h, rgba };
}

/** Glasglanz: weiss, Alpha waagrecht an beiden Enden weich auslaufend (je GLASS.fade der Breite), senkrecht weich */
export function glassImage() {
  const { w, h, fade } = GLASS;
  const rgba = new Uint8Array(w * h * 4);
  for (let y = 0; y < h; y++) {
    const vy = 1 - Math.abs((y + 0.5) / h * 2 - 1) * 0.6;
    for (let x = 0; x < w; x++) {
      const u = (x + 0.5) / w, e = Math.min(u, 1 - u) / fade;
      const a = smooth(Math.min(1, e), 0, 1) * vy;
      rgba.set([255, 255, 255, clamp(Math.round(a * 255))], (y * w + x) * 4);
    }
  }
  return { w, h, rgba };
}

/** Kapsel-Maske fuer den Schlitz: weiss, Alpha = Kapsel (runde Enden, Halbachsen rx x h/2), Kanten 1 px geglaettet */
export function maskImage() {
  const { w, h, rx } = MASK;
  const ry = h / 2, rgba = new Uint8Array(w * h * 4);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const px = x + 0.5, py = y + 0.5 - ry;
      const cx = px < rx ? rx : px > w - rx ? w - rx : px; // naechster Punkt der Mittellinie
      const d = Math.hypot((px - cx) / rx, py / ry);        // 1 = Rand
      const a = clamp((1 - d) * Math.min(rx, ry) + 0.5, 0, 1);
      rgba.set([255, 255, 255, Math.round(a * 255)], (y * w + x) * 4);
    }
  }
  return { w, h, rgba };
}

/** Innerer Schatten: Alpha dunkel an Ober-/Unterkante (oben staerker, Rahmen wirft Schatten) und an den Enden */
export function insetImage() {
  const { w, h } = INSET;
  const rgba = new Uint8Array(w * h * 4);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const v = (y + 0.5) / h;
      const top = Math.pow(Math.max(0, 1 - v / 0.38), 1.6), bottom = Math.pow(Math.max(0, 1 - (1 - v) / 0.3), 1.6) * 0.8;
      const ends = Math.pow(Math.max(0, 1 - Math.min(x + 0.5, w - x - 0.5) / 10), 1.5) * 0.7;
      const a = Math.min(1, Math.max(top, bottom, ends));
      rgba.set([255, 255, 255, clamp(Math.round(a * 255))], (y * w + x) * 4);
    }
  }
  return { w, h, rgba };
}

/** Tinten-Schleier hinter dem Namen: weiss, Alpha als weiche Ellipse (flache Mitte, sanft auslaufend) */
export function veilImage() {
  const { w, h } = VEIL;
  const rgba = new Uint8Array(w * h * 4);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const u = (x + 0.5) / w * 2 - 1, v = (y + 0.5) / h * 2 - 1;
      const ex = Math.max(0, Math.abs(u) - 0.45) / 0.55, d = Math.min(1, Math.hypot(ex, v));
      const a = Math.pow(1 - d, 1.8);
      rgba.set([255, 255, 255, clamp(Math.round(a * 255))], (y * w + x) * 4);
    }
  }
  return { w, h, rgba };
}

// Zier (Baustein 8/9, Etappe 4a): Elite-Krallen, Rar-Silber, Totenkopf, Quest-Siegel. Liegt eine freigegebene
// Gemini-Vorlage docs/nameplate-src/np-<name>-v1.jpg (schwarzer Grund) vor, wird sie freigestellt (Schwarz -> Alpha),
// auf die deckende Flaeche zugeschnitten und mittig in die Zielgroesse eingepasst; sonst ein prozeduraler Platzhalter.
// Freigabe (09.11.): Elite = Bronze-Drache um eine Scheibe (np-elite-v2), Rar = dasselbe in Silber (np-rare-v2),
// Boss = Bronze-Totenkopf (np-skull-v1), Quest = goldenes Ausrufezeichen (np-quest-v2); die v1-Entwuerfe von Elite/Rar/
// Quest sind abgelehnt. disc: Scheibenmitte als Anteil der Vorlagen-Box (Kreis-Fit am linken Scheibenrand); Layout R2 legt sie hinter
// die Plaettchenmitte (Style.RANK.disc, umgerechnet auf die Textur).
export const DECOR = {
  elite: { w: 64, h: 64, src: "np-elite-v2", disc: { x: 0.34, y: 0.474 } },
  rare: { w: 64, h: 64, src: "np-rare-v2", disc: { x: 0.34, y: 0.474 } },
  skull: { w: 32, h: 32, src: "np-skull-v1" },
  quest: { w: 16, h: 32, src: "np-quest-v2" },
  shield: { w: 32, h: 32, src: "np-shield-v1" }, // nicht unterbrechbar: Schild auf der linken Kappe der Zauberleiste
  // Quest-Ziel nach Questie (Freigabe np-objectives-v1: Beutel | gekreuzte Schwerter | Panzerhandschuh, je ein Drittel)
  "obj-loot": { w: 32, h: 32, src: "np-objectives-v1", part: 0, parts: 3 },
  "obj-slay": { w: 32, h: 32, src: "np-objectives-v1", part: 1, parts: 3 },
  "obj-interact": { w: 32, h: 32, src: "np-objectives-v1", part: 2, parts: 3 },
};

/** Drittel (part von parts) einer Vorlage waagrecht ausschneiden */
function slicePart(img, part, parts) {
  const w0 = Math.floor(img.w * part / parts), w1 = Math.floor(img.w * (part + 1) / parts), w = w1 - w0;
  const rgba = new Uint8Array(w * img.h * 4);
  for (let y = 0; y < img.h; y++) rgba.set(img.rgba.subarray((y * img.w + w0) * 4, (y * img.w + w1) * 4), y * w * 4);
  return { w, h: img.h, rgba };
}

const segDist = (px, py, ax, ay, bx, by) => {
  const vx = bx - ax, vy = by - ay, t = Math.max(0, Math.min(1, ((px - ax) * vx + (py - ay) * vy) / (vx * vx + vy * vy)));
  return [Math.hypot(px - ax - vx * t, py - ay - vy * t), t];
};
const img = (w, h, fn) => {
  const rgba = new Uint8Array(w * h * 4);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const [r, g, b, a] = fn(x + 0.5, y + 0.5);
    rgba.set([clamp(Math.round(r)), clamp(Math.round(g)), clamp(Math.round(b)), clamp(Math.round(a * 255))], (y * w + x) * 4);
  }
  return { w, h, rgba };
};

/** Platzhalter Elite: je Seite drei nach aussen gebogene Bronze-Krallen, Mitte frei (dort sitzt das Plaettchen) */
export function eliteImage() {
  const { w, h } = DECOR.elite;
  const claws = [[-10, 0.5], [0, 0.5], [10, 0.5]];
  return img(w, h, (x, y) => {
    let a = 0, shade = 0;
    for (const side of [-1, 1]) {
      const bx = side < 0 ? 17 : w - 17;
      for (const [dy] of claws) {
        const by = h / 2 + dy * 0.6, tx = side < 0 ? 2 : w - 2, ty = h / 2 + dy * 1.25 - 3;
        const [d, t] = segDist(x, y, bx, by, tx, ty);
        const r = 3.2 * (1 - t) + 0.6;
        const v = Math.max(0, Math.min(1, r - d + 0.5));
        if (v > a) { a = v; shade = 1 - t * 0.5; }
      }
    }
    return [158 * shade + 40, 112 * shade + 22, 58 * shade + 10, a];
  });
}

/** Platzhalter Rar: silberne Filigran-Schwingen (Ellipsen-Ring), Mitte frei */
export function rareImage() {
  const { w, h } = DECOR.rare;
  return img(w, h, (x, y) => {
    const u = (x - w / 2) / (w / 2 - 1), v = (y - h / 2) / (h / 2 - 1);
    const d = Math.hypot(u, v);
    const ring = Math.max(0, 1 - Math.abs(d - 0.92) / 0.08);
    const wing = Math.abs(u) > 0.62 ? Math.max(0, 1 - Math.abs(Math.abs(v) - (1 - Math.abs(u)) * 1.4) / 0.12) * 0.9 : 0;
    const a = Math.min(1, Math.max(ring, wing));
    const s = 170 + 60 * (1 - Math.abs(v));
    return [s, s + 4, s + 14, a];
  });
}

/** Platzhalter Totenkopf: knochenfarbener Schaedel mit dunklen Augen, Nase und Kiefer */
export function skullImage() {
  const { w, h } = DECOR.skull;
  return img(w, h, (x, y) => {
    const head = 11.5 - Math.hypot(x - 16, (y - 13) * 1.05);
    const jaw = Math.min(6 - Math.abs(x - 16), Math.min(y - 19, 27 - y));
    let a = Math.max(0, Math.min(1, Math.max(head, jaw) + 0.5));
    const eye = Math.min(Math.hypot(x - 11.5, y - 14), Math.hypot(x - 20.5, y - 14)) - 3.2;
    const nose = Math.max(Math.abs(x - 16) - 1.2, Math.abs(y - 19.5) - 1.6);
    const teeth = y > 23 && y < 26 && Math.abs(x - 16) < 5 && Math.round(x) % 3 === 0 ? 1 : 0;
    const hole = Math.max(Math.max(0, Math.min(1, 0.5 - eye)), Math.max(0, Math.min(1, 0.5 - nose)), teeth);
    a *= 1 - hole * 0.85;
    const s = 226 - (y / h) * 40;
    return [s, s - 8, s - 28, a];
  });
}

/** Platzhalter Quest-Siegel: rotes Wachssiegel mit welligem Rand, dunklerem Ring und hellerer Praegung */
export function questImage() {
  const { w, h } = DECOR.quest;
  return img(w, h, (x, y) => {
    const dx = x - 16, dy = y - 16, ang = Math.atan2(dy, dx), d = Math.hypot(dx, dy);
    const rim = 13 + Math.sin(ang * 9) * 1.1;
    const a = Math.max(0, Math.min(1, rim - d + 0.5));
    const ring = Math.max(0, 1 - Math.abs(d - 9) / 1.2);
    const emb = Math.max(0, 1 - Math.max(Math.abs(dx) - 1, Math.abs(dy) - 5) / 1.2) * (d < 8 ? 1 : 0)
      + Math.max(0, 1 - Math.max(Math.abs(dy) - 1, Math.abs(dx) - 5) / 1.2) * (d < 8 ? 1 : 0);
    const lit = 1 - (dy + dx) / 40;
    const r = (150 + 40 * Math.min(1, emb)) * lit - ring * 40, g = (28 + 20 * Math.min(1, emb)) * lit - ring * 10;
    return [r, g, (24 + 10 * Math.min(1, emb)) * lit, a];
  });
}

const DECOR_FALLBACK = { elite: eliteImage, rare: rareImage, skull: skullImage, quest: questImage, shield: questImage,
  "obj-loot": questImage, "obj-slay": questImage, "obj-interact": questImage };

/** Vorlage freistellen, zuschneiden und mittig einpassen (Seitenverhaeltnis bleibt) */
export function decorFromTemplate(keyed, size) {
  const b = alphaBox(keyed);
  const bw = b.x1 - b.x0, bh = b.y1 - b.y0, s = Math.min(size.w / bw, size.h / bh);
  const ow = Math.max(1, Math.round(bw * s)), oh = Math.max(1, Math.round(bh * s));
  const fit = resample(keyed, b.x0, b.y0, bw, bh, ow, oh);
  const out = { w: size.w, h: size.h, rgba: new Uint8Array(size.w * size.h * 4) };
  const ox = Math.floor((size.w - ow) / 2), oy = Math.floor((size.h - oh) / 2);
  for (let y = 0; y < oh; y++) for (let x = 0; x < ow; x++) {
    out.rgba.set(fit.rgba.subarray((y * ow + x) * 4, (y * ow + x) * 4 + 4), ((oy + y) * size.w + ox + x) * 4);
  }
  return out;
}

/** Platz der Stufenzahl in der fertigen Textur (Anteile 0..1), aus DECOR[name].disc und der Einpassung */
export function decorDisc(name, box) {
  const d = DECOR[name];
  const bw = box.x1 - box.x0, bh = box.y1 - box.y0, s = Math.min(d.w / bw, d.h / bh);
  const ow = Math.max(1, Math.round(bw * s)), oh = Math.max(1, Math.round(bh * s));
  const ox = Math.floor((d.w - ow) / 2), oy = Math.floor((d.h - oh) / 2);
  return { x: (ox + d.disc.x * ow) / d.w, y: (oy + d.disc.y * oh) / d.h };
}

/** Zier-Dateien: freigegebene Vorlage DECOR[name].src, falls vorhanden, sonst prozeduraler Platzhalter */
export const decorFiles = ({ useTemplates = true } = {}) => Object.keys(DECOR).map((name) => {
  const src = path.join(SRC, `${DECOR[name].src}.jpg`);
  const fromTpl = useTemplates && existsSync(src);
  if (!fromTpl) return { file: `np-${name}.tga`, template: false, img: DECOR_FALLBACK[name]() };
  let keyed = keyLuma(loadTemplate(DECOR[name].src));
  if (DECOR[name].parts) keyed = slicePart(keyed, DECOR[name].part, DECOR[name].parts);
  return { file: `np-${name}.tga`, template: true, img: decorFromTemplate(keyed, DECOR[name]),
    disc: DECOR[name].disc ? decorDisc(name, alphaBox(keyed)) : undefined };
});

export const proceduralFiles = () => [
  { file: "np-fill.tga", img: fillMattImage() },
  { file: "np-veil.tga", img: veilImage() },
  { file: "np-mask-capsule.tga", img: maskImage() },
  { file: "np-inset.tga", img: insetImage() },
  { file: "np-glass.tga", img: glassImage() },
  { file: "np-endfade.tga", img: endFadeImage() },
  { file: "np-glow.tga", img: glowImage() },
];

function run() {
  const frame = frameFromTemplate(keyLuma(loadTemplate("np-frame-v1")));
  const level = levelFromTemplate(keyOutside(loadTemplate("np-level-v1")));
  const liquid = liquidFromTemplate(loadTemplate("np-liquid-v1"));
  const castFrame = castFrameFromTemplate(keyLuma(loadTemplate("np-castframe-v1")));
  const castMagic = castMagicFromTemplate(loadTemplate("np-castmagic-v1"));
  const spark = sparkFromTemplate(loadTemplate("np-spark-v1"));
  const files = [{ file: "np-frame.tga", img: frame }, { file: "np-level.tga", img: level }, { file: "np-castframe.tga", img: castFrame },
    { file: "np-castmagic.tga", img: castMagic.color }, { file: "np-castmagic-mono.tga", img: castMagic.mono },
    { file: "np-spark.tga", img: spark },
    { file: "np-liquid.tga", img: liquid.color }, { file: "np-liquid-mono.tga", img: liquid.mono }, ...proceduralFiles(),
    ...decorFiles()];
  for (const { file, img } of files) {
    if (img.w > 256 || img.h > 256) throw new Error(file + ": groesser als 256 px");
    const buf = tgaRgba(img);
    writeFileSync(path.join(MEDIA, file), buf);
    console.log(`${file}: ${img.w} x ${img.h}, ${buf.length} B`);
  }
  console.log("Schlitz (fuer Style.FRAME_GEOMETRY):", JSON.stringify(measureSlit(frame)));
  console.log("Zauberleiste (fuer Style.CAST_GEOMETRY):", JSON.stringify(measureCastSlit(castFrame)));
  console.log("Funken-Streifen (fuer Style.CAST_ANIM.sparkStreak):", spark.streak);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) run();
