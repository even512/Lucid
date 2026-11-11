// Erzeugt die Zonen-Ornamente der Minimap (Delta Minimap-Ornament, Gestalt Runde 4).
// Quelle je freigegebenem Motiv (docs/minimap-ornament-src/approved.json): <motiv>-frei-v1.jpg, von Gemini pixelgleich zum
// Referenzbild freigestellt (Gold auf Schwarz, 2048 x 2048, unten teils Reste des Hintergrunds).
//   1. Geometrie: Gemini hat den Screenshot (tim-minimap-ecke.png, 554 x 516) auf 2048 x 2048 gestreckt (x * 3,70,
//      y * 3,97). Alles wird in Screenshot-Koordinaten gerechnet (y also um 3,70/3,97 gestaucht); Bezug ist das sichtbare
//      Kartenrechteck (Innenflaeche des Rahmens x 146-500, y 102-367; Rahmen aussen x 140-507, y 95-373), Sonnenmitte (422, 81).
//   2. Hintergrundreste weg: nur ein Bereich oben und rechts um die Karte (mit Rand) und nur goldene Farbtoene
//      (Rot >= Gruen >= Blau; dunkelgruene, blaue und graue Reste fallen heraus).
//   3. Alpha aus der Helligkeit (bezogen auf die hellen Goldtoene des Motivs), Farbe ent-multipliziert: die echten Farben
//      aus dem Gemini-Bild, kein Umfaerben. Dunkle Motivflaechen (deutlich ueber reinem Schwarz) bleiben deckend, dazu
//      eine schmale dunkle Kontur um das Gold (wie Gemini sie im Referenzbild zeichnet).
//   4. Drei Stuecke, jedes eine eigene, ungedrehte Textur: Ring (Kreis um die Sonne bis zum Aussenrand, Radius aus dem
//      Radialprofil der unteren Ringhaelfte, plus die damit verbundene Krone), Leiste oben und Spalte rechts (der Rest).
//   5. Aufloesung je Stueck: groesste Texelzahl je Screenshot-Pixel (>= 1, also bei der Groesse nie hochskaliert, hoechstens
//      MAX_SCALE), die mit Zweierpotenz-Massen unter 1 MiB passt.
// Ausgabe: addon/Lucid/Media/mmorn-<motiv>-top|side|ring.tga und modules/Minimap/OrnamentData.lua (Masse in Kartenbreiten,
// Lage relativ zur Sonnenmitte = Fixpunkt).
// Aufruf: node scripts/gen-minimap-ornament.mjs [motiv ...] (ohne Namen: alle aus approved.json). Deterministisch.
import { existsSync, mkdirSync, readdirSync, readFileSync, statSync, unlinkSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { decodePng, jpgToPng } from "./gen-zone-media.mjs";
import { resample, tgaRgba } from "./gen-minimap-media.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
export const SRC = path.join(ROOT, "docs", "minimap-ornament-src");
const MEDIA = path.join(ROOT, "addon", "Lucid", "Media");
const DATA = path.join(ROOT, "addon", "Lucid", "modules", "Minimap", "OrnamentData.lua");
const LIMIT = 1024 * 1024;

/** Screenshot: Masse, Kartenrechteck (sichtbar = Innenflaeche), Rahmen aussen, Sonne */
export const SHOT = { w: 554, h: 516 };
export const MAP = { x0: 146, y0: 102, x1: 500, y1: 367 };
export const OUTER = { x0: 140, y0: 95, x1: 507, y1: 373 };
export const SUN = { x: 422, y: 81, r: 31 };
/** Bereich, in dem Ornament liegen darf (Screenshot-Pixel): Leiste oben, Spalte rechts */
export const REGION = { topMaxY: OUTER.y0 + 40, topMinX: OUTER.x0 - 60, rightMinX: OUTER.x1 - 40, rightMaxY: OUTER.y1 + 30 };
/** hoechste Aufloesung je Stueck (Texel je Screenshot-Pixel) */
const MAX_SCALE = 2;
/** Vorbild der einheitlichen Geometrie */
const CANON = "dwarf";
const PAD = 2;
/** Kontur: voll bis OUTLINE[0], auslaufend bis OUTLINE[1] Gemini-Pixel neben dem Gold; Deckung der Kontur */
const OUTLINE = [1, 3];
const OUTLINE_ALPHA = 0.7;
/** Dunkle Motivflaechen: ab SOLID[0] ueber Schwarz auslaufend, ab SOLID[1] deckend (Helligkeit 0-255) */
const SOLID = [8, 30];

const clamp01 = (v) => Math.min(1, Math.max(0, v));
const smooth = (x, a, b) => {
  const t = clamp01((x - a) / (b - a));
  return t * t * (3 - 2 * t);
};
const pot = (n) => 2 ** Math.ceil(Math.log2(Math.max(1, n)));

/** Liste der freigegebenen Motive (Motivnamen klein, a-z/0-9) */
export function readApproved(dir = SRC) {
  const list = JSON.parse(readFileSync(path.join(dir, "approved.json"), "utf8"));
  if (!Array.isArray(list)) throw new Error("approved.json: Array von Motivnamen erwartet");
  for (const n of list) if (typeof n !== "string" || !/^[a-z0-9]{2,16}$/.test(n)) throw new Error("approved.json: Motivname ungueltig: " + n);
  return list;
}

/** Goldanteil 0..1 eines Pixels: Rot >= Gruen >= Blau mit deutlichem Abstand Rot-Blau */
export function goldWeight(r, g, b) {
  const mx = Math.max(r, g, b);
  if (mx <= 0) return 0;
  if (g > r * 1.04 || b > g * 1.08) return 0; // gruen- oder blaustichig
  return smooth((r - b) / mx, 0.18, 0.32);
}

/**
 * Freistellen: img (RGBA, Gemini-Raster) -> RGBA mit Alpha aus Helligkeit und ent-multiplizierter Farbe, nur im
 * erlaubten Bereich und nur Gold. fx/fy: Gemini-Pixel je Screenshot-Pixel.
 */
export function extract(img, fx = img.w / SHOT.w, fy = img.h / SHOT.h) {
  const { w, h, rgba } = img;
  const inRegion = (X, Y) => (Y <= REGION.topMaxY && X >= REGION.topMinX) || (X >= REGION.rightMinX && Y <= REGION.rightMaxY);
  // Bezugshelligkeit: helle Goldtoene des Motivs (95. Perzentil der Helligkeit goldener Pixel)
  const hist = new Uint32Array(256);
  let n = 0;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      if (!inRegion(x / fx, y / fy)) continue;
      const o = (y * w + x) * 4, r = rgba[o], g = rgba[o + 1], b = rgba[o + 2], mx = Math.max(r, g, b);
      if (mx > 60 && goldWeight(r, g, b) > 0.5) { hist[mx]++; n++; }
    }
  }
  if (n < 50) throw new Error("kein Gold im Bereich um die Karte gefunden");
  let acc = 0, ref = 255;
  for (let v = 0; v < 256; v++) { acc += hist[v]; if (acc >= 0.95 * n) { ref = v; break; } }
  const floor = 0.1 * ref;
  const alpha = new Float32Array(w * h);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      if (!inRegion(x / fx, y / fy)) continue;
      const o = (y * w + x) * 4, r = rgba[o], g = rgba[o + 1], b = rgba[o + 2], mx = Math.max(r, g, b);
      // Gold: Deckung aus der Helligkeit; dunkle Flaechen im Motiv (Schildgrund, Binnenlinien, dunkelbraun) heben sich klar
      // vom reinen Schwarz (0-2) ab und bleiben deckend mit ihrer echten Farbe, sofern sie nicht gruen-/blaustichig sind
      const lumA = clamp01(mx / ref) * smooth(mx, floor, 2 * floor) * goldWeight(r, g, b);
      const solidA = g > r * 1.08 || b > r * 1.05 ? 0 : smooth(mx, SOLID[0], SOLID[1]);
      alpha[y * w + x] = Math.max(lumA, solidA);
    }
  }
  // Dunkle Kontur: Gemini zeichnet das Gold mit dunklem Rand, der auf Schwarz unsichtbar ist. Pixel bis OUTLINE[0]
  // Gemini-Pixel neben deckendem Gold werden fast deckend (mit ihrer echten, dunklen Farbe), bis OUTLINE[1] auslaufend.
  const dist = outlineDistance(alpha, w, h, OUTLINE[1]);
  const out = new Uint8Array(w * h * 4);
  for (let p = 0; p < w * h; p++) {
    const d = dist[p];
    const edge = d > 0 && d <= OUTLINE[1] && inRegion((p % w) / fx, Math.floor(p / w) / fy)
      ? OUTLINE_ALPHA * (1 - smooth(d, OUTLINE[0], OUTLINE[1] + 1)) : 0;
    const a = Math.max(alpha[p], edge);
    if (a <= 0.004) continue;
    const o = p * 4;
    // ent-multiplizieren: das Bild ist Farbe x Deckung auf Schwarz
    const div = Math.max(a, clamp01(Math.max(rgba[o], rgba[o + 1], rgba[o + 2]) / ref), 1e-3);
    for (let c = 0; c < 3; c++) out[o + c] = Math.min(255, Math.round(rgba[o + c] / div));
    out[o + 3] = Math.round(a * 255);
  }
  return { w, h, rgba: out, ref };
}

