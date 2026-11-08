// Erzeugt die Texturen der Zonenkarte (B5) als unkomprimierte 32-bit-TGA. Farbe kommt per SetVertexColor aus
// Card.lua; die Texturen tragen Form (Alpha) und eine eingebackene Helligkeit (Grau), die nur getoent wird.
//   zone-band.tga      256 x 64    Lichtband: Alpha laeuft nach allen Seiten weich auf 0 aus (weiss)
//   zone-glow.tga      128 x 64    Glanz: radialer (elliptischer) Verlauf, Rand Alpha 0 (weiss)
//   zone-swirl.tga     1024 x 128  Verzierung "Geschwungen": EIN durchgehender Breitfeder-Strich (rechte Seite, links
//                                  gespiegelt) vom Titel als Haarlinie, schwellend, in eine Volute muendend, mit zwei
//                                  organisch abzweigenden Nebenranken; Schattierung (heller Grat oben, dunklere
//                                  Unterkante) und zarter Schein
//   zone-filigree.tga  1024 x 96   Verzierung "Filigran": Raute mit Schnoerkeln, die in die Doppellinie uebergehen
// Striche werden mit 6 x 6 Unterabtastungen je Pixel gerastert (Supersampling, keine Treppen).
// Aufruf: node scripts/gen-zone-media.mjs. Deterministisch; die erzeugten Dateien liegen im Repo.
// Vorlage uebernehmen: node scripts/gen-zone-media.mjs --from vorlage.png [--out zone-swirl.tga] [--side right|left|full]
//   [--rows top|bottom|full] [--max 1024] [--floor 0.03] [--gamma 1] [--bold 0]  (Gold auf Schwarz, PNG 8 bit; gibt
//   aspect/midY/fill aus; --floor hebt die Schwarzschwelle gegen JPG-Rauschen, --gamma < 1 und --bold > 0 staerken
//   sehr feine Striche)
// Alle Vorlagen-Stile auf einmal: node scripts/gen-zone-media.mjs --templates (liest docs/ornament-src/recipes.json,
//   wandelt JPG per Headless-Chrome nach PNG, schreibt Media/zone-<name>.tga und modules/Zone/Ornaments.lua)
// Layout "pair" (Zonen-Motive, "auto": true ohne layout.kind): eine 16:9-Vorlage mit zwei VERSCHIEDENEN Seiten (links ein
//   Ornament, rechts ein anderes, breite leere Mitte). Teilung an der breitesten leeren Spalte nahe der Mitte
//   (convert.split = Anteil erzwingt eine Stelle), je Seite Zuschnitt auf den Inhalt + eigene Stufen:
//   Media/zone-<name>-left-<stufe>[-n].tga und zone-<name>-right-...; Ornaments.lua: left/right mit aspect, midY, srcW, levels

import { existsSync, mkdirSync, readdirSync, readFileSync, unlinkSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import zlib from "node:zlib";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const MEDIA = path.join(ROOT, "addon", "Lucid", "Media");

const smoothstep = (a, b, x) => {
  const t = Math.min(1, Math.max(0, (x - a) / (b - a)));
  return t * t * (3 - 2 * t);
};
const lerp = (a, b, t) => a + (b - a) * t;
const clamp01 = (v) => Math.min(1, Math.max(0, v));

/** Alpha-Feld (0..1) aus alpha(u, v) mit u, v in [-1, 1] (Pixelmitten); Helligkeit 1 */
function field(w, h, alpha) {
  const a = new Float64Array(w * h);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) a[y * w + x] = alpha(((x + 0.5) / w) * 2 - 1, ((y + 0.5) / h) * 2 - 1);
  }
  return { w, h, a };
}

/** TGA (Typ 2, 32 bit, Ursprung oben links); Grau aus f.l (0..1, Standard weiss), Alpha aus f.a */
export function tga({ w, h, a, l }) {
  const head = Buffer.alloc(18);
  head[2] = 2; // unkomprimiert, Truecolor
  head.writeUInt16LE(w, 12);
  head.writeUInt16LE(h, 14);
  head[16] = 32;
  head[17] = 0x28; // 8 Alpha-Bits, Ursprung oben links
  const px = Buffer.alloc(w * h * 4, 255);
  for (let i = 0; i < w * h; i++) {
    if (l) px[i * 4] = px[i * 4 + 1] = px[i * 4 + 2] = Math.round(255 * clamp01(l[i]));
    px[i * 4 + 3] = Math.round(255 * clamp01(a[i]));
  }
  return Buffer.concat([head, px]);
}

// Striche ------------------------------------------------------------------------------------------
// Ein Strich ist eine Folge kurzer Segmente { x1, y1, r1, x2, y2, r2 } (r = halbe Breite, linear dazwischen).

/** Punktfolge [[x, y, r], ...] -> Segmente */
const toSegs = (pts) => pts.slice(1).map((p, i) => ({ x1: pts[i][0], y1: pts[i][1], r1: pts[i][2], x2: p[0], y2: p[1], r2: p[2] }));

/** Kurve p(t), t in [0, 1], als n + 1 Punkte [x, y] */
const sample = (p, n) => Array.from({ length: n + 1 }, (_, i) => p(i / n));
const bezier = (p0, p1, p2, p3) => (t) => {
  const u = 1 - t;
  return [0, 1].map((k) => u * u * u * p0[k] + 3 * u * u * t * p1[k] + 3 * u * t * t * p2[k] + t * t * t * p3[k]);
};
const dirOf = (pts, i) => {
  const a = pts[Math.max(0, i - 1)], b = pts[Math.min(pts.length - 1, i + 1)];
  const d = Math.hypot(b[0] - a[0], b[1] - a[1]) || 1;
  return [(b[0] - a[0]) / d, (b[1] - a[1]) / d];
};

/**
 * Logarithmische Spirale, die tangential an (x, y) mit Richtung dir anschliesst. side = +1 rollt (in Bildkoordinaten,
 * y nach unten) nach links ein, -1 nach rechts. r0 Startradius, turns Umlaeufe, rEnd Endradius.
 */
function volute(x, y, dir, r0, turns, rEnd, side, n) {
  const phiMax = turns * 2 * Math.PI, b = Math.log(r0 / rEnd) / phiMax;
  // Grundform: Start unter dem Mittelpunkt (0, -r0), Lauf nach rechts, im Uhrzeigersinn (Bild) einrollend
  const raw = sample((u) => {
    const phi = u * phiMax, r = r0 * Math.exp(-b * phi), th = Math.PI / 2 - phi;
    return [r * Math.cos(th), -r0 + r * Math.sin(th)];
  }, n).map(([px, py]) => [px, side < 0 ? py : -py]);
  const d0 = dirOf(raw, 0);
  const rot = Math.atan2(dir[1], dir[0]) - Math.atan2(d0[1], d0[0]);
  const c = Math.cos(rot), s = Math.sin(rot);
  return raw.map(([px, py]) => [x + px * c - py * s, y + px * s + py * c]);
}

/** Breitfeder: Halbbreite aus Huelle env (0..1) und Strichrichtung (Feder unter nib rad gehalten) */
const nibWidth = (hw, env, dir, nib = -0.5) => hw * env * (0.32 + 0.68 * Math.abs(Math.sin(Math.atan2(dir[1], dir[0]) - nib)));

/** Striche mit ss x ss Unterabtastungen je Pixel rastern (Abdeckung = Alpha), Segmente je Pixel vorsortiert */
function rasterize(w, h, segs, ss = 6) {
  const cells = Array.from({ length: w * h }, () => []);
  segs.forEach((s, i) => {
    const r = Math.max(s.r1, s.r2) + 1;
    const x0 = Math.max(0, Math.floor(Math.min(s.x1, s.x2) - r)), x1 = Math.min(w - 1, Math.ceil(Math.max(s.x1, s.x2) + r));
    const y0 = Math.max(0, Math.floor(Math.min(s.y1, s.y2) - r)), y1 = Math.min(h - 1, Math.ceil(Math.max(s.y1, s.y2) + r));
    for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) cells[y * w + x].push(i);
  });
  const a = new Float64Array(w * h);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const list = cells[y * w + x];
      if (list.length === 0) continue;
      let hit = 0;
      for (let sy = 0; sy < ss; sy++) {
        for (let sx = 0; sx < ss; sx++) {
          const px = x + (sx + 0.5) / ss, py = y + (sy + 0.5) / ss;
          for (const i of list) {
            const s = segs[i];
            const dx = s.x2 - s.x1, dy = s.y2 - s.y1;
            const len2 = dx * dx + dy * dy || 1e-12;
            const t = Math.min(1, Math.max(0, ((px - s.x1) * dx + (py - s.y1) * dy) / len2));
            const qx = s.x1 + dx * t - px, qy = s.y1 + dy * t - py;
            const r = lerp(s.r1, s.r2, t);
            if (qx * qx + qy * qy <= r * r) { hit++; break; }
          }
        }
      }
      a[y * w + x] = hit / (ss * ss);
    }
  }
  return { w, h, a };
}

