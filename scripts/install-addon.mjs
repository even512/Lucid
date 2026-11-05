// Installiert das Addon Lucid in den WoW-Ordner.
//
// Aufruf:  node scripts/install-addon.mjs [--retail] [--dry-run] [--help]
//   (ohne Flag)  Ziel: <WOW_DIR>\_forever_\Interface\AddOns\Lucid
//   --retail     Ziel: <WOW_DIR>\_retail_\Interface\AddOns\Lucid
//   --dry-run    zeigt nur, was passieren wuerde; schreibt und loescht nichts
// Die TOC traegt beide Interface-Nummern (Retail 120105, Forever 16001) und wird unveraendert kopiert.
// WOW_DIR kommt aus der Datei .env im Projektordner (siehe .env.example).
// Exit-Codes: 0 = ok, 1 = Fehler (fehlende/ungueltige Config, Quelle fehlt, Schreibfehler, unbekannte Option)
//
// Sicherheit:
// - Geschrieben und geleert wird ausschliesslich <WOW_DIR>\<_forever_|_retail_>\Interface\AddOns\Lucid
//   (Pfad wird normalisiert, muss innerhalb von WOW_DIR liegen und auf \Interface\AddOns\Lucid enden).
// - Symlinks/Junctions werden nirgends gefolgt: weder im Zielpfad noch in der Quelle (Symlink im Ziel = Abbruch).
// - Kopiert werden nur Dateien mit Endung .toc/.lua/.xml/.tga/.ttf/.txt/.md sowie LICENSE (Schriften + OFL-Lizenztexte in Fonts/, THIRD-PARTY.md) und harmlosem Namen (Allowlist), Unterordner nur mit harmlosem Namen.
// - Vor dem Kopieren wird nur der Inhalt des eigenen Addon-Ordners entfernt, nie etwas ausserhalb.

