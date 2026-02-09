import * as AST from "../../../parser/ast";
import type { Type } from "../../types";
import { Types, typeToString } from "../../types";
import { TypeErrors } from "../../../shared/errors";
import { astTypeToType, isAssignable } from "../../type-utils";
import type { InferContext } from "./context";
import { error, warning, setExpectedType } from "./context";
import { bindPattern } from "./check-pattern";
import { exprContainsSpawn, transferSpawnTracking } from "./infer-spawn";
import {
  checkIfStmt, checkForStmt, checkMatchStmt,
  checkReturnStmt, checkYieldStmt, checkTryStmt, checkWithStmt
} from "./check-control-flow";
import { checkFnDecl, checkTypeDecl, checkTestDecl } from "./check-declarations";

export function checkStatement(ctx: InferContext, stmt: AST.Statement): void {
  switch (stmt.kind) {
    case "LetStmt":
      checkLetStmt(ctx, stmt);
      break;
    case "VarStmt":
      checkVarStmt(ctx, stmt);
      break;
    case "AssignStmt":
      checkAssignStmt(ctx, stmt);
      break;
    case "IfStmt":
      checkIfStmt(ctx, stmt);
      break;
    case "ForStmt":
      checkForStmt(ctx, stmt);
      break;
    case "MatchStmt":
      checkMatchStmt(ctx, stmt);
      break;
    case "ReturnStmt":
      checkReturnStmt(ctx, stmt);
      break;
    case "YieldStmt":
      checkYieldStmt(ctx, stmt);
      break;
    case "BreakStmt":
    case "ContinueStmt":
      if (!ctx.inLoop) {
        const err = stmt.kind === "BreakStmt" ? TypeErrors.breakOutsideLoop() : TypeErrors.continueOutsideLoop();
        error(ctx, err.message, stmt.loc, err.hint);
      }
      break;
    case "DeferStmt":
      checkStatement(ctx, stmt.body);
      break;
    case "TryStmt":
      checkTryStmt(ctx, stmt);
      break;
    case "ThrowStmt":
      ctx.inferExpr(stmt.value);
      break;
    case "WithStmt":
      checkWithStmt(ctx, stmt);
      break;
    case "ExprStmt":
      if (stmt.expr.kind === "SpawnExpr")
        error(ctx, "spawn result must be used (await, pass to all(), or assign to variable)", stmt.expr.loc);
      ctx.inferExpr(stmt.expr);
      break;
    case "FnDecl":
      checkFnDecl(ctx, stmt);
      break;
    case "ExternFnDecl":
    case "InterfaceDecl":
    case "ImportDecl":
      break;
    case "TypeDecl":
      checkTypeDecl(ctx, stmt);
      break;
    case "TestDecl":
      checkTestDecl(ctx, stmt);
      break;
  }
}

function checkLetStmt(ctx: InferContext, stmt: AST.LetStmt): void {
  const declaredType = stmt.type ? astTypeToType(stmt.type) : undefined;
  if (declaredType) setExpectedType(stmt.value, declaredType);
  const valueType = ctx.inferExpr(stmt.value);
  const resolvedDeclared = declaredType ?? valueType;

  if (stmt.type && !isAssignable(valueType, resolvedDeclared, ctx.env)) {
    const err = TypeErrors.typeMismatch(typeToString(resolvedDeclared), typeToString(valueType));
    error(ctx, err.message, stmt.loc, err.hint);
  }

  if (stmt.pattern.kind === "IdentifierPattern") {
    const containsSpawn = exprContainsSpawn(ctx, stmt.value);
    const isConsumerResult = stmt.value.kind === "CallExpr" &&
      stmt.value.callee.kind === "Identifier" &&
      (stmt.value.callee.name === "race" || stmt.value.callee.name === "all");

    if (containsSpawn && !isConsumerResult) {
      ctx.unawaitedSpawns.set(stmt.pattern.name, stmt.loc);
      if (stmt.value.kind === "SpawnExpr" && ctx.lastSpawnInWithWasContextDependent && ctx.contextDependentSpawnsInWith)
        ctx.contextDependentSpawnsInWith.add(stmt.pattern.name);
      ctx.lastSpawnInWithWasContextDependent = false;
      transferSpawnTracking(ctx, stmt.value);
    }
  }

  bindPattern(ctx, stmt.pattern, resolvedDeclared, false);
}

function checkVarStmt(ctx: InferContext, stmt: AST.VarStmt): void {
  const declaredType = stmt.type ? astTypeToType(stmt.type) : undefined;
  if (declaredType) setExpectedType(stmt.value, declaredType);
  const valueType = ctx.inferExpr(stmt.value);
  const resolvedDeclared = declaredType ?? valueType;

  if (stmt.type && !isAssignable(valueType, resolvedDeclared, ctx.env)) {
    const err = TypeErrors.typeMismatch(typeToString(resolvedDeclared), typeToString(valueType));
    error(ctx, err.message, stmt.loc, err.hint);
  }

  try {
    ctx.env.define(stmt.name, resolvedDeclared, true);
  } catch (e) {
    const err = TypeErrors.variableAlreadyDefined(stmt.name);
    error(ctx, err.message, stmt.loc, err.hint);
  }
}

function checkAssignStmt(ctx: InferContext, stmt: AST.AssignStmt): void {
  const targetType = ctx.inferExpr(stmt.target);
  setExpectedType(stmt.value, targetType);
  const valueType = ctx.inferExpr(stmt.value);

  if (stmt.target.kind === "Identifier") {
    const symbol = ctx.env.lookup(stmt.target.name);
    if (symbol && !symbol.mutable) {
      const err = TypeErrors.cannotAssignToImmutable(stmt.target.name);
      error(ctx, err.message, stmt.loc, err.hint);
    }
  }

  if (!isAssignable(valueType, targetType, ctx.env)) {
    const err = TypeErrors.typeMismatch(typeToString(targetType), typeToString(valueType));
    error(ctx, err.message, stmt.loc, err.hint);
  }
}

function isTerminatingStatement(stmt: AST.Statement): boolean {
  switch (stmt.kind) {
    case "ReturnStmt": case "ThrowStmt": case "BreakStmt": case "ContinueStmt":
      return true;
    case "IfStmt":
      if (!stmt.else) return false;
      const thenTerminates = stmt.then.kind === "Block" ? blockTerminates(stmt.then) : isTerminatingStatement(stmt.then);
      return thenTerminates && blockTerminates(stmt.else);
    case "MatchStmt":
      const hasCatchAll = stmt.arms.some(arm =>
        arm.pattern.kind === "WildcardPattern" || (arm.pattern.kind === "IdentifierPattern" && !arm.guard));
      if (!hasCatchAll) return false;
      return stmt.arms.every(arm => arm.body.kind === "Block" ? blockTerminates(arm.body) : false);
    default:
      return false;
  }
}

function blockTerminates(block: AST.Block): boolean {
  for (const stmt of block.statements) if (isTerminatingStatement(stmt)) return true;
  return false;
}

export function checkBlock(ctx: InferContext, block: AST.Block): void {
  const blockEnv = ctx.env.child();
  const savedEnv = ctx.env;
  ctx.env = blockEnv;

  let seenTerminator = false;
  for (const stmt of block.statements) {
    if (seenTerminator) {
      const err = TypeErrors.unreachableCode();
      warning(ctx, `${err.message} at line ${stmt.loc.line}. ${err.hint}`);
    }
    checkStatement(ctx, stmt);
    if (isTerminatingStatement(stmt)) seenTerminator = true;
  }

  ctx.env = savedEnv;
}
