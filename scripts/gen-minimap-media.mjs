// Erzeugt die Texturen der Minimap (B6) als unkomprimierte 32-bit-TGA.
//
// Masken (Standard, ohne Argument): weiss, Form nur im Alphakanal
//   minimap-square.tga        256 x 256   volles Quadrat
//   minimap-rect-<b>x<h>.tga  256 x 256   zentriertes Rechteck im Seitenverhaeltnis b:h (Quadrat bleibt der Frame,
//                                         die Maske schneidet ab); Rand mit Flaechendeckung geglaettet
//
// Rahmen (--frames): aus den Vorlagen docs/minimap-src/*.jpg nach docs/minimap-src/frames.json
//   1. JPG -> PNG (Headless-Chrome wie gen-zone-media.mjs, Zwischenablage im Temp-Ordner), Chroma-Key (Gruen bzw.
//      Magenta) -> Alpha, Farbsaum entfernt
//   2. Rahmenband ausmessen (aeussere/innere Kante auf Zeile/Spalte 30 %, weg von Ecken und Mittelschmuck)
//   3. Neun-Teile-Zuschnitt: 4 Ecken (mit Ueberstand ueber das Band) + 4 gleichfoermige Kantenstreifen
//   4. Stufen nach physischen Pixeln (Eckgroesse c = 32 / 64 / 128 px, nie ueber die Vorlage hinaus), Box-Filter auf
//      vormultiplizierten Farben; je Stufe zwei Dateien unter 1 MiB:
//        minimap-<stil>-<c>-c.tga  die vier Ecken (2 x 2)
//        minimap-<stil>-<c>-e.tga  die vier Kantenstreifen uebereinander (links/rechts quer gestellt = transponiert)
//        minimap-<stil>-<c>-m.tga  (nur Stile mit "mid" im Rezept) Mittelschmuck der vier Kanten (2 x 2)
//   5. schreibt modules/Minimap/Frames.lua (Zuschnitt-Daten, Stile, Beschriftung)
// Aufruf: node scripts/gen-minimap-media.mjs [--frames] [--all]. Deterministisch; die erzeugten Dateien liegen im Repo.
import { existsSync, mkdirSync, readFileSync, readdirSync, unlinkSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { decodePng, jpgToPng, tga } from "./gen-zone-media.mjs";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const MEDIA = path.join(ROOT, "addon", "Lucid", "Media");
const SRC = path.join(ROOT, "docs", "minimap-src");
const LIMIT = 1024 * 1024;
export const SIZE = 256;
/** Seitenverhaeltnisse wie minimap.rectRatio (Breite:Hoehe) */
export const RATIOS = [[3, 2], [4, 3], [16, 9], [2, 3], [3, 4]];

// Masken ------------------------------------------------------------------------------------------
/** Anteil [0..1] der Strecke [lo, hi], der im Intervall [a, b] liegt (Pixelflaeche) */
const cover = (lo, hi, a, b) => Math.max(0, Math.min(hi, b) - Math.max(lo, a)) / (hi - lo);

/** Maske fuer ein Rechteck der Breite wf und Hoehe hf (Anteile 0..1 der Frame-Seite), zentriert */
export function maskField(wf, hf, size = SIZE) {
  const a = new Float64Array(size * size);
  const x0 = (size * (1 - wf)) / 2, x1 = size - x0, y0 = (size * (1 - hf)) / 2, y1 = size - y0;
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) a[y * size + x] = cover(x, x + 1, x0, x1) * cover(y, y + 1, y0, y1);
  }
  return { w: size, h: size, a };
}

/** Anteile (Breite, Hoehe) eines b:h-Rechtecks in einem Quadrat: die lange Seite fuellt das Quadrat */
export const ratioFractions = (b, h) => (b >= h ? [1, h / b] : [b / h, 1]);

export const maskFiles = () => [
  { file: "minimap-square.tga", field: maskField(1, 1) },
  ...RATIOS.map(([b, h]) => ({ file: `minimap-rect-${b}x${h}.tga`, field: maskField(...ratioFractions(b, h)) })),
];

// Rahmen ------------------------------------------------------------------------------------------
const smooth = (x, a, b) => {
  const t = Math.min(1, Math.max(0, (x - a) / (b - a)));
  return t * t * (3 - 2 * t);
};
const pot = (n) => 2 ** Math.ceil(Math.log2(Math.max(1, n)));