/**
 * Helligkeitsabgleich (immer klar erkennbar, aber nicht grell): Mass sind die hellen Goldtoene, das 90. Perzentil der
 * sichtbaren Helligkeit (Luma x Deckung) deckender Pixel. Liegt es unter LEVEL.lo, wird die Farbe angehoben, ueber LEVEL.hi
 * gedaempft; dazwischen bleibt das Motiv, wie Gemini es gemalt hat. Nur die Farbe, die Deckung (Freistellung) bleibt.
 */
export const LEVEL = { lo: 128, hi: 140, maxGain: 1.6, target: { frontier: 140 } };

export function brightness(img) {
  const v = [];
  for (let p = 0; p < img.w * img.h; p++) {
    const o = p * 4, a = img.rgba[o + 3] / 255;
    if (a >= 0.3) v.push((0.3 * img.rgba[o] + 0.59 * img.rgba[o + 1] + 0.11 * img.rgba[o + 2]) * a);
  }
  if (!v.length) return 0;
  v.sort((a, b) => a - b);
  return v[Math.floor(0.9 * (v.length - 1))];
}

export function level(img, name = "") {
  const p90 = brightness(img);
  if (!(p90 > 0)) return img;
  const t = LEVEL.target[name];
  const want = t ? t : p90 < LEVEL.lo ? LEVEL.lo : p90 > LEVEL.hi ? LEVEL.hi : p90;
  const gain = Math.min(LEVEL.maxGain, want / p90);
  img.level = { p90, gain };
  if (Math.abs(gain - 1) < 1e-3) return img;
  const c = img.rgba;
  for (let o = 0; o < c.length; o += 4) {
    if (!c[o + 3]) continue;
    for (let k = 0; k < 3; k++) c[o + k] = Math.min(255, Math.round(c[o + k] * gain));
  }
  return img;
}