/** Feld auf halbe Groesse (2 x 2 Flaechenmittel; Helligkeit nach Alpha gewichtet) */
function halve(f) {
  const w = f.w >> 1, h = f.h >> 1, a = new Float64Array(w * h), l = new Float64Array(w * h);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    let sa = 0, sl = 0;
    for (const [dx, dy] of [[0, 0], [1, 0], [0, 1], [1, 1]]) {
      const i = (2 * y + dy) * f.w + 2 * x + dx, al = f.a[i];
      sa += al; sl += al * (f.l ? f.l[i] : 1);
    }
    a[y * w + x] = sa / 4;
    l[y * w + x] = sa > 0 ? sl / sa : 1;
  }
  return { w, h, a, l };
}

/** Weichzeichnen (3 x Kastenfilter je Richtung ~ Gauss) */
function blur(w, h, src, r) {
  let a = Float64Array.from(src);
  const pass = (horiz) => {
    const out = new Float64Array(w * h);
    for (let y = 0; y < h; y++) {
      for (let x = 0; x < w; x++) {
        let sum = 0, n = 0;
        for (let k = -r; k <= r; k++) {
          const xx = horiz ? x + k : x, yy = horiz ? y : y + k;
          if (xx >= 0 && xx < w && yy >= 0 && yy < h) { sum += a[yy * w + xx]; n++; }
        }
        out[y * w + x] = sum / (2 * r + 1);
      }
    }
    a = out;
  };
  for (let i = 0; i < 3; i++) { pass(true); pass(false); }
  return a;
}

/**
 * Gold-Schattierung + Schein: Helligkeit aus dem senkrechten Abdeckungs-Gefaelle (Licht von oben: heller Grat oben,
 * dunklere Unterkante), dazu ein sehr zarter weicher Schein (weichgezeichnete Abdeckung) um den Strich.
 */
function shade(f, { d = 2, halo = 0.22, haloR = 4 } = {}) {
  const { w, h, a } = f;
  const at = (x, y) => (y < 0 || y >= h ? 0 : a[y * w + x]);
  const hb = blur(w, h, a, haloR);
  const outA = new Float64Array(w * h), outL = new Float64Array(w * h);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const i = y * w + x, c = a[i];
      const lum = Math.min(1, Math.max(0.4, 0.8 - 0.4 * (at(x, y - d) - at(x, y + d))));
      const g = (1 - c) * halo * Math.min(1, hb[i] * 1.6);
      const al = c + g;
      outA[i] = al;
      outL[i] = al > 0 ? (c * lum + g * 0.9) / al : 1;
    }
  }
  return { w, h, a: outA, l: outL };
}

// Entwuerfe ----------------------------------------------------------------------------------------

/** Ranke (rechte Seite), inneres Ende links bei x = 10 auf der Mittellinie y = 64 */
export function swirlField(k = 1) {
  const W = 1024, H = 128, HW = 8.5;
  // Hauptstrich: eine sanfte Welle bis zur Volute, endet waagerecht
  const A = sample((t) => [10 + 860 * t, 64 + 20 * t * t - 24 * (1 - t) * Math.sin(2 * Math.PI * t)], 600);
  const endDir = dirOf(A, A.length - 1);
  const B = volute(A[A.length - 1][0], A[A.length - 1][1], endDir, 50, 1.6, 7, -1, 480);
  const path = [...A, ...B.slice(1)];
  // Bogenlaenge -> Huelle (Haarlinie am Titel, Schwellung, feines Auslaufen in der Volute)
  const len = [0];
  for (let i = 1; i < path.length; i++) len.push(len[i - 1] + Math.hypot(path[i][0] - path[i - 1][0], path[i][1] - path[i - 1][1]));
  const total = len[len.length - 1];
  const env = (s) => 0.1 + 0.9 * Math.pow(Math.sin(Math.PI * Math.min(1, Math.pow(s, 0.9) * 1.02)), 0.65);
  const main = path.map((p, i) => [p[0], p[1], Math.max(0.55, nibWidth(HW, env(len[i] / total), dirOf(path, i)))]);
  // Nebenranken: zweigen tangential aus dem Hauptstrich ab, biegen weg und rollen sich klein ein
  const tendril = (t, side, L, bend, r0) => {
    const i = Math.round(t * (A.length - 1));
    const [bx, by] = A[i], d = dirOf(A, i), nrm = [-d[1] * side, d[0] * side];
    const p = (k, m) => [bx + d[0] * k + nrm[0] * m, by + d[1] * k + nrm[1] * m];
    const C = sample(bezier([bx, by], p(L * 0.3, 0), p(L * 0.7, bend * 0.9), p(L, bend)), 220);
    const V = volute(C[C.length - 1][0], C[C.length - 1][1], dirOf(C, C.length - 1), r0, 1.15, 2.2, side < 0 ? 1 : -1, 160);
    const pts = [...C, ...V.slice(1)];
    const w0 = main[i][2] * 0.62;
    return pts.map((q, k) => [q[0], q[1], Math.max(0.5, w0 * Math.pow(1 - k / pts.length, 0.85) * (0.55 + 0.45 *
      Math.abs(Math.sin(Math.atan2(dirOf(pts, k)[1], dirOf(pts, k)[0]) + 0.5))))]);
  };
  // y nach unten: side -1 = Nebenranke nach oben, +1 = nach unten
  const up = tendril(0.3, -1, 120, 30, 14);
  const down = tendril(0.58, 1, 120, 28, 13);
  const segs = [...toSegs(main), ...toSegs(up), ...toSegs(down)].map((q) => ({ x1: q.x1 * k, y1: q.y1 * k, r1: q.r1 * k, x2: q.x2 * k, y2: q.y2 * k, r2: q.r2 * k }));
  const f = rasterize(W * k, H * k, segs);
  return shade(f, { d: 2 * k, haloR: 4 * k });
}

/** Filigran: Raute mit Schnoerkeln, die stetig in die Doppellinie uebergehen; Linien laufen nach aussen aus */
export function filigreeField(k = 1) {
  const S = 2 * k, cx = 256, cy = 24;
  const pts = [];
  for (const side of [-1, 1]) {
    const X = (d) => cx + side * d;
    for (const dy of [-3, 3]) {
      // Schnoerkel von der Rautenspitze, laeuft waagerecht in die Linie aus (ein Strich)
      const curl = sample(bezier([X(14), cy], [X(19), cy + dy * 3.4], [X(26), cy + dy], [X(34), cy + dy]), 80)
        .map((p, k) => [p[0], p[1], lerp(0.95, 0.62, k / 80)]);
      const line = sample((t) => [X(lerp(34, 236, t)), cy + dy], 40).map((p) => [p[0], p[1], 0.62]);
      pts.push([...curl, ...line.slice(1)]);
    }
  }
  const ring = [[cx, cy - 12], [cx + 14, cy], [cx, cy + 12], [cx - 14, cy], [cx, cy - 12]];
  pts.push(ring.map((p) => [p[0], p[1], 0.85]));
  const inner = [[cx, cy - 5], [cx + 5, cy], [cx, cy + 5], [cx - 5, cy], [cx, cy - 5]];
  pts.push(inner.map((p) => [p[0], p[1], 1.6]));
  const segs = pts.flatMap((p) => toSegs(p.map(([x, y, r]) => [x * S, y * S, r * S])));
  const f = rasterize(512 * S, 48 * S, segs);
  for (let y = 0; y < f.h; y++) {
    for (let x = 0; x < f.w; x++) f.a[y * f.w + x] *= 1 - smoothstep(120, 236, Math.abs((x + 0.5) / S - cx));
  }
  return shade(f, { d: 2 * k, halo: 0.18, haloR: 3 * k });
}

