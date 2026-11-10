/**
 * Reads the OrvexORM version from fxmanifest.lua, the single source of the
 * version (the release workflow checks the tag against it).
 */
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const MANIFEST_PATH = join(dirname(fileURLToPath(import.meta.url)), "../../fxmanifest.lua");

export function readOrvexVersion(): string {
  const manifest = readFileSync(MANIFEST_PATH, "utf8");
  const version = manifest.match(/^version '([^']+)'$/m)?.[1];
  if (!version) throw new Error(`No "version '...'" line found in ${MANIFEST_PATH}`);
  return version;
}
