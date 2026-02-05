// Type Utilities - Pure functions for type operations
import * as AST from "../parser/ast";
import type { Type, FunctionType, ParameterType, ContextBinding, ObjectType, InterfaceType } from "./types";
import { Types, typeToString } from "./types";
import type { TypeEnvironment } from "./environment";
import { PRIMITIVE_TYPE_MAP, constructGenericType } from "./primitives";

// Convert AST type expression to internal Type representation
export function astTypeToType(astType: AST.TypeExpr): Type {
  switch (astType.kind) {
    case "NamedType": {
      // Check primitive type map first
      const primitiveType = PRIMITIVE_TYPE_MAP[astType.name];
      if (primitiveType) {
        return primitiveType;
      }
      // Handle unparameterized generic types
      if (astType.name === "list") return Types.list(Types.any);
      if (astType.name === "map") return Types.map(Types.any, Types.any);
      if (astType.name === "set") return Types.set(Types.any);
      return Types.ref(astType.name);
    }
    case "GenericType": {
      const args = astType.args.map(a => astTypeToType(a));
      // Use data-driven generic type constructor
      const constructed = constructGenericType(astType.name, args);
      if (constructed) {
        return constructed;
      }
      return Types.generic(Types.ref(astType.name), args);
    }
    case "FunctionType":
      return Types.fn(
        astType.params.map((p, i) => Types.param(`arg${i}`, astTypeToType(p))),
        astTypeToType(astType.returnType)
      );
    case "UnionType":
      return Types.union(...astType.types.map(t => astTypeToType(t)));
    case "OptionalType":
      return Types.optional(astTypeToType(astType.inner));
    case "ListType":
      return Types.list(astTypeToType(astType.elementType));
    case "MapType":
      return Types.map(astTypeToType(astType.keyType), astTypeToType(astType.valueType));
    case "TypePredicateExpr":
      // Type predicates return bool at runtime, but carry narrowing info
      // The predicate info is used during type checking for narrowing
      return Types.bool;
    default:
      return Types.any;
  }
}

// Resolve a type name string to a Type
export function resolveTypeName(name: string, env: TypeEnvironment): Type {
  // Check primitive type map first
  const primitiveType = PRIMITIVE_TYPE_MAP[name];
  if (primitiveType) {
    return primitiveType;
  }
  // Look up in environment
  const resolved = env.lookup(name);
  if (resolved) return resolved.type;
  return Types.ref(name);
}

// Convert function declaration to FunctionType
export function fnDeclToType(decl: AST.FnDecl): FunctionType {
  const params = decl.params.map(p => ({
    name: p.name,
    type: p.type ? astTypeToType(p.type) : Types.any,
    optional: p.optional,
    rest: p.rest,
  }));

  const returnType = decl.returnType ? astTypeToType(decl.returnType) : Types.any;

  const context: ContextBinding[] = decl.using?.bindings.map(c => ({
    name: c.name,
    type: astTypeToType(c.type),
  })) ?? [];

  const typeParams = decl.typeParams?.map(p => ({
    name: p.name,
    constraint: p.constraint ? astTypeToType(p.constraint) : undefined,
  }));

  return {
    kind: "function",
    typeParams,
    params,
    returnType,
    isGenerator: decl.isGenerator,
    context,
  };
}

// Convert method declaration to FunctionType
export function methodToFunctionType(method: AST.MethodDecl): FunctionType {
  const params = method.params.map(p => ({
    name: p.name,
    type: p.type ? astTypeToType(p.type) : Types.any,
    optional: p.optional,
    rest: p.rest,
  }));

  const returnType = method.returnType ? astTypeToType(method.returnType) : Types.any;

  const context: ContextBinding[] = method.using?.bindings.map(c => ({
    name: c.name,
    type: astTypeToType(c.type),
  })) ?? [];

  const typeParams = method.typeParams?.map(p => ({
    name: p.name,
    constraint: p.constraint ? astTypeToType(p.constraint) : undefined,
  }));

  return {
    kind: "function",
    typeParams,
    params,
    returnType,
    isGenerator: false,
    context,
  };
}

