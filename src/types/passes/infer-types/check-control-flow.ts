import * as AST from "../../../parser/ast";
import type { Type, FunctionType, ObjectType, UsingBinding } from "../../types";
import type { TypeEnvironment } from "../../environment";
import { Types, typeToString } from "../../types";
import { isNullable, nonNull } from "../../type-utils";
import { TypeErrors } from "../../../shared/errors";
import { astTypeToType, isAssignable, getIterableElementType, isIterable, substituteTypeParams } from "../../type-utils";
import type { InferContext } from "./context";
import { error, warning, setExpectedType } from "./context";
import { checkPattern, bindPattern } from "./check-pattern";
import { consumeSpawnsInExpr } from "./infer-spawn";
import { inferTypeParams, isNamedArg, getArgExpr } from "./infer-call";
import { exprContainsEscapingLambda } from "../context-utils";

function setNarrowTypes(env: TypeEnvironment, varName: string, types: Type[], mutable: boolean): void {
  if (types.length === 1) env.set(varName, types[0]!, mutable);
  else if (types.length > 1) env.set(varName, Types.union(...types), mutable);
}

function applyNarrowResult(
  env: TypeEnvironment,
  varName: string,
  narrowType: Type,
  symbol: { type: Type; mutable: boolean },
  ctx: InferContext,
  truthyBranch: boolean
): void {
  if (truthyBranch) {
    env.set(varName, narrowType, symbol.mutable);
  } else if (symbol.type.kind === "union") {
    const remaining = symbol.type.types.filter(
      (t: Type) => !(isAssignable(narrowType, t, ctx.env) && isAssignable(t, narrowType, ctx.env))
    );
    setNarrowTypes(env, varName, remaining, symbol.mutable);
  }
}

export function checkIfStmt(ctx: InferContext, stmt: AST.IfStmt): void {
  ctx.inferExpr(stmt.condition);

  const narrowedEnv = ctx.env.child();
  applyTypeNarrowing(ctx, stmt.condition, narrowedEnv, true);

  if (stmt.then.kind === "Block") {
    const savedEnv = ctx.env;
    ctx.env = narrowedEnv;
    for (const s of stmt.then.statements) ctx.checkStatement(s);
    ctx.env = savedEnv;
  } else {
    const savedEnv = ctx.env;
    ctx.env = narrowedEnv;
    ctx.checkStatement(stmt.then);
    ctx.env = savedEnv;
  }

  for (const elif of stmt.elseIfs) {
    ctx.inferExpr(elif.condition);
    const elifEnv = ctx.env.child();
    applyTypeNarrowing(ctx, elif.condition, elifEnv, true);
    const savedEnv = ctx.env;
    ctx.env = elifEnv;
    for (const s of elif.body.statements) ctx.checkStatement(s);
    ctx.env = savedEnv;
  }

  if (stmt.else) {
    const elseEnv = ctx.env.child();
    applyTypeNarrowing(ctx, stmt.condition, elseEnv, false);
    const savedEnv = ctx.env;
    ctx.env = elseEnv;
    for (const s of stmt.else.statements) ctx.checkStatement(s);
    ctx.env = savedEnv;
  }

  if (stmt.pattern && stmt.elseReturn) ctx.inferExpr(stmt.elseReturn);
}

export function applyTypeNarrowing(ctx: InferContext, condition: AST.Expr, env: TypeEnvironment, truthyBranch: boolean): void {
  if (condition.kind === "UnaryExpr" && (condition.op === "not" || condition.op === "!")) {
    applyTypeNarrowing(ctx, condition.operand, env, !truthyBranch);
    return;
  }
  if (condition.kind === "IsExpr") {
    narrowFromIsExpr(ctx, condition, env, truthyBranch);
    return;
  }
  if (condition.kind === "CallExpr") {
    narrowFromGuardCall(ctx, condition, env, truthyBranch);
    return;
  }
  if (condition.kind !== "BinaryExpr") return;

  if (condition.op === "and") {
    applyTypeNarrowing(ctx, condition.left, env, truthyBranch);
    applyTypeNarrowing(ctx, condition.right, env, truthyBranch);
  } else if (condition.op === "==" || condition.op === "!=") {
    narrowFromEquality(ctx, condition, env, truthyBranch);
  }
}

