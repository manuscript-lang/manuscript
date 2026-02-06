// Standard Library Function Registry
// Derives builtin functions and types from builtins.ms for single source of truth

import { Parser } from "../parser";
import { getStdlibFunctionNames, getExternFunctionNames, getExternTypeNames } from "../builtin/extractor";
import { builtinsSource } from "../builtin";
import { PRIMITIVE_TYPE_MAP } from "../types/primitives";

const builtinsProgram = new Parser(builtinsSource).parse();

export const STDLIB_FUNCTIONS = getStdlibFunctionNames(builtinsProgram);

// Only extern functions need runtime implementation
export const EXTERN_FUNCTIONS = getExternFunctionNames(builtinsProgram);

export const EXTERN_TYPES = getExternTypeNames(builtinsProgram);

// Check if name is a built-in (used by analyzer)
export function isBuiltin(name: string): boolean {
  return STDLIB_FUNCTIONS.has(name) || 
         PRIMITIVE_TYPE_MAP[name] !== undefined || 
         EXTERN_TYPES.has(name);
}
