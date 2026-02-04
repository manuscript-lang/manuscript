// Manuscript Type System
// Represents types at compile time for type checking and inference

// ============================================
// Base Type Interface
// ============================================

export interface BaseType {
  kind: string;
}

// ============================================
// Primitive Types
// ============================================

export interface NumberType extends BaseType {
  kind: "number";
}

export interface StringType extends BaseType {
  kind: "string";
}

export interface BoolType extends BaseType {
  kind: "bool";
}

export interface NullType extends BaseType {
  kind: "null";
}

export interface BytesType extends BaseType {
  kind: "bytes";
}

// ============================================
// Special Types
// ============================================

export interface AnyType extends BaseType {
  kind: "any";
}

export interface NeverType extends BaseType {
  kind: "never";
}

export interface UnknownType extends BaseType {
  kind: "unknown";
}

export interface VoidType extends BaseType {
  kind: "void";
}

// ============================================
// Composite Types
// ============================================

export interface ListType extends BaseType {
  kind: "list";
  elementType: Type;
}

export interface MapType extends BaseType {
  kind: "map";
  keyType: Type;
  valueType: Type;
}

export interface SetType extends BaseType {
  kind: "set";
  elementType: Type;
}

export interface TupleType extends BaseType {
  kind: "tuple";
  elements: Type[];
}

// ============================================
// Function Types
// ============================================

export interface FunctionType extends BaseType {
  kind: "function";
  typeParams?: TypeParamDef[];
  params: ParameterType[];
  returnType: Type;
  isGenerator: boolean;
  context: ContextBinding[];
}

export interface TypeParamDef {
  name: string;
  constraint?: Type;
}

export interface ParameterType {
  name: string;
  type: Type;
  optional: boolean;
  rest: boolean;
}

export interface ContextBinding {
  name?: string;  // Binding name (e.g., "fs" in "fs: Filesystem")
  type: Type;     // The type required from context
}

// ============================================
// Object/Struct Types
// ============================================

export interface ObjectType extends BaseType {
  kind: "object";
  name?: string;  // Named type (e.g., "User")
  properties: PropertyType[];
  methods: MethodType[];
  typeParams?: TypeParameter[];
  context?: ContextBinding[];
  alias?: Type[];  // For type aliases (type Foo = Bar)
}

export interface PropertyType {
  name: string;
  type: Type;
  optional: boolean;
  computed: boolean;
  defaultValue?: boolean;  // Has default value
  embedded?: boolean;  // Go-style embedded type
  promotedFrom?: string;  // Type name if promoted from embedded type
}

export interface MethodType {
  name: string;
  type: FunctionType;
  promotedFrom?: string;  // Type name if promoted from embedded type
}

// ============================================
// Union and Intersection Types
// ============================================

export interface UnionType extends BaseType {
  kind: "union";
  types: Type[];
}

export interface IntersectionType extends BaseType {
  kind: "intersection";
  types: Type[];
}

// ============================================
// Optional Type (T?)
// ============================================

export interface OptionalType extends BaseType {
  kind: "optional";
  inner: Type;
}

// ============================================
// Literal Types
// ============================================

export interface LiteralType extends BaseType {
  kind: "literal";
  value: string | number | boolean;
}

// ============================================
// Type Parameters (Generics)
// ============================================

export interface TypeParameter {
  name: string;
  constraint?: Type;
  default?: Type;
}

export interface TypeVariable extends BaseType {
  kind: "typevar";
  name: string;
  constraint?: Type;
}

export interface GenericType extends BaseType {
  kind: "generic";
  base: Type;
  args: Type[];
}

// ============================================
// Type References (for named types)
// ============================================

export interface TypeRef extends BaseType {
  kind: "ref";
  name: string;
  args?: Type[];  // Generic arguments
}

// ============================================
// Agent Type (special)
// ============================================

export interface AgentType extends BaseType {
  kind: "agent";
  name: string;
  context: ContextBinding[];
  tools: Type[];
  config?: Type;
}

// ============================================
// Channel Type (for concurrency)
// ============================================

export interface ChannelType extends BaseType {
  kind: "channel";
  elementType: Type;
}

// ============================================
// Promise Type (for async)
// ============================================

export interface PromiseType extends BaseType {
  kind: "promise";
  resolveType: Type;
}

// ============================================
// Stream Type (for generators/iterators)
// ============================================

export interface StreamType extends BaseType {
  kind: "stream";
  elementType: Type;
}

// ============================================
// Result Type (Ok | Err)
// ============================================

export interface ResultType extends BaseType {
  kind: "result";
  okType: Type;
  errType: Type;
}

// ============================================
// Union of all types
// ============================================

export type Type =
  | NumberType
  | StringType
  | BoolType
  | NullType
  | BytesType
  | AnyType
  | NeverType
  | UnknownType
  | VoidType
  | ListType
  | MapType
  | SetType
  | TupleType
  | FunctionType
  | ObjectType
  | UnionType
  | IntersectionType
  | OptionalType
  | LiteralType
  | TypeVariable
  | GenericType
  | TypeRef
  | AgentType
  | ChannelType
  | PromiseType
  | StreamType
  | ResultType;

// ============================================
// Type Constructors (helpers)
// ============================================

