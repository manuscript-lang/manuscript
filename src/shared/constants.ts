// Shared language constants and predicates

export const BUILTIN_PRIMITIVE_TYPES = ["number", "string", "bool", "null", "bytes", "unknown", "never", "void"];

export const NAME_OFFSET_FN = 3;
export const NAME_OFFSET_EXTERN_FN = 10;
export const NAME_OFFSET_TYPE = 5;
export const NAME_OFFSET_LET_VAR = 4;
export const NAME_OFFSET_INTERFACE = 10;

export function isStdlibImport(specifier: string): boolean {
  return specifier.startsWith("std/");
}