export const bandField = () =>
  field(256, 64, (u, v) => (1 - smoothstep(0, 1, Math.abs(u))) * (1 - smoothstep(0.3, 1, Math.abs(v))));
export const glowField = () => field(128, 64, (u, v) => Math.max(0, 1 - (u * u + v * v)) ** 2);
// Vorlage -> Verzierungs-TGA ----------------------------------------------------------------------
// Aus einer Gold-auf-Schwarz-Vorlage (PNG) eine weisse/graue TGA mit Alpha machen, wie Card.lua sie erwartet:
// Luminanz -> Alpha (Hintergrund schwarz = durchsichtig), Farbe auf einen hellen Gold-Grauwert normalisiert (die
// Helligkeitsunterschiede der Vorlage bleiben als Schattierung), eine Seite gewaehlt (rechts; links wird gespiegelt,
// damit das innere Ende links liegt), auf die Bounding-Box zugeschnitten und auf Zweierpotenz-Masse gebracht.

/** PNG (8 bit, nicht interlaced; Graustufen, RGB, Palette, Grau+Alpha, RGBA) -> { w, h, rgba: Uint8Array } */
export function decodePng(buf) {
  const SIG = [137, 80, 78, 71, 13, 10, 26, 10];
  if (!SIG.every((b, i) => buf[i] === b)) throw new Error("keine PNG-Datei (JPG bitte vorher als PNG speichern)");
  let pos = 8, w = 0, h = 0, depth = 0, type = 0, interlace = 0, plte = null, trns = null;
  const idat = [];
  while (pos < buf.length) {
    const len = buf.readUInt32BE(pos), kind = buf.toString("latin1", pos + 4, pos + 8), data = buf.subarray(pos + 8, pos + 8 + len);
    if (kind === "IHDR") { w = data.readUInt32BE(0); h = data.readUInt32BE(4); depth = data[8]; type = data[9]; interlace = data[12]; }
    else if (kind === "PLTE") plte = data;
    else if (kind === "tRNS") trns = data;
    else if (kind === "IDAT") idat.push(data);
    else if (kind === "IEND") break;
    pos += 12 + len;
  }
  if (depth !== 8 || interlace !== 0) throw new Error(`PNG nicht unterstuetzt (Bittiefe ${depth}, Interlace ${interlace}); bitte 8 bit ohne Interlace`);
  const ch = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }[type];
  if (!ch) throw new Error("PNG-Farbtyp nicht unterstuetzt: " + type);
  const raw = zlib.inflateSync(Buffer.concat(idat)), stride = w * ch, img = new Uint8Array(stride * h);
  for (let y = 0; y < h; y++) {
    const f = raw[y * (stride + 1)], src = y * (stride + 1) + 1, dst = y * stride;
    for (let x = 0; x < stride; x++) {
      const a = x >= ch ? img[dst + x - ch] : 0, b = y > 0 ? img[dst - stride + x] : 0, c = x >= ch && y > 0 ? img[dst - stride + x - ch] : 0;
      let v = raw[src + x];
      if (f === 1) v += a; else if (f === 2) v += b; else if (f === 3) v += (a + b) >> 1;
      else if (f === 4) { const p = a + b - c, pa = Math.abs(p - a), pb = Math.abs(p - b), pc = Math.abs(p - c); v += pa <= pb && pa <= pc ? a : pb <= pc ? b : c; }
      img[dst + x] = v & 255;
    }
  }
  const rgba = new Uint8Array(w * h * 4);
  for (let i = 0; i < w * h; i++) {
    const o = i * 4, s = i * ch;
    if (type === 0) { rgba[o] = rgba[o + 1] = rgba[o + 2] = img[s]; rgba[o + 3] = 255; }
    else if (type === 4) { rgba[o] = rgba[o + 1] = rgba[o + 2] = img[s]; rgba[o + 3] = img[s + 1]; }
    else if (type === 2) { rgba[o] = img[s]; rgba[o + 1] = img[s + 1]; rgba[o + 2] = img[s + 2]; rgba[o + 3] = 255; }
    else if (type === 6) { for (let k = 0; k < 4; k++) rgba[o + k] = img[s + k]; }
    else { const p = img[s] * 3; rgba[o] = plte[p]; rgba[o + 1] = plte[p + 1]; rgba[o + 2] = plte[p + 2]; rgba[o + 3] = trns && img[s] < trns.length ? trns[img[s]] : 255; }
  }
  return { w, h, rgba };
}

const nextPot = (n) => 2 ** Math.ceil(Math.log2(Math.max(1, n)));
const LIMIT = 1024 * 1024; // Hoechstgroesse je TGA
const percentile = (arr, q) => { const s = Float64Array.from(arr).sort(); return s[Math.min(s.length - 1, Math.floor(q * (s.length - 1)))]; };

/**
 * Vorlage -> Feld { w, h, a, l } (Zweierpotenz-Masse, hoechstens maxW breit) + Konstanten fuer Card.SWIRL
 * (aspect = Breite/Hoehe, midY = Hoehe der Strichmitte am inneren Ende als Anteil von oben).
 * side: "right" (rechte Bildhaelfte), "left" (linke Haelfte, gespiegelt) oder "full".
 */
/** Vorlage vorbereiten: Luminanz -> Alpha/Grau, Seite/Zeilen waehlen, auf die Bounding-Box zuschneiden */
export function prepareTemplate({ w, h, rgba }, { side = "right", rows = "full", floor = 0.03, split } = {}) {
  const L = new Float64Array(w * h);
  for (let i = 0; i < w * h; i++) {
    const o = i * 4;
    L[i] = ((0.2126 * rgba[o] + 0.7152 * rgba[o + 1] + 0.0722 * rgba[o + 2]) / 255) * (rgba[o + 3] / 255);
  }
  // rows: nur obere bzw. untere Bildhaelfte (z. B. bei gespiegelten Doppelornamenten)
  if (rows === "top" || rows === "bottom") {
    for (let y = 0; y < h; y++) if ((rows === "top") !== (y < h / 2)) for (let x = 0; x < w; x++) L[y * w + x] = 0;
  }
  const stroke = [];
  for (let i = 0; i < w * h; i++) if (L[i] > 0.06) stroke.push(L[i]);
  if (stroke.length === 0) throw new Error("Vorlage leer: keine hellen Pixel auf dunklem Grund gefunden");
  const lMid = Math.max(0.1, percentile(stroke, 0.5)), lMax = Math.max(lMid, percentile(stroke, 0.99));
  // split (Spalte): Trennstelle statt Bildmitte (Layout "pair")
  const mid = Number.isInteger(split) ? split : null;
  const x0s = side === "right" ? (mid ?? Math.floor(w / 2)) : 0, x1s = side === "left" ? (mid ?? Math.ceil(w / 2)) : w;
  const sw = x1s - x0s, A = new Float64Array(sw * h), G = new Float64Array(sw * h);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < sw; x++) {
      const sx = side === "left" ? x1s - 1 - x : x0s + x, v = L[y * w + sx];
      A[y * sw + x] = clamp01((v - floor) / (lMid - floor));
      G[y * sw + x] = 0.45 + 0.55 * clamp01(v / lMax);
    }
  }
  // Bounding-Box (Alpha > 0,02) + 2 px Rand
  let bx0 = sw, by0 = h, bx1 = -1, by1 = -1;
  for (let y = 0; y < h; y++) for (let x = 0; x < sw; x++) if (A[y * sw + x] > 0.02) { bx0 = Math.min(bx0, x); bx1 = Math.max(bx1, x); by0 = Math.min(by0, y); by1 = Math.max(by1, y); }
  if (bx1 < 0) throw new Error("Vorlage leer: auf der gewaehlten Seite nichts gefunden");
  bx0 = Math.max(0, bx0 - 2); by0 = Math.max(0, by0 - 2); bx1 = Math.min(sw - 1, bx1 + 2); by1 = Math.min(h - 1, by1 + 2);
  const cw = bx1 - bx0 + 1, chh = by1 - by0 + 1;
  return { A, G, sw, bx0, by0, cw, chh };
}

