/**
 * True when running as a standalone compiled binary (bun build --compile).
 * False when running from source (e.g. bun run bin/manuscript.ts).
 */
export function isCompiledBinary(): boolean {
  return typeof Bun !== "undefined" && Array.isArray(Bun.embeddedFiles) && Bun.embeddedFiles.length > 0;
}