function narrowFromIsExpr(ctx: InferContext, expr: AST.IsExpr, env: TypeEnvironment, truthyBranch: boolean): void {
  if (expr.expr.kind !== "Identifier") return;
  const varName = expr.expr.name;
  const symbol = ctx.env.lookup(varName);
  if (!symbol) return;
  applyNarrowResult(env, varName, astTypeToType(expr.type), symbol, ctx, truthyBranch);
}

function narrowFromGuardCall(ctx: InferContext, expr: AST.CallExpr, env: TypeEnvironment, truthyBranch: boolean): void {
  const fnType = (expr.callee as AST.BaseNode).resolvedType as FunctionType | undefined;
  if (!fnType || fnType.kind !== "function" || !fnType.predicate) return;

  let argExpr: AST.Expr | undefined;
  const named = expr.args.find(a => isNamedArg(a) && a.name === fnType.predicate!.paramName);
  if (named && isNamedArg(named)) argExpr = named.value;
  else {
    const paramIndex = fnType.params.findIndex(p => p.name === fnType.predicate!.paramName);
    if (paramIndex >= 0 && paramIndex < expr.args.length) {
      const a = expr.args[paramIndex]!;
      if (!isNamedArg(a)) argExpr = a;
    }
  }
  if (!argExpr || argExpr.kind !== "Identifier") return;

  const varName = argExpr.name;
  const symbol = ctx.env.lookup(varName);
  if (!symbol) return;

  const typeBindings = inferTypeParams(ctx, fnType, expr.args);
  const narrowType = substituteTypeParams(fnType.predicate.targetType, typeBindings);
  applyNarrowResult(env, varName, narrowType, symbol, ctx, truthyBranch);
}

function narrowFromEquality(ctx: InferContext, expr: AST.BinaryExpr, env: TypeEnvironment, truthyBranch: boolean): void {
  // null check: x != null / x == null
  if (expr.left.kind === "Identifier" && expr.right.kind === "Literal" && expr.right.value === null) {
    narrowFromNullCheck(ctx, expr.left.name, expr.op, env, truthyBranch);
    return;
  }
  // literal equality: x == "foo" / x != 42
  if (expr.left.kind === "Identifier" && expr.right.kind === "Literal") {
    narrowFromLiteralCheck(ctx, expr.left.name, expr.op, expr.right, env, truthyBranch);
    return;
  }
  // discriminant narrowing: x.tag == "A"
  if (expr.left.kind === "MemberExpr" && expr.right.kind === "Literal") {
    narrowFromMemberEquality(ctx, expr.left as AST.MemberExpr, expr.op, expr.right, env, truthyBranch);
    return;
  }
  // typeof narrowing: typeof(x) == "number"
  if (expr.left.kind === "CallExpr") {
    narrowFromTypeof(ctx, expr.left as AST.CallExpr, expr.op, expr.right, env, truthyBranch);
  }
}

function narrowFromNullCheck(ctx: InferContext, varName: string, op: string, env: TypeEnvironment, truthyBranch: boolean): void {
  const symbol = ctx.env.lookup(varName);
  if (symbol && isNullable(symbol.type)) {
    const isNotNull = (op === "!=" && truthyBranch) || (op === "==" && !truthyBranch);
    if (isNotNull) env.set(varName, nonNull(symbol.type), symbol.mutable);
  }
}

function narrowFromLiteralCheck(ctx: InferContext, varName: string, op: string, literal: AST.Literal, env: TypeEnvironment, truthyBranch: boolean): void {
  const symbol = ctx.env.lookup(varName);
  if (!symbol) return;

  const isEqual = (op === "==" && truthyBranch) || (op === "!=" && !truthyBranch);
  if (isEqual) {
    env.set(varName, Types.literal(literal.value as string | number | boolean), symbol.mutable);
  } else if (symbol.type.kind === "union") {
    const literalStr = JSON.stringify(literal.value);
    const remaining = symbol.type.types.filter((t: Type) => {
      if (t.kind === "literal") return JSON.stringify(t.value) !== literalStr;
      return true;
    });
    setNarrowTypes(env, varName, remaining, symbol.mutable);
  }
}

