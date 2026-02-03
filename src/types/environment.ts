// Type Environment - Symbol tables for type checking
import type { Type, ObjectType, FunctionType, TypeParameter, ContextBinding } from "./types";
import { Types } from "./types";

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

  constructor(parent: TypeEnvironment | null = null) {
    this.parent = parent;
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
   * Resolve a type reference to its actual type
   */
  resolveType(type: Type): Type {
    if (type.kind === "ref") {
      const resolved = this.lookupType(type.name);
      if (!resolved) {
        // Return the ref as-is if not found (might be forward reference)
        return type;
      }
      // TODO: Handle generic arguments
      return resolved;
    }
    return type;
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

export function createGlobalEnvironment(): TypeEnvironment {
  const env = new TypeEnvironment();

  // Primitive types
  env.defineType("number", Types.number);
  env.defineType("string", Types.string);
  env.defineType("bool", Types.bool);
  env.defineType("null", Types.null);
  env.defineType("bytes", Types.bytes);
  env.defineType("any", Types.any);
  env.defineType("never", Types.never);
  env.defineType("void", Types.void);

  // Built-in generic types (as type constructors)
  // list[T], map[K,V], set[T] are handled specially

  // Error type
  const errorType: ObjectType = {
    kind: "object",
    name: "Error",
    properties: [
      Types.prop("message", Types.string),
      Types.prop("cause", Types.optional(Types.ref("Error")), true),
      Types.prop("stack", Types.optional(Types.string), true),
    ],
    methods: [],
  };
  env.defineType("Error", errorType);

  // Built-in functions
  // Collections
  env.define("len", Types.fn([Types.param("x", Types.any)], Types.number));
  env.define("keys", Types.fn([Types.param("map", Types.map(Types.any, Types.any))], Types.list(Types.any)));
  env.define("values", Types.fn([Types.param("map", Types.map(Types.any, Types.any))], Types.list(Types.any)));
  env.define("entries", Types.fn([Types.param("map", Types.map(Types.any, Types.any))], Types.list(Types.any)));
  env.define("contains", Types.fn([Types.param("list", Types.list(Types.any)), Types.param("item", Types.any)], Types.bool));
  env.define("unique", Types.fn([Types.param("list", Types.list(Types.any))], Types.list(Types.any)));
  env.define("flatten", Types.fn([Types.param("list", Types.list(Types.any))], Types.list(Types.any)));
  env.define("sort", Types.fn([Types.param("list", Types.list(Types.any))], Types.list(Types.any)));
  env.define("reverse", Types.fn([Types.param("list", Types.list(Types.any))], Types.list(Types.any)));
  env.define("first", Types.fn([Types.param("list", Types.list(Types.any))], Types.optional(Types.any)));
  env.define("last", Types.fn([Types.param("list", Types.list(Types.any))], Types.optional(Types.any)));
  env.define("take", Types.fn([Types.param("list", Types.list(Types.any)), Types.param("n", Types.number)], Types.list(Types.any)));
  env.define("drop", Types.fn([Types.param("list", Types.list(Types.any)), Types.param("n", Types.number)], Types.list(Types.any)));
  env.define("zip", Types.fn([Types.param("a", Types.list(Types.any)), Types.param("b", Types.list(Types.any))], Types.list(Types.any)));
  env.define("range", Types.fn([Types.param("start", Types.number), Types.param("end", Types.number)], Types.list(Types.number)));
  env.define("slice", Types.fn([Types.param("list", Types.list(Types.any)), Types.param("start", Types.number), Types.param("end", Types.number, true)], Types.list(Types.any)));
  env.define("concat", Types.fn([Types.param("lists", Types.list(Types.any), false, true)], Types.list(Types.any)));

  // Higher-order functions
  env.define("map", Types.fn([
    Types.param("list", Types.list(Types.any)),
    Types.param("f", Types.fn([Types.param("item", Types.any)], Types.any)),
  ], Types.list(Types.any)));
  env.define("each", Types.fn([
    Types.param("list", Types.list(Types.any)),
    Types.param("f", Types.fn([Types.param("item", Types.any)], Types.any)),
  ], Types.list(Types.any)));
  env.define("filter", Types.fn([
    Types.param("list", Types.list(Types.any)),
    Types.param("pred", Types.fn([Types.param("item", Types.any)], Types.bool)),
  ], Types.list(Types.any)));
  env.define("reduce", Types.fn([
    Types.param("list", Types.list(Types.any)),
    Types.param("init", Types.any),
    Types.param("f", Types.fn([Types.param("acc", Types.any), Types.param("item", Types.any)], Types.any)),
  ], Types.any));
  env.define("find", Types.fn([
    Types.param("list", Types.list(Types.any)),
    Types.param("pred", Types.fn([Types.param("item", Types.any)], Types.bool)),
  ], Types.optional(Types.any)));
  env.define("any", Types.fn([
    Types.param("list", Types.list(Types.any)),
    Types.param("pred", Types.fn([Types.param("item", Types.any)], Types.bool)),
  ], Types.bool));
  env.define("all", Types.fn([
    Types.param("list", Types.list(Types.any)),
    Types.param("pred", Types.fn([Types.param("item", Types.any)], Types.bool)),
  ], Types.bool));
  env.define("group_by", Types.fn([
    Types.param("list", Types.list(Types.any)),
    Types.param("f", Types.fn([Types.param("item", Types.any)], Types.any)),
  ], Types.map(Types.any, Types.list(Types.any))));
  env.define("sort_by", Types.fn([
    Types.param("list", Types.list(Types.any)),
    Types.param("f", Types.fn([Types.param("item", Types.any)], Types.any)),
  ], Types.list(Types.any)));

  // String functions
  env.define("upper", Types.fn([Types.param("s", Types.string)], Types.string));
  env.define("lower", Types.fn([Types.param("s", Types.string)], Types.string));
  env.define("trim", Types.fn([Types.param("s", Types.string)], Types.string));
  env.define("split", Types.fn([Types.param("s", Types.string), Types.param("delim", Types.string)], Types.list(Types.string)));
  env.define("join", Types.fn([Types.param("list", Types.list(Types.string)), Types.param("delim", Types.string)], Types.string));
  env.define("replace", Types.fn([Types.param("s", Types.string), Types.param("old", Types.string), Types.param("new", Types.string)], Types.string));
  env.define("starts_with", Types.fn([Types.param("s", Types.string), Types.param("prefix", Types.string)], Types.bool));
  env.define("ends_with", Types.fn([Types.param("s", Types.string), Types.param("suffix", Types.string)], Types.bool));
  env.define("substring", Types.fn([Types.param("s", Types.string), Types.param("start", Types.number), Types.param("end", Types.number, true)], Types.string));
  env.define("matches", Types.fn([Types.param("s", Types.string), Types.param("pattern", Types.string)], Types.bool));

  // Number functions
  env.define("abs", Types.fn([Types.param("n", Types.number)], Types.number));
  env.define("min", Types.fn([Types.param("a", Types.number), Types.param("b", Types.number)], Types.number));
  env.define("max", Types.fn([Types.param("a", Types.number), Types.param("b", Types.number)], Types.number));
  env.define("floor", Types.fn([Types.param("n", Types.number)], Types.number));
  env.define("ceil", Types.fn([Types.param("n", Types.number)], Types.number));
  env.define("round", Types.fn([Types.param("n", Types.number)], Types.number));
  env.define("clamp", Types.fn([Types.param("n", Types.number), Types.param("lo", Types.number), Types.param("hi", Types.number)], Types.number));
  env.define("sqrt", Types.fn([Types.param("n", Types.number)], Types.number));
  env.define("pow", Types.fn([Types.param("base", Types.number), Types.param("exp", Types.number)], Types.number));
  env.define("random", Types.fn([], Types.number));
  env.define("random_int", Types.fn([Types.param("min", Types.number), Types.param("max", Types.number)], Types.number));

  // Utility functions
  env.define("print", Types.fn([Types.param("args", Types.any, false, true)], Types.void));
  env.define("log", Types.fn([Types.param("args", Types.any, false, true)], Types.void));
  env.define("now", Types.fn([], Types.number));
  env.define("sleep", Types.fn([Types.param("ms", Types.number)], Types.void));
  env.define("typeof", Types.fn([Types.param("x", Types.any)], Types.string));
  env.define("clone", Types.fn([Types.param("x", Types.any)], Types.any));
  env.define("equals", Types.fn([Types.param("a", Types.any), Types.param("b", Types.any)], Types.bool));
  env.define("hash", Types.fn([Types.param("x", Types.any)], Types.number));

  // Conversion functions
  env.define("to_str", Types.fn([Types.param("x", Types.any)], Types.string));
  env.define("to_num", Types.fn([Types.param("s", Types.string)], Types.number));
  env.define("to_json", Types.fn([Types.param("x", Types.any)], Types.string));
  env.define("from_json", Types.fn([Types.param("s", Types.string)], Types.any));

  // Concurrency functions
  env.define("spawn", Types.fn([Types.param("f", Types.fn([], Types.any))], Types.promise(Types.any)));
  // Note: 'all' is already defined as higher-order function for lists
  // For Promise.all, use await_all or call all() with promises
  env.define("race", Types.fn([Types.param("promises", Types.list(Types.promise(Types.any)))], Types.promise(Types.any)));
  env.define("timeout", Types.fn([Types.param("ms", Types.number), Types.param("promise", Types.promise(Types.any))], Types.promise(Types.any)));
  env.define("delay", Types.fn([Types.param("ms", Types.number)], Types.promise(Types.void)));

  // Channel constructor
  env.define("Channel", Types.fn([Types.param("buffer", Types.number, true)], Types.channel(Types.any)));

  // Set functions
  env.define("set", Types.fn([Types.param("list", Types.list(Types.any))], Types.set(Types.any)));
  env.define("union", Types.fn([Types.param("a", Types.set(Types.any)), Types.param("b", Types.set(Types.any))], Types.set(Types.any)));
  env.define("intersect", Types.fn([Types.param("a", Types.set(Types.any)), Types.param("b", Types.set(Types.any))], Types.set(Types.any)));
  env.define("difference", Types.fn([Types.param("a", Types.set(Types.any)), Types.param("b", Types.set(Types.any))], Types.set(Types.any)));
  env.define("is_subset", Types.fn([Types.param("a", Types.set(Types.any)), Types.param("b", Types.set(Types.any))], Types.bool));

  // Assert (for testing)
  env.define("assert", Types.fn([Types.param("value", Types.any), Types.param("message", Types.string, true)], Types.any));

  // Error function
  env.define("error", Types.fn([Types.param("message", Types.string), Types.param("cause", Types.ref("Error"), true)], Types.ref("Error")));

  // Result helpers
  env.define("ok", Types.fn([Types.param("value", Types.any)], Types.result(Types.any, Types.any)));
  env.define("err", Types.fn([Types.param("error", Types.any)], Types.result(Types.any, Types.any)));

  return env;
}