export function convertTemplate(img, { side = "right", rows = "full", maxW = 1024, floor = 0.03, gamma = 1, bold = 0 } = {}) {
  const { A, G, sw, bx0, by0, cw, chh } = prepareTemplate(img, { side, rows, floor });
  // Zielmasse: Breite Zweierpotenz (<= maxW), Hoehe Zweierpotenz mit senkrecht zentriertem Rand (keine Stauchung;
  // passt es nicht unter 1 MiB, halbiert convertToTga die Breite)
  const W = Math.min(maxW, nextPot(cw)), scale = W / cw;
  const sh = Math.max(1, Math.round(chh * scale)), H = nextPot(sh), scaleY = scale, aspect = W / H, squash = 1;
  const top = Math.floor((H - sh) / 2);
  const out = { w: W, h: H, a: new Float64Array(W * H), l: new Float64Array(W * H).fill(1) };
  const at = (F, x, y) => {
    x = Math.min(cw - 1, Math.max(0, x)); y = Math.min(chh - 1, Math.max(0, y));
    const xi = Math.floor(x), yi = Math.floor(y), fx = x - xi, fy = y - yi, x2 = Math.min(cw - 1, xi + 1), y2 = Math.min(chh - 1, yi + 1);
    const g = (xx, yy) => F[(by0 + yy) * sw + bx0 + xx];
    return lerp(lerp(g(xi, yi), g(x2, yi), fx), lerp(g(xi, y2), g(x2, y2), fx), fy);
  };
  const n = Math.max(2, Math.ceil(1 / Math.min(scale, scaleY)) * 2); // Unterabtastungen je Richtung (Flaechenmittel)
  for (let y = 0; y < sh; y++) {
    for (let x = 0; x < W; x++) {
      let sa = 0, sl = 0;
      for (let j = 0; j < n; j++) {
        for (let i = 0; i < n; i++) {
          const sx = (x + (i + 0.5) / n) / scale - 0.5, sy = (y + (j + 0.5) / n) / scaleY - 0.5, a = at(A, sx, sy);
          sa += a; sl += a * at(G, sx, sy);
        }
      }
      const k = (top + y) * W + x;
      out.a[k] = sa / (n * n);
      out.l[k] = sa > 0 ? sl / sa : 1;
    }
  }
  // feine Striche staerken: bold = Verbreiterung in Ausgabe-Pixeln (weicher Rand), gamma < 1 hebt blasse Kanten an.
  // Noetig fuer sehr duenne Vorlagen, die bei kleiner Anzeige (Mip-Stufen) sonst verschwinden bzw. verschmelzen.
  if (bold > 0) {
    const a0 = Float64Array.from(out.a), l0 = Float64Array.from(out.l), R = Math.ceil(bold + 0.5);
    for (let y = 0; y < H; y++) {
      for (let x = 0; x < W; x++) {
        let best = a0[y * W + x], gl = l0[y * W + x];
        for (let dy = -R; dy <= R; dy++) {
          for (let dx = -R; dx <= R; dx++) {
            const xx = x + dx, yy = y + dy;
            if (xx < 0 || yy < 0 || xx >= W || yy >= H || (dx === 0 && dy === 0)) continue;
            const v = a0[yy * W + xx] * clamp01(bold + 0.5 - Math.hypot(dx, dy));
            if (v > best) { best = v; gl = l0[yy * W + xx]; }
          }
        }
        out.a[y * W + x] = best;
        out.l[y * W + x] = gl;
      }
    }
  }
  if (gamma !== 1) for (let i = 0; i < W * H; i++) out.a[i] = Math.pow(out.a[i], gamma);
  // Strichmitte am inneren Ende (erste 3 % der Breite)
  let wy = 0, ws = 0;
  for (let y = 0; y < H; y++) for (let x = 0; x < Math.max(1, Math.round(W * 0.03)); x++) { const a = out.a[y * W + x]; wy += a * (y + 0.5); ws += a; }
  // Innenflaeche (fuer Rahmen): vom Mittelpunkt aus freie Strecke bis zum ersten Strich (Alpha > 0,3). Waagerecht:
  // Minimum ueber Zeilen um die Mitte; senkrecht: Median ueber Spalten +-20 % um die Mitte (einzelne Zier-Spitzen in
  // der Mitte wie Boegen/Lilien sollen die Hoehe nicht bestimmen). Anteile der Texturbreite bzw. -hoehe.
  const cx = W / 2, cy = top + sh / 2, hit = (x, y) => out.a[Math.round(y) * W + Math.round(x)] > 0.3;
  let freeX = W / 2;
  const ys = [];
  for (let k = -3; k <= 3; k++) {
    const y = Math.min(H - 1, Math.max(0, cy + (k / 3) * 0.12 * sh));
    for (const dir of [-1, 1]) { let d = 0; while (d < W / 2 - 1 && !hit(cx + dir * d, y)) d++; freeX = Math.min(freeX, d); }
  }
  for (let k = -5; k <= 5; k++) {
    const x = Math.min(W - 1, Math.max(0, cx + (k / 5) * 0.2 * W));
    let m = H / 2;
    for (const dir of [-1, 1]) { let d = 0; while (d < H / 2 - 1 && !hit(x, cy + dir * d)) d++; m = Math.min(m, d); }
    ys.push(m);
  }
  ys.sort((a, b) => a - b);
  const freeY = ys[Math.floor(ys.length / 2)];
  // Dehnstreifen (fuer Rahmen, 5-teiliger Zuschnitt): in der linken Haelfte der Innenflaeche (ohne die Mitte) die 8 px
  // breite Spaltengruppe mit der geringsten waagerechten Aenderung; rechts gespiegelt. stretchU = Beginn (Anteil),
  // stretchW = Breite (Anteil).
  const sw8 = Math.max(2, Math.round(W / 128));
  const colCost = (x) => { let c = 0; for (let y = 0; y < H; y++) c += Math.abs(out.a[y * W + x] - out.a[y * W + x + 1]); return c; };
  const lo = Math.max(1, Math.round(cx - freeX + 0.02 * W)), hi = Math.round(cx - 0.06 * W) - sw8;
  let bestX = lo, best = Infinity;
  for (let x = lo; x <= hi; x++) { let c = 0; for (let k = 0; k < sw8; k++) c += colCost(x + k); if (c < best) { best = c; bestX = x; } }
  // fill = Anteil der Hoehe mit Inhalt (der Rest ist senkrecht zentrierter Rand bis zur Zweierpotenz)
  return { field: out, aspect, midY: ws > 0 ? wy / ws / H : 0.5, fill: sh / H, innerW: (2 * freeX) / W, innerH: (2 * freeY) / H, squash,
    stretchU: bestX / W, stretchW: sw8 / W };
}

/**
 * Vorlage -> TGA-Puffer unter 1 MiB (Breite wird halbiert, bis es passt).
 * Liefert { buf, field, aspect, midY, fill }.
 */
export function convertToTga(img, opts = {}) {
  // Breite so waehlen, dass die Hoehe hoechstens x 2 gestaucht wird (hohe Motive wie Fluegel: lieber schmaler)
  let maxW = opts.maxW || 1024, res, buf;
  for (;;) {
    res = convertTemplate(img, { ...opts, maxW });
    buf = tga(res.field);
    if (buf.length < LIMIT || maxW <= 64) break;
    maxW = Math.floor(maxW / 2);
  }
  if (buf.length >= 1024 * 1024) throw new Error(`Ergebnis ${buf.length} B >= 1 MiB`);
  return { buf, ...res };
}


// Stufen (scharf in jeder Groesse) -----------------------------------------------------------------
// Je Vorlagen-Stil drei Stufen: "t" (Viertel), "s" (halbe Aufloesung) und "l" (groesste Zweierpotenz-Box unter 1 MiB, Inhalt mit echtem Seitenverhaeltnis
// eingepasst, keine Stauchung). Rahmen bestehen aus zwei Kacheln (linke/rechte Haelfte),
// damit sie trotz 1-MiB-Grenze die volle Breite behalten; die Naht liegt an der Texturkante (CLAMP, keine Linie).
// Card.lua schneidet per SetTexCoord auf den Inhalt zu und waehlt zur Laufzeit die Stufe zur Anzeigegroesse.

/** Ausschnitt [sx0, sx1) der vorbereiteten Vorlage in outW x outH rechnen: Flaechenmittel (Box-Supersampling),
 *  leichte Unschaerfemaske, dann optional gamma/bold */
