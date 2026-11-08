// Kontaktbogen der Zonen-Motive (Sichtvorschau), Layout wie Card.lua "pair":
//   node scripts/motif-preview.mjs [--out tests/screens/motive-vorschau-1.png] [--scale 1] [--sub "Subzonen-Name"] [--keep] [motiv ...]
// Ohne Motivnamen: alle Rezepte mit "auto": true. Je Motiv eine Zelle: dunkler, leicht unruhiger Hintergrund, Zonenname in
// Cinzel, links/rechts die erzeugten Texturen (Stufe wie im Spiel bei 1440p, UI-Skala 1,0), getoent mit Card.ORN_TINT,
// Alpha 0,95. Mit --sub steht eine Zeile 2 (Subzone, 22 pt, 85 % Alpha) darunter; die Seiten rutschen wie in Card.lua nach aussen,
// wenn sie neben dieser Zeile liegen. TGA -> PNG per Node, Rendern per Headless-Chrome mit eigenem Temp-Profil (nie ein fremdes Profil).
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import zlib from "node:zlib";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { createVm, ROOT } from "../tests/helpers/wow-vm.mjs";

const args = process.argv.slice(2);
const opt = (n, d) => { const i = args.indexOf(n); return i >= 0 ? args[i + 1] : d; };
const out = path.resolve(ROOT, opt("--out", "tests/screens/motive-vorschau-1.png"));
const scale = Number(opt("--scale", 1));
const cols = Number(opt("--cols", 2));
const sub = opt("--sub", "");
const names = args.filter((a, i) => !a.startsWith("--") && !["--out", "--scale", "--cols", "--sub"].includes(args[i - 1]));
const TINT = [1, 0.86, 0.55], ALPHA = 0.95, EFF = 1.875; // Stufenwahl: 1440p, UI-Skala 1,0 (Pixel je UI-Einheit)
const ZONE = { // passende Zone je Motiv (Zonenname deDE)
  ashen: "Eschental", atalai: "Sümpfe des Elends", centaur: "Desolace", delta: "Flusslande", dusk: "Dämmerwald",
  dwarf: "Eisenschmiede", forsaken: "Tirisfal", frost: "Winterquell", goblin: "Tanaris", gurubashi: "Schlingendorntal",
  highborne: "Azshara", jungle: "Feralas", kaldorei: "Teldrassil", karazhan: "Gebirgspass der Totenwinde", moon: "Mondlichtung",
  primal: "Krater von Un'Goro", qiraji: "Silithus", renewal: "Hyjal", savanna: "Brachland", scourge: "Westliche Pestländer",
  shire: "Wald von Elwynn", shore: "Dunkelküste", sky: "Insel Zephras", theramore: "Düstermarschen", tiki: "Dunkelspeerinseln",
  totem: "Mulgore", wildhammer: "Hinterland", shendralas: "Shen'dralas", royal: "Sturmwind", harvest: "Westfall",
  frontier: "Rotkammgebirge", orchard: "Vorgebirge des Hügellands", alterac: "Alteracgebirge", arathor: "Arathihochland",
  menethil: "Sumpfland", titan: "Ödland", darkiron: "Sengende Schlucht", blackrock: "Brennende Steppe", fel: "Verwüstete Lande",
  horde: "Durotar", needles: "Tausend Nadeln",
};

const MEDIA = path.join(ROOT, "addon", "Lucid", "Media");
const recipes = JSON.parse(readFileSync(path.join(ROOT, "docs", "ornament-src", "recipes.json"), "utf8"));
const list = names.length ? names : recipes.filter((r) => r.auto).map((r) => r.name);
const vm = createVm().boot();
const styles = vm.lua("return NS.ZoneOrnaments.styles");
const tmp = mkdtempSync(path.join(os.tmpdir(), "lucid-motifs-"));

function chunk(type, data) {
  const t = Buffer.from(type), len = Buffer.alloc(4), crc = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  crc.writeUInt32BE(zlib.crc32(Buffer.concat([t, data])) >>> 0);
  return Buffer.concat([len, t, data, crc]);
}
/** TGA (32 bit, oben links) -> getoentes RGBA-PNG */
function tgaToPng(file, dest) {
  const b = readFileSync(file), w = b.readUInt16LE(12), h = b.readUInt16LE(14);
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w * 4 + 1)] = 0;
    for (let x = 0; x < w; x++) {
      const s = 18 + (y * w + x) * 4, o = y * (w * 4 + 1) + 1 + x * 4, g = b[s];
      raw[o] = Math.round(g * TINT[0]); raw[o + 1] = Math.round(g * TINT[1]); raw[o + 2] = Math.round(g * TINT[2]);
      raw[o + 3] = Math.round(b[s + 3] * ALPHA);
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 6;
  writeFileSync(dest, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr),
    chunk("IDAT", zlib.deflateSync(raw, { level: 3 })), chunk("IEND", Buffer.alloc(0))]));
}

