import type * as AST from "../../../parser/ast";
import type { Type, FunctionType } from "../../types";
import { Types } from "../../types";
import { typeInvolvesPromise } from "../../type-utils";
import type { InferContext } from "./context";
import { exprContainsEscapingLambda, exprNeedsContext } from "../context-analysis";

export function inferSpawnExpr(ctx: InferContext, expr: AST.SpawnExpr): Type {
  ctx.lastSpawnInWithWasContextDependent = false;
  if (ctx.functionWithDepth > 0) {
    const capturesContext =
      exprContainsEscapingLambda(expr.expr, ctx.withContextVars, ctx.env, ctx.fnDecls, ctx.needsContextCache) ||
      exprNeedsContext(expr.expr, ctx.env, ctx.fnDecls, ctx.needsContextCache);
    if (capturesContext) ctx.lastSpawnInWithWasContextDependent = true;
  }
  const innerType = ctx.inferExpr(ctx, expr.expr);
  return Types.promise(innerType.kind === "function" ? (innerType as FunctionType).returnType : innerType);
}

export function consumeSpawnsInExpr(ctx: InferContext, expr: AST.Expr): void {
  switch (expr.kind) {
    case "Identifier":
      ctx.unawaitedSpawns.delete(expr.name);
      ctx.contextDependentSpawnsInWith?.delete(expr.name);
      break;
    case "ListExpr":
      for (const el of expr.elements) {
        if (el.kind !== "SpreadElement") consumeSpawnsInExpr(ctx, el);
        else consumeSpawnsInExpr(ctx, el.expr);
      }
      break;
    case "SetExpr":
      for (const el of expr.elements) consumeSpawnsInExpr(ctx, el);
      break;
    case "MapExpr":
      for (const entry of expr.entries) consumeSpawnsInExpr(ctx, entry.value);
      break;
    case "IfExpr":
      consumeSpawnsInExpr(ctx, expr.then);
      if (expr.else) consumeSpawnsInExpr(ctx, expr.else);
      break;
    case "IndexExpr":
      consumeSpawnsInExpr(ctx, expr.object);
      break;
    case "MemberExpr":
      consumeSpawnsInExpr(ctx, expr.object);
      break;
    case "CallExpr": {
      const callReturnType = expr.resolvedType ?? Types.unknown;
      const isValuesCall = expr.callee.kind === "Identifier" && expr.callee.name === "values";
      if (typeInvolvesPromise(callReturnType, ctx.env) || isValuesCall) {
        for (const arg of expr.args) consumeSpawnsInExpr(ctx, "kind" in arg ? arg : arg.value);
      }
      break;
    }
  }
}

export function exprContainsSpawn(ctx: InferContext, expr: AST.Expr): boolean {
  if (expr.kind === "SpawnExpr") return true;
  if (expr.kind === "Identifier" && ctx.unawaitedSpawns.has(expr.name)) return true;
  if (expr.kind === "CallExpr") {
    for (const arg of expr.args) {
      if (exprContainsSpawn(ctx, "kind" in arg ? arg : arg.value)) return true;
    }
  }
  if (expr.kind === "ListExpr") {
    for (const el of expr.elements) {
      if (el.kind === "SpreadElement" ? exprContainsSpawn(ctx, el.expr) : exprContainsSpawn(ctx, el)) return true;
    }
  }
  if (expr.kind === "SetExpr") {
    for (const el of expr.elements) if (exprContainsSpawn(ctx, el)) return true;
  }
  if (expr.kind === "MapExpr") {
    for (const entry of expr.entries) if (exprContainsSpawn(ctx, entry.value)) return true;
  }
  if (expr.kind === "IndexExpr" && expr.object.kind === "Identifier" && ctx.unawaitedSpawns.has(expr.object.name)) return true;
  if (expr.kind === "MemberExpr" && expr.object.kind === "Identifier" && ctx.unawaitedSpawns.has(expr.object.name)) return true;
  if (expr.kind === "IfExpr") {
    if (exprContainsSpawn(ctx, expr.then)) return true;
    if (expr.else && exprContainsSpawn(ctx, expr.else)) return true;
  }
  return false;
}

export function transferSpawnTracking(ctx: InferContext, expr: AST.Expr): void {
  if (expr.kind === "Identifier") {
    ctx.unawaitedSpawns.delete(expr.name);
  } else if (expr.kind === "IfExpr") {
    if (expr.then.kind === "Identifier") ctx.unawaitedSpawns.delete(expr.then.name);
    if (expr.else?.kind === "Identifier") ctx.unawaitedSpawns.delete(expr.else.name);
  } else if (expr.kind === "ListExpr") {
    for (const el of expr.elements) {
      if (el.kind === "Identifier") ctx.unawaitedSpawns.delete(el.name);
      else if (el.kind === "SpreadElement" && el.expr.kind === "Identifier") ctx.unawaitedSpawns.delete(el.expr.name);
    }
  } else if (expr.kind === "SetExpr") {
    for (const el of expr.elements) if (el.kind === "Identifier") ctx.unawaitedSpawns.delete(el.name);
  } else if (expr.kind === "MapExpr") {
    for (const entry of expr.entries) if (entry.value.kind === "Identifier") ctx.unawaitedSpawns.delete(entry.value.name);
  } else if (expr.kind === "CallExpr") {
    for (const arg of expr.args) transferSpawnTracking(ctx, "kind" in arg ? arg : arg.value);
  }
}
