import * as AST from "../../../parser/ast";
import type { Type, FunctionType, ObjectType, PropertyType } from "../../types";
import { Types, typeToString } from "../../types";
import { TypeErrors } from "../../../shared/errors";
import {
  astTypeToType, resolveTypeName, isAssignable, typeInvolvesPromise,
  substituteTypeParams, unifyTypes, substituteTypeInObject
} from "../../type-utils";
import { constructGenericType } from "../../primitives";
import type { InferContext } from "./context";
import { error, recordType, getExpectedType, setExpectedType } from "./context";
import { consumeSpawnsInExpr } from "./infer-spawn";

type NamedArg = { name: string; value: AST.Expr };
type CallArg = AST.Expr | NamedArg;

export function isNamedArg(arg: CallArg): arg is NamedArg {
  return "name" in arg && "value" in arg;
}

export function getArgExpr(arg: CallArg): AST.Expr {
  return isNamedArg(arg) ? arg.value : arg;
}

export function inferCallExpr(ctx: InferContext, expr: AST.CallExpr): Type {
  if (expr.callee.kind === "IndexExpr" && expr.callee.object.kind === "Identifier") {
    const constructorName = expr.callee.object.name;
    const baseTypeCheck = ctx.env.lookupType(constructorName);
    if (baseTypeCheck) {
      recordType(ctx, expr.callee.object, baseTypeCheck);
      const allTypeArgs: AST.Expr[] = [expr.callee.index];
      if (expr.callee.typeArgs) allTypeArgs.push(...expr.callee.typeArgs);
      for (const arg of allTypeArgs) {
        if (arg.kind !== "Identifier") {
          const err = TypeErrors.genericParamMustBeIdentifier();
          error(ctx, err.message, arg.loc, err.hint);
        }
      }
      const resolvedTypeArgs = allTypeArgs.map(arg =>
        resolveTypeName(arg.kind === "Identifier" ? arg.name : "unknown", ctx.env)
      );
      const builtinType = constructGenericType(constructorName, resolvedTypeArgs);
      if (builtinType) {
        const baseType = ctx.env.lookupType(constructorName);
        if (baseType && baseType.kind === "object") {
          const typeParams = baseType.typeParams || [];
          const bindings = new Map<string, Type>();
          for (let i = 0; i < typeParams.length && i < resolvedTypeArgs.length; i++)
            bindings.set(typeParams[i]!.name, resolvedTypeArgs[i]!);
          inferConstructorCall(ctx, expr, substituteTypeInObject(baseType, bindings));
        }
        return builtinType;
      }
      const baseType = ctx.env.lookupType(constructorName);
      if (baseType && baseType.kind === "object") {
        const typeParams = baseType.typeParams || [];
        const bindings = new Map<string, Type>();
        for (let i = 0; i < typeParams.length && i < resolvedTypeArgs.length; i++)
          bindings.set(typeParams[i]!.name, resolvedTypeArgs[i]!);
        const instantiated = substituteTypeInObject(baseType, bindings);
        inferConstructorCall(ctx, expr, instantiated);
        if (typeParams.length > 0 && resolvedTypeArgs.length > 0)
          return Types.generic(Types.ref(constructorName), resolvedTypeArgs);
        return instantiated;
      }
    }
  }

  const calleeType = ctx.inferExpr(expr.callee);

  if (calleeType.kind === "function") {
    for (let i = 0; i < expr.args.length && i < calleeType.params.length; i++) {
      const param = calleeType.params[i];
      if (param && typeInvolvesPromise(param.type, ctx.env)) {
        const arg = expr.args[i];
        if (arg) consumeSpawnsInExpr(ctx, getArgExpr(arg));
      }
    }
  }

  if (calleeType.kind === "function") {
    recordType(ctx, expr.callee, calleeType);
    return inferFunctionCall(ctx, expr, calleeType);
  }
  if (calleeType.kind === "object") {
    recordType(ctx, expr.callee, calleeType);
    return inferConstructorCall(ctx, expr, calleeType);
  }
  if (calleeType.kind === "interface") {
    error(ctx, `Interface '${calleeType.name}' cannot be constructed; use a type that satisfies the interface`, expr.loc);
    return calleeType;
  }

  for (const arg of expr.args) {
    ctx.inferExpr(getArgExpr(arg));
  }
  return Types.unknown;
}

