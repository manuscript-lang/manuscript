import * as AST from "../../../parser/ast";
import type { Type, FunctionType, ObjectType } from "../../types";
import { Types, typeToString } from "../../types";
import { TypeErrors } from "../../../shared/errors";
import { isAssignable, substituteTypeParams, substituteTypeInObject, resolveTypeName } from "../../type-utils";
import type { InferContext } from "./context";
import { error, setExpectedType } from "./context";
import { inferTypeParams, isNamedArg, getArgExpr } from "./infer-call";

export function inferIndexExpr(ctx: InferContext, expr: AST.IndexExpr): Type {
  if (expr.object.kind === "Identifier") {
    const typeRef = ctx.env.lookupType(expr.object.name);
    if (typeRef) {
      if (expr.index.kind === "Literal" && typeof (expr.index as AST.Literal).value === "string") {
        error(ctx, "Generic type arguments must be identifiers, not string literals", expr.index.loc);
        return Types.unknown;
      }
      ctx.inferExpr(expr.index);
      if (expr.typeArgs) for (const arg of expr.typeArgs) ctx.inferExpr(arg);
      return typeRef;
    }
  }

  let objectType = ctx.inferExpr(expr.object);
  if (expr.optional && objectType.kind === "optional") objectType = objectType.inner;

  if (expr.slice) {
    if (expr.slice.start) {
      const startType = ctx.inferExpr(expr.slice.start);
      if (startType.kind !== "number") {
        const err = TypeErrors.indexTypeMismatch("number", typeToString(startType));
        error(ctx, `Slice start index: ${err.message}`, expr.slice.start.loc, err.hint);
      }
    }
    if (expr.slice.end) {
      const endType = ctx.inferExpr(expr.slice.end);
      if (endType.kind !== "number") {
        const err = TypeErrors.indexTypeMismatch("number", typeToString(endType));
        error(ctx, `Slice end index: ${err.message}`, expr.slice.end.loc, err.hint);
      }
    }
    return expr.optional ? Types.optional(objectType) : objectType;
  }

  const indexType = ctx.inferExpr(expr.index);

  if (objectType.kind === "list") {
    if (indexType.kind !== "number") {
      const err = TypeErrors.indexTypeMismatch("number", typeToString(indexType));
      error(ctx, `List index: ${err.message}`, expr.index.loc, err.hint);
    }
    const result = objectType.elementType;
    return expr.optional ? Types.optional(result) : result;
  }
  if (objectType.kind === "map") {
    if (!isAssignable(indexType, objectType.keyType, ctx.env)) {
      const err = TypeErrors.indexTypeMismatch(typeToString(objectType.keyType), typeToString(indexType));
      error(ctx, `Map key: ${err.message}`, expr.index.loc, err.hint);
    }
    return Types.optional(objectType.valueType);
  }
  if (objectType.kind === "string") {
    if (indexType.kind !== "number") {
      const err = TypeErrors.indexTypeMismatch("number", typeToString(indexType));
      error(ctx, `String index: ${err.message}`, expr.index.loc, err.hint);
    }
    return expr.optional ? Types.optional(Types.string) : Types.string;
  }
  if (objectType.kind === "unknown") {
    const err = TypeErrors.operationNotAllowedOnUnknown("[]");
    error(ctx, err.message, expr.loc, err.hint);
    return expr.optional ? Types.optional(Types.unknown) : Types.unknown;
  }
  if (objectType.kind === "function") {
    const fnType = objectType as FunctionType;
    if (!fnType.typeParams?.length) {
      const err = TypeErrors.indexAccessOnInvalidType(typeToString(objectType));
      error(ctx, err.message, expr.loc, err.hint);
      return Types.unknown;
    }
    const typeArgExprs = [expr.index];
    if (expr.typeArgs) typeArgExprs.push(...expr.typeArgs);
    if (typeArgExprs.length !== fnType.typeParams.length) {
      error(ctx, `Expected ${fnType.typeParams.length} type argument(s), got ${typeArgExprs.length}`, expr.loc);
      return Types.unknown;
    }
    const bindings = new Map<string, Type>();
    for (let i = 0; i < fnType.typeParams.length; i++) {
      const arg = typeArgExprs[i]!;
      if (arg.kind !== "Identifier") {
        error(ctx, "Generic type argument must be a type name", arg.loc);
        return Types.unknown;
      }
      bindings.set(fnType.typeParams[i]!.name, resolveTypeName(arg.name, ctx.env));
    }
    const instantiated: FunctionType = {
      ...fnType,
      params: fnType.params.map(p => ({ ...p, type: substituteTypeParams(p.type, bindings) })),
      returnType: substituteTypeParams(fnType.returnType, bindings),
      predicate: fnType.predicate
        ? { paramName: fnType.predicate.paramName, targetType: substituteTypeParams(fnType.predicate.targetType, bindings) }
        : undefined,
    };
    return instantiated;
  }
  const err = TypeErrors.indexAccessOnInvalidType(typeToString(objectType));
  error(ctx, err.message, expr.loc, err.hint);
  return expr.optional ? Types.optional(Types.unknown) : Types.unknown;
}