function renderRegion(P, sx0, sx1, outW, outH, { sharpen = 0.5, gamma = 1, bold = 0 } = {}, sy0 = 0, sy1 = P.chh) {
  const { A, G, sw, bx0, by0, chh } = P;
  const sxs = (sx1 - sx0) / outW, sys = (sy1 - sy0) / outH;
  const n = Math.max(2, Math.ceil(Math.max(sxs, sys)) * 2);
  const at = (F, x, y) => {
    x = Math.min(P.cw - 1, Math.max(0, x)); y = Math.min(chh - 1, Math.max(0, y));
    const xi = Math.floor(x), yi = Math.floor(y), fx = x - xi, fy = y - yi, x2 = Math.min(P.cw - 1, xi + 1), y2 = Math.min(chh - 1, yi + 1);
    const g = (xx, yy) => F[(by0 + yy) * sw + bx0 + xx];
    return lerp(lerp(g(xi, yi), g(x2, yi), fx), lerp(g(xi, y2), g(x2, y2), fx), fy);
  };
  const a = new Float64Array(outW * outH), l = new Float64Array(outW * outH).fill(1);
  for (let y = 0; y < outH; y++) {
    for (let x = 0; x < outW; x++) {
      let sa = 0, sl = 0;
      for (let j = 0; j < n; j++) {
        for (let i = 0; i < n; i++) {
          const px = sx0 + (x + (i + 0.5) / n) * sxs - 0.5, py = sy0 + (y + (j + 0.5) / n) * sys - 0.5, v = at(A, px, py);
          sa += v; sl += v * at(G, px, py);
        }
      }
      a[y * outW + x] = sa / (n * n);
      l[y * outW + x] = sa > 0 ? sl / sa : 1;
    }
  }
  // Unschaerfemaske (3 x 3): Kanten nach dem Verkleinern wieder knackig, ohne Treppen
  if (sharpen > 0) {
    const b = Float64Array.from(a);
    for (let y = 0; y < outH; y++) {
      for (let x = 0; x < outW; x++) {
        let s = 0, c = 0;
        for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) {
          const xx = x + dx, yy = y + dy;
          if (xx >= 0 && yy >= 0 && xx < outW && yy < outH) { s += b[yy * outW + xx]; c++; }
        }
        a[y * outW + x] = clamp01(b[y * outW + x] + sharpen * (b[y * outW + x] - s / c));
      }
    }
  }
  const f = { w: outW, h: outH, a, l };
  if (bold > 0) strengthen(f, bold);
  if (gamma !== 1) for (let i = 0; i < a.length; i++) a[i] = Math.pow(a[i], gamma);
  return f;
}

/** Striche verbreitern (Ausgabe-Pixel, weicher Rand) */
function strengthen(f, bold) {
  const { w: W, h: H } = f, a0 = Float64Array.from(f.a), l0 = Float64Array.from(f.l), R = Math.ceil(bold + 0.5);
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      let best = a0[y * W + x], gl = l0[y * W + x];
      for (let dy = -R; dy <= R; dy++) for (let dx = -R; dx <= R; dx++) {
        const xx = x + dx, yy = y + dy;
        if (xx < 0 || yy < 0 || xx >= W || yy >= H || (dx === 0 && dy === 0)) continue;
        const v = a0[yy * W + xx] * clamp01(bold + 0.5 - Math.hypot(dx, dy));
        if (v > best) { best = v; gl = l0[yy * W + xx]; }
      }
      f.a[y * W + x] = best;
      f.l[y * W + x] = gl;
    }
  }
}

/** Kachel-Inhalt (cw x ch Pixel) in eine Box (W x H) legen; align "left" | "right" (Naht an der Kante) */
function placeInBox(tile, W, H, align) {
  const a = new Float64Array(W * H), l = new Float64Array(W * H).fill(1), ox = align === "right" ? W - tile.w : 0;
  for (let y = 0; y < tile.h; y++) for (let x = 0; x < tile.w; x++) { a[y * W + ox + x] = tile.a[y * tile.w + x]; l[y * W + ox + x] = tile.l[y * tile.w + x]; }
  return { field: { w: W, h: H, a, l }, u0: ox / W, u1: (ox + tile.w) / W, v0: 0, v1: tile.h / H };
}

/** groesste Zweierpotenz-Box (W*H*4 + 18 < 1 MiB), in die ein Inhalt mit Seitenverhaeltnis r am groessten passt */
function bestBox(r, maxW) {
  let best = null;
  for (let W = 32; W <= maxW; W *= 2) {
    for (let H = 32; W * H * 4 + 18 < LIMIT; H *= 2) {
      const cw = Math.min(W, H * r);
      if (!best || cw > best.cw) best = { W, H, cw };
    }
  }
  return best;
}

/** Messwerte am Inhalt (Anteile): midY (Strichmitte am inneren Ende), innerW/innerH, stretchU/stretchW */
function measure(f) {
  const { w: W, h: H, a } = f;
  let wy = 0, ws = 0;
  for (let y = 0; y < H; y++) for (let x = 0; x < Math.max(1, Math.round(W * 0.03)); x++) { wy += a[y * W + x] * (y + 0.5); ws += a[y * W + x]; }
  const cx = W / 2, cy = H / 2, hit = (x, y) => a[Math.round(y) * W + Math.round(x)] > 0.3;
  let freeX = W / 2;
  for (let k = -3; k <= 3; k++) {
    const y = Math.min(H - 1, Math.max(0, cy + (k / 3) * 0.12 * H));
    for (const dir of [-1, 1]) { let d = 0; while (d < W / 2 - 1 && !hit(cx + dir * d, y)) d++; freeX = Math.min(freeX, d); }
  }
  const ys = [];
  for (let k = -5; k <= 5; k++) {
    const x = Math.min(W - 1, Math.max(0, cx + (k / 5) * 0.2 * W));
    let m = H / 2;
    for (const dir of [-1, 1]) { let d = 0; while (d < H / 2 - 1 && !hit(x, cy + dir * d)) d++; m = Math.min(m, d); }
    ys.push(m);
  }
  ys.sort((p, q) => p - q);
  const sw8 = Math.max(2, Math.round(W / 128));
  const colCost = (x) => { let c = 0; for (let y = 0; y < H; y++) c += Math.abs(a[y * W + x] - a[y * W + x + 1]); return c; };
  const lo = Math.max(1, Math.round(cx - freeX + 0.02 * W)), hi = Math.max(lo, Math.round(cx - 0.06 * W) - sw8);
  let bestX = lo, best = Infinity;
  for (let x = lo; x <= hi; x++) { let c = 0; for (let k = 0; k < sw8; k++) c += colCost(x + k); if (c < best) { best = c; bestX = x; } }
  return { midY: ws > 0 ? wy / ws / H : 0.5, innerW: (2 * freeX) / W, innerH: (2 * ys[Math.floor(ys.length / 2)]) / H,
    stretchU: bestX / W, stretchW: sw8 / W };
}

/**
 * Vorlage -> Stufen. tiles = 1 (Seiten/Leisten) oder 2 (Rahmen). Liefert { aspect, midY, ..., levels: [{ key, cw,
 * tiles: [{ field, u0, u1, v0, v1, from, to }] }] } (levels klein -> gross; from/to = Inhaltsbereich der Kachel).
 */
export function buildLevels(img, opts = {}) {
  const P = prepareTemplate(img, opts);
  const r = P.cw / P.chh;
  const m = measure(renderRegion(P, 0, P.cw, 1024, Math.max(8, Math.round(1024 / r)), { sharpen: 0 }));
  return { aspect: r, ...m, srcW: Math.round(P.cw), levels: levelsOf(P, opts) };
}

/**
 * Hoehe der Spitze(n) am inneren Ende (Anteil von oben) fuer "pair": ab der innersten belegten Spalte (Alpha > 0,3) die
 * Zeilen mit Inhalt in den naechsten 4 % der Breite; Mitte von oberster bis unterster Zeile. Eine Spitze liefert ihre
 * Hoehe, mehrere uebereinander (Ober-/Unterschiene) ihre gemeinsame Mitte - dort sitzt der Titel.
 */
