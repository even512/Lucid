// Sichtvorschau des Minimap-Zonen-Ornaments (Delta minimap-ornament) AUS DER LAUFZEIT: Ornament.lua laeuft in der Test-VM
// (tests/fixtures/vm-harness.lua) mit Minimap und GameTimeFrame an den Stellen aus einem Screenshot; gerendert werden genau die
// Aufrufe, die die Texturen dort bekommen haben (SetPoint-Ketten bis zu Minimap/GameTimeFrame, SetSize, SetTexCoord,
// SetScale, SetAlpha). Ergebnis: tests/screens/mmorn-<motiv>[-<suffix>].png (Zoom 2).
//   node scripts/preview-minimap-ornament.mjs <motiv> [--bg spiel3|rot|hell|spiel|ecke] [--size 100] [--offx 0] [--offy 0]
//        [--alpha 100] [--nosun] [--gtf x,y] [--zoom 2] [--out datei.png]
//   node scripts/preview-minimap-ornament.mjs --sheet [Optionen]: Kontaktbogen aller freigegebenen Motive (approved.json) mit
//        identischen Reglerwerten, zeilenweise in der Reihenfolge von approved.json -> tests/screens/mmorn-kontaktbogen.png
// --bg spiel3: Spiel-Screenshot tim-spiel-3.png (435 x 401; Kartenrechteck x 33-391, y 81-350; Mond (308, 56), r 25).
// --bg spiel: Spiel-Screenshot docs/minimap-ornament-src/tim-spiel-2.png (449 x 396; Rahmen aussen x 60-432, y 60-338,
//   Kartenrechteck x 66-426, y 66-332; Mond (343, 42), Radius 26); --bg ecke: tim-minimap-ecke.png (Referenz-Geometrie).
// --nosun: ohne GameTimeFrame (Rueckfall Kartenecke); --gtf x,y: GameTimeFrame-Mitte an anderer Stelle (Bildpixel).
// Deckkraft standardmaessig 100 % (Vergleich mit der Referenz); --alpha 85 entspricht dem Profilstandard.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import zlib from "node:zlib";
import path from "node:path";
import { decodePng } from "./gen-zone-media.mjs";
import { createVm, ROOT } from "../tests/helpers/wow-vm.mjs";

/** Hintergruende: Bild, Kartenrechteck (sichtbar, Bildpixel), Sonnenmitte */
export const BACKGROUNDS = {
  spiel3: { file: "tim-spiel-3.png", map: { x0: 33, y0: 81, x1: 391, y1: 350 }, sun: { x: 308, y: 56, r: 25 } },
  // wie spiel3, ausserhalb der Karte roter Fels aus Rotkammgebirge-Screenshot (Kontrastprobe Gold auf Rot)
  // wie spiel3, ausserhalb der Karte heller Himmel aus Screenshot (Probe: Schattenrand darf hier nicht als Klecks wirken)
  hell: { file: "tim-spiel-hell.png", map: { x0: 33, y0: 81, x1: 391, y1: 350 }, sun: { x: 308, y: 56, r: 25 } },
  rot: { file: "tim-spiel-rot.png", map: { x0: 33, y0: 81, x1: 391, y1: 350 }, sun: { x: 308, y: 56, r: 25 } },
  spiel: { file: "tim-spiel-2.png", map: { x0: 66, y0: 66, x1: 426, y1: 332 }, sun: { x: 343, y: 42, r: 26 } },
  ecke: { file: "tim-minimap-ecke.png", map: { x0: 146, y0: 102, x1: 500, y1: 367 }, sun: { x: 422, y: 81, r: 31 } },
};

/**
 * Laufzeit in der VM: liefert { list: [{ file, tc, rect: { l, t, w, h } (Bildpixel) }], alpha, state }.
 * bg: Eintrag aus BACKGROUNDS mit Bildhoehe imgH; opts: size, offx, offy, alpha, sun (false = kein GameTimeFrame), gtf ({x, y}).
 */
