// Sichtvorschau des Plaketten-Stils aus den erzeugten Texturen (vor dem Spieltest):
//   node scripts/preview-nameplate.mjs [--out docs/nameplate-src/preview-etappe2b.png] [--zoom 3]
//   node scripts/preview-nameplate.mjs --variants [--friz <frizqt__.ttf>] [--zoom 2]   (Varianten auf Screenshot)
//   node scripts/preview-nameplate.mjs --final [--zoom 2]   (Standard aus Style.lua auf Screenshot -> preview-r3.png)
//   node scripts/preview-nameplate.mjs --r5 [--zoom 2]      (Runde 5: Fluessigkeit + Ziel-Schein auf ist-r4.webp, t = 0..3 s -> preview-r5.png)
//   node scripts/preview-nameplate.mjs --r6 [--zoom 2]      (Runde 6: wie r5 auf ist-r5.png, Massstab 1,5 -> preview-r6.png)
//   node scripts/preview-nameplate.mjs --r7 [--zoom 2]      (Runde 7: Namens-Varianten A/B/C auf ist-r6.png -> varianten-r7.png)
//   node scripts/preview-nameplate.mjs --r8 [--zoom 2]      (Runde 8: eingelassener Balken A/B/C auf ist-r7.png -> varianten-r8.png)
// Baut die Plakette wie modules/Nameplates/Style.lua (Schlitz-Geometrie, Balkenhoehe 6, Fuellung 60 %, Glutfarbe,
// Stufen-Plaettchen, Name in Marcellus mit Schatten, Ziel-Glut) in HTML nach und rendert sie per Headless-Chrome mit
// eigenem Temp-Profil ueber einem mittelgrauen, einem hellen und einem dunklen Hintergrund. TGA -> PNG per Node.
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import zlib from "node:zlib";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { createVm, ROOT } from "../tests/helpers/wow-vm.mjs";

const args = process.argv.slice(2);
const opt = (n, d) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : d; };
const out = path.resolve(ROOT, opt("--out", "docs/nameplate-src/preview-etappe2b.png"));
const zoom = Number(opt("--zoom", 3));
const MEDIA = path.join(ROOT, "addon", "Lucid", "Media");
const CHROME = [process.env.CHROME, "C:/Program Files/Google/Chrome/Application/chrome.exe",
  "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe", "/usr/bin/google-chrome", "/usr/bin/chromium"].filter(Boolean);

function chunk(type, data) {
  const t = Buffer.from(type), len = Buffer.alloc(4), crc = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  crc.writeUInt32BE(zlib.crc32(Buffer.concat([t, data])) >>> 0);
  return Buffer.concat([len, t, data, crc]);
}
/** TGA (32 bit, oben links, BGRA) -> PNG als data-URL */
function tgaUrl(name) {
  const b = readFileSync(path.join(MEDIA, name + ".tga")), w = b.readUInt16LE(12), h = b.readUInt16LE(14);
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w; x++) {
      const s = 18 + (y * w + x) * 4, o = y * (w * 4 + 1) + 1 + x * 4;
      raw[o] = b[s + 2]; raw[o + 1] = b[s + 1]; raw[o + 2] = b[s]; raw[o + 3] = b[s + 3];
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 6;
  const png = Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]);
  return "data:image/png;base64," + png.toString("base64");
}

const vm = createVm();
const S = vm.lua("return NS.NameplateStyle");
const G = S.FRAME_GEOMETRY, C = S.COLORS, NC = S.NAME_COLORS, BACK = S.BACK_COLOR, GLOWC = S.GLOW_COLOR;
const tex = { frame: tgaUrl("np-frame"), fill: tgaUrl("np-fill"), level: tgaUrl("np-level"), glow: tgaUrl("np-glow"), liquid: tgaUrl("np-liquid") };
const font = pathToFileURL(path.join(ROOT, "addon", "Lucid", "Fonts", "Marcellus-Regular.ttf")).href;
const rgb = (c, a = 1) => `rgba(${Math.round(c[0] * 255)},${Math.round(c[1] * 255)},${Math.round(c[2] * 255)},${a})`;