function tipMid(f) {
  const { w: W, h: H, a } = f;
  let x0 = -1;
  for (let x = 0; x < W && x0 < 0; x++) for (let y = 0; y < H; y++) if (a[y * W + x] > 0.3) { x0 = x; break; }
  if (x0 < 0) return 0.5;
  let y0 = H, y1 = -1;
  for (let x = x0; x < Math.min(W, x0 + Math.max(4, Math.round(W * 0.04))); x++) {
    for (let y = 0; y < H; y++) if (a[y * W + x] > 0.3) { y0 = Math.min(y0, y); y1 = Math.max(y1, y); }
  }
  return (y0 + y1 + 1) / 2 / H;
}

/**
 * Trennspalte fuer zwei eigenstaendige Seiten: die breiteste leere Spalten-Folge (hellster Pixel der Spalte <= Schwelle)
 * im mittleren Bereich [0,25 w, 0,75 w] (bei gleicher Breite die naechste zur Bildmitte); Trennstelle = ihre Mitte.
 * Gibt es dort keine leere Spalte, gilt die Bildmitte. frac (0..1) erzwingt eine Trennstelle.
 */
export function findSplit({ w, h, rgba }, { rows = "full", frac } = {}) {
  if (typeof frac === "number") return Math.min(w - 1, Math.max(1, Math.round(frac * w)));
  const colMax = new Float64Array(w);
  for (let y = 0; y < h; y++) {
    if ((rows === "top" && y >= h / 2) || (rows === "bottom" && y < h / 2)) continue;
    for (let x = 0; x < w; x++) {
      const o = (y * w + x) * 4, v = ((0.2126 * rgba[o] + 0.7152 * rgba[o + 1] + 0.0722 * rgba[o + 2]) / 255) * (rgba[o + 3] / 255);
      if (v > colMax[x]) colMax[x] = v;
    }
  }
  const lo = Math.floor(w * 0.25), hi = Math.ceil(w * 0.75), centre = w / 2;
  let best = null;
  for (let x = lo; x < hi;) {
    if (colMax[x] > 0.06) { x++; continue; }
    let e = x;
    while (e < hi && colMax[e] <= 0.06) e++;
    const run = { len: e - x, mid: Math.floor((x + e) / 2) };
    if (!best || run.len > best.len || (run.len === best.len && Math.abs(run.mid - centre) < Math.abs(best.mid - centre))) best = run;
    x = e;
  }
  return best ? best.mid : Math.floor(centre);
}

/**
 * Vorlage mit zwei verschiedenen Seiten -> { split, left, right }. Jede Seite wird an der Trennspalte abgeteilt, auf ihren
 * Inhalt zugeschnitten und wie bei "sides" zu Stufen gerechnet: { aspect, midY, srcW, levels }. Das innere Ende liegt in
 * beiden Faellen links in der Textur (die linke Haelfte wird beim Erzeugen gespiegelt abgelegt; Card.lua spiegelt sie
 * beim Zeichnen zurueck, auf dem Bildschirm steht also jede Seite wie in der Vorlage). Die Helligkeits-Normierung gilt
 * fuer das ganze Bild, damit beide Seiten gleich hell werden.
 */
export function buildPair(img, opts = {}) {
  const split = findSplit(img, { rows: opts.rows, frac: opts.split });
  const one = (side) => {
    const o = { ...opts, side, split };
    const P = prepareTemplate(img, o);
    const r = P.cw / P.chh;
    const midY = tipMid(renderRegion(P, 0, P.cw, 1024, Math.max(8, Math.round(1024 / r)), { sharpen: 0 }));
    return { aspect: r, midY, srcW: Math.round(P.cw), levels: levelsOf(P, { ...o, strips: true }) };
  };
  return { split, left: one("left"), right: one("right") };
}

/** Feld (eingebaute Entwuerfe) -> Stufen wie bei den Vorlagen (Quelle ohne Zuschnitt) */
export function fieldLevels(f, opts = {}) {
  return levelsOf({ A: f.a, G: f.l, sw: f.w, bx0: 0, by0: 0, cw: f.w, chh: f.h }, { sharpen: 0.3, ...opts });
}

/**
 * Zerlegung eines Inhalts (Breite W = Zweierpotenz, Hoehe th) in waagerechte Streifen voller Breite mit kleinster
 * Gesamtflaeche: Streifenhoehe Hb = Zweierpotenz mit W * Hb * 4 + 18 < 1 MiB, der letzte Streifen nur so hoch wie
 * noetig (Zweierpotenz). Unter Zerlegungen mit hoechstens 10 % mehr Flaeche als die kleinste gewinnt die mit den
 * wenigsten Kacheln. Liefert [{ r0, r1, boxH }] (Inhaltszeilen r0..r1, Texturhoehe boxH); die letzte Zeile r1 ist die
 * Gesamthoehe (th, bei 1-2 Restzeilen um diese kleiner).
 */
export function stripPlan(W, th) {
  let best = null, minArea = Infinity;
  const plans = [];
  for (let Hb = 8; Hb <= 1024; Hb *= 2) {
    if (W * Hb * 4 + 18 >= LIMIT) break;
    // ein Rest von hoechstens 2 Zeilen waere eine eigene Kachel fuer fast nichts: der Inhalt wird um diese Zeilen
    // gestaucht (unter 0,5 %, nicht sichtbar)
    let n = Math.ceil(th / Hb), rem = th - (n - 1) * Hb;
    if (n > 1 && rem <= 2) { n--; rem = Hb; }
    const lastH = nextPot(rem), area = W * ((n - 1) * Hb + lastH);
    plans.push({ Hb, n, lastH, rem, area });
    minArea = Math.min(minArea, area);
  }
  if (plans.length === 0) throw new Error("Streifen passen nicht unter 1 MiB (Breite " + W + ")");
  for (const p of plans) {
    if (p.area > minArea * 1.1) continue;
    if (!best || p.n < best.n || (p.n === best.n && p.area < best.area)) best = p;
  }
  const rows = [];
  for (let i = 0; i < best.n; i++) {
    const r0 = i * best.Hb, r1 = i === best.n - 1 ? r0 + best.rem : r0 + best.Hb;
    rows.push({ r0, r1, boxH: i === best.n - 1 ? best.lastH : best.Hb });
  }
  return rows;
}

function levelsOf(P, opts) {
  const r = P.cw / P.chh, ro = { sharpen: opts.sharpen ?? 0.5, gamma: opts.gamma ?? 1, bold: opts.bold ?? 0 };
  // Stufen mit Inhaltsbreite 256, 512, 1024, 2048 px (nicht breiter als die Vorlage selbst). Jede Stufe wird in
  // gleich breite Kacheln zerlegt: Kachel = Zweierpotenz-Box W x H unter 1 MiB, Inhalt fuellt die Breite ganz
  // (Naehte an Texturkanten, CLAMP), Hoehe = Inhaltshoehe (v1 < 1 bei Rand unten).
  // nicht ueber die Aufloesung der Vorlage hinaus (hoechstens 25 % Hochrechnen)
  const levels = [], maxCw = Math.min(opts.maxW || 2048, P.cw * 1.25);
  for (const [key, target] of [["t", 256], ["s", 512], ["l", 1024], ["x", 2048]]) {
    if (target > maxCw && key !== "t") break;
    if (opts.strips) {
      // waagerechte Streifen voller Breite (Layout pair): kaum Verschnitt, Naehte an Texturkanten
      const Ws = target, tiles = [], plan = stripPlan(nextPot(Ws), Math.max(4, Math.round(Ws / r)));
      const ths = plan[plan.length - 1].r1;
      for (const { r0, r1, boxH } of plan) {
        const tile = renderRegion(P, 0, P.cw, Ws, r1 - r0, ro, (P.chh * r0) / ths, (P.chh * r1) / ths);
        tiles.push({ ...placeInBox(tile, nextPot(Ws), boxH, "left"), from: 0, to: 1, y0: r0 / ths, y1: r1 / ths, w: nextPot(Ws), h: boxH });
      }
      levels.push({ key, cw: Ws, tiles });
      continue;
    }
    // Hoehe: Zweierpotenz; waere sie mehr als 1,4-mal so hoch wie der Inhalt, halbe Hoehe und schmalerer Inhalt
    let Wt = target, th = Math.max(4, Math.round(Wt / r)), H = nextPot(th);
    if (H / th > 1.4 && H > 8 && Math.floor((H / 2) * r) >= 0.9 * target) { H /= 2; Wt = Math.floor(H * r); th = H; }
    let W = nextPot(Wt);
    while (W > 8 && W * H * 4 + 18 >= LIMIT) W /= 2;
    if (W * H * 4 + 18 >= LIMIT) throw new Error("Stufe " + key + " passt nicht unter 1 MiB");
    // Kacheln: alle voll breit (Naehte an Texturkanten), die letzte ggf. schmaler (Rand rechts = Aussenkante)
    const n = Math.ceil(Wt / W), out = [];
    for (let t = 0; t < n; t++) {
      const x0 = t * W, x1 = Math.min(Wt, x0 + W);
      const tile = renderRegion(P, (P.cw * x0) / Wt, (P.cw * x1) / Wt, x1 - x0, th, ro);
      out.push({ ...placeInBox(tile, W, H, "left"), from: x0 / Wt, to: x1 / Wt, w: W, h: H });
    }
    levels.push({ key, cw: Wt, tiles: out });
  }
  return levels;
}

