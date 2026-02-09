// Type Utilities - Pure functions for type operations
import * as AST from "../parser/ast";
import type {
  Type,
  FunctionType,
  ParameterType,
  UsingBinding,
  ObjectType,
  InterfaceType,
  MethodType,
  OptionalType,
  ListType,
  MapType,
  PromiseType,
  SetType,
  StreamType,
  TupleType,
  UnionType,
  IntersectionType,
  GenericType,
  TypeRef,
  TypeVariable,
} from "./types";
import { Types, typeToString } from "./types";
import type { TypeEnvironment } from "./environment";
import { PRIMITIVE_TYPE_MAP, constructGenericType } from "./primitives";
import { findTypeDecl } from "./ast-query";

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
      if (astType.name === "list") return Types.list(Types.unknown);
      if (astType.name === "map") return Types.map(Types.unknown, Types.unknown);
      if (astType.name === "set") return Types.set(Types.unknown);
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
      return Types.unknown;
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

export function getTypeDisplayName(env: TypeEnvironment, type: Type): string | null {
  if (type.kind === "ref") return type.name;
  if (type.kind === "object" && (type as ObjectType).name) return (type as ObjectType).name!;
  if (type.kind === "interface") return (type as InterfaceType).name;
  if (type.kind === "optional") return getTypeDisplayName(env, (type as OptionalType).inner);
  const resolved = env.resolveType(type);
  if (resolved !== type) {
    if (resolved.kind === "object" && (resolved as ObjectType).name) return (resolved as ObjectType).name!;
    if (resolved.kind === "ref") return resolved.name;
    if (resolved.kind === "interface") return (resolved as InterfaceType).name;
  }
  return null;
}