export function runtimeLayout(motif, bg, imgH, { size = 100, offx = 0, offy = 0, alpha = 100, sun = true, gtf = null } = {}) {
  const S = bg.map.x1 - bg.map.x0; // 4:3: Breite des sichtbaren Rechtecks = Seitenlaenge des quadratischen Minimap-Frames
  const top = bg.map.y0 - (S * (1 - 3 / 4)) / 2;
  let ids = createVm().lua(`return NS.ZoneMotifs.ids[${JSON.stringify(motif)}]`);
  // Minimap-eigene Motive (O.MapOverride, z. B. legion im Teufelswald): Karten-ID aus dem Override
  if (!Array.isArray(ids) || ids.length === 0) {
    const ov = createVm().lua(`for id, m in pairs(NS.Minimap.Ornament.MapOverride) do if m == ${JSON.stringify(motif)} then return id end end`);
    if (typeof ov === "number") ids = [ov];
  }
  // Motive ohne eigene Karte (nur ueber den Zonennamen zugeordnet, z. B. dalaran): Name statt Karten-ID
  const byName = !Array.isArray(ids) || ids.length === 0
    ? createVm().lua(`for n, m in pairs(NS.ZoneMotifs.byName) do if m == ${JSON.stringify(motif)} then return n end end`) : null;
  if (!byName && (!Array.isArray(ids) || ids.length === 0)) throw new Error("Motiv ohne Zonen-ID: " + motif);
  const mapId = byName ? 1 : ids[0];
  const g = gtf || bg.sun;
  const vm = createVm({ setup: `H.blizzardUi({}, {})
Minimap.SetMaskTexture = function() end
Minimap.SetHitRectInsets = function() end
Minimap.GetWidth = function() return ${S} end
Minimap.GetRect = function() return ${bg.map.x1 - S}, ${imgH - (top + S)}, ${S}, ${S} end
Minimap.GetEffectiveScale = function() return 1 end
H.w.mapId = ${mapId}
H.maps[${mapId}] = { mapType = 3 }${byName ? `
GetZoneText = function() return ${JSON.stringify(byName)} end` : ""}
${sun ? `local g = CreateFrame("Frame", "GameTimeFrame", MinimapCluster)
g.GetCenter = function() return ${g.x}, ${imgH - g.y} end
g.GetEffectiveScale = function() return 1 end
g.w, g.h = ${2 * bg.sun.r}, ${2 * bg.sun.r}` : ""}` }).boot();
  vm.exec(`NS.Minimap.Set({ shape = "rect", rectRatio = "4:3", ornament = true, ornamentSize = ${size}, ornamentOffsetX = ${offx}, ornamentOffsetY = ${offy}, ornamentAlpha = ${alpha} })`);
  const state = vm.lua("return NS.Minimap.Ornament.State()");
  if (!state.shown) throw new Error("Ornament nicht angezeigt: " + JSON.stringify(state));
  // Ankerketten in der VM aufloesen: Rechteck jeder Region in Bildpixeln (y nach unten)
  const list = vm.lua(`
local fixed = {}
fixed[Minimap] = { l = ${bg.map.x1 - S}, t = ${top}, w = ${S}, h = ${S} }
if GameTimeFrame then fixed[GameTimeFrame] = { l = ${g.x - bg.sun.r}, t = ${g.y - bg.sun.r}, w = ${2 * bg.sun.r}, h = ${2 * bg.sun.r} } end
local function eff(o)
  if fixed[o] then return 1 end
  local s = (o.type ~= "Texture" and o.scale) or 1
  return s * (o.parent and eff(o.parent) or 1)
end
local function pos(r, name)
  local x = name:find("LEFT") and r.l or (name:find("RIGHT") and r.l + r.w or r.l + r.w / 2)
  local y = name:find("TOP") and r.t or (name:find("BOTTOM") and r.t + r.h or r.t + r.h / 2)
  return x, y
end
local resolve
resolve = function(o)
  if fixed[o] then return fixed[o] end
  local p = assert(o.points and o.points[1], "Region ohne Anker")
  local e = eff(o)
  local ax, ay = pos(resolve(p[2]), p[3])
  local w, h = (o.w or 0) * e, (o.h or 0) * e
  local x, y = ax + (p[4] or 0) * e, ay - (p[5] or 0) * e
  local r = { w = w, h = h }
  r.l = p[1]:find("LEFT") and x or (p[1]:find("RIGHT") and x - w or x - w / 2)
  r.t = p[1]:find("TOP") and y or (p[1]:find("BOTTOM") and y - h or y - h / 2)
  return r
end
local f, tex = NS.Minimap.Ornament.Parts()
local out = {}
for _, key in ipairs({ "top", "side", "ring" }) do
  local t = tex[key]
  if t and t.shown then out[#out + 1] = { file = t.texture, tc = t.texCoord, rect = resolve(t) } end
end
return { list = out, alpha = f.alpha, center = resolve(f) }`);
  return { ...list, state };
}