/**
 * Schattenrand (auf jedem Untergrund klar erkennbar - Gold auf rotem Fels -, aber auf hellem Himmel kein dunkler
 * Klecks): schmale, weiche Kontur ohne Versatz in dunkler Bronze. Deckung = smooth(weichgezeichnete Deckung) - ueberall
 * gleich breit (~r Bildschirmpixel), fuellt nur Luecken schmaler als ~2 r. Das Gold liegt darueber, Deckung und Farbe bleiben.
 */
export const HALO = { r: 1.0, from: 0.03, to: 0.3, alpha: 0.7, rgb: [34, 23, 12] };

function boxBlur(src, w, h, r) {
  const tmp = new Float32Array(w * h), out = new Float32Array(w * h), n = 2 * r + 1;
  for (let y = 0; y < h; y++) {
    let acc = 0;
    for (let x = -r; x <= r; x++) acc += src[y * w + Math.min(w - 1, Math.max(0, x))];
    for (let x = 0; x < w; x++) {
      tmp[y * w + x] = acc / n;
      acc += src[y * w + Math.min(w - 1, x + r + 1)] - src[y * w + Math.max(0, x - r)];
    }
  }
  for (let x = 0; x < w; x++) {
    let acc = 0;
    for (let y = -r; y <= r; y++) acc += tmp[Math.min(h - 1, Math.max(0, y)) * w + x];
    for (let y = 0; y < h; y++) {
      out[y * w + x] = acc / n;
      acc += tmp[Math.min(h - 1, y + r + 1) * w + x] - tmp[Math.max(0, y - r) * w + x];
    }
  }
  return out;
}

export function halo(img, fx = img.w / SHOT.w) {
  const { w, h, rgba } = img;
  const r = Math.max(1, Math.round((HALO.r * fx) / 2));
  let a = new Float32Array(w * h);
  for (let p = 0; p < w * h; p++) a[p] = rgba[p * 4 + 3] / 255;
  for (let i = 0; i < 2; i++) a = boxBlur(a, w, h, r); // zwei Durchgaenge ~ Gauss, Reichweite ~ 2 r
  const out = new Uint8Array(rgba.length);
  for (let p = 0; p < w * h; p++) {
    const o = p * 4, ga = rgba[o + 3] / 255, sa = HALO.alpha * smooth(a[p], HALO.from, HALO.to);
    const oa = ga + sa * (1 - ga);
    if (oa <= 0.004) continue;
    for (let c = 0; c < 3; c++) out[o + c] = Math.round((rgba[o + c] * ga + HALO.rgb[c] * sa * (1 - ga)) / oa);
    out[o + 3] = Math.round(oa * 255);
  }
  return { w, h, rgba: out };
}

/** Konturabstand: Schritte (8er-Nachbarschaft) zum naechsten deckenden Goldpixel (Alpha > 0,45), 0 = selbst Gold, bis max */
function outlineDistance(alpha, w, h, max) {
  const dist = new Uint8Array(w * h).fill(255);
  let front = [];
  for (let p = 0; p < w * h; p++) if (alpha[p] > 0.45) { dist[p] = 0; front.push(p); }
  for (let d = 1; d <= max && front.length; d++) {
    const next = [];
    for (const p of front) {
      const x = p % w, y = (p - x) / w;
      for (let dy = -1; dy <= 1; dy++) {
        for (let dx = -1; dx <= 1; dx++) {
          const nx = x + dx, ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          const q = ny * w + nx;
          if (dist[q] <= d) continue;
          dist[q] = d;
          next.push(q);
        }
      }
    }
    front = next;
  }
  return dist;
}

