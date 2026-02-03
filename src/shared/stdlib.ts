// Standard Library Function Registry
// Centralized list of all stdlib functions, types, and constructors

// Stdlib function names for codegen
export const STDLIB_FUNCTIONS = new Set([
  // Collections
  "len", "keys", "values", "entries", "contains", "unique", "flatten",
  "sort", "reverse", "first", "last", "take", "drop", "zip", "slice", "concat",
  "map", "each", "filter", "reduce", "find", "any", "all", "group_by", "sort_by",
  // Strings
  "upper", "lower", "trim", "split", "join", "replace",
  "starts_with", "ends_with", "substring", "matches",
  // Numbers
  "abs", "min", "max", "floor", "ceil", "round", "sqrt", "pow",
  "clamp", "random", "random_int",
  // Utility
  "print", "log", "now", "sleep", "typeof", "clone", "equals", "hash", "range",
  // Conversion
  "to_str", "to_num", "to_json", "from_json",
  // Concurrency
  "spawn", "race", "timeout", "delay",
  // Sets
  "set", "union", "intersect", "difference", "is_subset",
  // Errors
  "assert", "panic", "attempt", "error", "ok", "err",
]);

// Built-in type names
const BUILTIN_TYPES = new Set([
  "number", "string", "bool", "null", "bytes", "any",
  "list", "map", "set", "tuple", "result", "promise", "channel", "stream",
]);

// Capability/context constructors
const BUILTIN_CONSTRUCTORS = new Set([
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