// Bilder ---------------------------------------------------------------------------------------------
function readTga(file) {
  const b = readFileSync(file), w = b.readUInt16LE(12), h = b.readUInt16LE(14);
  if (b[16] !== 32 || (b[17] & 0x20) === 0) throw new Error("TGA nicht 32 bit oben links: " + file);
  const rgba = new Uint8Array(w * h * 4);
  for (let i = 0; i < w * h; i++) {
    const s = 18 + i * 4;
    rgba[i * 4] = b[s + 2]; rgba[i * 4 + 1] = b[s + 1]; rgba[i * 4 + 2] = b[s]; rgba[i * 4 + 3] = b[s + 3];
  }
  return { w, h, rgba };
}
/** bilinear, vormultipliziert, Rand transparent; u, v in Texeln */
function sample(img, u, v) {
  const x = u - 0.5, y = v - 0.5, x0 = Math.floor(x), y0 = Math.floor(y), fx = x - x0, fy = y - y0;
  const acc = [0, 0, 0, 0];
  for (const [dx, dy, wt] of [[0, 0, (1 - fx) * (1 - fy)], [1, 0, fx * (1 - fy)], [0, 1, (1 - fx) * fy], [1, 1, fx * fy]]) {
    const px = x0 + dx, py = y0 + dy;
    if (px < 0 || py < 0 || px >= img.w || py >= img.h || wt === 0) continue;
    const o = (py * img.w + px) * 4, a = img.rgba[o + 3] / 255;
    acc[0] += img.rgba[o] * a * wt; acc[1] += img.rgba[o + 1] * a * wt; acc[2] += img.rgba[o + 2] * a * wt; acc[3] += a * wt;
  }
  return acc;
}
function chunk(type, data) {
  const t = Buffer.from(type), len = Buffer.alloc(4), crc = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  crc.writeUInt32BE(zlib.crc32(Buffer.concat([t, data])) >>> 0);
  return Buffer.concat([len, t, data, crc]);
}
function writePng(file, { w, h, rgba }) {
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) Buffer.from(rgba.buffer, rgba.byteOffset + y * w * 4, w * 4).copy(raw, y * (w * 4 + 1) + 1);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 6;
  writeFileSync(file, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr),
    chunk("IDAT", zlib.deflateSync(raw, { level: 6 })), chunk("IEND", Buffer.alloc(0))]));
}

