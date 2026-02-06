// Shared language constants and predicates

export function isStdlibImport(specifier: string): boolean {
  return specifier.startsWith("std/");
}