// Rezepte -> Ornaments.lua -----------------------------------------------------------------------
// docs/ornament-src/recipes.json: [{ name, src, convert: { side, rows, floor, gamma, bold, maxW }, layout: { kind,
// ... }, label: { deDE, enUS } }]. --templates wandelt jede Vorlage in Media/zone-<name>.tga und schreibt
// addon/Lucid/modules/Zone/Ornaments.lua (Stil-Tabelle mit gemessenem aspect/midY/fill + Beschriftungen).

const NAME_RE = /^[a-z][a-z0-9]{1,15}$/;
const LAYOUT_NUM = ["factor", "extra", "min", "max", "gap", "top", "alpha", "grow", "marginX", "marginY"];
// Zonen-Motive ("auto": true) ohne eigenes layout.kind sind zwei eigenstaendige Seiten ("pair")
const PAIR_DEFAULTS = { kind: "pair", factor: 1.6, min: 150, max: 340, gap: 6, alpha: 0.95, grow: 0.94 };
export const layoutOf = (r) => (r.auto && !r.layout?.kind ? { ...PAIR_DEFAULTS, ...(r.layout || {}) } : r.layout || {});
const luaStr = (s) => {
  if (typeof s !== "string" || s.length === 0 || s.length > 40 || /[\x00-\x1f|\\"]/.test(s)) throw new Error("Beschriftung ungueltig: " + s);
  return '"' + s + '"';
};
const luaNum = (v, what) => {
  if (typeof v !== "number" || !Number.isFinite(v)) throw new Error(what + ": Zahl erwartet");
  return String(Math.round(v * 10000) / 10000);
};

/**
 * Lua-Quelltext der Stil-Tabelle (entries: Rezept + gemessene Werte { aspect, midY, fill }).
 * Rezepte mit "auto": true sind Zonen-Motive: sie stehen in O.order NACH allen uebrigen Vorlagen-Stilen und zusaetzlich
 * in O.motif[name] = true (Ausklapper: Gruppe nach den bisherigen Stilen; Motiv-Wahl der Karte). Motive duerfen keine
 * Rahmen sein: die Dehnstreifen zerreissen geschwungene Motive.
 */
export function ornamentsLua(entries, builtin) {
  const lines = [
    "-- ERZEUGT von scripts/gen-zone-media.mjs --templates aus docs/ornament-src/recipes.json. Nicht von Hand aendern.",
    "-- Vorlagen-Stile der Zonenkarte (Card.STYLES) samt Beschriftung; Texturen in Media/zone-<name>.tga.",
    "local _, ns = ...",
    "local O = { order = {}, styles = {}, motif = {} }",
    "ns.ZoneOrnaments = O",
    "local function add(name, style, deDE, enUS)",
    "    O.order[#O.order + 1] = name",
    "    O.styles[name] = style",
    "    local loc = ns.Locales or {}",
    '    if loc.deDE then loc.deDE["ZONE_ORNAMENT_" .. name] = deDE end',
    '    if loc.enUS then loc.enUS["ZONE_ORNAMENT_" .. name] = enUS end',
    "end",
  ];
  const seen = new Set();
  for (const e of entries) {
    if (e.auto !== undefined && typeof e.auto !== "boolean") throw new Error(e.name + ": auto muss true/false sein");
    if (e.auto && layoutOf(e).kind === "frame") throw new Error(e.name + ": Zonen-Motive duerfen kein frame-Layout haben");
  }
  // Reihenfolge: bisherige Vorlagen-Stile, dann Zonen-Motive (je in Rezept-Reihenfolge)
  const ordered = [...entries.filter((e) => !e.auto), ...entries.filter((e) => e.auto)];
  for (const e of ordered) {
    if (!NAME_RE.test(e.name || "") || seen.has(e.name)) throw new Error("Stilname ungueltig/doppelt: " + e.name);
    seen.add(e.name);
    const L = layoutOf(e);
    if (!["sides", "bar", "frame", "pair"].includes(L.kind)) throw new Error(e.name + ": layout.kind sides|bar|frame|pair");
    if (L.kind === "pair") {
      const side = (X, what) => {
        if (!X) throw new Error(e.name + ": pair braucht " + what);
        return `{ aspect = ${luaNum(X.aspect, what + ".aspect")}, midY = ${luaNum(X.midY, what + ".midY")}, fill = 1, srcW = ${luaNum(X.srcW ?? 0, what + ".srcW")}, levels = { ${levelsLua(e.name, X.levels, what).join(", ")} } }`;
      };
      const pf = [`kind = "pair"`];
      for (const k of LAYOUT_NUM) if (L[k] !== undefined) pf.push(`${k} = ${luaNum(L[k], e.name + "." + k)}`);
      pf.push(`right = ${side(e.right, "right")}`, `left = ${side(e.left, "left")}`);
      lines.push(`add("${e.name}", { ${pf.join(", ")} },`, `    ${luaStr(e.label?.deDE)}, ${luaStr(e.label?.enUS)})`);
      continue;
    }
    const f = [`kind = "${L.kind}"`, `aspect = ${luaNum(e.aspect, "aspect")}`, `midY = ${luaNum(e.midY, "midY")}`, "fill = 1",
      `srcW = ${luaNum(e.srcW ?? 0, "srcW")}`];
    if (L.kind === "frame") f.push(`innerW = ${luaNum(e.innerW, "innerW")}`, `innerH = ${luaNum(e.innerH, "innerH")}`,
      `stretchU = ${luaNum(e.stretchU, "stretchU")}`, `stretchW = ${luaNum(e.stretchW, "stretchW")}`);
    for (const k of LAYOUT_NUM) if (L[k] !== undefined) f.push(`${k} = ${luaNum(L[k], e.name + "." + k)}`);
    for (const k of ["flipTop", "flipBottom"]) if (L[k] !== undefined) f.push(`${k} = ${L[k] ? "true" : "false"}`);
    const lv = levelsLua(e.name, e.levels);
    f.push(`levels = { ${lv.join(", ")} }`);
    lines.push(`add("${e.name}", { ${f.join(", ")} },`, `    ${luaStr(e.label?.deDE)}, ${luaStr(e.label?.enUS)})`);
  }
  for (const e of ordered) if (e.auto) lines.push(`O.motif.${e.name} = true`);
  // eingebaute Stile (Geschwungen/Filigran): nur Stufen, Layout steht in Card.lua
  lines.push("O.builtin = {}");
  for (const [name, levels] of Object.entries(builtin || {})) lines.push(`O.builtin.${name} = { ${levelsLua(name, levels).join(", ")} }`);
  return lines.join("\n") + "\n";
}

/** Stufen als Lua: { cw = Inhaltsbreite in Pixeln, tiles = { { file, u0, u1, v0, v1, from, to, w, h } } } (klein -> gross) */
function levelsLua(name, levels, side) {
  const base = side ? name + "-" + side : name;
  const lv = (levels || []).map((l) => {
      if (!/^[tslx]$/.test(l.key)) throw new Error(name + ": Stufe ungueltig");
      const t = l.tiles.map((x, i) => `{ file = "zone-${base}-${l.key}${l.tiles.length > 1 ? "-" + (i + 1) : ""}", u0 = ${luaNum(x.u0, "u0")}, u1 = ${luaNum(x.u1, "u1")}, v0 = ${luaNum(x.v0, "v0")}, v1 = ${luaNum(x.v1, "v1")}, from = ${luaNum(x.from, "from")}, to = ${luaNum(x.to, "to")}, ${x.y0 !== undefined ? `y0 = ${luaNum(x.y0, "y0")}, y1 = ${luaNum(x.y1, "y1")}, ` : ""}w = ${luaNum(x.w ?? 0, "w")}, h = ${luaNum(x.h ?? 0, "h")} }`);
      return `{ cw = ${luaNum(l.cw, "cw")}, tiles = { ${t.join(", ")} } }`;
    });
  if (lv.length === 0) throw new Error(name + ": keine Stufen");
  return lv;
}

const CHROME = [process.env.CHROME, "C:/Program Files/Google/Chrome/Application/chrome.exe",
  "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe", "/usr/bin/google-chrome", "/usr/bin/chromium"].filter(Boolean);

/** JPG -> PNG (verlustfrei aus den dekodierten Pixeln) per Headless-Browser-Bildschirmfoto in Originalgroesse */
export function jpgToPng(jpg, png) {
  const b = readFileSync(jpg);
  let i = 2, w = 0, h = 0;
  while (i < b.length) {
    if (b[i] !== 0xff) { i++; continue; }
    const m = b[i + 1];
    if (m >= 0xc0 && m <= 0xc3) { h = b.readUInt16BE(i + 5); w = b.readUInt16BE(i + 7); break; }
    i += 2 + b.readUInt16BE(i + 2);
  }
  if (!w || !h) throw new Error("JPG-Masse nicht lesbar: " + jpg);
  const browser = CHROME.find((p) => existsSync(p));
  if (!browser) throw new Error("kein Chrome/Edge gefunden (Umgebungsvariable CHROME setzen) - oder die Vorlage als PNG ablegen");
  const html = png + ".html";
  writeFileSync(html, `<!doctype html><html><body style="margin:0;background:#000"><img src="${pathToFileURL(jpg).href}" style="display:block;width:${w}px;height:${h}px"></body></html>`);
  const r = spawnSync(browser, ["--headless=new", "--disable-gpu", "--allow-file-access-from-files", "--hide-scrollbars",
    "--force-device-scale-factor=1", `--window-size=${w},${h}`, "--virtual-time-budget=3000", `--screenshot=${png}`,
    pathToFileURL(html).href], { stdio: "ignore", timeout: 60000 });
  unlinkSync(html);
  if (r.status !== 0 || !existsSync(png)) throw new Error("Umwandlung JPG -> PNG fehlgeschlagen: " + jpg);
}

/** root: Projektwurzel (Standard: dieses Repo); Tests geben einen Temp-Ordner mit docs/ornament-src/ an */
export function runTemplates(root = ROOT, { quiet = false } = {}) {
  const log = quiet ? () => {} : console.log;
  const media = path.join(root, "addon", "Lucid", "Media");
  mkdirSync(media, { recursive: true });
  mkdirSync(path.join(root, "addon", "Lucid", "modules", "Zone"), { recursive: true });
  const dir = path.join(root, "docs", "ornament-src");
  const recipes = JSON.parse(readFileSync(path.join(dir, "recipes.json"), "utf8"));
  const entries = [], written = new Set();
  for (const r of recipes) {
    if (!NAME_RE.test(r.name || "")) throw new Error("Stilname ungueltig: " + r.name);
    if (r.auto !== undefined && typeof r.auto !== "boolean") throw new Error(r.name + ": auto muss true/false sein");
    const layout = layoutOf(r);
    if (r.auto && layout.kind === "frame") throw new Error(r.name + ": Zonen-Motive duerfen kein frame-Layout haben");
    const src = path.join(dir, path.basename(r.src));
    let pngPath = src;
    if (/\.jpe?g$/i.test(src)) {
      pngPath = src.replace(/\.jpe?g$/i, ".png");
      if (!existsSync(pngPath)) jpgToPng(src, pngPath);
    }
    const writeLevels = (levels, base) => {
      for (const l of levels) {
        l.tiles.forEach((t, i) => {
          const file = `zone-${base}-${l.key}${l.tiles.length > 1 ? "-" + (i + 1) : ""}.tga`, buf = tga(t.field);
          written.add(file);
          if (buf.length >= LIMIT) throw new Error(file + " >= 1 MiB");
          writeFileSync(path.join(media, file), buf);
          log(`${file}: ${t.field.w} x ${t.field.h}, ${buf.length} B (Inhalt ${l.cw} px breit)`);
        });
      }
    };
    const img = decodePng(readFileSync(pngPath));
    if (layout.kind === "pair") {
      const res = buildPair(img, r.convert || {});
      writeLevels(res.left.levels, r.name + "-left");
      writeLevels(res.right.levels, r.name + "-right");
      log(`${r.name}: Trennung bei Spalte ${res.split}; links aspect ${res.left.aspect.toFixed(3)} midY ${res.left.midY.toFixed(4)} srcW ${res.left.srcW}, rechts aspect ${res.right.aspect.toFixed(3)} midY ${res.right.midY.toFixed(4)} srcW ${res.right.srcW}`);
      entries.push({ ...r, layout, ...res });
      continue;
    }
    const res = buildLevels(img, r.convert || {});
    writeLevels(res.levels, r.name);
    entries.push({ ...r, ...res });
  }
  // eingebaute Verzierungen (Vektor-Entwuerfe in doppelter Aufloesung) ebenfalls als Stufen
  const builtin = {};
  for (const [name, make] of [["swirl", swirlField], ["filigree", filigreeField]]) {
    builtin[name] = fieldLevels(make(2));
    for (const l of builtin[name]) l.tiles.forEach((t, i) => {
      const file = `zone-${name}-${l.key}${l.tiles.length > 1 ? "-" + (i + 1) : ""}.tga`;
      writeFileSync(path.join(media, file), tga(t.field));
      written.add(file);
      log(`${file}: ${t.field.w} x ${t.field.h} (Inhalt ${l.cw} px breit)`);
    });
  }
  writeFileSync(path.join(root, "addon", "Lucid", "modules", "Zone", "Ornaments.lua"), ornamentsLua(entries, builtin));
  // veraltete Stufen-Dateien der Vorlagen-Stile entfernen (nur zone-<rezept>-*.tga in Media)
  const names = new Set([...recipes.map((r) => r.name), "swirl", "filigree"]);
  for (const f of readdirSync(media)) {
    const m = /^zone-([a-z0-9]+)(?:-left|-right)?-[a-z](-\d+)?\.tga$/.exec(f);
    if (m && names.has(m[1]) && !written.has(f)) { unlinkSync(path.join(media, f)); log("entfernt: " + f); }
  }
  log(`Ornaments.lua: ${entries.length} Stil(e)`);
}

const args = process.argv.slice(2);
const opt = (name) => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : undefined; };

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (args.includes("--templates")) {
    runTemplates();
  } else if (opt("--from")) {
    const from = opt("--from"), name = path.basename(opt("--out") || "zone-swirl.tga");
    if (!/^[A-Za-z0-9_.-]+\.tga$/.test(name)) throw new Error("--out: nur ein Dateiname mit .tga (landet in addon/Lucid/Media)");
    const num = (k, d) => (opt(k) !== undefined ? Number(opt(k)) : d);
    const res = convertToTga(decodePng(readFileSync(from)), { side: opt("--side") || "right", rows: opt("--rows") || "full",
      maxW: num("--max", 1024), floor: num("--floor", 0.03), gamma: num("--gamma", 1), bold: num("--bold", 0) });
    writeFileSync(path.join(MEDIA, name), res.buf);
    console.log(`${name}: ${res.field.w} x ${res.field.h}, ${res.buf.length} B`);
    console.log(`Card.STYLES: aspect = ${res.aspect}, midY = ${res.midY.toFixed(4)}, fill = ${res.fill.toFixed(4)}`);
  } else {
    // Lichtband und Glanz; Geschwungen/Filigran entstehen als Stufen mit --templates
    for (const [name, make] of [["zone-band", bandField], ["zone-glow", glowField]]) {
      const f = make();
      const buf = tga(f);
      writeFileSync(path.join(MEDIA, name + ".tga"), buf);
      console.log(`${name}.tga ${buf.length} B`);
    }
  }
}