/** Rendern: Hintergrund (Zoom Z) + Texturen nach Laufzeit-Rechtecken und Texturkoordinaten (UL, LL, UR, LR bei 8 Werten) */
export function render(bgImg, layout, Z) {
  const W = Math.round(bgImg.w * Z), H = Math.round(bgImg.h * Z), img = new Uint8Array(W * H * 4);
  for (let y = 0; y < H; y++) {
    for (let x = 0; x < W; x++) {
      const s = sample(bgImg, (x + 0.5) / Z, (y + 0.5) / Z), o = (y * W + x) * 4, a = Math.max(s[3], 1e-6);
      img[o] = s[0] / a; img[o + 1] = s[1] / a; img[o + 2] = s[2] / a; img[o + 3] = 255;
    }
  }
  const cache = {};
  for (const t of layout.list) {
    const file = path.join(ROOT, "addon", "Lucid", "Media", t.file.split("\\").pop() + ".tga");
    const tex = (cache[file] ??= readTga(file));
    const tc = t.tc.length === 4 ? [t.tc[0], t.tc[2], t.tc[0], t.tc[3], t.tc[1], t.tc[2], t.tc[1], t.tc[3]] : t.tc;
    const { l, t: top, w, h } = t.rect;
    for (let y = Math.max(0, Math.floor(top * Z)); y < Math.min(H, Math.ceil((top + h) * Z)); y++) {
      for (let x = Math.max(0, Math.floor(l * Z)); x < Math.min(W, Math.ceil((l + w) * Z)); x++) {
        const u = ((x + 0.5) / Z - l) / w, v = ((y + 0.5) / Z - top) / h;
        if (u < 0 || u > 1 || v < 0 || v > 1) continue;
        const lerp = (p, q, k) => p + (q - p) * k;
        const tx = lerp(lerp(tc[0], tc[4], u), lerp(tc[2], tc[6], u), v), ty = lerp(lerp(tc[1], tc[5], u), lerp(tc[3], tc[7], u), v);
        const s = sample(tex, tx * tex.w, ty * tex.h), k = layout.alpha, o = (y * W + x) * 4;
        for (let c = 0; c < 3; c++) img[o + c] = Math.round(img[o + c] * (1 - s[3] * k) + s[c] * k);
      }
    }
  }
  return { w: W, h: H, rgba: img };
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === path.resolve(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1"));
if (isMain) {
  const args = process.argv.slice(2);
  const opt = (n, d) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : d; };
  const VALUED = ["--size", "--offx", "--offy", "--alpha", "--zoom", "--out", "--bg", "--gtf"];
  const motif = args.find((a, i) => !a.startsWith("--") && !VALUED.includes(args[i - 1]));
  const sheet = args.includes("--sheet");
  if (!sheet && (!motif || !/^[a-z0-9]{2,16}$/.test(motif))) {
    console.error("Aufruf: node scripts/preview-minimap-ornament.mjs <motiv>|--sheet [--bg spiel3|rot|hell|spiel|ecke] [--size 100] [--offx 0] [--offy 0] [--alpha 100] [--nosun] [--gtf x,y]");
    process.exit(1);
  }
  const bgKey = opt("--bg", "spiel3"), bg = BACKGROUNDS[bgKey];
  if (!bg) throw new Error("--bg: spiel3, rot, hell, spiel oder ecke");
  const bgFile = path.join(ROOT, "docs", "minimap-ornament-src", bg.file);
  if (!existsSync(bgFile)) throw new Error("Hintergrund fehlt: " + bgFile);
  const bgImg = decodePng(readFileSync(bgFile));
  const o = { size: Number(opt("--size", 100)), offx: Number(opt("--offx", 0)), offy: Number(opt("--offy", 0)),
    alpha: Number(opt("--alpha", 100)), sun: !args.includes("--nosun") };
  const gtfArg = opt("--gtf", null);
  if (gtfArg) { const [x, y] = gtfArg.split(","); o.gtf = { x: Number(x), y: Number(y) }; }
  const Z = Number(opt("--zoom", sheet ? 1.5 : 2));
  const names = sheet ? JSON.parse(readFileSync(path.join(ROOT, "docs", "minimap-ornament-src", "approved.json"), "utf8")) : [motif];
  const out = path.resolve(ROOT, opt("--out", sheet ? "tests/screens/mmorn-kontaktbogen.png" : `tests/screens/mmorn-${motif}.png`));
  const tiles = names.map((n) => {
    const layout = runtimeLayout(n, bg, bgImg.h, o);
    const c = layout.center;
    console.log(`${n}: Fixpunkt ${layout.state.anchor}, Ringmitte (${(c.l + c.w / 2).toFixed(1)}, ${(c.t + c.h / 2).toFixed(1)}), ` +
      `K ${layout.state.K.toFixed(1)}, Groesse ${o.size} %, Verschiebung ${o.offx}/${o.offy}`);
    const full = render(bgImg, layout, Z);
    if (!sheet) return full;
    // Kontaktbogen: nur die rechte Haelfte (Leiste ab der Kartenmitte, Ring, Spalte)
    const cx0 = Math.round(((bg.map.x0 + bg.map.x1) / 2) * Z), cw = full.w - cx0, part = new Uint8Array(cw * full.h * 4);
    for (let y = 0; y < full.h; y++) part.set(full.rgba.subarray((y * full.w + cx0) * 4, (y * full.w + full.w) * 4), y * cw * 4);
    return { w: cw, h: full.h, rgba: part };
  });
  const cols = Math.min(tiles.length, sheet ? 4 : 1), rows = Math.ceil(tiles.length / cols), tw = tiles[0].w, th = tiles[0].h, gap = 6;
  const W = cols * tw + (cols - 1) * gap, H = rows * th + (rows - 1) * gap, img = new Uint8Array(W * H * 4).fill(255);
  tiles.forEach((t, i) => {
    const ox = (i % cols) * (tw + gap), oy = Math.floor(i / cols) * (th + gap);
    for (let y = 0; y < th; y++) img.set(t.rgba.subarray(y * tw * 4, (y + 1) * tw * 4), ((oy + y) * W + ox) * 4);
  });
  mkdirSync(path.dirname(out), { recursive: true });
  writePng(out, { w: W, h: H, rgba: img });
  console.log(`${path.relative(ROOT, out)}: ${W} x ${H}` + (sheet ? ` (Reihenfolge: ${names.join(", ")})` : ""));
}