function narrowFromMemberEquality(ctx: InferContext, memberExpr: AST.MemberExpr, op: string, literal: AST.Literal, env: TypeEnvironment, truthyBranch: boolean): void {
  if (memberExpr.object.kind !== "Identifier") return;
  const varName = memberExpr.object.name;
  const propName = memberExpr.property;
  const symbol = ctx.env.lookup(varName);
  if (!symbol || symbol.type.kind !== "union") return;

  const isEqual = (op === "==" && truthyBranch) || (op === "!=" && !truthyBranch);
  const literalValue = literal.value;
  const matching: Type[] = [];
  const nonMatching: Type[] = [];

  for (const t of symbol.type.types) {
    const resolved = t.kind === "ref" ? ctx.env.resolveType(t) : t;
    if (resolved.kind === "object") {
      const prop = (resolved as ObjectType).properties.find(p => p.name === propName);
      if (prop && prop.type.kind === "literal" && prop.type.value === literalValue) matching.push(t);
      else nonMatching.push(t);
    } else nonMatching.push(t);
  }

  if (isEqual && matching.length > 0) setNarrowTypes(env, varName, matching, symbol.mutable);
  else if (!isEqual && nonMatching.length > 0) setNarrowTypes(env, varName, nonMatching, symbol.mutable);
}

function narrowFromTypeof(ctx: InferContext, call: AST.CallExpr, op: string, right: AST.Expr, env: TypeEnvironment, truthyBranch: boolean): void {
  const callee = call.callee;
  const typeStr = right.kind === "Literal" && typeof right.value === "string" ? right.value : null;
  if (callee.kind !== "Identifier" || callee.name !== "typeof" || call.args.length !== 1 || !typeStr) return;

  const raw = call.args[0];
  const argExpr: AST.Expr | undefined = raw && "value" in raw ? (raw as { value: AST.Expr }).value : (raw as AST.Expr);
  if (argExpr?.kind !== "Identifier") return;

  const varName = (argExpr as AST.Identifier).name;
  const symbol = ctx.env.lookup(varName);
  if (!symbol) return;

  const TYPE_MAP: Record<string, Type> = {
    "number": Types.number, "string": Types.string, "boolean": Types.bool, "null": Types.null,
  };
  const narrowedType = TYPE_MAP[typeStr];
  if (narrowedType) {
    const isEqual = (op === "==" && truthyBranch) || (op === "!=" && !truthyBranch);
    if (isEqual) env.set(varName, narrowedType, symbol.mutable);
  }
}

export function checkForStmt(ctx: InferContext, stmt: AST.ForStmt): void {
  const prevInLoop = ctx.inLoop;
  ctx.inLoop = true;

  const bodyEnv = ctx.env.child();
  if (stmt.pattern && stmt.iterable) {
    const iterableType = ctx.inferExpr(stmt.iterable);
    if (!isIterable(iterableType)) {
      const err = TypeErrors.nonIterableForLoop(typeToString(iterableType));
      error(ctx, err.message, stmt.iterable.loc, err.hint);
    }
    const elementType = getIterableElementType(iterableType);
    const savedEnv = ctx.env;
    ctx.env = bodyEnv;
    bindPattern(ctx, stmt.pattern, elementType, false);
    ctx.env = savedEnv;
  }

  const savedEnv = ctx.env;
  ctx.env = bodyEnv;
  ctx.checkBlock(stmt.body);
  ctx.env = savedEnv;
  ctx.inLoop = prevInLoop;
}

export function checkMatchStmt(ctx: InferContext, stmt: AST.MatchStmt): void {
  const valueType = ctx.inferExpr(stmt.value);

  for (const arm of stmt.arms) {
    const armEnv = ctx.env.child();
    const savedEnv = ctx.env;
    ctx.env = armEnv;
    checkPattern(ctx, arm.pattern, valueType);
    if (arm.guard) {
      const guardType = ctx.inferExpr(arm.guard);
      if (guardType.kind !== "bool") {
        const err = TypeErrors.guardMustBeBool(typeToString(guardType));
        error(ctx, err.message, arm.guard.loc, err.hint);
      }
    }
    if (arm.body.kind === "Block") ctx.checkBlock(arm.body as AST.Block);
    else ctx.inferExpr(arm.body as AST.Expr);
    ctx.env = savedEnv;
  }

  checkMatchExhaustiveness(ctx, valueType, stmt.arms, stmt.loc);
}