export const Types = {
  number: { kind: "number" } as NumberType,
  string: { kind: "string" } as StringType,
  bool: { kind: "bool" } as BoolType,
  null: { kind: "null" } as NullType,
  bytes: { kind: "bytes" } as BytesType,
  any: { kind: "any" } as AnyType,
  never: { kind: "never" } as NeverType,
  unknown: { kind: "unknown" } as UnknownType,
  void: { kind: "void" } as VoidType,

  list(elementType: Type): ListType {
    return { kind: "list", elementType };
  },

  map(keyType: Type, valueType: Type): MapType {
    return { kind: "map", keyType, valueType };
  },

  set(elementType: Type): SetType {
    return { kind: "set", elementType };
  },

  tuple(...elements: Type[]): TupleType {
    return { kind: "tuple", elements };
  },

  fn(params: ParameterType[], returnType: Type, context: ContextBinding[] = []): FunctionType {
    return { kind: "function", params, returnType, isGenerator: false, context };
  },

  generator(params: ParameterType[], yieldType: Type, context: ContextBinding[] = []): FunctionType {
    return { 
      kind: "function", 
      params, 
      returnType: Types.stream(yieldType), 
      isGenerator: true, 
      context 
    };
  },

  object(props: PropertyType[], methods: MethodType[] = [], name?: string): ObjectType {
    return { kind: "object", name, properties: props, methods };
  },

  union(...types: Type[]): UnionType {
    // Flatten nested unions
    const flattened: Type[] = [];
    for (const t of types) {
      if (t.kind === "union") {
        flattened.push(...t.types);
      } else {
        flattened.push(t);
      }
    }
    return { kind: "union", types: flattened };
  },

  intersection(...types: Type[]): IntersectionType {
    return { kind: "intersection", types };
  },

  optional(inner: Type): OptionalType {
    // T? is sugar for T | null, but we keep OptionalType for better error messages
    return { kind: "optional", inner };
  },

  literal(value: string | number | boolean): LiteralType {
    return { kind: "literal", value };
  },

  typevar(name: string, constraint?: Type): TypeVariable {
    return { kind: "typevar", name, constraint };
  },

  generic(base: Type, args: Type[]): GenericType {
    return { kind: "generic", base, args };
  },

  ref(name: string, args?: Type[]): TypeRef {
    return { kind: "ref", name, args };
  },

  channel(elementType: Type): ChannelType {
    return { kind: "channel", elementType };
  },

  promise(resolveType: Type): PromiseType {
    return { kind: "promise", resolveType };
  },

  stream(elementType: Type): StreamType {
    return { kind: "stream", elementType };
  },

  result(okType: Type, errType: Type): ResultType {
    return { kind: "result", okType, errType };
  },

  param(name: string, type: Type, optional = false, rest = false): ParameterType {
    return { name, type, optional, rest };
  },

  prop(name: string, type: Type, optional = false): PropertyType {
    return { name, type, optional, computed: false };
  },
};

// ============================================
// Type Utilities
// ============================================

/**
 * Check if a type is a primitive type
 */
export function isPrimitive(type: Type): boolean {
  return ["number", "string", "bool", "null", "bytes"].includes(type.kind);
}

/**
 * Check if a type is nullable (can be null)
 */
export function isNullable(type: Type): boolean {
  if (type.kind === "null") return true;
  if (type.kind === "optional") return true;
  if (type.kind === "union") {
    return type.types.some(t => t.kind === "null");
  }
  return false;
}

/**
 * Get the non-null version of a type
 */
export function nonNull(type: Type): Type {
  if (type.kind === "optional") return type.inner;
  if (type.kind === "union") {
    const nonNullTypes = type.types.filter(t => t.kind !== "null");
    if (nonNullTypes.length === 1) return nonNullTypes[0]!;
    return Types.union(...nonNullTypes);
  }
  return type;
}

/**
 * Convert a type to a human-readable string
 */
export function typeToString(type: Type): string {
  switch (type.kind) {
    case "number":
    case "string":
    case "bool":
    case "null":
    case "bytes":
    case "any":
    case "never":
    case "unknown":
    case "void":
      return type.kind;

    case "list":
      return `list[${typeToString(type.elementType)}]`;

    case "map":
      return `map[${typeToString(type.keyType)}, ${typeToString(type.valueType)}]`;

    case "set":
      return `set[${typeToString(type.elementType)}]`;

    case "tuple":
      return `(${type.elements.map(typeToString).join(", ")})`;

    case "function": {
      const params = type.params.map(p => {
        let s = p.name;
        if (p.optional) s += "?";
        s += ": " + typeToString(p.type);
        if (p.rest) s = "..." + s;
        return s;
      }).join(", ");
      const ret = typeToString(type.returnType);
      const ctx = type.context.length > 0
        ? ` using (${type.context.map(c => c.name ? `${c.name}: ${typeToString(c.type)}` : typeToString(c.type)).join(", ")})`
        : "";
      return `fn(${params}): ${ret}${ctx}`;
    }

    case "object":
      return type.name ?? "{ ... }";

    case "union":
      return type.types.map(typeToString).join(" | ");

    case "intersection":
      return type.types.map(typeToString).join(" & ");

    case "optional":
      return `${typeToString(type.inner)}?`;

    case "literal":
      return typeof type.value === "string" ? `"${type.value}"` : String(type.value);

    case "typevar":
      return type.name;

    case "generic":
      return `${typeToString(type.base)}[${type.args.map(typeToString).join(", ")}]`;

    case "ref":
      return type.args
        ? `${type.name}[${type.args.map(typeToString).join(", ")}]`
        : type.name;

    case "agent":
      return `agent ${type.name}`;

    case "channel":
      return `Channel[${typeToString(type.elementType)}]`;

    case "promise":
      return `Promise[${typeToString(type.resolveType)}]`;

    case "stream":
      return `Stream[${typeToString(type.elementType)}]`;

    case "result":
      return `Result[${typeToString(type.okType)}, ${typeToString(type.errType)}]`;

    default:
      return "unknown";
  }
}