const motifs = [];
for (const name of list) {
  const S = styles[name];
  if (!S || S.kind !== "pair") { console.log("uebersprungen (kein pair-Stil):", name); continue; }
  const sides = {};
  for (const key of ["left", "right"]) {
    const X = S[key];
    for (const lv of X.levels) for (const t of lv.tiles) {
      const dest = path.join(tmp, t.file + ".png");
      if (!existsSync(dest)) tgaToPng(path.join(MEDIA, t.file + ".tga"), dest);
    }
    sides[key] = { aspect: X.aspect, midY: X.midY, srcW: X.srcW, levels: X.levels.map((lv) => ({ cw: lv.cw,
      tiles: lv.tiles.map((t) => ({ ...t, url: pathToFileURL(path.join(tmp, t.file + ".png")).href })) })) };
  }
  motifs.push({ sub, name, label: recipes.find((r) => r.name === name)?.label?.deDE || name, zone: ZONE[name] || name, gap: S.gap,
    factor: S.factor, min: S.min, max: S.max, left: sides.left, right: sides.right });
}
if (!motifs.length) throw new Error("keine Motive");

const font = pathToFileURL(path.join(ROOT, "addon", "Lucid", "Fonts", "Cinzel-Regular.ttf")).href;
const noise = encodeURIComponent("<svg xmlns='http://www.w3.org/2000/svg' width='400' height='400'><filter id='n'><feTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='2' stitchTiles='stitch' seed='7'/><feColorMatrix values='0 0 0 0 0.5  0 0 0 0 0.45  0 0 0 0 0.35  0 0 0 0.16 0'/></filter><rect width='400' height='400' filter='url(#n)'/></svg>");
const blobs = encodeURIComponent("<svg xmlns='http://www.w3.org/2000/svg' width='900' height='600'><filter id='b'><feTurbulence type='fractalNoise' baseFrequency='0.004' numOctaves='3' stitchTiles='stitch' seed='3'/><feColorMatrix values='0 0 0 0 0.35  0 0 0 0 0.3  0 0 0 0 0.22  0 0 0 0.5 -0.1'/></filter><rect width='900' height='600' filter='url(#b)'/></svg>");
const PAGEW = Math.round(1550 * cols * scale), CELLW = Math.round(1550 * scale);
const html = `<!doctype html><html><head><meta charset="utf-8"><style>
@font-face{font-family:Cinzel;src:url("${font}")}
html,body{margin:0;background:#15120e}
body{width:${PAGEW}px}
#grid{display:grid;grid-template-columns:repeat(${cols},1fr);gap:0}
.cell{position:relative;overflow:hidden;box-sizing:border-box;border:1px solid #2c261c;
 background:url("data:image/svg+xml,${noise}"),url("data:image/svg+xml,${blobs}"),linear-gradient(160deg,#1a1611,#12100c 55%,#1b1712)}
.name{position:absolute;font-family:Cinzel,serif;color:#f4e7c6;white-space:nowrap;text-shadow:0 2px 6px #000;line-height:1}
.cap{position:absolute;left:10px;top:6px;font:13px Consolas,monospace;color:#8c8068}
.tex{position:absolute}
.sub{position:absolute;font-family:Cinzel,serif;color:#f4e7c6;opacity:.85;white-space:nowrap;text-shadow:0 2px 6px #000;line-height:1}
.tile{position:absolute;background-repeat:no-repeat}
</style></head><body><div id="grid"></div><script>
const M=${JSON.stringify(motifs)}, K=${scale}, FS=44*K, EFF=${EFF}, CELLW=${CELLW}, COLS=${cols};
function side(X,wRef,wide,mirror){
  const w=wRef*X.srcW/wide, h=w/X.aspect;
  const lv=X.levels.find(l=>l.cw>=w/K*EFF)||X.levels[X.levels.length-1];
  const el=document.createElement('div'); el.className='tex'; el.style.width=w+'px'; el.style.height=h+'px';
  if(mirror) el.style.transform='scaleX(-1)';
  for(const t of lv.tiles){
    const d=document.createElement('div'); d.className='tile';
    const left=t.from*w, wd=(t.to-t.from)*w, top=(t.y0??0)*h, ht=t.y0!==undefined?(t.y1-t.y0)*h:h;
    d.style.cssText='left:'+left+'px;top:'+top+'px;width:'+wd+'px;height:'+ht+'px;background-image:url("'+t.url+'");'+
      'background-size:'+(wd/(t.u1-t.u0))+'px '+(ht/(t.v1-t.v0))+'px;background-position:'+(-t.u0*wd/(t.u1-t.u0))+'px '+(-t.v0*ht/(t.v1-t.v0))+'px';
    el.appendChild(d);
  }
  return {el,w,h,lv};
}
document.fonts.load('44px Cinzel').then(()=>document.fonts.load('22px Cinzel')).then(()=>{
  const grid=document.getElementById('grid'); const items=[];
  M.forEach(m=>{
    const cell=document.createElement('div'); cell.className='cell'; grid.appendChild(cell);
    const t=document.createElement('div'); t.className='name'; t.textContent=m.zone; t.style.fontSize=FS+'px'; cell.appendChild(t);
    const w1=t.getBoundingClientRect().width/K, ornLen=Math.min(220,Math.max(60,0.35*w1));
    const wRef=Math.min(m.max,Math.max(m.min,m.factor*ornLen))*K, wide=Math.max(m.left.srcW,m.right.srcW);
    const R=side(m.right,wRef,wide,false), L=side(m.left,wRef,wide,true);
    let t2=null, w2=0;
    if(m.sub){ t2=document.createElement('div'); t2.className='sub'; t2.textContent=m.sub; t2.style.fontSize=(22*K)+'px'; cell.appendChild(t2); w2=t2.getBoundingClientRect().width/K; }
    const H=Math.max(R.h,L.h), cellH=Math.round(Math.max(H+80*K+(m.sub?40*K:0),200*K));
    items.push({m,cell,t,t2,w2,R,L,w1,cellH});
    cell.appendChild(L.el); cell.appendChild(R.el);
    const cap=document.createElement('div'); cap.className='cap';
    cap.textContent=m.name+' - '+m.label+'  |  Stufe links '+L.lv.cw+' / rechts '+R.lv.cw; cell.appendChild(cap);
  });
  for(let i=0;i<items.length;i+=COLS){
    const row=items.slice(i,i+COLS), rowH=Math.max(...row.map(x=>x.cellH));
    for(const {m,cell,t,t2,w2,R,L,w1} of row){
      cell.style.height=rowH+'px';
      const cx=CELLW/2, cy=rowH/2, tw=w1*K, gap=m.gap*K;
      t.style.left=(cx-tw/2)+'px'; t.style.top=(cy-FS/2)+'px';
      // Abstand wie Card.lua (sideReach): breiteste Zeile, die senkrecht im Bereich einer Seite liegt (Zeile 2: 6 px unter Zeile 1)
      const rT=cy-m.right.midY*R.h, lT=cy-m.left.midY*L.h;
      const l2T=cy+FS/2+6*K, l2B=l2T+22*K;
      const hit=(top,h)=>t2&&l2T<top+h&&l2B>top;
      const half=Math.max(tw/2,hit(rT,R.h)||hit(lT,L.h)?w2*K/2:0), extra=half-tw/2;
      if(t2){ t2.style.left=(cx-w2*K/2)+'px'; t2.style.top=l2T+'px'; }
      R.el.style.left=(cx+tw/2+gap+extra)+'px'; R.el.style.top=rT+'px';
      L.el.style.left=(cx-tw/2-gap-extra-L.w)+'px'; L.el.style.top=lT+'px';
    }
  }
  document.body.dataset.h=document.body.scrollHeight;
});
</script></body></html>`;
const htmlFile = path.join(tmp, "vorschau.html");
writeFileSync(htmlFile, html);
const CHROME = [process.env.CHROME, "C:/Program Files/Google/Chrome/Application/chrome.exe", "C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"]
  .filter(Boolean).find((p) => existsSync(p));