/**
 * Ring finden: Radius aus dem Radialprofil der unteren Ringhaelfte (Winkel 55..125 Grad unter der Waagrechten), Krone =
 * mit dem Ring verbundene Pixel in einem Kegel ueber der Sonne. Liefert { radius, mask } (mask: 1 = Ring, Gemini-Raster).
 */
export function findRing(img, fx = img.w / SHOT.w, fy = img.h / SHOT.h, sun = SUN) {
  const { w, h, rgba } = img;
  const alpha = (X, Y) => {
    const x = Math.round(X * fx), y = Math.round(Y * fy);
    if (x < 0 || y < 0 || x >= w || y >= h) return 0;
    return rgba[(y * w + x) * 4 + 3] / 255;
  };
  const prof = [];
  for (let r = 0; r <= sun.r * 3; r += 0.5) {
    let s = 0, c = 0;
    for (let a = 55; a <= 125; a += 1) {
      const t = (a * Math.PI) / 180;
      s += alpha(sun.x + r * Math.cos(t), sun.y + r * Math.sin(t)) > 0.25 ? 1 : 0;
      c++;
    }
    prof.push({ r, v: s / c });
  }
  // Ringband: erste Stelle ab 0,6 x Sonnenradius mit Deckung > 0,3; Aussenrand: danach Deckung < 0,04 (zweimal)
  let i = prof.findIndex((p) => p.r >= sun.r * 0.6 && p.v > 0.3);
  if (i < 0) throw new Error("Ring um die Sonne nicht gefunden");
  let quiet = 0;
  for (; i < prof.length; i++) {
    quiet = prof[i].v < 0.04 ? quiet + 1 : 0;
    if (quiet >= 2) break;
  }
  if (i >= prof.length) throw new Error("Aussenrand des Rings nicht gefunden");
  const radius = prof[i].r + 1.5;
  const mask = new Uint8Array(w * h);
  const sx = sun.x * fx, sy = sun.y * fy;
  const dist = (x, y) => Math.hypot((x - sx) / fx, (y - sy) / fy);
  // Scheibe
  const x0 = Math.max(0, Math.floor((sun.x - radius) * fx)), x1 = Math.min(w - 1, Math.ceil((sun.x + radius) * fx));
  const y0 = Math.max(0, Math.floor((sun.y - radius) * fy)), y1 = Math.min(h - 1, Math.ceil((sun.y + radius) * fy));
  for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) if (dist(x, y) <= radius) mask[y * w + x] = 1;
  // Krone: Kegel ueber der Sonne (|dx| < 0,7 r, bis 2,5 r hoch), Flutfuellung von der oberen Ringkante durch deckende Pixel
  const inCone = (x, y) => {
    const X = x / fx, Y = y / fy;
    return Math.abs(X - sun.x) < 0.7 * radius && Y < sun.y && Y > sun.y - 2.5 * radius;
  };
  const solid = (x, y) => rgba[(y * w + x) * 4 + 3] > 25;
  const crown = new Uint8Array(w * h), queue = [];
  for (let y = y0; y <= y1; y++) {
    for (let x = x0; x <= x1; x++) {
      if (mask[y * w + x] && inCone(x, y) && solid(x, y) && dist(x, y) > radius - 3) { crown[y * w + x] = 1; queue.push(y * w + x); }
    }
  }
  while (queue.length) {
    const p = queue.pop(), x = p % w, y = (p - x) / w;
    for (let dy = -1; dy <= 1; dy++) {
      for (let dx = -1; dx <= 1; dx++) {
        const nx = x + dx, ny = y + dy;
        if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
        const q = ny * w + nx;
        if (crown[q] || mask[q] || !inCone(nx, ny) || !solid(nx, ny)) continue;
        crown[q] = 1;
        queue.push(q);
      }
    }
  }
  // Kronenrand: weiche Kantenpixel (Alpha <= 25) um die Krone mitnehmen (3 Gemini-Pixel)
  const grown = crown.slice();
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      if (!crown[y * w + x]) continue;
      for (let dy = -3; dy <= 3; dy++) {
        for (let dx = -3; dx <= 3; dx++) {
          const nx = x + dx, ny = y + dy;
          if (nx >= 0 && ny >= 0 && nx < w && ny < h && inCone(nx, ny)) grown[ny * w + nx] = 1;
        }
      }
    }
  }
  let crownPx = 0;
  for (let p = 0; p < w * h; p++) if (grown[p] && !mask[p]) { mask[p] = 1; crownPx++; }
  return { radius, mask, crownPx };
}

/** Teilbild: nur Pixel, fuer die keep(p) gilt */
function select(img, keep) {
  const out = new Uint8Array(img.rgba.length);
  for (let p = 0; p < img.w * img.h; p++) {
    if (!keep(p)) continue;
    for (let k = 0; k < 4; k++) out[p * 4 + k] = img.rgba[p * 4 + k];
  }
  return { w: img.w, h: img.h, rgba: out };
}