/** RGBA-TGA (Typ 2, 32 bit, Ursprung oben links, BGRA) */
export function tgaRgba({ w, h, rgba }) {
  const head = Buffer.alloc(18);
  head[2] = 2;
  head.writeUInt16LE(w, 12);
  head.writeUInt16LE(h, 14);
  head[16] = 32;
  head[17] = 0x28;
  const px = Buffer.alloc(w * h * 4);
  for (let i = 0; i < w * h; i++) {
    px[i * 4] = rgba[i * 4 + 2];
    px[i * 4 + 1] = rgba[i * 4 + 1];
    px[i * 4 + 2] = rgba[i * 4];
    px[i * 4 + 3] = rgba[i * 4 + 3];
  }
  return Buffer.concat([head, px]);
}

/**
 * Chroma-Key: key = "green" | "magenta". Alpha aus der Schluesselfarb-Dominanz (Gruen: G ueber max(R, B); Magenta:
 * min(R, B) ueber G), Farbsaum an Randpixeln entfernt (die Dominanz wird abgezogen); volltransparent => schwarz.
 */
export function chromaKey({ w, h, rgba }, key) {
  const out = new Uint8Array(w * h * 4);
  for (let i = 0; i < w * h; i++) {
    let r = rgba[i * 4], g = rgba[i * 4 + 1], b = rgba[i * 4 + 2];
    const k = key === "green" ? g - Math.max(r, b) : Math.min(r, b) - g;
    const a = 1 - smooth(k, 40, 150);
    if (k > 0) {
      if (key === "green") g -= k;
      else { r -= k; b -= k; }
    }
    if (a <= 0) { r = g = b = 0; }
    out[i * 4] = Math.max(0, r);
    out[i * 4 + 1] = Math.max(0, g);
    out[i * 4 + 2] = Math.max(0, b);
    out[i * 4 + 3] = Math.round(a * 255);
  }
  return { w, h, rgba: out };
}

/** Rahmenband ausmessen: aeussere Kanten (oL, oT, oR1, oB1; exklusive Obergrenze) und innere Kanten (iL, iT, iR, iB) */
export function measureFrame({ w, h, rgba }) {
  const op = (x, y) => rgba[(y * w + x) * 4 + 3] > 127;
  const r1 = Math.round(0.3 * h), c1 = Math.round(0.3 * w), cx = w >> 1, cy = h >> 1;
  let oL = 0, oR = w - 1, oT = 0, oB = h - 1;
  while (oL < w && !op(oL, r1)) oL++;
  while (oR >= 0 && !op(oR, r1)) oR--;
  while (oT < h && !op(c1, oT)) oT++;
  while (oB >= 0 && !op(c1, oB)) oB--;
  let iL = cx, iR = cx, iT = cy, iB = cy;
  while (iL > 0 && !op(iL, r1)) iL--;
  while (iR < w - 1 && !op(iR, r1)) iR++;
  while (iT > 0 && !op(c1, iT)) iT--;
  while (iB < h - 1 && !op(c1, iB)) iB++;
  const m = { oL, oT, oR: oR + 1, oB: oB + 1, iL: iL + 1, iT: iT + 1, iR, iB };
  if (!(m.oL < m.iL && m.iL < m.iR && m.iR < m.oR && m.oT < m.iT && m.iT < m.iB && m.iB < m.oB)) {
    throw new Error("Rahmenband nicht erkannt: " + JSON.stringify(m));
  }
  return m;
}