if (!CHROME) throw new Error("kein Chrome/Edge gefunden (CHROME setzen)");
mkdirSync(path.dirname(out), { recursive: true });
const base = ["--headless=new", "--disable-gpu", "--allow-file-access-from-files", "--hide-scrollbars", "--force-device-scale-factor=1",
  `--user-data-dir=${path.join(tmp, "profil")}`, "--no-first-run", "--no-default-browser-check", "--virtual-time-budget=20000"];
// Durchgang 1: Seitenhoehe messen (DOM ausgeben), Durchgang 2: Screenshot in genau dieser Hoehe
const dom = spawnSync(CHROME, [...base, `--window-size=${PAGEW},800`, "--dump-dom", pathToFileURL(htmlFile).href],
  { encoding: "utf8", timeout: 180000, maxBuffer: 1 << 28 });
const estH = Number(/data-h="([0-9]+)"/.exec(dom.stdout || "")?.[1]);
if (!estH) throw new Error("Seitenhoehe nicht messbar: " + (dom.stdout || dom.error || "").toString().slice(-600).replace(/url([^)]*)/g, "url(..)"));
const r = spawnSync(CHROME, [...base, `--window-size=${PAGEW},${estH}`, `--screenshot=${out}`, pathToFileURL(htmlFile).href],
  { stdio: "ignore", timeout: 180000 });
if (!existsSync(out)) throw new Error("Vorschau nicht entstanden (Chrome-Status " + r.status + ")");
console.log("Vorschau:", out, "- Motive:", motifs.length, args.includes("--keep") ? "- Arbeitsordner: " + tmp : "");
if (!args.includes("--keep")) rmSync(tmp, { recursive: true, force: true });