export function inferMemberExpr(ctx: InferContext, expr: AST.MemberExpr): Type {
  if (expr.object.kind === "Identifier") {
    const symbol = ctx.env.lookup(expr.object.name);
    if (!symbol) {
      const typeRef = ctx.env.lookupType(expr.object.name);
      if (typeRef && typeRef.kind === "object") {
        const err = TypeErrors.memberAccessOnType(expr.object.name);
        error(ctx, err.message, expr.loc, err.hint);
        return Types.unknown;
      }
    }
  }

  const objectType = ctx.inferExpr(expr.object);
  if (objectType.kind === "unknown") {
    const err = TypeErrors.operationNotAllowedOnUnknown(".");
    error(ctx, err.message, expr.loc, err.hint);
    return Types.unknown;
  }
  let resolved = ctx.env.resolveType(objectType);

  if (resolved.kind === "function") {
    const err = TypeErrors.memberAccessOnFunction();
    error(ctx, err.message, expr.loc, err.hint);
    return Types.unknown;
  }

  if (resolved.kind === "generic" && resolved.base.kind === "ref") {
    const baseType = ctx.env.lookupType(resolved.base.name);
    if (baseType && baseType.kind === "object") {
      const typeParams = baseType.typeParams || [];
      const bindings = new Map<string, Type>();
      for (let i = 0; i < typeParams.length && i < resolved.args.length; i++)
        bindings.set(typeParams[i]!.name, resolved.args[i]!);
      resolved = substituteTypeInObject(baseType, bindings);
    }
  }

  if (resolved.kind === "interface") {
    const method = resolved.methods.find(m => m.name === expr.property);
    if (method) return method.type;
    if (!expr.optional) {
      const err = TypeErrors.propertyNotExist(expr.property, resolved.name);
      error(ctx, err.message, expr.loc, err.hint);
    }
    return Types.unknown;
  }

  if (resolved.kind === "object") {
    const prop = resolved.properties.find(p => p.name === expr.property);
    if (prop) {
      if (expr.property.startsWith("_") && resolved.name && ctx.currentTypeName !== resolved.name) {
        const err = TypeErrors.privateAccess(expr.property, resolved.name);
        error(ctx, err.message, expr.loc, err.hint);
      }
      return expr.optional ? Types.optional(prop.type) : prop.type;
    }
    const method = resolved.methods.find(m => m.name === expr.property);
    if (method) {
      if (expr.property.startsWith("_") && resolved.name && ctx.currentTypeName !== resolved.name) {
        const err = TypeErrors.privateAccess(expr.property, resolved.name);
        error(ctx, err.message, expr.loc, err.hint);
      }
      return method.type;
    }
    if (resolved.name && !expr.optional) {
      const err = TypeErrors.propertyNotExist(expr.property, resolved.name);
      error(ctx, err.message, expr.loc, err.hint);
    }
  }

  return inferBuiltinMember(ctx, objectType, expr);
}