/** Deckende Box (Alpha > 2) in Screenshot-Koordinaten oder null */
export function shotBox(img, fx = img.w / SHOT.w, fy = img.h / SHOT.h) {
  const { w, h, rgba } = img;
  let x0 = w, y0 = h, x1 = -1, y1 = -1;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      if (rgba[(y * w + x) * 4 + 3] <= 2) continue;
      if (x < x0) x0 = x;
      if (x > x1) x1 = x;
      if (y < y0) y0 = y;
      if (y > y1) y1 = y;
    }
  }
  if (x1 < 0) return null;
  return { x0: x0 / fx, y0: y0 / fy, x1: (x1 + 1) / fx, y1: (y1 + 1) / fy };
}

function blit(dst, src, dx, dy) {
  for (let y = 0; y < src.h; y++) {
    for (let x = 0; x < src.w; x++) {
      const s = (y * src.w + x) * 4, d = ((dy + y) * dst.w + dx + x) * 4;
      for (let k = 0; k < 4; k++) dst.rgba[d + k] = src.rgba[s + k];
    }
  }
}
const blank = (w, h) => ({ w, h, rgba: new Uint8Array(w * h * 4) });

/** Ausschnitt box (Screenshot-Koordinaten) mit s Texeln je Screenshot-Pixel aus dem Gemini-Raster */
function cut(img, box, s, fx, fy) {
  const ow = Math.max(1, Math.round((box.x1 - box.x0) * s)), oh = Math.max(1, Math.round((box.y1 - box.y0) * s));
  return resample(img, box.x0 * fx, box.y0 * fy, (box.x1 - box.x0) * fx, (box.y1 - box.y0) * fy, ow, oh);
}

/** Groesste Aufloesung s (Texel je Screenshot-Pixel, Schritt 0,05, hoechstens maxS), fuer die fits(s) gilt; null, wenn < 1 */
function bestScale(fits, maxS) {
  for (let s = maxS; s >= 1 - 1e-9; s = Math.round((s - 0.05) * 100) / 100) if (fits(s)) return s;
  return null;
}

/** Eine Textur je Stueck: groesste Aufloesung (1 bis MAX_SCALE Texel je Screenshot-Pixel) mit Zweierpotenz-Massen < 1 MiB */
function pieceTexture(img, box, fx, fy) {
  const w = box.x1 - box.x0, h = box.y1 - box.y0;
  const dims = (s) => [pot(Math.round(w * s) + 2 * PAD), pot(Math.round(h * s) + 2 * PAD)];
  const s = bestScale((k) => { const [aw, ah] = dims(k); return aw * ah * 4 + 18 < LIMIT; }, MAX_SCALE);
  if (!s) throw new Error("Stueck passt nicht unter 1 MiB ohne Hochskalieren");
  const tex = cut(img, box, s, fx, fy);
  const [aw, ah] = dims(s);
  const atlas = blank(aw, ah);
  blit(atlas, tex, PAD, PAD);
  return { atlas, scale: s, rect: { x: PAD, y: PAD, w: tex.w, h: tex.h } };
}

/**
 * Ein Motiv aus dem Gemini-Raster (PNG-dekodiert) bauen: { pieces: [{ key, box, atlas, rect, scale }], ringRadius, info }.
 * Stuecke: "top" (Leiste ueber der Karte), "side" (Spalte rechts), "ring" (Ring um die Sonne mit Krone); jedes eine eigene,
 * ungedrehte Textur. box in Screenshot-Pixeln; die Lua-Daten rechnen sie in Kartenbreiten ab der Sonnenmitte um.
 */
export function buildMotif(src, name = "") {
  const fx = src.w / SHOT.w, fy = src.h / SHOT.h;
  const orn = level(extract(src, fx, fy), name);
  const ring = findRing(orn, fx, fy);
  const ringImg = select(orn, (p) => ring.mask[p] === 1);
  const bodyImg = select(orn, (p) => ring.mask[p] !== 1);
  const ringBox = shotBox(ringImg, fx, fy);
  if (!shotBox(bodyImg, fx, fy) || !ringBox) throw new Error("Koerper oder Ring leer");
  // Teilung des Koerpers: Spalte rechts = x >= xs und y >= ys; ys = Unterkante des Koerpers links der Spalte
  const xs = REGION.rightMinX;
  const leftBox = shotBox(select(bodyImg, (p) => (p % src.w) / fx < xs), fx, fy);
  const ys = Math.max(OUTER.y0, leftBox ? Math.ceil(leftBox.y1) : OUTER.y0);
  const inSide = (p) => { const x = p % src.w, y = (p - x) / src.w; return x / fx >= xs && y / fy >= ys; };
  const topImg = select(bodyImg, (p) => !inSide(p)), sideImg = select(bodyImg, inSide);
  const pieces = [];
  for (const [key, raw] of [["top", topImg], ["side", sideImg], ["ring", ringImg]]) {
    if (!shotBox(raw, fx, fy)) continue;
    const img = halo(raw, fx);
    const box = shotBox(img, fx, fy);
    if (!box) continue;
    pieces.push({ key, box, ...pieceTexture(img, box, fx, fy) });
  }
  return { pieces, ringRadius: ring.radius, measure: measureMotif(orn, fx, fy), level: orn.level,
    info: { ref: orn.ref, crownPx: ring.crownPx, split: { xs, ys } } };
}

