import * as AST from "../../../parser/ast";
import type { Type, FunctionType, ObjectType, ParameterType } from "../../types";
import { Types, typeToString } from "../../types";
import { TypeErrors, RESERVED_PROPERTY_NAMES } from "../../../shared/errors";
import { astTypeToType, isAssignable, findCommonType, isNullable, nonNull } from "../../type-utils";
import type { InferContext } from "./context";
import { error, warning, recordType, getExpectedType, setExpectedType } from "./context";
import { checkPattern } from "./check-pattern";
import { inferCallExpr } from "./infer-call";
import { inferIndexExpr, inferMemberExpr, inferPipeExpr } from "./infer-member";
import { inferSpawnExpr } from "./infer-spawn";

function expectedFunctionType(expected: Type | undefined): FunctionType | undefined {
  if (!expected) return undefined;
  if (expected.kind === "function") return expected;
  return undefined;
}

function expectedCollectionType(expected: Type | undefined): Type | undefined {
  if (!expected) return undefined;
  if (expected.kind === "list" || expected.kind === "map") return expected;
  if (expected.kind === "optional" && expected.inner) return expectedCollectionType(expected.inner);
  return undefined;
}

export function inferExpr(ctx: InferContext, expr: AST.Expr): Type {
  const expectedType = getExpectedType(expr);
  let type: Type;

  switch (expr.kind) {
    case "Literal":
      type = inferLiteral(expr);
      break;
    case "Identifier":
      type = inferIdentifier(ctx, expr);
      break;
    case "BinaryExpr":
      type = inferBinaryExpr(ctx, expr);
      break;
    case "UnaryExpr":
      type = inferUnaryExpr(ctx, expr);
      break;
    case "CallExpr":
      type = inferCallExpr(ctx, expr);
      break;
    case "IndexExpr":
      type = inferIndexExpr(ctx, expr);
      break;
    case "MemberExpr":
      type = inferMemberExpr(ctx, expr);
      break;
    case "PipeExpr":
      type = inferPipeExpr(ctx, expr);
      break;
    case "LambdaExpr":
      type = inferLambdaExpr(ctx, expr, expectedFunctionType(expectedType));
      break;
    case "IfExpr":
      type = inferIfExpr(ctx, expr);
      break;
    case "MatchExpr":
      type = inferMatchExpr(ctx, expr);
      break;
    case "ListExpr":
      type = inferListExpr(ctx, expr, expectedCollectionType(expectedType));
      break;
    case "SetExpr":
      type = inferSetExpr(ctx, expr, expectedCollectionType(expectedType));
      break;
    case "MapExpr":
      type = inferMapExpr(ctx, expr, expectedCollectionType(expectedType));
      break;
    case "SpawnExpr":
      type = inferSpawnExpr(ctx, expr);
      break;
    case "TypeAssertion": {
      const exprType = inferExpr(ctx, expr.expr);
      const assertedType = astTypeToType(expr.type);
      const canAssert =
        exprType.kind === "unknown" || assertedType.kind === "unknown" ||
        isAssignable(exprType, assertedType, ctx.env) ||
        isAssignable(assertedType, exprType, ctx.env);
      if (!canAssert) {
        const err = TypeErrors.invalidTypeAssertion(typeToString(exprType), typeToString(assertedType));
        error(ctx, err.message, expr.loc, err.hint);
      }
      type = assertedType;
      break;
    }
    case "NullAssertion": {
      const innerType = inferExpr(ctx, expr.expr);
      if (!isNullable(innerType)) {
        const err = TypeErrors.unnecessaryNullAssertion(typeToString(innerType));
        warning(ctx, `${err.message}. ${err.hint}`);
      }
      type = nonNull(innerType);
      break;
    }
    case "RangeExpr":
      type = Types.list(Types.number);
      break;
    case "TemplateLiteral":
      type = inferTemplateLiteral(ctx, expr);
      break;
    default:
      type = Types.unknown;
  }

  recordType(ctx, expr, type);
  return type;
}

function inferLiteral(expr: AST.Literal): Type {
  if (typeof expr.value === "number") return Types.number;
  if (typeof expr.value === "string") return Types.string;
  if (typeof expr.value === "boolean") return Types.bool;
  if (expr.value === null) return Types.null;
  return Types.unknown;
}

