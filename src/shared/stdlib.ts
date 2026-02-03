// Standard Library Function Registry
// Derives stdlib functions from stdlib.ms for single source of truth

import { Parser } from "../parser";
import { getStdlibFunctionNames } from "../stdlib/extractor";
import { stdlibSource } from "../stdlib";

// Parse stdlib once and extract function names
const stdlibProgram = new Parser(stdlibSource).parse();

// Stdlib function names derived from stdlib.ms
export const STDLIB_FUNCTIONS = getStdlibFunctionNames(stdlibProgram);

// Built-in type names
const BUILTIN_TYPES = new Set([
  "number", "string", "bool", "null", "bytes", "any",
  "list", "map", "set", "tuple", "result", "promise", "channel", "stream",
]);

// Capability/context constructors
export const BUILTIN_CONSTRUCTORS = new Set([
  "Claude", "GPT", "MockLLM",
  "LocalFilesystem", "Filesystem", "MockFilesystem",
  "LocalShell", "Shell", "MockShell",
  "FetchHTTP", "HTTP", "MockHTTP",
  "Channel",
]);

// Check if name is a built-in (used by analyzer)
export function isBuiltin(name: string): boolean {
  return STDLIB_FUNCTIONS.has(name) || BUILTIN_TYPES.has(name) || BUILTIN_CONSTRUCTORS.has(name);
}