/** laengste zusammenhaengende Strecke deckender Pixel (Alpha > 0,4) auf einer Linie: n Schritte ab (x, y) in (dx, dy) */
function longestRun(img, x, y, dx, dy, n) {
  let best = 0, run = 0;
  for (let i = 0; i < n; i++) {
    const px = x + i * dx, py = y + i * dy;
    const on = px >= 0 && py >= 0 && px < img.w && py < img.h && img.rgba[(py * img.w + px) * 4 + 3] > 102;
    run = on ? run + 1 : 0;
    if (run > best) best = run;
  }
  return best;
}

/**
 * Geometrie eines Motivs messen (Screenshot-Pixel), Grundlage der einheitlichen Lage aller Motive:
 *  - Ringmitte und Innenradius: Innenkante des Rings von der Sonnenmitte aus nach links, rechts, oben, unten (je Median
 *    ueber 7 parallele Strahlen); Mitte = Mittelpunkt der gegenueberliegenden Kanten
 *  - topLine: Zeile mit der laengsten durchgehenden Goldstrecke in der Leiste (links vom Ring, um die Rahmenoberkante)
 *  - sideLine: Spalte mit der laengsten durchgehenden Goldstrecke in der Spalte rechts (unterhalb der Ecke)
 *  sure = false, wenn die laengste Strecke kurz ist (unsichere Messung).
 */
export function measureMotif(img, fx = img.w / SHOT.w, fy = img.h / SHOT.h) {
  const solid = (X, Y) => {
    const x = Math.round(X * fx), y = Math.round(Y * fy);
    return x >= 0 && y >= 0 && x < img.w && y < img.h && img.rgba[(y * img.w + x) * 4 + 3] > 127;
  };
  const median = (a) => a.slice().sort((p, q) => p - q)[a.length >> 1];
  const edge = (dx, dy) => {
    const hits = [];
    for (let o = -3; o <= 3; o++) {
      for (let r = SUN.r * 0.6; r <= SUN.r * 2; r += 0.25) {
        const X = SUN.x + dx * r + dy * o, Y = SUN.y + dy * r + dx * o;
        if (solid(X, Y)) { hits.push(r); break; }
      }
    }
    if (hits.length < 4) throw new Error("Innenkante des Rings nicht gefunden");
    return median(hits);
  };
  const L = edge(-1, 0), R = edge(1, 0), U = edge(0, -1), Dn = edge(0, 1);
  const cx = SUN.x + (R - L) / 2, cy = SUN.y + (Dn - U) / 2, inner = (L + R + U + Dn) / 4;
  // Leiste: Zeilen um die Rahmenoberkante, x vom Rahmen links bis vor den Ring
  const x0 = Math.round(OUTER.x0 * fx), x1 = Math.round((cx - inner * 1.6) * fx);
  let top = null;
  for (let y = Math.round((OUTER.y0 - 45) * fy); y <= Math.round((OUTER.y0 + 8) * fy); y++) {
    const run = longestRun(img, x0, y, 1, 0, x1 - x0);
    if (!top || run > top.run) top = { run, y };
  }
  // Spalte: Spalten um die Rahmenkante rechts, y von unterhalb der Ecke bis vor die Rahmenunterkante
  const y0 = Math.round((OUTER.y0 + 150) * fy), y1 = Math.round((OUTER.y1 + 15) * fy);
  let side = null;
  for (let x = Math.round((OUTER.x1 - 25) * fx); x <= Math.round((OUTER.x1 + 45) * fx); x++) {
    const run = longestRun(img, x, y0, 0, 1, y1 - y0);
    if (!side || run > side.run) side = { run, x };
  }
  return {
    cx, cy, inner,
    topLine: (top.y + 0.5) / fy, topRun: top.run / fx, topSure: top.run / fx >= 40,
    sideLine: (side.x + 0.5) / fx, sideRun: side.run / fy, sideSure: side.run / fy >= 30,
  };
}

/**
 * Einheitliche Geometrie: Korrektur eines Motivs auf die kanonische Messung canon (Vorbild dwarf). Ringmitte auf die
 * Sonne, Massstab k = Innenradius kanonisch / gemessen (alle Stuecke gleich), danach Leiste senkrecht auf die kanonische
 * Hauptlinie, Spalte waagrecht auf die kanonische Hauptlinie (nur verschieben; beide Verschiebungen gelten fuer Leiste UND Spalte). Liefert { k, dyTop, dxSide, ... }.
 */