function inferIdentifier(ctx: InferContext, expr: AST.Identifier): Type {
  const symbol = ctx.env.lookup(expr.name);
  if (!symbol) {
    const typeRef = ctx.env.lookupType(expr.name);
    if (typeRef) {
      if (typeRef.kind === "object" && typeRef.name) {
        const obj = typeRef as ObjectType;
        const ownProps = obj.properties.filter(p => !p.promotedFrom);
        const params: ParameterType[] = [];
        for (const p of ownProps) {
          if (p.embedded) {
            const embeddedType = ctx.env.lookupType(p.name);
            params.push(Types.param(p.name, embeddedType || Types.unknown, true));
          } else {
            params.push(Types.param(p.name, p.type, p.optional || !!p.defaultValue));
          }
        }
        const fnType: FunctionType = {
          kind: "function",
          params,
          returnType: obj.typeParams && obj.typeParams.length > 0
            ? Types.generic(Types.ref(obj.name!), obj.typeParams.map(tp => Types.typevar(tp.name)))
            : typeRef,
          isGenerator: false,
          context: [],
          typeParams: obj.typeParams?.map(tp => ({ name: tp.name, constraint: tp.constraint })),
        };
        return fnType;
      }
      return typeRef;
    }
    const err = TypeErrors.unknownIdentifier(expr.name);
    error(ctx, err.message, expr.loc, err.hint);
    return Types.unknown;
  }
  return symbol.type;
}

function inferBinaryExpr(ctx: InferContext, expr: AST.BinaryExpr): Type {
  const leftType = inferExpr(ctx, expr.left);
  const rightType = inferExpr(ctx, expr.right);

  switch (expr.op) {
    case "+":
      if (leftType.kind === "unknown" || rightType.kind === "unknown") {
        const err = TypeErrors.operationNotAllowedOnUnknown("+");
        error(ctx, err.message, expr.loc, err.hint);
      }
      if (leftType.kind === "string" || rightType.kind === "string") return Types.string;
      if (leftType.kind !== "number") {
        const err = TypeErrors.operatorRequiresType("+", "number or string", typeToString(leftType));
        error(ctx, err.message, expr.left.loc, err.hint);
      }
      if (rightType.kind !== "number") {
        const err = TypeErrors.operatorRequiresType("+", "number or string", typeToString(rightType));
        error(ctx, err.message, expr.right.loc, err.hint);
      }
      return Types.number;
    case "-": case "*": case "/": case "%": case "^":
      if (leftType.kind === "unknown" || rightType.kind === "unknown") {
        const err = TypeErrors.operationNotAllowedOnUnknown(expr.op);
        error(ctx, err.message, expr.loc, err.hint);
      }
      if (leftType.kind !== "number") {
        const err = TypeErrors.operatorRequiresType(expr.op, "number", typeToString(leftType));
        error(ctx, err.message, expr.left.loc, err.hint);
      }
      if (rightType.kind !== "number") {
        const err = TypeErrors.operatorRequiresType(expr.op, "number", typeToString(rightType));
        error(ctx, err.message, expr.right.loc, err.hint);
      }
      return Types.number;
    case "<": case ">": case "<=": case ">=": {
      if (leftType.kind === "unknown" || rightType.kind === "unknown") {
        const err = TypeErrors.operationNotAllowedOnUnknown(expr.op);
        error(ctx, err.message, expr.loc, err.hint);
      }
      const leftBase = leftType.kind === "optional" ? leftType.inner : leftType;
      const rightBase = rightType.kind === "optional" ? rightType.inner : rightType;
      if (leftBase.kind !== rightBase.kind &&
          !((leftBase.kind === "number" || leftBase.kind === "string") &&
            (rightBase.kind === "number" || rightBase.kind === "string"))) {
        const err = TypeErrors.cannotCompare(typeToString(leftType), typeToString(rightType));
        error(ctx, err.message, expr.loc, err.hint);
      }
      return Types.bool;
    }
    case "==": case "!=":
      if (leftType.kind === "unknown" || rightType.kind === "unknown") {
        const err = TypeErrors.operationNotAllowedOnUnknown(expr.op);
        error(ctx, err.message, expr.loc, err.hint);
      }
      return Types.bool;
    case "and": case "or": case "is":
      return Types.bool;
    case "??":
      if (isNullable(leftType)) return Types.union(nonNull(leftType), rightType);
      return leftType;
    default:
      return Types.unknown;
  }
}

function inferUnaryExpr(ctx: InferContext, expr: AST.UnaryExpr): Type {
  const operandType = inferExpr(ctx, expr.operand);
  switch (expr.op) {
    case "-":
      if (operandType.kind === "unknown") {
        const err = TypeErrors.operationNotAllowedOnUnknown("-");
        error(ctx, err.message, expr.operand.loc, err.hint);
      }
      if (operandType.kind !== "number") {
        const err = TypeErrors.operatorRequiresType("-", "number", typeToString(operandType));
        error(ctx, err.message, expr.operand.loc, err.hint);
      }
      return Types.number;
    case "not": case "!":
      return Types.bool;
    default:
      return operandType;
  }
}