function inferFunctionCall(ctx: InferContext, expr: AST.CallExpr, fnType: FunctionType): Type {
  const args = expr.args;
  const expectedType = getExpectedType(expr);
  const hasNamed = args.some(isNamedArg);
  const hasPositional = args.some(a => !isNamedArg(a));
  if (hasNamed && hasPositional) {
    const err = TypeErrors.mixedPositionalAndNamedArguments();
    error(ctx, err.message, expr.loc, err.hint);
  }

  let typeBindings = inferTypeParams(ctx, fnType, args);
  if (expectedType && fnType.typeParams?.length) {
    const currentReturn = substituteTypeParams(fnType.returnType, typeBindings);
    unifyTypes(currentReturn, expectedType, typeBindings);
  }

  const params = fnType.params.map(p => ({ ...p, type: substituteTypeParams(p.type, typeBindings) }));
  const requiredCount = params.filter(p => !p.optional && !p.rest).length;
  const hasRest = params.some(p => p.rest);
  const maxArgs = hasRest ? Infinity : params.length;

  if (args.length < requiredCount) {
    const err = TypeErrors.wrongArgumentCount(`at least ${requiredCount}`, args.length);
    error(ctx, err.message, expr.loc, err.hint);
  } else if (args.length > maxArgs) {
    const err = TypeErrors.wrongArgumentCount(`at most ${params.length}`, args.length);
    error(ctx, err.message, expr.loc, err.hint);
  }

  for (let i = 0; i < args.length; i++) {
    const arg = args[i]!;
    if (isNamedArg(arg)) {
      const param = params.find(p => p.name === arg.name);
      if (param?.type) setExpectedType(arg.value, param.type);
      const argType = ctx.inferExpr(arg.value);
      if (!param) {
        const err = TypeErrors.unknownParameter(arg.name, params.map(p => p.name).filter(Boolean) as string[]);
        error(ctx, err.message, arg.value.loc, err.hint);
      } else if (!isAssignable(argType, param.type, ctx.env)) {
        const err = TypeErrors.typeMismatch(typeToString(param.type), typeToString(argType));
        error(ctx, `Argument '${arg.name}': ${err.message}`, arg.value.loc, err.hint);
      }
    } else {
      const paramIndex = Math.min(i, params.length - 1);
      const param = params[paramIndex];
      const expected = param && (param.rest && param.type.kind === "list" ? param.type : param.type);
      if (expected) setExpectedType(arg, expected);
      const argType = ctx.inferExpr(arg);
      if (param) {
        const expectedType = param.rest && param.type.kind === "list" ? param.type.elementType : param.type;
        if (!isAssignable(argType, expectedType, ctx.env)) {
          const err = TypeErrors.typeMismatch(typeToString(expectedType), typeToString(argType));
          error(ctx, `Argument ${i + 1}: ${err.message}`, arg.loc, err.hint);
        }
      }
    }
  }

  for (const binding of fnType.context) {
    if (binding.name && !ctx.env.isDefined(binding.name) && !ctx.insideWithContext)
      error(ctx, `No context of type '${typeToString(binding.type)}' available`, expr.loc);
  }

  return substituteTypeParams(fnType.returnType, typeBindings);
}

export function inferConstructorCall(ctx: InferContext, expr: AST.CallExpr, objType: ObjectType): Type {
  const args = expr.args;
  const hasNamed = args.some(isNamedArg);
  const hasPositional = args.some(a => !isNamedArg(a));
  if (hasNamed && hasPositional) {
    const err = TypeErrors.mixedPositionalAndNamedArguments();
    error(ctx, err.message, expr.loc, err.hint);
  }

  const ownProps = objType.properties.filter((p: PropertyType) => !p.promotedFrom && !(p.embedded && p.name === "Context"));
  const requiredCount = ownProps.filter((p: PropertyType) => !p.embedded && !p.optional && !p.defaultValue).length;
  const maxArgs = ownProps.length;

  if (args.length < requiredCount) {
    const err = TypeErrors.wrongArgumentCount(`at least ${requiredCount}`, args.length);
    error(ctx, `Type '${objType.name}': ${err.message}`, expr.loc, err.hint);
  } else if (args.length > maxArgs) {
    const err = TypeErrors.wrongArgumentCount(`at most ${maxArgs}`, args.length);
    error(ctx, `Type '${objType.name}': ${err.message}`, expr.loc, err.hint);
  }

  for (let i = 0; i < args.length; i++) {
    const arg = args[i]!;
    if (isNamedArg(arg)) {
      const prop = ownProps.find((p: PropertyType) => p.name === arg.name);
      const expected = prop ? (prop.embedded ? ctx.env.lookupType(prop.name) || Types.unknown : prop.type) : undefined;
      if (expected) setExpectedType(arg.value, expected);
      const argType = ctx.inferExpr(arg.value);
      if (!prop) {
        const err = TypeErrors.propertyNotExist(arg.name, objType.name!);
        error(ctx, err.message, arg.value.loc, err.hint);
      } else if (!isAssignable(argType, expected!, ctx.env)) {
        const err = TypeErrors.typeMismatch(typeToString(expected!), typeToString(argType));
        error(ctx, `Property '${arg.name}': ${err.message}`, arg.value.loc, err.hint);
      }
    } else {
      const prop = ownProps[i];
      const expected = prop ? (prop.embedded ? ctx.env.lookupType(prop.name) || Types.unknown : prop.type) : undefined;
      if (expected) setExpectedType(arg, expected);
      const argType = ctx.inferExpr(arg);
      if (prop && !isAssignable(argType, expected!, ctx.env)) {
        const err = TypeErrors.typeMismatch(typeToString(expected!), typeToString(argType));
        error(ctx, `Argument ${i + 1}: ${err.message}`, arg.loc, err.hint);
      }
    }
  }

  return objType;
}

export function inferTypeParams(ctx: InferContext, fnType: FunctionType, args: (AST.Expr | NamedArg)[]): Map<string, Type> {
  const bindings = new Map<string, Type>();
  if (!fnType.typeParams) return bindings;
  for (const tp of fnType.typeParams) bindings.set(tp.name, Types.unknown);

  let posIdx = 0;
  for (const arg of args) {
    let paramType: Type | undefined;
    let isRest = false;
    if (isNamedArg(arg)) {
      const param = fnType.params.find(p => p.name === arg.name);
      paramType = param?.type;
      isRest = param?.rest ?? false;
    } else {
      const param = fnType.params[Math.min(posIdx, fnType.params.length - 1)];
      paramType = param?.type;
      isRest = param?.rest ?? false;
      if (!isRest) posIdx++;
    }
    const effectiveType = paramType && isRest && paramType.kind === "list"
      ? (paramType as { elementType: Type }).elementType
      : paramType;
    const expected = effectiveType ? substituteTypeParams(effectiveType, bindings) : undefined;
    const argExpr = getArgExpr(arg);
    if (expected) setExpectedType(argExpr, expected);
    const argType = ctx.inferExpr(argExpr);
    if (effectiveType) unifyTypes(effectiveType, argType, bindings);
  }
  return bindings;
}