export function normalization(m, canon) {
  const k = canon.inner / m.inner;
  // Hauptlinien des Vorbilds in der korrigierten Lage (Vorbild-Ringmitte auf der Sonne, k = 1)
  const canonTop = SUN.y + (canon.topLine - canon.cy), canonSide = SUN.x + (canon.sideLine - canon.cx);
  const topScaled = SUN.y + (m.topLine - m.cy) * k, sideScaled = SUN.x + (m.sideLine - m.cx) * k;
  return { k, dxRing: SUN.x - m.cx, dyRing: SUN.y - m.cy, dyTop: canonTop - topScaled, dxSide: canonSide - sideScaled };
}

/** Box eines Stuecks nach der Korrektur (Screenshot-Pixel) */
export function normBox(box, key, m, n) {
  // Leiste und Spalte gemeinsam verschoben (dxSide waagrecht, dyTop senkrecht): getrennt verschoben brach alles, was ueber die
  // Teilung reicht (Banner, Totempfahl, Kette); den Versatz der Leiste zum Ring verdeckt der Ring.
  const body = key === "top" || key === "side";
  const t = (X, Y) => [SUN.x + (X - m.cx) * n.k + (body ? n.dxSide : 0), SUN.y + (Y - m.cy) * n.k + (body ? n.dyTop : 0)];
  const [x0, y0] = t(box.x0, box.y0), [x1, y1] = t(box.x1, box.y1);
  return { x0, y0, x1, y1 };
}

const luaNum = (v) => {
  if (!Number.isFinite(v)) throw new Error("keine endliche Zahl");
  return String(Math.round(v * 100000) / 100000);
};
const luaRect = (r) => `x = ${r.x}, y = ${r.y}, w = ${r.w}, h = ${r.h}`;

/** Inhalt von modules/Minimap/OrnamentData.lua; entries: [{ name, motif (aus buildMotif) }] */
export function ornamentLua(entries) {
  const W = MAP.x1 - MAP.x0;
  const lines = [
    "-- ERZEUGT von scripts/gen-minimap-ornament.mjs aus docs/minimap-ornament-src/<motiv>-frei-v1.jpg. Nicht von Hand aendern.",
    "-- Zonen-Ornament der Minimap (4:3). Fixpunkt ist die Sonnenmitte (GameTimeFrame): alle Stuecke liegen relativ zu ihr wie",
    "-- im Referenzbild. Masse in Kartenbreiten (sichtbares Kartenrechteck in der Vorlage), x nach rechts, y nach unten.",
    "-- pieces[i]: key (top | side | ring), file (Media/<file>.tga, ungedreht), tw/th = Texturgroesse, r = Rechteck in der",
    "-- Textur, x/y = obere linke Ecke ab der Sonnenmitte, w/h = Groesse. sunX/sunY = Sonnenmitte ab der oberen rechten Ecke",
    "-- des Kartenrechtecks (Rueckfall ohne Sonne), sunR = Sonnenradius, ringR = Aussenradius des Rings.",
    "-- Einheitliche Geometrie (Vorbild dwarf): norm.k = Massstab (Innenradius des Rings), dxRing/dyRing = Ringmitte auf die",
    "-- Sonne, dyTop = Leiste senkrecht, dxSide = Spalte waagrecht verschoben (Screenshot-Pixel) - so sitzen alle Motive bei",
    "-- denselben Reglerwerten gleich am Rahmen.",
    "local _, ns = ...",
    `local D = { ratio = "4:3", ref = { mapW = ${W}, mapH = ${MAP.y1 - MAP.y0} }, order = {}, motifs = {} }`,
    "ns.MinimapOrnamentData = D",
    "local function add(name, m)",
    "    D.order[#D.order + 1] = name",
    "    D.motifs[name] = m",
    "end",
  ];
  for (const { name, motif, norm } of entries) {
    const m = motif.measure, n = norm || { k: 1, dxRing: 0, dyRing: 0, dyTop: 0, dxSide: 0 };
    const mm = m || { cx: SUN.x, cy: SUN.y };
    const pcs = motif.pieces.map((p) => {
      const b = normBox(p.box, p.key, mm, n);
      return `{ key = "${p.key}", file = "mmorn-${name}-${p.key}", tw = ${p.atlas.w}, th = ${p.atlas.h}, ` +
        `r = { ${luaRect(p.rect)} }, x = ${luaNum((b.x0 - SUN.x) / W)}, y = ${luaNum((b.y0 - SUN.y) / W)}, ` +
        `w = ${luaNum((b.x1 - b.x0) / W)}, h = ${luaNum((b.y1 - b.y0) / W)} }`;
    }).join(",\n    ");
    if (m) {
      lines.push(`-- ${name}: gemessen Ringmitte (${m.cx.toFixed(1)}, ${m.cy.toFixed(1)}), Innenradius ${m.inner.toFixed(1)}, ` +
        `Leiste y ${m.topLine.toFixed(1)} (Strecke ${m.topRun.toFixed(0)}${m.topSure ? "" : ", UNSICHER"}), ` +
        `Spalte x ${m.sideLine.toFixed(1)} (Strecke ${m.sideRun.toFixed(0)}${m.sideSure ? "" : ", UNSICHER"}) px`);
    }
    lines.push(`add(${JSON.stringify(name)}, { sunX = ${luaNum((SUN.x - MAP.x1) / W)}, sunY = ${luaNum((SUN.y - MAP.y0) / W)}, ` +
      `sunR = ${luaNum(SUN.r / W)}, ringR = ${luaNum((motif.ringRadius * n.k) / W)}, ` +
      `norm = { k = ${luaNum(n.k)}, dxRing = ${luaNum(n.dxRing)}, dyRing = ${luaNum(n.dyRing)}, dyTop = ${luaNum(n.dyTop)}, dxSide = ${luaNum(n.dxSide)} }, pieces = {`);
    lines.push(`    ${pcs},`);
    lines.push("} })");
  }
  return lines.join("\n") + "\n";
}