// Check if source type is assignable to target type
export function isAssignable(source: Type, target: Type, env: TypeEnvironment): boolean {
  if (source.kind === "any" || target.kind === "any") return true;
  
  // never is assignable to anything (bottom type)
  if (source.kind === "never") return true;
  // nothing is assignable to never except never itself
  if (target.kind === "never") return false;

  const resolvedSource = source.kind === "ref" ? env.resolveType(source) : source;
  const resolvedTarget = target.kind === "ref" ? env.resolveType(target) : target;

  if (resolvedSource.kind === resolvedTarget.kind) {
    switch (resolvedSource.kind) {
      case "number":
      case "string":
      case "bool":
      case "null":
      case "bytes":
      case "void":
      case "never":
        return true;
      case "ref":
        return (resolvedSource as any).name === (resolvedTarget as any).name;
      case "list":
        if ((resolvedTarget as any).elementType.kind === "any") return true;
        // Lists are invariant for mutation safety
        return isAssignable((resolvedSource as any).elementType, (resolvedTarget as any).elementType, env) &&
               isAssignable((resolvedTarget as any).elementType, (resolvedSource as any).elementType, env);
      case "map":
        if ((resolvedTarget as any).keyType.kind === "any" && (resolvedTarget as any).valueType.kind === "any") return true;
        // Maps are invariant for mutation safety
        return isAssignable((resolvedSource as any).keyType, (resolvedTarget as any).keyType, env) &&
               isAssignable((resolvedTarget as any).keyType, (resolvedSource as any).keyType, env) &&
               isAssignable((resolvedSource as any).valueType, (resolvedTarget as any).valueType, env) &&
               isAssignable((resolvedTarget as any).valueType, (resolvedSource as any).valueType, env);
      case "channel":
        if ((resolvedTarget as any).elementType.kind === "any") return true;
        // Channels are invariant (read and write)
        return isAssignable((resolvedSource as any).elementType, (resolvedTarget as any).elementType, env) &&
               isAssignable((resolvedTarget as any).elementType, (resolvedSource as any).elementType, env);
      case "promise":
        if ((resolvedTarget as any).resolveType.kind === "any") return true;
        // Promises are covariant (read-only)
        return isAssignable((resolvedSource as any).resolveType, (resolvedTarget as any).resolveType, env);
      case "set":
        if ((resolvedTarget as any).elementType.kind === "any") return true;
        // Sets are invariant for mutation safety
        return isAssignable((resolvedSource as any).elementType, (resolvedTarget as any).elementType, env) &&
               isAssignable((resolvedTarget as any).elementType, (resolvedSource as any).elementType, env);
      case "stream":
        if ((resolvedTarget as any).elementType.kind === "any") return true;
        // Streams are covariant (read-only)
        return isAssignable((resolvedSource as any).elementType, (resolvedTarget as any).elementType, env);
      case "tuple":
        return isTupleAssignable(resolvedSource as any, resolvedTarget as any, env);
      case "object":
        return isObjectAssignable(resolvedSource as ObjectType, resolvedTarget as ObjectType, env);
      case "interface": {
        const src = resolvedSource as InterfaceType;
        const tgt = resolvedTarget as InterfaceType;
        if (src.name === tgt.name) return true;
        for (const tgtMethod of tgt.methods) {
          const srcMethod = src.methods.find(m => m.name === tgtMethod.name);
          if (!srcMethod) return false;
          if (!isFunctionAssignable(srcMethod.type, tgtMethod.type, env)) return false;
        }
        return true;
      }
      case "function":
        return isFunctionAssignable(resolvedSource as FunctionType, resolvedTarget as FunctionType, env);
      case "intersection":
        return isIntersectionAssignable(resolvedSource as any, resolvedTarget as any, env);
      case "generic":
        return isGenericAssignable(resolvedSource as any, resolvedTarget as any, env);
      case "typevar":
        // Type variables match by name (same scoped variable)
        return (resolvedSource as any).name === (resolvedTarget as any).name;
      default:
        return true;
    }
  }

  // Handle cross-kind assignability
  
  // Type variable is assignable to any (or the same type variable)
  if (resolvedSource.kind === "typevar") {
    // A type variable can be assigned to any or to itself
    return resolvedTarget.kind === "any" || 
           (resolvedTarget.kind === "typevar" && (resolvedSource as any).name === (resolvedTarget as any).name);
  }
  
  // Anything can be assigned to a type variable (during unification)
  if (resolvedTarget.kind === "typevar") {
    return true;
  }
  if (resolvedSource.kind === "null" && resolvedTarget.kind === "optional") return true;

  if (resolvedTarget.kind === "optional") {
    if (resolvedSource.kind === "union") {
      const unionTypes = (resolvedSource as any).types as Type[];
      const nonNullTypes = unionTypes.filter((t: Type) => t.kind !== "null");
      if (nonNullTypes.length === unionTypes.length - 1) {
        return nonNullTypes.every((t: Type) => isAssignable(t, (resolvedTarget as any).inner, env));
      }
    }
    return isAssignable(resolvedSource, (resolvedTarget as any).inner, env);
  }

  // Union target: source must be assignable to at least one member
  if (resolvedTarget.kind === "union") {
    return (resolvedTarget as any).types.some((t: Type) => isAssignable(resolvedSource, t, env));
  }

  // Union source: all members must be assignable to target
  if (resolvedSource.kind === "union") {
    return (resolvedSource as any).types.every((t: Type) => isAssignable(t, resolvedTarget, env));
  }
  
  // Intersection source: at least one member must be assignable to target
  if (resolvedSource.kind === "intersection") {
    return (resolvedSource as any).types.some((t: Type) => isAssignable(t, resolvedTarget, env));
  }
  
  // Intersection target: source must be assignable to all members
  if (resolvedTarget.kind === "intersection") {
    return (resolvedTarget as any).types.every((t: Type) => isAssignable(resolvedSource, t, env));
  }

  // Object satisfies interface (structural): source must have all interface methods
  if (resolvedTarget.kind === "interface") {
    const concrete = resolvedSource.kind === "ref" ? env.resolveType(resolvedSource) : resolvedSource;
    if (concrete.kind !== "object") return false;
    const obj = concrete as ObjectType;
    const iface = resolvedTarget as InterfaceType;
    for (const ifaceMethod of iface.methods) {
      const objMethod = obj.methods.find(m => m.name === ifaceMethod.name);
      if (!objMethod) return false;
      if (!isFunctionAssignable(objMethod.type, ifaceMethod.type, env)) return false;
    }
    return true;
  }

  return false;
}