/** Alpha-Bounding-Box im Fenster [x0, x1) x [y0, y1) */
function alphaBox({ w, h, rgba }, x0, y0, x1, y1) {
  let minX = x1, minY = y1, maxX = x0 - 1, maxY = y0 - 1;
  for (let y = Math.max(0, y0); y < Math.min(h, y1); y++) {
    for (let x = Math.max(0, x0); x < Math.min(w, x1); x++) {
      if (rgba[(y * w + x) * 4 + 3] > 127) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  return { minX, minY, maxX: maxX + 1, maxY: maxY + 1 };
}

/** Box-Filter auf vormultiplizierten Farben: Ausschnitt (x0, y0, cw, ch) -> ow x oh */
export function resample(img, x0, y0, cw, ch, ow, oh) {
  const { w, h, rgba } = img;
  const out = new Uint8Array(ow * oh * 4), sx = cw / ow, sy = ch / oh;
  for (let oy = 0; oy < oh; oy++) {
    const ya = y0 + oy * sy, yb = ya + sy;
    for (let ox = 0; ox < ow; ox++) {
      const xa = x0 + ox * sx, xb = xa + sx;
      let r = 0, g = 0, b = 0, a = 0, wt = 0;
      for (let y = Math.floor(ya); y < Math.ceil(yb); y++) {
        const wy = Math.min(yb, y + 1) - Math.max(ya, y);
        for (let x = Math.floor(xa); x < Math.ceil(xb); x++) {
          const wgt = wy * (Math.min(xb, x + 1) - Math.max(xa, x));
          wt += wgt;
          if (x < 0 || y < 0 || x >= w || y >= h) continue; // ausserhalb: transparent
          const o = (y * w + x) * 4, al = (rgba[o + 3] / 255) * wgt;
          r += rgba[o] * al; g += rgba[o + 1] * al; b += rgba[o + 2] * al; a += al;
        }
      }
      const p = (oy * ow + ox) * 4;
      if (a > 0) {
        out[p] = Math.round(r / a); out[p + 1] = Math.round(g / a); out[p + 2] = Math.round(b / a);
        out[p + 3] = Math.round((a / wt) * 255);
      }
    }
  }
  return { w: ow, h: oh, rgba: out };
}

function blit(dst, src, dx, dy) {
  for (let y = 0; y < src.h; y++) {
    for (let x = 0; x < src.w; x++) {
      const s = (y * src.w + x) * 4, d = ((dy + y) * dst.w + dx + x) * 4;
      for (let k = 0; k < 4; k++) dst.rgba[d + k] = src.rgba[s + k];
    }
  }
}

const transpose = (f) => {
  const out = new Uint8Array(f.w * f.h * 4);
  for (let y = 0; y < f.h; y++) {
    for (let x = 0; x < f.w; x++) for (let k = 0; k < 4; k++) out[(x * f.h + y) * 4 + k] = f.rgba[(y * f.w + x) * 4 + k];
  }
  return { w: f.h, h: f.w, rgba: out };
};
const blank = (w, h) => ({ w, h, rgba: new Uint8Array(w * h * 4) });
const fits = (w, h) => w * h * 4 + 18 < LIMIT;

/** Zuschnitt eines Stils in Vorlagen-Pixeln: Band, Ecken (mit Ueberstand), Kantenstreifen */
export function cutFrame(img, recipe) {
  const m = measureFrame(img);
  const S = m.oR - m.oL, Sh = m.oB - m.oT;
  const cs = Math.round(recipe.corner * S);
  const pad = Math.round(0.08 * S);
  const tH = Math.round(((m.iT - m.oT) + (m.oB - m.iB)) / 2);
  const tV = Math.round(((m.iL - m.oL) + (m.oR - m.iR)) / 2);
  const box = (x0, y0, x1, y1) => alphaBox(img, x0, y0, x1, y1);
  const tl = box(m.oL - pad, m.oT - pad, m.oL + cs, m.oT + cs);
  const tr = box(m.oR - cs, m.oT - pad, m.oR + pad, m.oT + cs);
  const bl = box(m.oL - pad, m.oB - cs, m.oL + cs, m.oB + pad);
  const br = box(m.oR - cs, m.oB - cs, m.oR + pad, m.oB + pad);
  const corners = {
    TL: { bx: Math.max(0, m.oL - tl.minX), by: Math.max(0, m.oT - tl.minY) },
    TR: { bx: Math.max(0, tr.maxX - m.oR), by: Math.max(0, m.oT - tr.minY) },
    BL: { bx: Math.max(0, m.oL - bl.minX), by: Math.max(0, bl.maxY - m.oB) },
    BR: { bx: Math.max(0, br.maxX - m.oR), by: Math.max(0, br.maxY - m.oB) },
  };
  const rect = {
    TL: (c) => [m.oL - c.bx, m.oT - c.by, cs + c.bx, cs + c.by],
    TR: (c) => [m.oR - cs, m.oT - c.by, cs + c.bx, cs + c.by],
    BL: (c) => [m.oL - c.bx, m.oB - cs, cs + c.bx, cs + c.by],
    BR: (c) => [m.oR - cs, m.oB - cs, cs + c.bx, cs + c.by],
  };
  for (const k of Object.keys(corners)) {
    const [x, y, cw, ch] = rect[k](corners[k]);
    Object.assign(corners[k], { x, y, w: cw, h: ch });
  }
  const [e0, e1] = recipe.edge;
  const ex0 = m.oL + Math.round(e0 * S), ex1 = m.oL + Math.round(e1 * S);
  const ey0 = m.oT + Math.round(e0 * Sh), ey1 = m.oT + Math.round(e1 * Sh);
  const strips = {
    top: { x: ex0, y: m.oT, w: ex1 - ex0, h: tH },
    bottom: { x: ex0, y: m.oB - tH, w: ex1 - ex0, h: tH },
    left: { x: m.oL, y: ey0, w: tV, h: ey1 - ey0 },
    right: { x: m.oR - tV, y: ey0, w: tV, h: ey1 - ey0 },
  };
  // Mittelschmuck der Kanten (Pfeil, Raute ...): je Seite ein eigenes Stueck um die Kantenmitte, ragt ueber das Band hinaus
  let mids = null;
  if (recipe.mid) {
    const half = Math.round(recipe.mid * S);
    const cx = Math.round((m.oL + m.oR) / 2), cy = Math.round((m.oT + m.oB) / 2);
    const need = (b, what) => {
      if (b.maxX <= b.minX || b.maxY <= b.minY) throw new Error("Mittelschmuck nicht gefunden: " + what);
      return b;
    };
    const top = need(box(cx - half, m.oT - pad, cx + half, m.oT + tH + pad), "oben");
    const bot = need(box(cx - half, m.oB - tH - pad, cx + half, m.oB + pad), "unten");
    const lef = need(box(m.oL - pad, cy - half, m.oL + tV + pad, cy + half), "links");
    const rig = need(box(m.oR - tV - pad, cy - half, m.oR + pad, cy + half), "rechts");
    mids = {
      top: { x: cx - half, y: top.minY, w: 2 * half, h: top.maxY - top.minY, out: Math.max(0, m.oT - top.minY), inn: Math.max(0, top.maxY - (m.oT + tH)) },
      bottom: { x: cx - half, y: bot.minY, w: 2 * half, h: bot.maxY - bot.minY, out: Math.max(0, bot.maxY - m.oB), inn: Math.max(0, m.oB - tH - bot.minY) },
      left: { x: lef.minX, y: cy - half, w: lef.maxX - lef.minX, h: 2 * half, out: Math.max(0, m.oL - lef.minX), inn: Math.max(0, lef.maxX - (m.oL + tV)) },
      right: { x: rig.minX, y: cy - half, w: rig.maxX - rig.minX, h: 2 * half, out: Math.max(0, rig.maxX - m.oR), inn: Math.max(0, m.oR - tV - rig.minX) },
    };
  }
  return { m, S, cs, tH, tV, corners, strips, mids };
}

/** Atlas einer Stufe (2 x 2 Zellen) aus vier Stuecken (Ecken oder Kantenmitten) bei Eckgroesse c; null, wenn er nicht unter 1 MiB passt */
function gridAtlas(img, cut, c, items, order) {
  const s = c / cut.cs, parts = {};
  let cw = 1, ch = 1;
  for (const k of order) {
    const d = items[k];
    const ow = Math.max(1, Math.round(d.w * s)), oh = Math.max(1, Math.round(d.h * s));
    parts[k] = { ow, oh, tex: resample(img, d.x, d.y, d.w, d.h, ow, oh) };
    cw = Math.max(cw, ow);
    ch = Math.max(ch, oh);
  }
  const aw = pot(2 * cw + 6), ah = pot(2 * ch + 6);
  if (!fits(aw, ah)) return null;
  const atlas = blank(aw, ah), rects = {};
  order.forEach((k, n) => {
    const i = n % 2, j = Math.floor(n / 2);
    const x = 2 + i * (cw + 2), y = 2 + j * (ch + 2);
    blit(atlas, parts[k].tex, x, y);
    rects[k] = { x, y, w: parts[k].ow, h: parts[k].oh };
  });
  return { atlas, rects };
}

const cornerAtlas = (img, cut, c) => gridAtlas(img, cut, c, cut.corners, ["TL", "TR", "BL", "BR"]);
const midAtlas = (img, cut, c) => (cut.mids ? gridAtlas(img, cut, c, cut.mids, ["top", "bottom", "left", "right"]) : undefined);

/** Kantenstreifen-Atlas einer Stufe: oben, unten, links, rechts uebereinander (links/rechts transponiert) */
function stripAtlas(img, cut, c) {
  const s = c / cut.cs;
  const tHs = Math.max(1, Math.round(cut.tH * s)), tVs = Math.max(1, Math.round(cut.tV * s));
  const lenH = cut.strips.top.w * s, lenV = cut.strips.left.h * s;
  for (const cap of [512, 256, 128]) {
    const LH = Math.max(1, Math.min(cap, Math.round(lenH))), LV = Math.max(1, Math.min(cap, Math.round(lenV)));
    const aw = pot(Math.max(LH, LV) + 4), ah = pot(2 * tHs + 2 * tVs + 10);
    if (!fits(aw, ah)) continue;
    const atlas = blank(aw, ah), rects = {};
    let y = 2;
    for (const [k, vertical] of [["top", false], ["bottom", false], ["left", true], ["right", true]]) {
      const d = cut.strips[k];
      let tex, rw, rh;
      if (!vertical) {
        tex = resample(img, d.x, d.y, d.w, d.h, LH, tHs);
        rw = LH; rh = tHs;
      } else {
        tex = transpose(resample(img, d.x, d.y, d.w, d.h, tVs, LV));
        rw = LV; rh = tVs;
      }
      blit(atlas, tex, 2, y);
      rects[k] = { x: 2, y, w: rw, h: rh };
      y += rh + 2;
    }
    return { atlas, rects };
  }
  return null;
}

export const LEVELS = [32, 64, 128];

/** Alle Stufen eines Stils: [{ c, corners: { atlas, rects }, strips: { atlas, rects } }] (Stufen nie ueber die Vorlage) */
export function buildFrameLevels(img, cut) {
  const out = [];
  for (const want of LEVELS) {
    let c = Math.min(want, cut.cs);
    let corners = null, strips = null, mids = null;
    while (c >= 8 && !(corners && strips && (mids || !cut.mids))) {
      corners = cornerAtlas(img, cut, c);
      strips = stripAtlas(img, cut, c);
      mids = midAtlas(img, cut, c);
      if (!(corners && strips && (mids || !cut.mids))) c = Math.floor(c * 0.9);
    }
    if (!corners || !strips || (cut.mids && !mids)) throw new Error("Stufe passt nicht unter 1 MiB");
    if (!out.some((l) => l.c === c)) out.push({ c, corners, strips, mids });
  }
  return out;
}

const luaNum = (v) => {
  if (!Number.isFinite(v)) throw new Error("keine endliche Zahl");
  return String(Math.round(v * 10000) / 10000);
};
const luaStr = (s) => JSON.stringify(s);
const luaRect = (r) => `{ x = ${r.x}, y = ${r.y}, w = ${r.w}, h = ${r.h} }`;

/** Inhalt von modules/Minimap/Frames.lua */
export function framesLua(entries) {
  const lines = [
    "-- ERZEUGT von scripts/gen-minimap-media.mjs --frames aus docs/minimap-src/frames.json. Nicht von Hand aendern.",
    "-- Minimap-Rahmen (B6): Zuschnitt-Daten je Stil und Stufe; Texturen in Media/minimap-<stil>-<c>-c|e.tga.",
    "-- Je Stil: units = Eckgroesse in UI-Einheiten bei 100 %, cs = Eckgroesse in Vorlagenpixeln, tH/tV = Bandstaerke oben/unten",
    "-- bzw. links/rechts in Vorlagenpixeln. mids (optional): Mittelschmuck je Kante (out/inn = Ueberstand nach aussen/innen). corners.<TL|TR|BL|BR>: bx/by = Ueberstand ueber das Band, sw/sh = Groesse in",
    "-- Vorlagenpixeln, r = Rechteck im Atlas. strips.<top|bottom|left|right>: Rechteck im Atlas (links/rechts transponiert).",
    "local _, ns = ...",
    "local F = { order = {}, styles = {} }",
    "ns.MinimapFrames = F",
    "local function add(name, style, deDE, enUS)",
    "    F.order[#F.order + 1] = name",
    "    F.styles[name] = style",
    "    local loc = ns.Locales or {}",
    "    if loc.deDE then loc.deDE[\"MINIMAP_BORDER_\" .. name] = deDE end",
    "    if loc.enUS then loc.enUS[\"MINIMAP_BORDER_\" .. name] = enUS end",
    "end",
  ];
  for (const e of entries) {
    const lv = e.levels.map((l) => {
      const cs = ["TL", "TR", "BL", "BR"].map((k) => {
        const d = e.cut.corners[k], r = l.corners.rects[k];
        return `${k} = { bx = ${d.bx}, by = ${d.by}, sw = ${d.w}, sh = ${d.h}, r = ${luaRect(r)} }`;
      }).join(", ");
      const st = ["top", "bottom", "left", "right"].map((k) => `${k} = ${luaRect(l.strips.rects[k])}`).join(", ");
      let mid = "";
      if (l.mids) {
        const ms = ["top", "bottom", "left", "right"].map((k) => {
          const d = e.cut.mids[k], r = l.mids.rects[k];
          return `${k} = { out = ${d.out}, inn = ${d.inn}, sw = ${d.w}, sh = ${d.h}, r = ${luaRect(r)} }`;
        }).join(", ");
        mid = `, mids = { file = ${luaStr(`minimap-${e.name}-${l.c}-m`)}, w = ${l.mids.atlas.w}, h = ${l.mids.atlas.h}, ${ms} }`;
      }
      return `{ c = ${l.c}, corners = { file = ${luaStr(`minimap-${e.name}-${l.c}-c`)}, w = ${l.corners.atlas.w}, h = ${l.corners.atlas.h}, ${cs} }, ` +
        `strips = { file = ${luaStr(`minimap-${e.name}-${l.c}-e`)}, w = ${l.strips.atlas.w}, h = ${l.strips.atlas.h}, ${st} }${mid} }`;
    }).join(", ");
    lines.push(`add(${luaStr(e.name)}, { units = ${luaNum(e.units)}, cs = ${e.cut.cs}, tH = ${e.cut.tH}, tV = ${e.cut.tV}, levels = { ${lv} } },`);
    lines.push(`    ${luaStr(e.label.deDE)}, ${luaStr(e.label.enUS)})`);
  }
  return lines.join("\n") + "\n";
}

function runFrames() {
  const recipes = JSON.parse(readFileSync(path.join(SRC, "frames.json"), "utf8")).frames;
  const cache = path.join(os.tmpdir(), "lucid-minimap-src");
  mkdirSync(cache, { recursive: true });
  const entries = [], written = new Set();
  let total = 0;
  for (const r of recipes) {
    if (!/^[a-z0-9]{2,16}$/.test(r.name)) throw new Error("Stilname ungueltig: " + r.name);
    const jpg = path.join(SRC, r.src + ".jpg"), png = path.join(cache, r.src + ".png");
    if (!existsSync(png)) jpgToPng(jpg, png);
    const keyed = chromaKey(decodePng(readFileSync(png)), r.key);
    const cut = cutFrame(keyed, r);
    const levels = buildFrameLevels(keyed, cut);
    for (const l of levels) {
      for (const [suffix, part] of [["c", l.corners], ["e", l.strips], ["m", l.mids]]) {
        if (!part) continue;
        const file = `minimap-${r.name}-${l.c}-${suffix}.tga`, buf = tgaRgba(part.atlas);
        if (buf.length >= LIMIT) throw new Error(file + " >= 1 MiB");
        writeFileSync(path.join(MEDIA, file), buf);
        written.add(file);
        total += buf.length;
      }
    }
    console.log(`${r.name}: Band ${cut.tH}/${cut.tV} px, Ecke ${cut.cs} px, Stufen ${levels.map((l) => l.c).join("/")}`);
    entries.push({ ...r, cut, levels });
  }
  writeFileSync(path.join(ROOT, "addon", "Lucid", "modules", "Minimap", "Frames.lua"), framesLua(entries));
  const names = new Set(recipes.map((r) => r.name));
  for (const f of readdirSync(MEDIA)) {
    const m = /^minimap-([a-z0-9]+)-\d+-[cem]\.tga$/.exec(f);
    if (m && !written.has(f)) { unlinkSync(path.join(MEDIA, f)); console.log("entfernt: " + f); }
    else if (m && !names.has(m[1])) unlinkSync(path.join(MEDIA, f));
  }
  console.log(`Frames.lua: ${entries.length} Stil(e), ${written.size} Dateien, ${(total / 1048576).toFixed(2)} MiB`);
}

function runMasks() {
  for (const { file, field } of maskFiles()) {
    const buf = tga(field);
    if (buf.length >= LIMIT) throw new Error(file + " >= 1 MiB");
    writeFileSync(path.join(MEDIA, file), buf);
    console.log(`${file}: ${field.w} x ${field.h}, ${buf.length} B`);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const args = process.argv.slice(2);
  if (args.includes("--frames") || args.includes("--all")) runFrames();
  if (!args.includes("--frames")) runMasks();
}
