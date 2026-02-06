// Builtins module - imports source from builtins.ms at build time
import builtinsSourceContent from "./builtins.ms" with { type: "text" };
import type * as AST from "../parser/ast";
import { parseAndExtractTypes, type BuiltinsTypes } from "./extractor";
import { PRIMITIVE_TYPE_MAP } from "../types/primitives";

export const BUILTINS_PATH_URI = `manuscript://builtins.ms`;
export const builtinsSource = builtinsSourceContent;

let builtinsCache: { ast: AST.Program; types: BuiltinsTypes } | null = null;

function ensureBuiltinsCache(): { ast: AST.Program; types: BuiltinsTypes } {
  if (!builtinsCache) builtinsCache = parseAndExtractTypes(builtinsSource);
  return builtinsCache;
}

export function getBuiltinsAST(): AST.Program {
  return ensureBuiltinsCache().ast;
}

export function getBuiltinsTypes(): BuiltinsTypes {
  return ensureBuiltinsCache().types;
}

// Derived from getBuiltinsTypes() — no separate AST scan needed
const { functions, externTypes } = getBuiltinsTypes();
export const STDLIB_FUNCTIONS = new Set(functions.keys());
export const EXTERN_TYPES = externTypes;
export const PRIMITIVE_EXTERN_TYPES = new Set(["string", "list", "map", "set"]);

export function isBuiltin(name: string): boolean {
  return STDLIB_FUNCTIONS.has(name) ||
    PRIMITIVE_TYPE_MAP[name] !== undefined ||
    EXTERN_TYPES.has(name);
}

// Re-export for codegen layer (avoids reaching into stdlib/loader)
export { isStdlibExternType } from "../stdlib/loader";