// Check if source object is structurally assignable to target object
function isObjectAssignable(source: ObjectType, target: ObjectType, env: TypeEnvironment): boolean {
  // Named types: exact match only (no inheritance)
  if (source.name && target.name) {
    return source.name === target.name;
  }
  
  // Named target with unnamed source: check structural compatibility
  if (target.name && !source.name) {
    for (const targetProp of target.properties) {
      if (targetProp.optional) continue;
      const sourceProp = source.properties.find(p => p.name === targetProp.name);
      if (!sourceProp) return false;
      if (!isAssignable(sourceProp.type, targetProp.type, env)) return false;
    }
    return true;
  }
  
  // Unnamed source to named target or both unnamed: structural subtyping
  for (const targetProp of target.properties) {
    if (targetProp.optional) continue;
    const sourceProp = source.properties.find(p => p.name === targetProp.name);
    if (!sourceProp) return false;
    if (!isAssignable(sourceProp.type, targetProp.type, env)) return false;
  }

  for (const targetMethod of target.methods) {
    const sourceMethod = source.methods.find(m => m.name === targetMethod.name);
    if (!sourceMethod) return false;
    if (!isFunctionAssignable(sourceMethod.type, targetMethod.type, env)) return false;
  }

  return true;
}

// Check function type assignability with proper variance
// Functions are contravariant in parameters and covariant in return type
function isFunctionAssignable(source: FunctionType, target: FunctionType, env: TypeEnvironment): boolean {
  // If source params have any `any` types, be permissive (common with untyped lambdas)
  // This maintains backward compatibility while still catching obviously wrong types
  const sourceHasAnyParam = source.params.some(p => p.type.kind === "any");
  if (sourceHasAnyParam) return true;
  
  // Check parameter counts (source can have fewer required params)
  const sourceRequired = source.params.filter(p => !p.optional && !p.rest).length;
  const targetRequired = target.params.filter(p => !p.optional && !p.rest).length;
  
  if (sourceRequired > targetRequired) return false;
  
  // Check each parameter (contravariant: target param must be assignable to source param)
  for (let i = 0; i < target.params.length; i++) {
    const targetParam = target.params[i]!;
    const sourceParam = source.params[i];
    
    if (!sourceParam) {
      // Source doesn't have this param - OK if target param is optional
      if (!targetParam.optional && !targetParam.rest) return false;
      continue;
    }
    
    // Contravariance: target param type must be assignable to source param type
    if (!isAssignable(targetParam.type, sourceParam.type, env)) {
      return false;
    }
  }
  
  // Check return type (covariant: source return must be assignable to target return)
  if (!isAssignable(source.returnType, target.returnType, env)) return false;
  
  return true;
}