import { existsSync } from "node:fs";
import { lstat, mkdir, readdir, readFile, rmdir, unlink, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
export const ADDON_NAME = "Lucid";
const SOURCE_DIR = path.join(ROOT, "addon", ADDON_NAME);
const TOC_NAME = `${ADDON_NAME}.toc`;
const ALLOWED_EXT = new Set([".toc", ".lua", ".xml", ".tga", ".ttf", ".txt", ".md"]);
// Dateien ohne Endung, die im Paket mitgehen (Lizenz)
const ALLOWED_NAMES = new Set(["LICENSE"]);
const NAME_OK = /^[A-Za-z0-9_.-]+$/;
const MAX_FILE_BYTES = 1024 * 1024;
const MAX_TGA_BYTES = 1024 * 1024 * 4 + 1024; // 1024 x 1024 x 32 bit + Kopf
const MAX_DEPTH = 3;
const KNOWN_FLAGS = new Set(["--retail", "--dry-run", "--help", "-h"]);
const VALUE_FLAGS = new Set(["--package"]);

const HELP = `Lucid: Addon in den WoW-Ordner installieren

Aufruf:
  npm run install-addon [-- --retail] [-- --dry-run]
  node scripts/install-addon.mjs [--retail] [--dry-run] [--package <ordner>] [--help]

Optionen:
  --retail    nach <WOW_DIR>\\_retail_ statt _forever_ installieren
  --dry-run   nur anzeigen, was passieren wuerde; nichts schreiben oder loeschen
  --package   statt addon/Lucid den Ordner <ordner> installieren (Ergebnis von scripts/build-package.mjs, also <out>/Lucid)
  --help, -h  diese Hilfe

Ohne --retail wird nach <WOW_DIR>\\_forever_ installiert. Die TOC traegt beide Interface-Nummern
und wird in beiden Faellen unveraendert kopiert.
Zielordner: <WOW_DIR>\\<_forever_|_retail_>\\Interface\\AddOns\\${ADDON_NAME}

Konfiguration: WOW_DIR steht in der Datei .env im Projektordner (Vorlage: .env.example),
z. B.  WOW_DIR=D:\\World of Warcraft
Vor dem Kopieren wird nur der Inhalt des eigenen Addon-Ordners geleert.
Nach einem Update das Spiel einmal komplett neu starten (neue Dateien erkennt der Client nur beim Start).
`;

/** Wert eines Schluessels aus .env-Text lesen (KEY=Wert, optional in Anfuehrungszeichen, # beginnt Kommentarzeile). */
export function parseEnvValue(text, key) {
  for (const line of text.split(/\r?\n/)) {
    if (/^\s*#/.test(line)) continue;
    const m = /^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/.exec(line);
    if (!m || m[1] !== key) continue;
    let v = m[2];
    if (/^".*"$/.test(v) || /^'.*'$/.test(v)) v = v.slice(1, -1);
    return v;
  }
  return undefined;
}

/** Kommandozeile pruefen; wirft bei unbekannten Flags oder Positionsargumenten. */
export function parseArgs(argv) {
  let pkg;
  const rest = [];
  for (let i = 0; i < argv.length; i++) {
    if (VALUE_FLAGS.has(argv[i])) {
      const v = argv[i + 1];
      if (!v || v.startsWith("--")) throw new Error(`${argv[i]} braucht einen Ordner.`);
      pkg = v;
      i++;
    } else rest.push(argv[i]);
  }
  const unknown = rest.filter((a) => !KNOWN_FLAGS.has(a));
  if (unknown.length) {
    throw new Error(`Unbekannte Option bzw. unerwartetes Argument: ${unknown.join(" ")}\nHilfe: npm run install-addon -- --help`);
  }
  const opts = { help: rest.includes("--help") || rest.includes("-h"), retail: rest.includes("--retail"), dry: rest.includes("--dry-run") };
  if (pkg !== undefined) opts.package = pkg;
  return opts;
}

/** Beide Pfade normalisiert, Vergleich unter Windows ohne Gross-/Kleinschreibung. */
function norm(p) {
  const r = path.resolve(p);
  return process.platform === "win32" ? r.toLowerCase() : r;
}

/** liegt child echt innerhalb von parent? */
export function isInside(parent, child) {
  const rel = path.relative(norm(parent), norm(child));
  return rel !== "" && !rel.startsWith("..") && !path.isAbsolute(rel);
}

/**
 * Zielordner bestimmen und gegen die Allowlist pruefen.
 * Ergebnis endet immer auf <_forever_|_retail_>\Interface\AddOns\Lucid und liegt innerhalb von WOW_DIR.
 */
export function resolveTarget(wowDir, retail) {
  const v = String(wowDir ?? "").trim().replace(/^"(.*)"$/, "$1");
  if (v === "") throw new Error("WOW_DIR ist leer.");
  if (v.includes("\0")) throw new Error("WOW_DIR enthaelt ungueltige Zeichen.");
  if (!path.isAbsolute(v)) throw new Error(`WOW_DIR muss ein absoluter Pfad sein (erhalten: "${v}").`);
  const base = path.resolve(v);
  const flavor = retail ? "_retail_" : "_forever_";
  const flavorDir = path.join(base, flavor);
  const addons = path.join(flavorDir, "Interface", "AddOns");
  const target = path.join(addons, ADDON_NAME);
  const tail = target.split(path.sep).slice(-3).join("\\").toLowerCase();
  if (tail !== `interface\\addons\\${ADDON_NAME.toLowerCase()}` || !isInside(base, target)) {
    throw new Error(`Zielpfad ausserhalb der Allowlist (\\Interface\\AddOns\\${ADDON_NAME} innerhalb von WOW_DIR).`);
  }
  return { base, flavor, flavorDir, addons, target };
}

/** Quellordner einlesen: Liste {rel, from, size} aller erlaubten Dateien; Fremdes wird gemeldet (skipped). Folgt keinen Symlinks. */
export async function listSource(dir = SOURCE_DIR, rel = "", depth = 0, acc = { files: [], skipped: [] }) {
  if (depth > MAX_DEPTH) throw new Error(`Quellordner zu tief verschachtelt: ${rel}`);
  const entries = await readdir(dir, { withFileTypes: true });
  for (const e of entries) {
    const relPath = rel ? `${rel}/${e.name}` : e.name;
    const from = path.join(dir, e.name);
    if (!NAME_OK.test(e.name) || e.name.includes("..")) {
      acc.skipped.push(relPath);
    } else if (e.isDirectory()) {
      await listSource(from, relPath, depth + 1, acc);
    } else if (e.isFile() && (ALLOWED_EXT.has(path.extname(e.name).toLowerCase()) || ALLOWED_NAMES.has(e.name))) {
      const st = await lstat(from);
      if (st.size > (path.extname(e.name).toLowerCase() === ".tga" ? MAX_TGA_BYTES : MAX_FILE_BYTES)) throw new Error(`Datei zu gross: ${relPath}`);
      acc.files.push({ rel: relPath, from, size: st.size });
    } else {
      acc.skipped.push(relPath);
    }
  }
  acc.files.sort((a, b) => a.rel.localeCompare(b.rel));
  return acc;
}

async function isRealDir(p) {
  try {
    const st = await lstat(p);
    return st.isDirectory() && !st.isSymbolicLink();
  } catch {
    return false;
  }
}

async function loadWowDir() {
  const envFile = path.join(ROOT, ".env");
  if (existsSync(envFile)) {
    const v = parseEnvValue(await readFile(envFile, "utf8"), "WOW_DIR");
    if (v) return v;
  }
  return "";
}

/** Dateiname fuer die Ausgabe: nur druckbare ASCII-Zeichen (Steuer- und Escape-Zeichen aus fremden Namen werden zu "?"). */
export function printable(name) {
  return String(name).replace(/[^ -~]/g, "?");
}

/** Einen Eintrag im Addon-Ordner entfernen: Links (Symlink/Junction) und Dateien per unlink, echte Ordner rekursiv. Folgt nie einem Link. */
async function removeEntry(p) {
  const st = await lstat(p);
  if (st.isSymbolicLink() || !st.isDirectory()) {
    await unlink(p);
    return;
  }
  for (const name of await readdir(p)) await removeEntry(path.join(p, name));
  await rmdir(p);
}

/**
 * Inhalt des Addon-Ordners entfernen (der Ordner selbst bleibt). Prueft das Ziel unmittelbar davor erneut (kein Link, echter Ordner),
 * damit zwischen Pruefung und Loeschen kein Austausch gegen einen Link durchschlaegt. Entfernt Links, folgt ihnen nicht.
 */
export async function clearTarget(target) {
  const st = await lstat(target);
  if (st.isSymbolicLink() || !st.isDirectory()) throw new Error(`Zielordner ist ein Symlink oder kein Ordner; Abbruch: ${target}`);
  for (const name of await readdir(target)) {
    await removeEntry(path.join(target, name));
  }
}

export async function main(argv) {
  const opts = parseArgs(argv);
  if (opts.help) {
    console.log(HELP);
    return;
  }

  const wowDir = await loadWowDir();
  if (!wowDir) {
    throw new Error(
      "WOW_DIR ist nicht konfiguriert. Lege im Projektordner eine Datei .env an (Vorlage: .env.example), z. B.\n" +
        "  WOW_DIR=D:\\World of Warcraft",
    );
  }
  const t = resolveTarget(wowDir, opts.retail);
  if (!(await isRealDir(t.base))) throw new Error(`WOW_DIR existiert nicht, ist kein Ordner oder ein Symlink: ${t.base}`);
  if (!(await isRealDir(t.flavorDir))) {
    throw new Error(`Der Ordner ${t.flavor} fehlt unter WOW_DIR (${t.flavorDir}). Ist die Spielversion installiert und WOW_DIR richtig?`);
  }
  if (!(await isRealDir(path.join(t.flavorDir, "Interface"))) || !(await isRealDir(t.addons))) {
    throw new Error(`Der Ordner Interface\\AddOns fehlt unter ${t.flavorDir} (oder ist ein Symlink). Stimmt WOW_DIR?`);
  }

  // Quelle vollstaendig pruefen und vorbereiten, bevor am Ziel irgendetwas angefasst wird.
  const src = await listSource(opts.package ? path.resolve(opts.package) : undefined);
  const toc = src.files.find((f) => f.rel === TOC_NAME);
  if (!toc) throw new Error(`Im Quellordner fehlt ${TOC_NAME}.`);

  // Zielordner: darf nicht existieren oder muss ein echter Ordner (kein Symlink) sein.
  let targetExists = false;
  try {
    const st = await lstat(t.target);
    if (st.isSymbolicLink() || !st.isDirectory()) throw new Error(`Zielordner ist ein Symlink oder kein Ordner; Abbruch: ${t.target}`);
    targetExists = true;
  } catch (err) {
    if (!err || err.code !== "ENOENT") throw err;
  }

  const dry = opts.dry;
  console.log(dry ? "Trockenlauf (--dry-run): es wird nichts geschrieben oder geloescht." : `Installiere ${ADDON_NAME} ...`);
  if (opts.package) console.log(`Quelle: Paketordner ${path.resolve(opts.package)}`);
  console.log(`Ziel: ${t.target}${opts.retail ? "  (Retail)" : "  (Forever)"}`);
  if (targetExists) console.log(`  ${dry ? "wuerde leeren" : "leere"}: vorhandener Addon-Ordner (nur dieser)`);

  if (!dry) {
    if (targetExists) await clearTarget(t.target);
    else await mkdir(t.target);
  }
  for (const f of src.files) {
    const to = path.join(t.target, ...f.rel.split("/"));
    if (!isInside(t.target, to)) throw new Error(`Ungueltiger Dateipfad: ${f.rel}`);
    console.log(`  ${dry ? "wuerde kopieren" : "kopiere"}: ${f.rel}`);
    if (dry) continue;
    await mkdir(path.dirname(to), { recursive: true });
    await writeFile(to, await readFile(f.from));
  }
  for (const s of src.skipped) console.log(`  uebersprungen (nicht erlaubt): ${printable(s)}`);
  console.log(
    dry ? `Fertig (Trockenlauf): ${src.files.length} Datei(en) wuerden installiert.` : `Fertig: ${src.files.length} Datei(en) installiert.`,
  );
  if (!dry) console.log("Nach einem Addon-Update das Spiel EINMAL komplett neu starten (neue Dateien erkennt der Client nur beim Start).");
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2)).catch((err) => {
    console.error(`FEHLER: ${err instanceof Error ? err.message : String(err)}`);
    process.exit(1);
  });
}