function checkMatchExhaustiveness(ctx: InferContext, valueType: Type, arms: AST.MatchArm[], loc: AST.SourceLocation): void {
  const hasCatchAll = arms.some(arm =>
    arm.pattern.kind === "WildcardPattern" || (arm.pattern.kind === "IdentifierPattern" && !arm.guard));
  if (hasCatchAll) return;

  if (valueType.kind === "union") {
    const coveredTypes = new Set<string>();
    for (const arm of arms) {
      if (arm.guard) continue;
      if (arm.pattern.kind === "TypePattern") {
        coveredTypes.add(arm.pattern.type.kind === "NamedType"
          ? arm.pattern.type.name : typeToString(astTypeToType(arm.pattern.type)));
      } else if (arm.pattern.kind === "LiteralPattern" && arm.pattern.value === null) {
        coveredTypes.add("null");
      }
    }
    const uncovered: string[] = [];
    for (const t of valueType.types) {
      const typeName: string = t.kind === "ref" ? t.name :
        t.kind === "object" && (t as ObjectType).name ? (t as ObjectType).name! : typeToString(t);
      if (!coveredTypes.has(typeName)) uncovered.push(typeName);
    }
    if (uncovered.length > 0) {
      const err = TypeErrors.matchNotExhaustive(uncovered);
      error(ctx, err.message, loc, err.hint);
    }
  }

  if (valueType.kind === "optional") {
    const hasNullCase = arms.some(arm => arm.pattern.kind === "LiteralPattern" && arm.pattern.value === null);
    const hasValueCase = arms.some(arm => arm.pattern.kind === "TypePattern" || arm.pattern.kind === "IdentifierPattern");
    const missing: string[] = [];
    if (!hasNullCase) missing.push("null");
    if (!hasValueCase) missing.push(typeToString(valueType.inner));
    if (missing.length > 0) {
      const err = TypeErrors.matchNotExhaustive(missing);
      error(ctx, err.message, loc, err.hint);
    }
  }

  if (valueType.kind === "bool") {
    const hasTrue = arms.some(arm => arm.pattern.kind === "LiteralPattern" && arm.pattern.value === true);
    const hasFalse = arms.some(arm => arm.pattern.kind === "LiteralPattern" && arm.pattern.value === false);
    const missing: string[] = [];
    if (!hasTrue) missing.push("true");
    if (!hasFalse) missing.push("false");
    if (missing.length > 0) {
      const err = TypeErrors.matchNotExhaustive(missing);
      error(ctx, err.message, loc, err.hint);
    }
  }
}

export function checkReturnStmt(ctx: InferContext, stmt: AST.ReturnStmt): void {
  if (!ctx.currentFunction) {
    const err = TypeErrors.returnOutsideFunction();
    error(ctx, err.message, stmt.loc, err.hint);
    return;
  }

  if (stmt.value) {
    setExpectedType(stmt.value, ctx.currentFunction.returnType);
    const returnType = ctx.inferExpr(stmt.value);
    if (!isAssignable(returnType, ctx.currentFunction.returnType, ctx.env)) {
      const err = TypeErrors.typeMismatch(typeToString(ctx.currentFunction.returnType), typeToString(returnType));
      error(ctx, err.message, stmt.loc, err.hint);
    }
    consumeSpawnsInExpr(ctx, stmt.value);
    if (ctx.functionWithDepth > 0 && exprContainsEscapingLambda(stmt.value, ctx.withContextVars, ctx.env, ctx.fnDecls, ctx.needsContextCache)) {
      error(ctx,
        `Cannot return closure that depends on context from 'with' block - it would outlive the context scope`,
        stmt.loc,
        `Context is cleaned up when 'with' block exits, but the returned closure needs it to execute`
      );
    }
  } else if (ctx.currentFunction.returnType.kind !== "void") {
    const err = TypeErrors.returnMissingValue(typeToString(ctx.currentFunction.returnType));
    error(ctx, err.message, stmt.loc, err.hint);
  }
}