// Check tuple assignability
function isTupleAssignable(source: { elements: Type[] }, target: { elements: Type[] }, env: TypeEnvironment): boolean {
  if (source.elements.length !== target.elements.length) return false;
  for (let i = 0; i < source.elements.length; i++) {
    if (!isAssignable(source.elements[i]!, target.elements[i]!, env)) return false;
  }
  return true;
}

// Check intersection assignability
function isIntersectionAssignable(source: { types: Type[] }, target: { types: Type[] }, env: TypeEnvironment): boolean {
  // Source intersection is assignable to target intersection if
  // for each type in target, there's a compatible type in source
  for (const targetType of target.types) {
    const hasMatch = source.types.some(st => isAssignable(st, targetType, env));
    if (!hasMatch) return false;
  }
  return true;
}

// Check generic type assignability (e.g., Result[T, E] to Result[T, never])
function isGenericAssignable(source: { base: Type; args: Type[] }, target: { base: Type; args: Type[] }, env: TypeEnvironment): boolean {
  // Base types must be assignable
  if (!isAssignable(source.base, target.base, env)) return false;
  
  // Check each type argument (covariant for now)
  // If lengths differ, compare available args
  const minLen = Math.min(source.args.length, target.args.length);
  for (let i = 0; i < minLen; i++) {
    if (!isAssignable(source.args[i]!, target.args[i]!, env)) return false;
  }
  
  return true;
}

// Check structural equality of two types
export function typesEqual(a: Type, b: Type): boolean {
  if (a.kind !== b.kind) return false;

  switch (a.kind) {
    case "number":
    case "string":
    case "bool":
    case "null":
    case "bytes":
    case "void":
    case "any":
    case "never":
      return true;
    case "ref":
      return (a as any).name === (b as any).name;
    case "list":
      return typesEqual((a as any).elementType, (b as any).elementType);
    case "map":
      return typesEqual((a as any).keyType, (b as any).keyType) &&
             typesEqual((a as any).valueType, (b as any).valueType);
    case "optional":
      return typesEqual((a as any).inner, (b as any).inner);
    case "function":
      const fa = a as FunctionType, fb = b as FunctionType;
      return paramsMatch(fa.params, fb.params) &&
             typesEqual(fa.returnType, fb.returnType) &&
             contextMatch(fa.context, fb.context);
    default:
      return typeToString(a) === typeToString(b);
  }
}

// Check if two parameter lists match exactly
export function paramsMatch(a: ParameterType[], b: ParameterType[]): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    const pa = a[i]!, pb = b[i]!;
    if (pa.optional !== pb.optional) return false;
    if (pa.rest !== pb.rest) return false;
    if (!typesEqual(pa.type, pb.type)) return false;
  }
  return true;
}

// Check if two context binding lists match exactly
export function contextMatch(a: ContextBinding[], b: ContextBinding[]): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    const ca = a[i]!, cb = b[i]!;
    if (!typesEqual(ca.type, cb.type)) return false;
  }
  return true;
}

// Check if a type has an embedded type by name (Go-style composition)
// Replaces old inheritance check - now checks for embedded field
export function extendsType(type: Type, baseName: string, env: TypeEnvironment): boolean {
  const resolved = type.kind === "ref" ? env.resolveType(type) : type;

  // Direct match
  if (resolved.kind === "object" && (resolved as ObjectType).name === baseName) {
    return true;
  }

  if (resolved.kind === "object") {
    const obj = resolved as ObjectType;
    // Context types: only those declared with `context TypeName`, not embedded Context
    if (baseName === "Context") return obj.isContextType === true;
    const embedded = obj.properties.find(p => p.embedded && p.name === baseName);
    if (embedded) return true;
  }

  return false;
}

/** True if type is a context type (declared with `context TypeName`). Used for with/using. */
export function typeIsContext(type: Type, env: TypeEnvironment): boolean {
  const resolved = type.kind === "ref" ? env.resolveType(type) : type;
  return resolved.kind === "object" && (resolved as ObjectType).isContextType === true;
}