/** eine Plakette (Masse in UI-Einheiten wie im Spiel) */
function plate({ name, stance, level, fill = 0.6, target = false, height = 6, width = 120 }) {
  const L = vm.lua(`return NS.NameplateStyle.Layout(${height})`);
  const fw = width + (G.left + G.right) * L.scale, fh = L.total;
  const col = C[stance], nc = NC[stance];
  const glow = target ? `<div style="position:absolute;left:${-L.glowX}px;top:${-L.glowY}px;width:${fw + 2 * L.glowX}px;height:${fh + 2 * L.glowY}px;
      background:url(${tex.glow}) 0 0/100% 100%;mix-blend-mode:screen;opacity:${GLOWC[3]};filter:drop-shadow(0 0 0 ${rgb(GLOWC)})"><div style="width:100%;height:100%;background:${rgb(GLOWC)};-webkit-mask:url(${tex.glow}) 0 0/100% 100%"></div></div>` : "";
  const cap = L.cap, mid = fw - 2 * cap;
  return `<div style="position:relative;width:${fw + L.levelW + 4}px;height:${fh + 16}px;margin:10px 16px">
    <div style="position:absolute;left:${G.left * L.scale}px;top:0;font:${10}px Marcellus;color:${rgb(nc)};text-shadow:1px 1px 0 rgba(0,0,0,.9);white-space:nowrap">${name}</div>
    <div style="position:absolute;left:0;top:14px;width:${fw}px;height:${fh}px">
      ${glow}
      <div style="position:absolute;left:${G.left * L.scale}px;top:${G.top * L.scale}px;width:${width}px;height:${height}px;background:${rgb(BACK, BACK[3])}"></div>
      <div style="position:absolute;left:${G.left * L.scale}px;top:${G.top * L.scale}px;width:${width * fill}px;height:${height}px;background:url(${tex.fill}) 0 0/100% 100%;background-blend-mode:multiply;background-color:${rgb(col)}"></div>
      <div style="position:absolute;left:0;top:0;width:${cap}px;height:${fh}px;background:url(${tex.frame}) 0 0/${(G.w / G.cap) * cap}px ${fh}px"></div>
      <div style="position:absolute;left:${cap}px;top:0;width:${mid}px;height:${fh}px;overflow:hidden"><div style="width:100%;height:100%;background:url(${tex.frame}) ${-(G.cap / (G.w - 2 * G.cap)) * mid}px 0/${(G.w / (G.w - 2 * G.cap)) * mid}px ${fh}px"></div></div>
      <div style="position:absolute;left:${cap + mid}px;top:0;width:${cap}px;height:${fh}px;background:url(${tex.frame}) ${-(G.w / G.cap - 1) * cap}px 0/${(G.w / G.cap) * cap}px ${fh}px"></div>
      <div style="position:absolute;left:${fw + 1}px;top:${(fh - L.levelH) / 2}px;width:${L.levelW}px;height:${L.levelH}px;background:url(${tex.level}) 0 0/100% 100%;
        font:${L.levelFont}px Marcellus;color:${rgb(S.LEVEL_COLOR)};text-align:center;line-height:${L.levelH}px;text-shadow:1px 1px 0 #000">${level}</div>
    </div></div>`;
}


/** HTML per Headless-Chrome (eigenes Temp-Profil) als PNG der Groesse W x H rendern */
function render(html, dest, W, H) {
  const tmp = mkdtempSync(path.join(os.tmpdir(), "lucid-np-preview-"));
  try {
    const file = path.join(tmp, "p.html");
    writeFileSync(file, html);
    const browser = CHROME.find((p) => { try { readFileSync(p); return true; } catch { return false; } });
    if (!browser) throw new Error("kein Chrome/Edge gefunden (Umgebungsvariable CHROME setzen)");
    const r = spawnSync(browser, ["--headless=new", "--disable-gpu", "--allow-file-access-from-files", "--hide-scrollbars",
      `--user-data-dir=${path.join(tmp, "profile")}`, "--force-device-scale-factor=1", `--window-size=${Math.round(W)},${Math.round(H)}`,
      "--virtual-time-budget=3000", `--screenshot=${dest}`, pathToFileURL(file).href], { stdio: "ignore", timeout: 90000 });
    if (r.status !== 0) throw new Error("Rendern fehlgeschlagen");
    console.log("Vorschau: " + dest);
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}

/** RGBA-Bild aus dem Generator -> PNG als data-URL */
function imgUrl({ w, h, rgba }) {
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) Buffer.from(rgba.buffer, rgba.byteOffset + y * w * 4, w * 4).copy(raw, y * (w * 4 + 1) + 1);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 6;
  const png = Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]);
  return "data:image/png;base64," + png.toString("base64");
}

