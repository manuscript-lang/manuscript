// Type Environment - Symbol tables for type checking
import type { Type, ObjectType, FunctionType, TypeParameter, ContextBinding } from "./types";
import { Types } from "./types";
import { substituteTypeParams, substituteTypeInObject } from "./type-utils";
import { Parser } from "../parser";
import { extractStdlibTypes } from "../stdlib/extractor";
import { stdlibSource } from "../stdlib";
import { PRIMITIVE_TYPE_MAP, type BuiltinMethodRegistry, type BuiltinMemberInfo } from "./primitives";

// ============================================
// Symbol Entry
// ============================================

export interface Symbol {
  name: string;
  type: Type;
  mutable: boolean;  // var vs let
  defined: boolean;  // Has been assigned
}

// ============================================
// Type Environment (Scope)
// ============================================

export class TypeEnvironment {
  private symbols: Map<string, Symbol> = new Map();
  private types: Map<string, Type> = new Map();
  private typeParams: Map<string, Type> = new Map();
  private parent: TypeEnvironment | null;
  private builtinMethods: BuiltinMethodRegistry | null = null;

  constructor(parent: TypeEnvironment | null = null) {
    this.parent = parent;
  }

  // Set builtin method registry (called during global env setup)
  setBuiltinMethods(registry: BuiltinMethodRegistry): void {
    this.builtinMethods = registry;
  }

  // Look up a builtin method/property by type kind and member name
  lookupBuiltinMethod(typeKind: string, memberName: string): BuiltinMemberInfo | undefined {
    if (this.builtinMethods) {
      const members = this.builtinMethods.get(typeKind);
      if (members) {
        return members.get(memberName);
      }
    }
    if (this.parent) {
      return this.parent.lookupBuiltinMethod(typeKind, memberName);
    }
    return undefined;
  }

  // ============================================
  // Variable/Symbol Operations
  // ============================================

  /**
   * Define a new variable in the current scope
   */
  define(name: string, type: Type, mutable: boolean = false): void {
    if (this.symbols.has(name)) {
      throw new TypeError(`Variable '${name}' is already defined in this scope`);
    }
    this.symbols.set(name, { name, type, mutable, defined: true });
  }

  /**
   * Look up a variable in the current or parent scopes
   */
  lookup(name: string): Symbol | undefined {
    const symbol = this.symbols.get(name);
    if (symbol) return symbol;
    if (this.parent) return this.parent.lookup(name);
    return undefined;
  }

  /**
   * Check if a variable is defined (in any scope)
   */
  isDefined(name: string): boolean {
    return this.lookup(name) !== undefined;
  }

  /**
   * Get the type of a variable
   */
  getType(name: string): Type | undefined {
    return this.lookup(name)?.type;
  }

  /**
   * Check if a variable is mutable
   */
  isMutable(name: string): boolean {
    return this.lookup(name)?.mutable ?? false;
  }

  // ============================================
  // Type Definition Operations
  // ============================================

  /**
   * Define a named type (type declaration)
   */
  defineType(name: string, type: Type): void {
    if (this.types.has(name)) {
      throw new TypeError(`Type '${name}' is already defined in this scope`);
    }
    this.types.set(name, type);
  }

  /**
   * Look up a type definition
   */
  lookupType(name: string): Type | undefined {
    const type = this.types.get(name);
    if (type) return type;
    if (this.parent) return this.parent.lookupType(name);
    return undefined;
  }

  /**
   * Resolve a type reference to its actual type.
   * When ref has generic args, substitutes type params into the resolved type.
   */
  resolveType(type: Type): Type {
    if (type.kind !== "ref") return type;
    const resolved = this.lookupType(type.name);
    if (!resolved) return type;
    if (!type.args?.length) return resolved;
    const typeParams = resolved.kind === "object" ? resolved.typeParams : undefined;
    if (!typeParams?.length) return resolved;
    const bindings = new Map<string, Type>();
    for (let i = 0; i < typeParams.length && i < type.args.length; i++) {
      bindings.set(typeParams[i]!.name, type.args[i]!);
    }
    if (resolved.kind === "object") return substituteTypeInObject(resolved, bindings);
    return substituteTypeParams(resolved, bindings);
  }

  // ============================================
  // Type Parameter Operations (for generics)
  // ============================================

  /**
   * Bind a type parameter to a concrete type
   */
  bindTypeParam(name: string, type: Type): void {
    this.typeParams.set(name, type);
  }

  /**
   * Look up a type parameter binding
   */
  lookupTypeParam(name: string): Type | undefined {
    const type = this.typeParams.get(name);
    if (type) return type;
    if (this.parent) return this.parent.lookupTypeParam(name);
    return undefined;
  }

  /**
   * Substitute type parameters in a type
   */
  substitute(type: Type): Type {
    switch (type.kind) {
      case "typevar": {
        const bound = this.lookupTypeParam(type.name);
        return bound ?? type;
      }
      case "list":
        return Types.list(this.substitute(type.elementType));
      case "map":
        return Types.map(this.substitute(type.keyType), this.substitute(type.valueType));
      case "set":
        return Types.set(this.substitute(type.elementType));
      case "optional":
        return Types.optional(this.substitute(type.inner));
      case "union":
        return Types.union(...type.types.map(t => this.substitute(t)));
      case "function":
        return {
          ...type,
          params: type.params.map(p => ({ ...p, type: this.substitute(p.type) })),
          returnType: this.substitute(type.returnType),
        };
      case "generic":
        return Types.generic(this.substitute(type.base), type.args.map(a => this.substitute(a)));
      default:
        return type;
    }
  }

  // ============================================
  // Scope Operations
  // ============================================

  /**
   * Create a child scope
   */
  child(): TypeEnvironment {
    return new TypeEnvironment(this);
  }

  /**
   * Create a child scope with context bindings
   * Context bindings are just regular variable bindings
   */
  withContext(bindings: ContextBinding[]): TypeEnvironment {
    const child = this.child();
    for (const binding of bindings) {
      if (binding.name) {
        child.define(binding.name, binding.type, false);
      }
    }
    return child;
  }

  /**
   * Get the parent scope
   */
  getParent(): TypeEnvironment | null {
    return this.parent;
  }
}

// ============================================
// Global Environment with Builtins
// ============================================

// Cache for parsed stdlib types (parse once)
let stdlibTypesCache: ReturnType<typeof extractStdlibTypes> | null = null;

export function getStdlibTypes() {
  if (!stdlibTypesCache) {
    const program = new Parser(stdlibSource).parse();
    stdlibTypesCache = extractStdlibTypes(program);
  }
  return stdlibTypesCache;
}

export function createGlobalEnvironment(): TypeEnvironment {
  const env = new TypeEnvironment();

  // Primitive types from centralized map
  for (const [name, type] of Object.entries(PRIMITIVE_TYPE_MAP)) {
    env.defineType(name, type);
  }

  // Load types and functions from stdlib.ms
  const stdlib = getStdlibTypes();

  // Set builtin method registry
  env.setBuiltinMethods(stdlib.builtinMethods);

  // Register type declarations from stdlib (skip primitives - already defined)
  const primitiveNames = new Set(Object.keys(PRIMITIVE_TYPE_MAP));
  for (const [name, type] of stdlib.types) {
    // Skip primitive extern types - their internal types are already defined
    if (primitiveNames.has(name)) continue;
    env.defineType(name, type);
  }

  // Register function declarations from stdlib
  for (const [name, type] of stdlib.functions) {
    env.define(name, type);
  }

  return env;
}