// Check if a type is iterable
export function isIterable(type: Type): boolean {
  const kind = type.kind;
  if (kind === "list" || kind === "set" || kind === "string" ||
      kind === "map" || kind === "stream" || kind === "channel" ||
      kind === "any") {
    return true;
  }
  // Check if it's a generic type like Channel[T]
  if (kind === "generic") {
    const genType = type as any;
    if (genType.base?.kind === "ref") {
      const baseName = genType.base.name.toLowerCase();
      return baseName === "channel" || baseName === "list" || baseName === "set" ||
             baseName === "map" || baseName === "stream";
    }
  }
  return false;
}

// Get element type from iterable
export function getIterableElementType(type: Type): Type {
  if (type.kind === "list") return type.elementType;
  if (type.kind === "set") return type.elementType;
  if (type.kind === "string") return Types.string;
  if (type.kind === "map") return Types.tuple(type.keyType, type.valueType);
  if (type.kind === "stream") return type.elementType;
  if (type.kind === "channel") return type.elementType;
  return Types.any;
}

// Find common type of multiple types
export function findCommonType(types: Type[]): Type {
  if (types.length === 0) return Types.any;
  if (types.length === 1) return types[0]!;

  const first = types[0]!;
  if (types.every(t => t.kind === first.kind)) {
    return first;
  }

  return Types.union(...types);
}

// Check if a type involves Promise
export function typeInvolvesPromise(t: Type, env: TypeEnvironment, visited: Set<string> = new Set()): boolean {
  if (t.kind === "promise") return true;
  if (t.kind === "list") return typeInvolvesPromise((t as any).elementType, env, visited);
  if (t.kind === "map") return typeInvolvesPromise((t as any).valueType, env, visited);
  if (t.kind === "optional") return typeInvolvesPromise((t as any).inner, env, visited);

  if (t.kind === "object") {
    const objType = t as any;
    if (objType.name && visited.has(objType.name)) return false;
    if (objType.name) visited.add(objType.name);
    for (const prop of objType.properties || []) {
      if (typeInvolvesPromise(prop.type, env, visited)) return true;
    }
  }

  if (t.kind === "ref") {
    const resolved = env.resolveType(t);
    if (resolved && resolved !== t) {
      return typeInvolvesPromise(resolved, env, visited);
    }
  }

  return false;
}

// Substitute type parameters in a type
export function substituteTypeParams(type: Type, bindings: Map<string, Type>): Type {
  if (bindings.size === 0) return type;

  switch (type.kind) {
    case "typevar": {
      const bound = bindings.get(type.name);
      return bound ?? type;
    }
    case "ref": {
      const bound = bindings.get(type.name);
      if (bound) return bound;
      // Handle ref with generic args
      if (type.args && type.args.length > 0) {
        return Types.ref(type.name, type.args.map(a => substituteTypeParams(a, bindings)));
      }
      return type;
    }
    case "list":
      return Types.list(substituteTypeParams(type.elementType, bindings));
    case "map":
      return Types.map(
        substituteTypeParams(type.keyType, bindings),
        substituteTypeParams(type.valueType, bindings)
      );
    case "set":
      return Types.set(substituteTypeParams(type.elementType, bindings));
    case "promise":
      return Types.promise(substituteTypeParams(type.resolveType, bindings));
    case "channel":
      return Types.channel(substituteTypeParams(type.elementType, bindings));
    case "optional":
      return Types.optional(substituteTypeParams(type.inner, bindings));
    case "tuple":
      return Types.tuple(...type.elements.map(e => substituteTypeParams(e, bindings)));
    case "union":
      return Types.union(...type.types.map(t => substituteTypeParams(t, bindings)));
    case "intersection":
      return Types.intersection(...type.types.map(t => substituteTypeParams(t, bindings)));
    case "generic":
      return Types.generic(
        substituteTypeParams(type.base, bindings),
        type.args.map(a => substituteTypeParams(a, bindings))
      );
    case "function":
      return Types.fn(
        type.params.map(p => Types.param(
          p.name,
          substituteTypeParams(p.type, bindings),
          p.optional,
          p.rest
        )),
        substituteTypeParams(type.returnType, bindings)
      );
    case "stream":
      return Types.stream(substituteTypeParams(type.elementType, bindings));
    case "result":
      return Types.result(
        substituteTypeParams(type.okType, bindings),
        substituteTypeParams(type.errType, bindings)
      );
    default:
      return type;
  }
}