function inferBuiltinMember(ctx: InferContext, objectType: Type, expr: AST.MemberExpr): Type {
  const member = ctx.env.lookupBuiltinMethod(objectType.kind, expr.property);
  if (member) return substituteBuiltinTypeParams(member.type, objectType);

  if (objectType.kind === "map")
    return expr.optional ? Types.optional(objectType.valueType) : objectType.valueType;

  if (objectType.kind === "unknown") {
    const err = TypeErrors.operationNotAllowedOnUnknown(".");
    error(ctx, err.message, expr.loc, err.hint);
    return Types.unknown;
  }

  if (objectType.kind === "number" || objectType.kind === "bool" ||
      objectType.kind === "string" || objectType.kind === "list" || objectType.kind === "set") {
    if (!expr.optional)
      error(ctx, `Property '${expr.property}' does not exist on type '${objectType.kind}'`, expr.loc);
    return expr.optional ? Types.optional(Types.unknown) : Types.unknown;
  }

  return expr.optional ? Types.optional(Types.unknown) : Types.unknown;
}

function substituteBuiltinTypeParams(type: Type, objectType: Type): Type {
  const bindings = new Map<string, Type>();
  if (objectType.kind === "list" || objectType.kind === "set")
    bindings.set("T", objectType.elementType);
  else if (objectType.kind === "map") {
    bindings.set("K", objectType.keyType);
    bindings.set("V", objectType.valueType);
  }
  if (bindings.size === 0) return type;
  return substituteTypeParams(type, bindings);
}

export function inferPipeExpr(ctx: InferContext, expr: AST.PipeExpr): Type {
  const leftType = ctx.inferExpr(expr.left);
  const expectedPipeFn = Types.fn([Types.param("_", leftType)], Types.unknown);
  setExpectedType(expr.right, expectedPipeFn);

  if (expr.right.kind === "CallExpr") {
    const callExpr = expr.right;
    setExpectedType(callExpr.callee, expectedPipeFn);
    const calleeType = ctx.inferExpr(callExpr.callee);

    if (calleeType.kind === "function") {
      const syntheticArgs: (AST.Expr | { name: string; value: AST.Expr })[] = [expr.left, ...callExpr.args];
      const typeBindings = inferTypeParams(ctx, calleeType, syntheticArgs);
      const params = calleeType.params.map(p => ({ ...p, type: substituteTypeParams(p.type, typeBindings) }));
      const requiredCount = params.filter(p => !p.optional && !p.rest).length;

      if (1 + callExpr.args.length < requiredCount) {
        const err = TypeErrors.wrongArgumentCount(`at least ${requiredCount}`, 1 + callExpr.args.length);
        error(ctx, err.message, callExpr.loc, err.hint);
      }
      if (params.length > 0) {
        if (!isAssignable(leftType, params[0]!.type, ctx.env)) {
          const err = TypeErrors.typeMismatch(typeToString(params[0]!.type), typeToString(leftType));
          error(ctx, `Pipe argument: ${err.message}`, expr.left.loc, err.hint);
        }
      }
      for (let i = 0; i < callExpr.args.length; i++) {
        const arg = callExpr.args[i]!;
        const paramIndex = i + 1;
        const param = paramIndex < params.length ? params[paramIndex] : params[params.length - 1];
        if (param) {
          const argExpr = getArgExpr(arg);
          const argType = ctx.inferExpr(argExpr);
          const argLoc = argExpr.loc;
          const expected = param.rest && param.type.kind === "list" ? param.type.elementType : param.type;
          if (!isAssignable(argType, expected, ctx.env)) {
            const err = TypeErrors.typeMismatch(typeToString(expected), typeToString(argType));
            error(ctx, `Argument ${paramIndex + 1}: ${err.message}`, argLoc, err.hint);
          }
        }
      }
      return substituteTypeParams(calleeType.returnType, typeBindings);
    }

    for (const arg of callExpr.args) {
      ctx.inferExpr(getArgExpr(arg));
    }
    return Types.unknown;
  }

  const rightType = ctx.inferExpr(expr.right);
  if (rightType.kind === "function") return rightType.returnType;
  return Types.unknown;
}