function inferLambdaExpr(ctx: InferContext, expr: AST.LambdaExpr, expectedFn?: FunctionType): Type {
  const restParam = expectedFn?.params.find(p => p.rest);
  const restElementType = restParam?.type.kind === "list" ? restParam.type.elementType : undefined;

  const params = expr.params.map((p, i) => {
    let type: Type;
    if (p.type) {
      type = astTypeToType(p.type);
    } else if (expectedFn?.params) {
      if (p.rest) {
        type = restElementType ?? Types.unknown;
      } else {
        const expectedParam = expectedFn.params[i] ?? (restParam && restElementType ? { type: restElementType } : null);
        type = expectedParam?.type ?? Types.unknown;
      }
    } else {
      type = Types.unknown;
    }
    return { name: p.name, type, optional: p.optional, rest: p.rest };
  });

  const lambdaEnv = ctx.env.child();
  for (const param of params) lambdaEnv.define(param.name, param.type);

  const savedEnv = ctx.env;
  ctx.env = lambdaEnv;

  let returnType: Type;
  if (expr.body.kind === "Block") {
    ctx.checkBlock(expr.body as AST.Block);
    returnType = Types.void;
  } else {
    returnType = inferExpr(ctx, expr.body as AST.Expr);
  }

  ctx.env = savedEnv;
  return Types.fn(params, returnType);
}

function inferIfExpr(ctx: InferContext, expr: AST.IfExpr): Type {
  const expectedType = getExpectedType(expr);
  inferExpr(ctx, expr.condition);
  if (expectedType) {
    setExpectedType(expr.then, expectedType);
    setExpectedType(expr.else, expectedType);
  }
  const thenType = inferExpr(ctx, expr.then);
  const elseType = inferExpr(ctx, expr.else);

  if (isAssignable(thenType, elseType, ctx.env)) return elseType;
  if (isAssignable(elseType, thenType, ctx.env)) return thenType;
  return Types.union(thenType, elseType);
}

function inferMatchExpr(ctx: InferContext, expr: AST.MatchExpr): Type {
  const valueType = inferExpr(ctx, expr.value);
  const expectedType = getExpectedType(expr);
  const armTypes: Type[] = [];

  for (const arm of expr.arms) {
    const armEnv = ctx.env.child();
    const savedEnv = ctx.env;
    ctx.env = armEnv;
    checkPattern(ctx, arm.pattern, valueType);
    if (arm.guard) inferExpr(ctx, arm.guard);

    let armType: Type;
    if (arm.body.kind === "Block") {
      ctx.checkBlock(arm.body as AST.Block);
      armType = Types.void;
    } else {
      if (expectedType) setExpectedType(arm.body as AST.Expr, expectedType);
      armType = inferExpr(ctx, arm.body as AST.Expr);
    }
    armTypes.push(armType);
    ctx.env = savedEnv;
  }

  if (armTypes.length === 0) return Types.never;
  if (armTypes.length === 1) return armTypes[0]!;
  return Types.union(...armTypes);
}

function inferListExpr(ctx: InferContext, expr: AST.ListExpr, expected?: Type): Type {
  if (expr.elements.length === 0) {
    if (expected?.kind === "list") return Types.list(expected.elementType);
    return Types.list(Types.unknown);
  }
  const elementTypes: Type[] = [];
  for (const el of expr.elements) {
    if (el.kind === "SpreadElement") {
      const spreadType = inferExpr(ctx, el.expr);
      if (spreadType.kind === "list") elementTypes.push(spreadType.elementType);
      if (el.expr.kind === "Identifier") ctx.unawaitedSpawns.delete(el.expr.name);
    } else {
      elementTypes.push(inferExpr(ctx, el));
      if (el.kind === "Identifier") ctx.unawaitedSpawns.delete(el.name);
    }
  }
  return Types.list(findCommonType(elementTypes));
}

function inferSetExpr(ctx: InferContext, expr: AST.SetExpr, expected?: Type): Type {
  if (expr.elements.length === 0) {
    if (expected?.kind === "set") return Types.set(expected.elementType);
    return Types.set(Types.unknown);
  }
  const elementTypes = expr.elements.map(el => inferExpr(ctx, el));
  for (const el of expr.elements) if (el.kind === "Identifier") ctx.unawaitedSpawns.delete(el.name);
  return Types.set(findCommonType(elementTypes));
}

function inferMapExpr(ctx: InferContext, expr: AST.MapExpr, expected?: Type): Type {
  if (expr.entries.length === 0) {
    if (expected?.kind === "map") return Types.map(expected.keyType, expected.valueType);
    return Types.map(Types.string, Types.unknown);
  }
  const keyTypes: Type[] = [];
  const valueTypes: Type[] = [];
  for (const entry of expr.entries) {
    if (!entry.spread) {
      if (entry.key.kind === "Identifier") {
        if (RESERVED_PROPERTY_NAMES.has(entry.key.name)) {
          const err = TypeErrors.reservedPropertyName(entry.key.name);
          error(ctx, err.message, entry.key.loc, err.hint);
        }
        keyTypes.push(Types.string);
      } else {
        keyTypes.push(inferExpr(ctx, entry.key));
      }
      valueTypes.push(inferExpr(ctx, entry.value));
    }
  }
  return Types.map(findCommonType(keyTypes), findCommonType(valueTypes));
}

function inferTemplateLiteral(ctx: InferContext, expr: AST.TemplateLiteral): Type {
  for (const part of expr.parts) {
    if (typeof part !== "string") inferExpr(ctx, part.expr);
  }
  return Types.string;
}