// Substitute type parameters in an object type
export function substituteTypeInObject(objType: ObjectType, bindings: Map<string, Type>): ObjectType {
  if (bindings.size === 0) return objType;
  
  const result: ObjectType = {
    kind: "object",
    name: objType.name,
    properties: objType.properties.map(p => ({
      ...p,
      type: substituteTypeParams(p.type, bindings)
    })),
    methods: objType.methods.map(m => ({
      name: m.name,
      type: {
        ...m.type,
        params: m.type.params.map(p => ({
          ...p,
          type: substituteTypeParams(p.type, bindings)
        })),
        returnType: substituteTypeParams(m.type.returnType, bindings)
      }
    })),
    typeParams: objType.typeParams,
    alias: objType.alias,
    context: objType.context
  };
  return result;
}

// Unify parameter type with argument type to infer type variables
export function unifyTypes(paramType: Type, argType: Type, bindings: Map<string, Type>): void {
  if (paramType.kind === "typevar") {
    const existing = bindings.get(paramType.name);
    if (existing?.kind === "any") {
      bindings.set(paramType.name, argType);
    }
    return;
  }

  if (paramType.kind === "ref" && bindings.has(paramType.name)) {
    const existing = bindings.get(paramType.name);
    if (existing?.kind === "any") {
      bindings.set(paramType.name, argType);
    }
    return;
  }

  if (paramType.kind === "list" && argType.kind === "list") {
    unifyTypes(paramType.elementType, argType.elementType, bindings);
  } else if (paramType.kind === "map" && argType.kind === "map") {
    unifyTypes(paramType.keyType, argType.keyType, bindings);
    unifyTypes(paramType.valueType, argType.valueType, bindings);
  } else if (paramType.kind === "set" && argType.kind === "set") {
    unifyTypes(paramType.elementType, argType.elementType, bindings);
  } else if (paramType.kind === "promise" && argType.kind === "promise") {
    unifyTypes(paramType.resolveType, argType.resolveType, bindings);
  } else if (paramType.kind === "channel" && argType.kind === "channel") {
    unifyTypes(paramType.elementType, argType.elementType, bindings);
  } else if (paramType.kind === "optional" && argType.kind === "optional") {
    unifyTypes(paramType.inner, argType.inner, bindings);
  } else if (paramType.kind === "function" && argType.kind === "function") {
    for (let i = 0; i < paramType.params.length && i < argType.params.length; i++) {
      unifyTypes(paramType.params[i]!.type, argType.params[i]!.type, bindings);
    }
    unifyTypes(paramType.returnType, argType.returnType, bindings);
  }
}

// ============================================
// AST Formatting Utilities (for IDE)
// ============================================

// Format an AST type expression to string
export function formatAstType(t: AST.TypeExpr | undefined): string {
  if (!t) return "any";
  try {
    return typeToString(astTypeToType(t));
  } catch {
    return "any";
  }
}

// Format function signature
export function formatFnSignature(fn: AST.FnDecl | AST.ExternFnDecl, isExtern = false): string {
  const params = fn.params.map(p => `${p.name}: ${formatAstType(p.type)}`).join(", ");
  const ret = formatAstType(fn.returnType) || "void";
  const typeParams = fn.typeParams?.length ? `[${fn.typeParams.map(t => t.name).join(", ")}]` : "";
  const prefix = isExtern ? "extern fn" : "fn";
  return `${prefix} ${fn.name}${typeParams}(${params}): ${ret}`;
}

// Format method signature
export function formatMethodSignature(m: AST.MethodDecl): string {
  const params = m.params.map(p => `${p.name}${p.optional ? "?" : ""}: ${formatAstType(p.type)}`).join(", ");
  const ret = formatAstType(m.returnType) || "void";
  return `fn(${params}): ${ret}`;
}

// Format type signature with fields
export function formatTypeSignature(t: AST.TypeDecl): { signature: string; fields: string[] } {
  const fields: string[] = [];
  for (const m of t.body?.members || []) {
    if (m.kind === "FieldDecl") {
      const opt = m.optional ? "?" : "";
      const def = m.defaultValue ? " = ..." : "";
      fields.push(`${m.name}${opt}: ${formatAstType(m.type)}${def}`);
    }
  }
  const sig = fields.length ? `${t.name}(${fields.join(", ")})` : t.name;
  return { signature: sig, fields };
}