// Convert function declaration to FunctionType
export function fnDeclToType(decl: AST.FnDecl): FunctionType {
  const params = decl.params.map(p => ({
    name: p.name,
    type: p.type ? astTypeToType(p.type) : Types.unknown,
    optional: p.optional,
    rest: p.rest,
  }));

  const returnType = decl.returnType ? astTypeToType(decl.returnType) : Types.unknown;

  const context: UsingBinding[] = decl.using?.bindings.map(c => ({
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
    type: p.type ? astTypeToType(p.type) : Types.unknown,
    optional: p.optional,
    rest: p.rest,
  }));

  const returnType = method.returnType ? astTypeToType(method.returnType) : Types.unknown;

  const context: UsingBinding[] = method.using?.bindings.map(c => ({
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
  if (target.kind === "unknown") return true;
  if (source.kind === "unknown") return false;

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
        return (resolvedSource as TypeRef).name === (resolvedTarget as TypeRef).name;
      case "list":
        if ((resolvedTarget as ListType).elementType.kind === "unknown") return true;
        const sl = resolvedSource as ListType, tl = resolvedTarget as ListType;
        return isAssignable(sl.elementType, tl.elementType, env) && isAssignable(tl.elementType, sl.elementType, env);
      case "map":
        const tm = resolvedTarget as MapType;
        if (tm.keyType.kind === "unknown" && tm.valueType.kind === "unknown") return true;
        const sm = resolvedSource as MapType;
        return isAssignable(sm.keyType, tm.keyType, env) && isAssignable(tm.keyType, sm.keyType, env) &&
               isAssignable(sm.valueType, tm.valueType, env) && isAssignable(tm.valueType, sm.valueType, env);
      case "promise":
        if ((resolvedTarget as PromiseType).resolveType.kind === "unknown") return true;
        return isAssignable((resolvedSource as PromiseType).resolveType, (resolvedTarget as PromiseType).resolveType, env);
      case "set":
        if ((resolvedTarget as SetType).elementType.kind === "unknown") return true;
        const ss = resolvedSource as SetType, ts = resolvedTarget as SetType;
        return isAssignable(ss.elementType, ts.elementType, env) && isAssignable(ts.elementType, ss.elementType, env);
      case "stream":
        if ((resolvedTarget as StreamType).elementType.kind === "unknown") return true;
        return isAssignable((resolvedSource as StreamType).elementType, (resolvedTarget as StreamType).elementType, env);
      case "tuple":
        return isTupleAssignable(resolvedSource as TupleType, resolvedTarget as TupleType, env);
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
        return isIntersectionAssignable(resolvedSource as IntersectionType, resolvedTarget as IntersectionType, env);
      case "generic":
        return isGenericAssignable(resolvedSource as GenericType, resolvedTarget as GenericType, env);
      case "typevar":
        return (resolvedSource as TypeVariable).name === (resolvedTarget as TypeVariable).name;
      default:
        return true;
    }
  }

  // Handle cross-kind assignability
  
  // Type variable is assignable to unknown (or the same type variable)
  if (resolvedSource.kind === "typevar") {
    return resolvedTarget.kind === "unknown" ||
           (resolvedTarget.kind === "typevar" && (resolvedSource as TypeVariable).name === (resolvedTarget as TypeVariable).name);
  }
  
  // Anything can be assigned to a type variable (during unification)
  if (resolvedTarget.kind === "typevar") {
    return true;
  }
  if (resolvedSource.kind === "null" && resolvedTarget.kind === "optional") return true;

  if (resolvedTarget.kind === "optional") {
    const optTarget = resolvedTarget as OptionalType;
    if (resolvedSource.kind === "union") {
      const unionTypes = (resolvedSource as UnionType).types;
      const nonNullTypes = unionTypes.filter((t: Type) => t.kind !== "null");
      if (nonNullTypes.length === unionTypes.length - 1) {
        return nonNullTypes.every((t: Type) => isAssignable(t, optTarget.inner, env));
      }
    }
    return isAssignable(resolvedSource, optTarget.inner, env);
  }

  if (resolvedTarget.kind === "union") {
    return (resolvedTarget as UnionType).types.some((t: Type) => isAssignable(resolvedSource, t, env));
  }

  if (resolvedSource.kind === "union") {
    return (resolvedSource as UnionType).types.every((t: Type) => isAssignable(t, resolvedTarget, env));
  }

  if (resolvedSource.kind === "intersection") {
    return (resolvedSource as IntersectionType).types.some((t: Type) => isAssignable(t, resolvedTarget, env));
  }

  if (resolvedTarget.kind === "intersection") {
    return (resolvedTarget as IntersectionType).types.every((t: Type) => isAssignable(resolvedSource, t, env));
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
    case "unknown":
    case "never":
      return true;
    case "ref":
      return (a as TypeRef).name === (b as TypeRef).name;
    case "list":
      return typesEqual((a as ListType).elementType, (b as ListType).elementType);
    case "map":
      return typesEqual((a as MapType).keyType, (b as MapType).keyType) &&
             typesEqual((a as MapType).valueType, (b as MapType).valueType);
    case "optional":
      return typesEqual((a as OptionalType).inner, (b as OptionalType).inner);
    case "function":
      const fa = a as FunctionType, fb = b as FunctionType;
      return paramsMatch(fa.params, fb.params) &&
             typesEqual(fa.returnType, fb.returnType) &&
             usingMatch(fa.context, fb.context);
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

export function usingMatch(a: UsingBinding[], b: UsingBinding[]): boolean {
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
    const embedded = obj.properties.find(p => p.embedded && p.name === baseName);
    if (embedded) return true;
  }

  return false;
}

// Check if a type is iterable
export function isIterable(type: Type): boolean {
  const kind = type.kind;
  if (kind === "list" || kind === "set" || kind === "string" || kind === "map" || kind === "stream") {
    return true;
  }
  if (kind === "generic") {
    const genType = type as GenericType;
    if (genType.base?.kind === "ref") {
      const baseName = (genType.base as TypeRef).name.toLowerCase();
      return baseName === "list" || baseName === "set" || baseName === "map" || baseName === "stream";
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
  return Types.unknown;
}

// Find common type of multiple types
export function findCommonType(types: Type[]): Type {
  if (types.length === 0) return Types.unknown;
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
  if (t.kind === "list") return typeInvolvesPromise((t as ListType).elementType, env, visited);
  if (t.kind === "map") return typeInvolvesPromise((t as MapType).valueType, env, visited);
  if (t.kind === "optional") return typeInvolvesPromise((t as OptionalType).inner, env, visited);

  if (t.kind === "object") {
    const objType = t as ObjectType;
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
    case "stream":
      return Types.unknown;
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
    if (existing === undefined) return;
    if (existing.kind === "unknown") {
      bindings.set(paramType.name, argType);
    } else if (existing.kind !== "typevar" || existing.name !== paramType.name) {
      unifyTypes(existing, argType, bindings);
    }
    return;
  }

  if (paramType.kind === "ref" && bindings.has(paramType.name)) {
    const existing = bindings.get(paramType.name);
    if (existing === undefined) return;
    if (existing.kind === "unknown") {
      bindings.set(paramType.name, argType);
    } else if (existing.kind !== "ref" || existing.name !== paramType.name) {
      unifyTypes(existing, argType, bindings);
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
  } else if (paramType.kind === "tuple" && argType.kind === "tuple") {
    const len = Math.min(paramType.elements.length, argType.elements.length);
    for (let i = 0; i < len; i++) {
      unifyTypes(paramType.elements[i]!, argType.elements[i]!, bindings);
    }
  } else if (paramType.kind === "generic" && argType.kind === "generic") {
    unifyTypes(paramType.base, argType.base, bindings);
    const len = Math.min(paramType.args.length, argType.args.length);
    for (let i = 0; i < len; i++) {
      unifyTypes(paramType.args[i]!, argType.args[i]!, bindings);
    }
  } else if (paramType.kind === "promise" && argType.kind === "promise") {
    unifyTypes(paramType.resolveType, argType.resolveType, bindings);
  } else if (paramType.kind === "optional" && argType.kind === "optional") {
    unifyTypes(paramType.inner, argType.inner, bindings);
  } else if (paramType.kind === "function" && argType.kind === "function") {
    for (let i = 0; i < paramType.params.length && i < argType.params.length; i++) {
      unifyTypes(paramType.params[i]!.type, argType.params[i]!.type, bindings);
    }
    unifyTypes(paramType.returnType, argType.returnType, bindings);
  }
}