// Varianten (Runde 2): Plakette in echter Spielgroesse auf Screenshot ------------------------------------------
// Massstab aus docs/nameplate-src/ist-etappe2b.png (507 x 379): Blizzards Fuellung dort x 127..399 (272 px), Mitte
// y 64; die alte Plakette (y ~30..80) wird mit dem Gelaende 52 px darunter ueberdeckt. Je Variante Ziel / Nicht-Ziel.
// Friz Quadrata liegt nicht im Repo: --friz <pfad zu frizqt__.ttf> (z. B. aus einem Addon-Ordner, nur gelesen).
// --r4: Runde 4 auf docs/nameplate-src/ist-r3.webp (725 x 562; Fuellung dort x ~294..566, Mitte y ~92): Ziel-Schein
// (BLEND, dunkles Glut-Orange, Alpha oben im Atem-Bereich) und lebendige Fuellung aus np-ember (Standbild).
async function variants(final = false, r4 = false) {
  const r8 = r4 === "r8";
  const r7 = r4 === "r7" || r8;
  const r5 = r4 === "r5" || r4 === "r6" || r7;
  const r6 = r4 === "r6";
  const { fillMattImage } = await import("./gen-nameplate-media.mjs");
  // ist-r5.png (396 x 240, Ausschnitt etwa 1,5-fach): Fuellung x ~32..300, Mitte y ~65 -> Massstab k
  // ist-r6.png (465 x 230, etwa 1,4-fach): Fuellung x ~52..320, Mitte y ~85
  // ist-r7.png (519 x 284, etwa 1,3-fach): Fuellung x ~92..360, Mitte y ~110; im Spiel ist die Fuellung dort so hoch
  // wie der Schlitz (~10 px) -> fillH aus dem Screenshot
  const SHOT = r8
    ? { file: "ist-r7.png", SW: 519, SH: 130, SLIT_X: 92, SLIT_W: 268, MID_Y: 110, k: 1.3, cover: [40, 55, 470, 80, 95], name: "Waldlauerer" }
    : r7
    ? { file: "ist-r6.png", SW: 465, SH: 120, SLIT_X: 52, SLIT_W: 268, MID_Y: 85, k: 1.4, cover: [0, 40, 465, 60, 80], name: "Geschwärzter Basilisk" }
    : r6
    ? { file: "ist-r5.png", SW: 396, SH: 120, SLIT_X: 32, SLIT_W: 268, MID_Y: 66, k: 1.5, cover: [0, 22, 396, 62, 70], name: "Kluftmoosgiftspucker" }
    : r4
    ? { file: r5 ? "ist-r4.webp" : "ist-r3.webp", SW: 725, SH: 180, SLIT_X: 294, SLIT_W: 272, MID_Y: 92, cover: [230, 38, 470, 100, 105], name: "Sturmschnauze" }
    : { file: "ist-etappe2b.png", SW: 507, SH: 140, SLIT_X: 127, SLIT_W: 272, MID_Y: 64, cover: [85, 20, 420, 70, 62], name: "Störrischer Ebenenschreiter" };
  const shot = pathToFileURL(path.join(ROOT, "docs", "nameplate-src", SHOT.file)).href;
  const fonts = {
    Marcellus: font,
    Cinzel: pathToFileURL(path.join(ROOT, "addon", "Lucid", "Fonts", "Cinzel-Regular.ttf")).href,
    Friz: opt("--friz", "") ? pathToFileURL(path.resolve(opt("--friz", ""))).href : null,
  };
  const matt = imgUrl(fillMattImage());
  const { SW, SH, SLIT_X, SLIT_W, MID_Y } = SHOT;
  const EMBER = [0.92, 0.44, 0.17];
  // --final: der Standard aus Style.lua (Wahl R2: Marcellus 13 warm, kleines Plaettchen, Ziel-Linie, Fuellung 5 matt)
  const LY = vm.lua("return NS.NameplateStyle.Layout(5)");
  const FINAL = { id: "R3", label: "Standard (Style.lua): Marcellus 13 px warm, Balken 5 px matt, Rahmen 11 px, kleines Plaettchen, Ziel = warme Linie",
    frameH: LY.total, fillH: 5, font: "Marcellus", size: 13, color: NC.hostile, level: "box", target: "line", levelH: LY.levelH, levelFont: LY.levelFont,
    ember: C.hostile, back: BACK, line: S.TARGET_LINE_COLOR, fillUrl: tex.fill };
  const GL = S.GLOW, LY5 = LY;
  // --r5: Runde 5 (Lebensfluessigkeit in zwei Lagen, atmender Ziel-Schein) als Bildstreifen zu mehreren Zeitpunkten
  const R5 = { ...FINAL, id: "R5", label: "Runde 5", target: "glow4", liquid: true,
    glowPad: LY5.glowPad, glowCap: LY5.glowCap, glowColor: GL.color };
  const TIMES = [0, 1, 2, 3];
  // --r7: Name eingebettet statt draufgesetzt (A/B/C), je Ziel / kein Ziel bei t = 1 s
  const NAME_GOLD = [0.90, 0.80, 0.60];
  const SOFT = "1px 1px 1.5px rgba(20,10,4,0.8)";
  const R7 = [
    { ...R5, id: "A", label: "A: Marcellus 12 px Pergament-Gold, weicher dunkler Schatten, keine Kontur, dicht am Rahmen",
      size: 12, color: NAME_GOLD, nameStroke: "none", nameShadow: SOFT, nameGap: 1 },
    { ...R5, id: "B", label: "B: wie A, dahinter ein kaum sichtbarer weicher Tinten-Schleier (Alpha 0,3)",
      size: 12, color: NAME_GOLD, nameStroke: "none", nameShadow: SOFT, nameGap: 1, veil: 0.3 },
    { ...R5, id: "C", label: "C: Cinzel 11 px (Kapitaelchen), Pergament-Gold, weicher Schatten, dicht am Rahmen",
      font: "Cinzel", size: 11, color: NAME_GOLD, nameStroke: "none", nameShadow: SOFT, nameGap: 1 },
  ];
  // --r8: Balken eingelassen statt aufgeklebt (A/B/C), je Ziel (t = 1 s) / kein Ziel (t = 3 s)
  const R7B = { ...R7[1], veil: 0.38, fillH: 10 / 1.3 };
  const R8 = [
    { ...R7B, id: "A", label: "A: Kapsel-Maske (runde Enden) + innerer Schatten, leerer Teil rotbraun mit Tiefe", capsule: true, inset: true },
    { ...R7B, id: "B", label: "B: wie A + heller Meniskus oben und weich auslaufende, glimmende Vorderkante", capsule: true, inset: true, meniscus: true },
    { ...R7B, id: "C", label: "C: wie B + feiner Glasglanz oben im Schlitz", capsule: true, inset: true, meniscus: true, glass: true },
  ];
  const V = r4 ? [R5] : final ? [FINAL] : [
    { id: "A", label: "A: Friz 12 px pergament, Stufe ohne Kasten, Ziel = Rahmen heller/goldener",
      frameH: 12, fillH: 4, font: "Friz", size: 12, color: [0.93, 0.84, 0.62], level: "plain", target: "frame" },
    { id: "B", label: "B: Cinzel 12 px kupfer, kleines Stufen-Plaettchen, Ziel = duenne warme Linie unter dem Balken",
      frameH: 11, fillH: 5, font: "Cinzel", size: 12, color: [0.93, 0.62, 0.40], level: "box", target: "line" },
    { id: "C", label: "C: Marcellus 13 px warm, kleines Plaettchen, Ziel = enger schwacher Schein (Alpha 0,25)",
      frameH: 10, fillH: 3, font: "Marcellus", size: 13, color: [0.95, 0.80, 0.56], level: "box", target: "glow" },
  ];

  function plateAt(v0, isTarget, t = 0) {
    const k = SHOT.k || 1; // Screenshot-Massstab: alle Masse der Plakette mitskalieren
    const v = k === 1 ? v0 : { ...v0, frameH: v0.frameH * k, fillH: v0.fillH * k, size: v0.size * k, levelH: v0.levelH && v0.levelH * k,
      levelFont: v0.levelFont && v0.levelFont * k, glowPad: v0.glowPad && v0.glowPad * k, glowCap: v0.glowCap && v0.glowCap * k };
    const s = v.frameH / G.h;                                  // Rahmen-Massstab (Textur-Pixel -> Bildschirm-Pixel)
    const slitH = (G.h - G.top - G.bottom) * s;
    const fw = SLIT_W + (G.left + G.right) * s, fh = v.frameH, cap = G.cap * s, mid = fw - 2 * cap;
    const fx = SLIT_X - G.left * s, fy = MID_Y - (G.top * s + slitH / 2);
    const bright = v.target === "frame" ? (isTarget ? "brightness(1.18) sepia(0.25)" : "brightness(0.78)") : "none";
    const frame = `<div style="position:absolute;left:${fx}px;top:${fy}px;width:${fw}px;height:${fh}px;filter:${bright}">
      <div style="position:absolute;left:0;top:0;width:${cap}px;height:${fh}px;background:url(${tex.frame}) 0 0/${(G.w / G.cap) * cap}px ${fh}px"></div>
      <div style="position:absolute;left:${cap}px;top:0;width:${mid}px;height:${fh}px;overflow:hidden"><div style="width:100%;height:100%;background:url(${tex.frame}) ${-(G.cap / (G.w - 2 * G.cap)) * mid}px 0/${(G.w / (G.w - 2 * G.cap)) * mid}px ${fh}px"></div></div>
      <div style="position:absolute;left:${cap + mid}px;top:0;width:${cap}px;height:${fh}px;background:url(${tex.frame}) ${-(G.w / G.cap - 1) * cap}px 0/${(G.w / G.cap) * cap}px ${fh}px"></div></div>`;
    const slit = `<div style="position:absolute;left:${SLIT_X}px;top:${MID_Y - slitH / 2}px;width:${SLIT_W}px;height:${slitH}px;background:${v.back ? rgb(v.back, v.back[3]) : "rgba(6,4,3,0.88)"}"></div>`;
    const fill = `<div style="position:absolute;left:${SLIT_X}px;top:${MID_Y - v.fillH / 2}px;width:${SLIT_W * 0.7}px;height:${v.fillH}px;
      background:url(${v.fillUrl || matt}) 0 0/100% 100%;background-color:${rgb(v.ember || EMBER)};background-blend-mode:multiply"></div>`;
    let liquid = "", r8slit = "";
    if (v.capsule) {
      // ein Block im Schlitz: Kapsel (runde Enden), leerer Teil rotbraun mit Tiefe, Fluessigkeit, innerer Schatten,
      // Meniskus/Vorderkante, Glasglanz
      const [la, lb] = vm.lua(`local a, b = NS.NameplateStyle.FlowState(${t}, 0.3); return { a, b }`);
      const SH2 = slitH, W = SLIT_W * 0.7, H = Math.min(v.fillH, SH2), top = (SH2 - H) / 2;
      const layer = (l, extra) => {
        const mirror = l.u0 > l.u1, u0 = Math.min(l.u0, l.u1), r = Math.abs(l.u1 - l.u0), tw = W / r, th = H / (l.v1 - l.v0);
        return `<div style="position:absolute;left:0;top:0;width:${W}px;height:${H}px;opacity:${l.alpha};${extra}
          ${mirror ? "transform:scaleX(-1);" : ""}background:url(${tex.liquid}) ${-u0 * tw}px ${-l.v0 * th}px/${tw}px ${th}px repeat;filter:brightness(${l.bright})"></div>`;
      };
      const edgeW = 7 * k;
      const fade = v.meniscus ? `-webkit-mask-image:linear-gradient(90deg,#000 0,#000 calc(100% - ${edgeW}px),transparent 100%);` : "";
      const front = v.meniscus ? `<div style="position:absolute;left:${W - edgeW * 1.4}px;top:${top - 1}px;width:${edgeW * 2}px;height:${H + 2}px;
        background:radial-gradient(ellipse at 40% 50%, rgba(255,120,60,0.55) 0%, rgba(255,90,40,0.25) 40%, rgba(255,80,30,0) 72%);mix-blend-mode:screen"></div>` : "";
      const meniscus = v.meniscus ? `<div style="position:absolute;left:${H / 2}px;top:${top}px;width:${W - H / 2 - edgeW}px;height:1.4px;
        background:linear-gradient(90deg,rgba(255,205,175,0) 0,rgba(255,205,175,0.42) 8%,rgba(255,205,175,0.42) 85%,rgba(255,205,175,0));filter:blur(0.4px)"></div>` : "";
      const glass = v.glass ? `<div style="position:absolute;left:${SH2 * 0.6}px;top:${SH2 * 0.12}px;width:${SLIT_W - SH2 * 1.2}px;height:${Math.max(1, SH2 * 0.16)}px;
        border-radius:2px;background:linear-gradient(90deg,rgba(255,255,255,0),rgba(255,248,235,0.14) 20%,rgba(255,248,235,0.10) 70%,rgba(255,255,255,0));filter:blur(0.3px)"></div>` : "";
      const inset = v.inset ? `<div style="position:absolute;inset:0;border-radius:${SH2 / 2}px;
        box-shadow:inset 0 ${1.6 * k}px ${2.2 * k}px rgba(0,0,0,0.75), inset 0 -${1.2 * k}px ${1.8 * k}px rgba(0,0,0,0.6), inset ${1.5 * k}px 0 ${2 * k}px rgba(0,0,0,0.5), inset -${1.5 * k}px 0 ${2 * k}px rgba(0,0,0,0.5)"></div>` : "";
      r8slit = `<div style="position:absolute;left:${SLIT_X}px;top:${MID_Y - SH2 / 2}px;width:${SLIT_W}px;height:${SH2}px;border-radius:${SH2 / 2}px;overflow:hidden;
          background:linear-gradient(180deg, rgba(34,10,7,0.92) 0%, rgba(52,16,10,0.86) 45%, rgba(18,5,4,0.94) 100%)">
        <div style="position:absolute;left:0;top:${top}px;width:${W}px;height:${H}px;${fade}">
          <div style="position:absolute;inset:0;background:url(${tex.fill}) 0 0/100% 100%;background-color:${rgb(C.hostile)};background-blend-mode:multiply"></div>
          ${layer(la, "")}${layer(lb, "mix-blend-mode:screen;")}${meniscus}
        </div>${front}${inset}${glass}</div>`;
    } else if (v.liquid) {
      const [la, lb] = vm.lua(`local a, b = NS.NameplateStyle.FlowState(${t}, 0.3); return { a, b }`);
      const W = SLIT_W * 0.7, H = v.fillH;
      const layer = (l, extra) => {
        const mirror = l.u0 > l.u1, u0 = Math.min(l.u0, l.u1), r = Math.abs(l.u1 - l.u0), tw = W / r, th = H / (l.v1 - l.v0);
        return `<div style="position:absolute;left:${SLIT_X}px;top:${MID_Y - H / 2}px;width:${W}px;height:${H}px;opacity:${l.alpha};${extra}
          ${mirror ? "transform:scaleX(-1);" : ""}background:url(${tex.liquid}) ${-u0 * tw}px ${-l.v0 * th}px/${tw}px ${th}px repeat;filter:brightness(${l.bright})"></div>`;
      };
      liquid = layer(la, "") + layer(lb, "mix-blend-mode:screen;")
        + `<div style="position:absolute;left:${SLIT_X}px;top:${MID_Y - H / 2}px;width:${W}px;height:1px;background:${rgb(S.EDGE_COLOR, S.ANIM.edgeBase)};mix-blend-mode:screen"></div>`;
    }
    const flow = v.flowUrl ? `<div style="position:absolute;left:${SLIT_X}px;top:${MID_Y - v.fillH / 2}px;width:${SLIT_W * 0.7}px;height:${v.fillH}px;
      opacity:${v.flowAlpha};background:url(${v.flowUrl}) 0 0/${(SLIT_W * 0.7) / v.flowRepeat}px 100% repeat-x"></div>
      <div style="position:absolute;left:${SLIT_X}px;top:${MID_Y - v.fillH / 2}px;width:${SLIT_W * 0.7}px;height:1px;background:${rgb(S.EDGE_COLOR, S.ANIM.edgeBase)};mix-blend-mode:screen"></div>` : "";
    let mark = "";
    if (isTarget && v.target === "line") {
      mark = `<div style="position:absolute;left:${SLIT_X + 4}px;top:${fy + fh + 1}px;width:${SLIT_W - 8}px;height:1px;background:${v.line ? rgb(v.line, v.line[3]) : "rgba(255,160,70,0.85)"}"></div>`;
    } else if (isTarget && v.target === "glow4") {
      const gp = v.glowPad, gw = fw + 2 * gp, gh = fh + 2 * gp, gc = v.glowCap, gm = gw - 2 * gc;
      const capFrac = GL.cap / GL.w, midFrac = 1 - 2 * capFrac;
      const piece = (left, width, bx, bw) => `<div style="position:absolute;left:${left}px;top:0;width:${width}px;height:${gh}px;background:${rgb(v.glowColor)};
        -webkit-mask:url(${tex.glow}) ${bx}px 0/${bw}px ${gh}px no-repeat"></div>`;
      const ga = GL.alphaMin + (GL.alphaMax - GL.alphaMin) * (0.5 + 0.5 * Math.sin(t * Math.PI * 2 / GL.period));
      mark = `<div style="position:absolute;left:${fx - gp}px;top:${fy - gp}px;width:${gw}px;height:${gh}px;opacity:${ga}">
        ${piece(0, gc, 0, gc / capFrac)}${piece(gc, gm, -gm * capFrac / midFrac, gm / midFrac)}${piece(gc + gm, gc, -(gc / capFrac - gc), gc / capFrac)}</div>`;
    } else if (isTarget && v.target === "glow") {
      const gx = fh * 0.3, gy = fh * 0.35;
      mark = `<div style="position:absolute;left:${fx - gx}px;top:${fy - gy}px;width:${fw + 2 * gx}px;height:${fh + 2 * gy}px;opacity:0.25;mix-blend-mode:screen;
        background:rgb(255,133,46);-webkit-mask:url(${tex.glow}) 0 0/100% 100%"></div>`;
    }
    const lvlStyle = `font-family:${v.font};color:${rgb([0.95, 0.86, 0.66])};text-shadow:1px 1px 0 rgba(0,0,0,.9);-webkit-text-stroke:0.4px rgba(0,0,0,.7);paint-order:stroke fill`;
    let level;
    if (v.level === "plain") {
      level = `<div style="position:absolute;left:${fx + fw + 3}px;top:${MID_Y - 7}px;height:14px;line-height:14px;font-size:10px;${lvlStyle}">17</div>`;
    } else {
      const bh = v.levelH || v.frameH + 2, bw = bh * 2;
      level = `<div style="position:absolute;left:${fx + fw + 2}px;top:${MID_Y - bh / 2}px;width:${bw}px;height:${bh}px;background:url(${tex.level}) 0 0/100% 100%;
        text-align:center;line-height:${bh}px;font-size:${v.levelFont || Math.max(8, bh - 4)}px;${lvlStyle}">17</div>`;
    }
    const gap = v.nameGap !== undefined ? v.nameGap * k : 5;
    const veil = v.veil ? `<div style="position:absolute;left:${SLIT_X - 14 * k}px;top:${fy - v.size * 1.35 - gap - 4 * k}px;width:${v.size * 0.62 * SHOT.name.length + 28 * k}px;
      height:${v.size * 1.35 + 8 * k}px;background:radial-gradient(ellipse at 40% 55%, rgba(12,7,3,${v.veil}) 0%, rgba(12,7,3,${v.veil * 0.6}) 45%, rgba(12,7,3,0) 75%)"></div>` : "";
    const name = `${veil}<div style="position:absolute;left:${SLIT_X + (v.nameGap !== undefined ? 2 * k : 0)}px;top:${fy - v.size * 1.25 - gap}px;line-height:${v.size * 1.25}px;white-space:nowrap;font-family:${v.font};font-size:${v.size}px;
      color:${rgb(v.color)};${v.nameStroke === "none" ? "" : "-webkit-text-stroke:0.6px rgba(0,0,0,.75);paint-order:stroke fill;"}text-shadow:${v.nameShadow || "1px 1px 1px rgba(0,0,0,.9)"}">${SHOT.name}</div>`;
    const [cx, cy, cw, ch, cdy] = SHOT.cover;
    const cover = `<div style="position:absolute;left:${cx}px;top:${cy}px;width:${cw}px;height:${ch}px;background:url(${shot}) ${-cx}px ${-(cy + cdy)}px/${SW}px auto;filter:blur(1.5px);
      -webkit-mask:linear-gradient(90deg,transparent,#000 12%,#000 88%,transparent),linear-gradient(transparent,#000 22%,#000 78%,transparent);-webkit-mask-composite:source-in"></div>`;
    return `<div style="position:relative;width:${SW}px;height:${SH}px;overflow:hidden;background:url(${shot}) 0 0/${SW}px auto;display:inline-block;margin:0 4px 0 0">
      ${cover}${mark}${v.capsule ? r8slit : slit + fill + flow + liquid}${frame}${level}${name}
      <div style="position:absolute;right:6px;bottom:4px;font:11px sans-serif;color:#fff;text-shadow:1px 1px 1px #000">${isTarget ? "Ziel" : "kein Ziel"}${v.liquid ? ", t = " + t + " s" : ""}</div></div>`;
  }

  const faces = Object.entries(fonts).filter(([, u]) => u).map(([n, u]) => `@font-face{font-family:${n};src:url(${u})}`).join("");
  const rowsHtml = r8 ? R8.map((v) => `<div style="margin:0 0 6px 0"><div style="font:13px sans-serif;color:#eee;padding:4px 2px">${v.label}</div>
      ${plateAt(v, true, 1)}${plateAt(v, false, 3)}</div>`).join("")
    : r7 ? R7.map((v) => `<div style="margin:0 0 6px 0"><div style="font:13px sans-serif;color:#eee;padding:4px 2px">${v.label}</div>
      ${plateAt(v, true, 1)}${plateAt(v, false, 1)}</div>`).join("")
    : r5 ? TIMES.map((t) => `<div style="margin:0 0 4px 0">${plateAt(R5, true, t)}${plateAt(R5, false, t)}</div>`).join("")
    : V.map((v) => `<div style="margin:0 0 6px 0"><div style="font:13px sans-serif;color:#eee;padding:4px 2px">${v.label}${!fonts[v.font] ? " (Schrift fehlt: --friz angeben)" : ""}</div>
    ${plateAt(v, true)}${plateAt(v, false)}</div>`).join("");
  const z = Number(opt("--zoom", 2));
  const html = `<!doctype html><html><head><style>${faces}body{margin:0;background:#111}#z{zoom:${z};display:inline-block;padding:4px}</style></head>
    <body><div id="z">${rowsHtml}</div></body></html>`;
  const outFile = opt("--out", r8 ? "docs/nameplate-src/varianten-r8.png" : r7 ? "docs/nameplate-src/varianten-r7.png" : r6 ? "docs/nameplate-src/preview-r6.png" : r5 ? "docs/nameplate-src/preview-r5.png" : r4 ? "docs/nameplate-src/preview-r4.png" : final ? "docs/nameplate-src/preview-r3.png" : "docs/nameplate-src/varianten-r2.png");
  render(html, path.resolve(ROOT, outFile), (2 * SW + 18) * z, (r8 ? R8.length * (SH + 30) : r7 ? R7.length * (SH + 30) : r5 ? TIMES.length * (SH + 4) : V.length * (SH + 30)) * z + 8 * z);
}

