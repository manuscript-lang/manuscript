// Centralized Primitive Type Registry
// Single source of truth for primitive type mappings and builtin methods

import type { Type, FunctionType, PropertyType } from "./types";
import { Types } from "./types";

// Primitive type name to Type mapping
export const PRIMITIVE_TYPE_MAP: Record<string, Type> = {
  number: Types.number,
  string: Types.string,
  bool: Types.bool,
  null: Types.null,
  bytes: Types.bytes,
  any: Types.any,
  never: Types.never,
  void: Types.void,
};

// Generic type constructors for built-in types that need special internal representation
// Only types that map to JS primitives or have special language semantics
export const GENERIC_TYPE_CONSTRUCTORS: Record<string, (args: Type[]) => Type | undefined> = {
  list: (args) => args[0] ? Types.list(args[0]) : undefined,
  map: (args) => args[0] && args[1] ? Types.map(args[0], args[1]) : undefined,
  set: (args) => args[0] ? Types.set(args[0]) : undefined,
  Promise: (args) => args[0] ? Types.promise(args[0]) : undefined,
  Stream: (args) => args[0] ? Types.stream(args[0]) : undefined,
};

// Builtin method/property info
export interface BuiltinMemberInfo {
  type: FunctionType | Type;
  isProperty: boolean;
}

// Builtin method registry - maps type kind to member name to member info
export type BuiltinMethodRegistry = Map<string, Map<string, BuiltinMemberInfo>>;

// Create empty registry
export function createBuiltinMethodRegistry(): BuiltinMethodRegistry {
  return new Map();
}

// Helper to resolve primitive type name
export function resolvePrimitiveType(name: string): Type | undefined {
  return PRIMITIVE_TYPE_MAP[name];
}

// Helper to construct generic type
export function constructGenericType(name: string, args: Type[]): Type | undefined {
  const constructor = GENERIC_TYPE_CONSTRUCTORS[name];
  if (constructor) {
    return constructor(args);
  }
  return undefined;
}

// Type kind to stdlib extern type name mapping
// Maps internal type kinds to the extern type names in stdlib.ms
// Only for true primitives (string, list, map, set)
export const TYPE_KIND_TO_EXTERN_NAME: Record<string, string> = {
  string: "string",
  list: "list",
  map: "map",
  set: "set",
};
