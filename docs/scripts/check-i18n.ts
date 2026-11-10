/**
 * Checks that the English translation stays in sync with the French source docs.
 *
 * For every page under docs/docs, the English copy under
 * i18n/en/docusaurus-plugin-content-docs/current must exist and contain the same
 * number of "##" and "###" headings. Headings inside fenced code blocks are ignored.
 * A translated version label, if any, must match the version in fxmanifest.lua.
 *
 * Usage: bun run check:i18n   (exits with 1 when a page drifts)
 */
import { readdirSync, readFileSync, existsSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { readOrvexVersion } from "./orvex-version";

const DOCS_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const SOURCE_DIR = join(DOCS_ROOT, "docs");
const TRANSLATION_DIR = join(DOCS_ROOT, "i18n/en/docusaurus-plugin-content-docs/current");
const VERSION_LABELS_PATH = join(DOCS_ROOT, "i18n/en/docusaurus-plugin-content-docs/current.json");
const CHECKED_LEVELS = [2, 3] as const;

type HeadingCounts = Record<(typeof CHECKED_LEVELS)[number], number>;

function listMarkdownPages(dir: string): string[] {
  return readdirSync(dir, { recursive: true, encoding: "utf8" })
    .filter((path) => /\.mdx?$/.test(path))
    .sort();
}

function stripFencedCode(markdown: string): string {
  return markdown.replace(/^(```|~~~)[^\n]*\n[\s\S]*?^\1[^\n]*$/gm, "");
}

function countHeadings(markdown: string): HeadingCounts {
  const prose = stripFencedCode(markdown);
  const counts = {} as HeadingCounts;
  for (const level of CHECKED_LEVELS) {
    const pattern = new RegExp(`^#{${level}}\\s`, "gm");
    counts[level] = prose.match(pattern)?.length ?? 0;
  }
  return counts;
}

function describeDrift(page: string): string[] {
  const translatedPath = join(TRANSLATION_DIR, page);
  if (!existsSync(translatedPath)) {
    return [`${page}: missing English translation (${relative(DOCS_ROOT, translatedPath)})`];
  }
  const source = countHeadings(readFileSync(join(SOURCE_DIR, page), "utf8"));
  const translated = countHeadings(readFileSync(translatedPath, "utf8"));
  return CHECKED_LEVELS.filter((level) => source[level] !== translated[level]).map(
    (level) =>
      `${page}: ${"#".repeat(level)} headings differ (fr ${source[level]}, en ${translated[level]})`,
  );
}

function describeOrphans(sourcePages: string[]): string[] {
  const known = new Set(sourcePages);
  return listMarkdownPages(TRANSLATION_DIR)
    .filter((page) => !known.has(page))
    .map((page) => `${page}: English page has no French source`);
}

function describeStaleVersionLabel(): string[] {
  const labels = JSON.parse(readFileSync(VERSION_LABELS_PATH, "utf8")) as Record<string, { message: string }>;
  const translated = labels["version.label"]?.message;
  const expected = readOrvexVersion();
  if (translated === undefined || translated === expected) return [];
  return [
    `${relative(DOCS_ROOT, VERSION_LABELS_PATH)}: version label is ${translated}, fxmanifest.lua says ${expected}`,
  ];
}

const pages = listMarkdownPages(SOURCE_DIR);
const problems = [
  ...pages.flatMap(describeDrift),
  ...describeOrphans(pages),
  ...describeStaleVersionLabel(),
];

if (problems.length > 0) {
  console.error(`i18n drift found in ${problems.length} place(s):`);
  for (const problem of problems) console.error(`  - ${problem}`);
  process.exit(1);
}

console.log(`i18n OK: ${pages.length} pages have matching ## and ### heading counts.`);