export function checkYieldStmt(ctx: InferContext, stmt: AST.YieldStmt): void {
  if (!ctx.currentFunction || !ctx.currentFunction.isGenerator) {
    const err = TypeErrors.yieldOutsideGenerator();
    error(ctx, err.message, stmt.loc, err.hint);
    return;
  }
  setExpectedType(stmt.value, ctx.currentFunction.returnType);
  ctx.inferExpr(stmt.value);
}

export function checkTryStmt(ctx: InferContext, stmt: AST.TryStmt): void {
  ctx.checkBlock(stmt.body);
  if (stmt.catch) {
    const catchEnv = ctx.env.child();
    catchEnv.define(stmt.catch.name, Types.ref("Error"));
    const savedEnv = ctx.env;
    ctx.env = catchEnv;
    ctx.checkBlock(stmt.catch.body);
    ctx.env = savedEnv;
  }
}

export function checkWithStmt(ctx: InferContext, stmt: AST.WithStmt): void {
  const bindings: UsingBinding[] = [];
  const isFunctionLevel = ctx.currentFunction !== null;
  const savedWithContextVars = new Set(ctx.withContextVars);

  const closableType = ctx.env.lookupType("Closable") ?? null;
  if (!closableType) {
    error(ctx, "Closable interface not found (builtins required)", stmt.loc);
    return;
  }

  for (const ctxBinding of stmt.contexts) {
    const ctxType = ctx.inferExpr(ctxBinding.expr);
    if (!isAssignable(ctxType, closableType, ctx.env)) {
      error(ctx,
        `Expression in 'with' must satisfy Closable (must have close(): void)`,
        ctxBinding.expr.loc,
        `Type '${typeToString(ctxType)}' does not have close(): void`
      );
    }
    if (ctxBinding.name) {
      bindings.push({ name: ctxBinding.name, type: ctxType });
      if (isFunctionLevel) ctx.withContextVars.add(ctxBinding.name);
    }
  }

  const withEnv = ctx.env.withContext(bindings);
  const savedEnv = ctx.env;
  ctx.env = withEnv;
  ctx.withBlockDepth++;
  ctx.insideWithContext = true;

  let savedContextDependent: Set<string> | null = null;
  if (isFunctionLevel) {
    ctx.functionWithDepth++;
    savedContextDependent = ctx.contextDependentSpawnsInWith;
    ctx.contextDependentSpawnsInWith = new Set();
  }

  ctx.checkBlock(stmt.body);

  if (isFunctionLevel) {
    const lastStmt = stmt.body.statements[stmt.body.statements.length - 1];
    if (lastStmt?.kind === "ExprStmt" && exprContainsEscapingLambda(lastStmt.expr, ctx.withContextVars, ctx.env, ctx.fnDecls, ctx.needsContextCache)) {
      error(ctx,
        `Cannot return closure that depends on context from 'with' block - it would outlive the context scope`,
        lastStmt.loc,
        `Context is cleaned up when 'with' block exits, but the returned closure needs it to execute`
      );
    }
    for (const name of ctx.contextDependentSpawnsInWith!) {
      const loc = ctx.unawaitedSpawns.get(name);
      if (loc) {
        error(ctx,
          `Cannot use 'spawn' inside function-level 'with' block - spawned task may outlive context scope`,
          loc,
          `Add e.g. \`let _ = race([${name}])\` or \`all_settled([${name}])\` before the block ends, or spawn a task that does not use the context`
        );
        ctx.unawaitedSpawns.delete(name);
      }
    }
    ctx.contextDependentSpawnsInWith = savedContextDependent;
    ctx.functionWithDepth--;
  }

  ctx.env = savedEnv;
  ctx.withBlockDepth--;
  ctx.insideWithContext = ctx.withBlockDepth > 0;
  ctx.withContextVars = savedWithContextVars;
}
