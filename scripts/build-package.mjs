// Baut den Paketsatz so nach, wie ihn der BigWigs-Packager laut .pkgmeta ergibt (Ignore-Liste, move-folders, manual-changelog),
// in einen Ordner ausserhalb des Repos: <out>/Lucid. Der Block #@do-not-package@ der TOC fliegt raus, @project-version@ wird ersetzt.
// Aufruf: node scripts/build-package.mjs --out <ordner> [--version 1.0.0-rc1]
//   Danach ins Spiel: node scripts/install-addon.mjs --package <out>/Lucid [--retail]
// Das ist ein Nachbau fuer lokale Tests, kein Ersatz fuer den echten Packager-Lauf. Gelesen wird die Arbeitskopie (ohne Dateien,
// die mit "." beginnen, ohne node_modules und ohne .env). Geschrieben wird nur in <out>/Lucid.
// Exit-Codes: 0 ok, 1 Fehler.

import { cpSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");

/** Ignore-Eintraege der .pkgmeta (Pfade relativ zur Repo-Wurzel) */
export function readIgnore(pkgmeta) {
  const i = pkgmeta.indexOf("\nignore:");
  if (i < 0) throw new Error(".pkgmeta hat keine ignore-Liste.");
  return [...pkgmeta.slice(i).matchAll(/^  - (\S+)\s*$/gm)].map((m) => m[1]);
}

/** Alle Dateien unter dir, relativ mit "/"; Eintraege der Wurzel mit "." sowie node_modules werden nicht betreten */
export function walk(dir, rel = "") {
  const out = [];
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    if (!rel && (e.name.startsWith(".") || e.name === "node_modules")) continue;
    const r = rel ? `${rel}/${e.name}` : e.name;
    if (e.isSymbolicLink()) continue;
    if (e.isDirectory()) out.push(...walk(path.join(dir, e.name), r));
    else out.push(r);
  }
  return out;
}

/** TOC fuer das Paket: Block #@do-not-package@ entfernen, Platzhalter ersetzen */
export function packageToc(text, version) {
  return text.replace(/#@do-not-package@[\s\S]*?#@end-do-not-package@\r?\n?/g, "").split("@project-version@").join(version);
}

/** Paketdatei (relativ zu <out>/Lucid) zu einer Repo-Datei, oder null, wenn sie nicht ins Paket gehoert */
export function packagePath(rel) {
  if (rel === "CHANGELOG.md") return "CHANGELOG.md"; // manual-changelog landet im Paketordner
  if (rel.startsWith("addon/Lucid/")) return rel.slice("addon/Lucid/".length);
  return null;
}

/** Baut <out>/Lucid; liefert die Liste der Paketdateien (relativ, "/") */
export function buildPackage({ root = ROOT, out, version }) {
  const o = path.resolve(out);
  const r = path.resolve(root);
  const withSep = (x) => (x.endsWith(path.sep) ? x : x + path.sep);
  if (o === r || o.startsWith(withSep(r))) throw new Error("Der Ausgabeordner darf nicht im Repo liegen.");
  if (r.startsWith(withSep(o))) throw new Error("Der Ausgabeordner darf das Repo nicht enthalten.");
  if (!/^[0-9A-Za-z][0-9A-Za-z._-]*$/.test(version)) throw new Error(`Ungueltige Version: ${version}`);
  if (existsSync(o)) {
    const rest = readdirSync(o).filter((n) => n !== "Lucid");
    if (rest.length) throw new Error(`${o} enthaelt Fremdes (${rest.slice(0, 3).join(", ")}); Abbruch.`);
  }
  const ignore = readIgnore(readFileSync(path.join(r, ".pkgmeta"), "utf8"));
  const dest = path.join(o, "Lucid");
  rmSync(dest, { recursive: true, force: true });
  mkdirSync(dest, { recursive: true });
  const files = [];
  for (const rel of walk(r)) {
    if (ignore.some((i) => rel === i || rel.startsWith(`${i}/`))) continue;
    const to = packagePath(rel);
    if (!to) throw new Error(`Weder ignoriert noch Teil des Pakets: ${rel} (.pkgmeta pruefen)`);
    mkdirSync(path.dirname(path.join(dest, to)), { recursive: true });
    cpSync(path.join(r, rel), path.join(dest, to));
    files.push(to);
  }
  const tocPath = path.join(dest, "Lucid.toc");
  writeFileSync(tocPath, packageToc(readFileSync(tocPath, "utf8"), version));
  // jede Datei der Paket-TOC muss im Paket liegen
  const toc = readFileSync(tocPath, "utf8").split(/\r?\n/).map((l) => l.trim()).filter((l) => l && !l.startsWith("#"));
  const have = new Set(files.map((f) => f.split("/").join("\\")));
  const missing = toc.filter((f) => !have.has(f));
  if (missing.length) throw new Error(`TOC nennt Dateien, die im Paket fehlen: ${missing.join(", ")}`);
  return files.sort();
}

function main() {
  const argv = process.argv.slice(2);
  const opt = (name) => { const i = argv.indexOf(name); return i >= 0 ? argv[i + 1] : undefined; };
  try {
    if (!opt("--out")) throw new Error("Aufruf: node scripts/build-package.mjs --out <ordner> [--version 1.0.0-rc1]");
    const version = opt("--version") ?? "0.0.0-local";
    const files = buildPackage({ out: opt("--out"), version });
    console.log(`Paket gebaut: ${path.resolve(opt("--out"), "Lucid")} (Version ${version}, ${files.length} Dateien)`);
  } catch (e) {
    console.error(`FEHLER: ${e instanceof Error ? e.message : String(e)}`);
    process.exit(1);
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
