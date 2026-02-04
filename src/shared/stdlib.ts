// Standard Library Function Registry
// Derives stdlib functions and types from stdlib.ms for single source of truth

import { Parser } from "../parser";
import { getStdlibFunctionNames, getExternFunctionNames, getExternTypeNames } from "../stdlib/extractor";
import { stdlibSource } from "../stdlib";
import { PRIMITIVE_TYPE_MAP } from "../types/primitives";

// Parse stdlib once and extract names
const stdlibProgram = new Parser(stdlibSource).parse();

// All stdlib function names (for type checking)
export const STDLIB_FUNCTIONS = getStdlibFunctionNames(stdlibProgram);

// Only extern functions need runtime implementation
export const EXTERN_FUNCTIONS = getExternFunctionNames(stdlibProgram);

// Extern type names (extracted from stdlib.ms, replaces hardcoded BUILTIN_CONSTRUCTORS)
export const EXTERN_TYPES = getExternTypeNames(stdlibProgram);

// Check if name is a built-in (used by analyzer)
export function isBuiltin(name: string): boolean {
  return STDLIB_FUNCTIONS.has(name) || 
         PRIMITIVE_TYPE_MAP[name] !== undefined || 
         EXTERN_TYPES.has(name);
}