if (args.includes("--variants") || args.includes("--final") || args.includes("--r5") || args.includes("--r6") || args.includes("--r7") || args.includes("--r8")) {
  await variants(args.includes("--final"), args.includes("--r8") ? "r8" : args.includes("--r7") ? "r7" : args.includes("--r6") ? "r6" : args.includes("--r5") ? "r5" : false);
} else {
  const rows = [
    { name: "Wassersucher der Grimmtotem", stance: "hostile", level: 11, target: true },
    { name: "Waldgroll-Eber", stance: "hostile", level: 70 },
    { name: "Kodo der Ebene", stance: "neutral", level: 9, fill: 0.35 },
    { name: "Wache von Donnerfels", stance: "friendly", level: "??", fill: 1 },
    { name: "Ausgemergelter Wolf", stance: "tapped", level: 8, fill: 0.2 },
  ];
  const panel = (bg) => `<div style="background:${bg};padding:8px;display:inline-block;vertical-align:top">${rows.map(plate).join("")}</div>`;
  const html = `<!doctype html><html><head><style>@font-face{font-family:Marcellus;src:url(${font})}body{margin:0;background:#111}
    #z{zoom:${zoom};display:inline-block}</style></head><body><div id="z">${panel("#7a7a7a")}${panel("#d8d4c8")}${panel("#2d3a24")}</div></body></html>`;
  render(html, out, 3 * 214 * zoom, 207 * zoom);
}