/** Gemini-JPG -> dekodiertes RGBA (PNG-Zwischenstand im Temp-Ordner, Schluessel = Groesse + Aenderungszeit) */
export function loadSource(jpg) {
  const cache = path.join(os.tmpdir(), "lucid-mmorn-src");
  mkdirSync(cache, { recursive: true });
  const st = statSync(jpg);
  const png = path.join(cache, `${path.basename(jpg, ".jpg")}-${st.size}-${Math.round(st.mtimeMs)}.png`);
  if (!existsSync(png)) jpgToPng(jpg, png);
  return decodePng(readFileSync(png));
}

export function run(names) {
  const approved = readApproved();
  const list = names.length ? names : approved;
  for (const n of list) if (!approved.includes(n)) throw new Error("Motiv nicht freigegeben (approved.json): " + n);
  const entries = [];
  for (const name of approved) {
    const jpg = path.join(SRC, `${name}-frei-v1.jpg`);
    if (!existsSync(jpg)) throw new Error("Vorlage fehlt: " + jpg);
    const motif = buildMotif(loadSource(jpg), name);
    if (list.includes(name) || motif.pieces.some((p) => !existsSync(path.join(MEDIA, `mmorn-${name}-${p.key}.tga`)))) {
      for (const p of motif.pieces) {
        const file = path.join(MEDIA, `mmorn-${name}-${p.key}.tga`), buf = tgaRgba(p.atlas);
        if (buf.length >= LIMIT) throw new Error(file + " >= 1 MiB");
        writeFileSync(file, buf);
      }
    }
    console.log(`${name}: ` + motif.pieces.map((p) => `${p.key} ${p.atlas.w} x ${p.atlas.h} (${p.scale} Texel/px)`).join(", ") +
      `, Helligkeit ${motif.level ? motif.level.p90.toFixed(0) + " x " + motif.level.gain.toFixed(2) : "-"}` +
      `, Ringradius ${motif.ringRadius.toFixed(1)} px, Krone ${motif.info.crownPx} px, Bezug ${motif.info.ref}`);
    entries.push({ name, motif });
  }
  // einheitliche Geometrie: alle Motive auf die Messung des Vorbilds (dwarf, sonst das erste freigegebene)
  const canon = (entries.find((e) => e.name === CANON) || entries[0]).motif.measure;
  for (const e of entries) {
    e.norm = normalization(e.motif.measure, canon);
    const m = e.motif.measure, n = e.norm;
    console.log(`  ${e.name}: Ring (${m.cx.toFixed(1)}, ${m.cy.toFixed(1)}) r ${m.inner.toFixed(1)} -> k ${n.k.toFixed(3)}, ` +
      `Leiste y ${m.topLine.toFixed(1)}${m.topSure ? "" : " UNSICHER"} -> dy ${n.dyTop.toFixed(1)}, ` +
      `Spalte x ${m.sideLine.toFixed(1)}${m.sideSure ? "" : " UNSICHER"} -> dx ${n.dxSide.toFixed(1)}`);
  }
  writeFileSync(DATA, ornamentLua(entries));
  // verwaiste Texturen nicht mehr freigegebener Motive entfernen
  for (const f of readdirSync(MEDIA)) {
    const m = /^mmorn-([a-z0-9]+)-([a-z]+)\.tga$/.exec(f);
    if (m && (!approved.includes(m[1]) || !["top", "side", "ring"].includes(m[2]))) { unlinkSync(path.join(MEDIA, f)); console.log("entfernt: " + f); }
  }
  console.log(`OrnamentData.lua: ${entries.length} Motiv(e)`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  run(process.argv.slice(2).filter((a) => !a.startsWith("--")));
}
