// Context utilities - Functions for analyzing context-dependent code
import * as AST from "../../parser/ast";
import { isFunctionType } from "../types";
import type { TypeEnvironment } from "../environment";

// Check if function needs context
function fnNeedsContext(name: string, env: TypeEnvironment, fnDecls: Map<string, AST.FnDecl>, cache: Map<string, boolean>): boolean {
  if (cache.has(name)) return cache.get(name)!;
  cache.set(name, false);

  const symbol = env.lookup(name);
  if (symbol && isFunctionType(symbol.type) && symbol.type.context.length > 0) {
    cache.set(name, true);
    return true;
  }

  const decl = fnDecls.get(name);
  if (decl?.body && blockNeedsContext(decl.body, env, fnDecls, cache)) {
    cache.set(name, true);
    return true;
  }
  return false;
}

function blockNeedsContext(block: AST.Block, env: TypeEnvironment, fnDecls: Map<string, AST.FnDecl>, cache: Map<string, boolean>): boolean {
  return block.statements.some(s => stmtNeedsContext(s, env, fnDecls, cache));
}

function stmtNeedsContext(stmt: AST.Statement, env: TypeEnvironment, fnDecls: Map<string, AST.FnDecl>, cache: Map<string, boolean>): boolean {
  switch (stmt.kind) {
    case "ExprStmt": return exprNeedsContext(stmt.expr, env, fnDecls, cache);
    case "LetStmt": case "VarStmt": return exprNeedsContext(stmt.value, env, fnDecls, cache);
    case "AssignStmt": return exprNeedsContext(stmt.value, env, fnDecls, cache);
    case "IfStmt": {
      const then = stmt.then.kind === "Block" ? blockNeedsContext(stmt.then, env, fnDecls, cache) : stmtNeedsContext(stmt.then, env, fnDecls, cache);
      return exprNeedsContext(stmt.condition, env, fnDecls, cache) || then || (stmt.else ? blockNeedsContext(stmt.else, env, fnDecls, cache) : false);
    }
    case "ForStmt": return (stmt.iterable ? exprNeedsContext(stmt.iterable, env, fnDecls, cache) : false) || blockNeedsContext(stmt.body, env, fnDecls, cache);
    case "ReturnStmt": return stmt.value ? exprNeedsContext(stmt.value, env, fnDecls, cache) : false;
    case "WithStmt": return blockNeedsContext(stmt.body, env, fnDecls, cache);
    default: return false;
  }
}

export function exprNeedsContext(expr: AST.Expr, env: TypeEnvironment, fnDecls: Map<string, AST.FnDecl>, cache: Map<string, boolean>): boolean {
  switch (expr.kind) {
    case "CallExpr":
      if (expr.callee.kind === "Identifier" && fnNeedsContext(expr.callee.name, env, fnDecls, cache)) return true;
      return expr.args.some(a => exprNeedsContext("kind" in a ? a : a.value, env, fnDecls, cache));
    case "LambdaExpr": return expr.body.kind === "Block" ? blockNeedsContext(expr.body, env, fnDecls, cache) : exprNeedsContext(expr.body, env, fnDecls, cache);
    case "BinaryExpr": return exprNeedsContext(expr.left, env, fnDecls, cache) || exprNeedsContext(expr.right, env, fnDecls, cache);
    case "UnaryExpr": return exprNeedsContext(expr.operand, env, fnDecls, cache);
    case "IfExpr": return exprNeedsContext(expr.condition, env, fnDecls, cache) || exprNeedsContext(expr.then, env, fnDecls, cache) || exprNeedsContext(expr.else, env, fnDecls, cache);
    case "ListExpr": return expr.elements.some(e => exprNeedsContext(e.kind === "SpreadElement" ? e.expr : e, env, fnDecls, cache));
    case "SetExpr": return expr.elements.some(e => exprNeedsContext(e, env, fnDecls, cache));
    case "MapExpr": return expr.entries.some(e => exprNeedsContext(e.value, env, fnDecls, cache));
    case "MemberExpr": return exprNeedsContext(expr.object, env, fnDecls, cache);
    case "IndexExpr": return exprNeedsContext(expr.object, env, fnDecls, cache) || exprNeedsContext(expr.index, env, fnDecls, cache);
    case "PipeExpr": return exprNeedsContext(expr.left, env, fnDecls, cache) || exprNeedsContext(expr.right, env, fnDecls, cache);
    case "IsExpr": return exprNeedsContext(expr.expr, env, fnDecls, cache);
    default: return false;
  }
}

// Check if expression contains escaping lambda
export function exprContainsEscapingLambda(expr: AST.Expr, ctxVars: Set<string>, env: TypeEnvironment, fnDecls: Map<string, AST.FnDecl>, cache: Map<string, boolean>): boolean {
  switch (expr.kind) {
    case "LambdaExpr": return expr.body.kind === "Block" ? blockNeedsContext(expr.body, env, fnDecls, cache) : exprNeedsContext(expr.body, env, fnDecls, cache);
    case "Identifier": return ctxVars.has(expr.name);
    case "ListExpr": return expr.elements.some(e => exprContainsEscapingLambda(e.kind === "SpreadElement" ? e.expr : e, ctxVars, env, fnDecls, cache));
    case "SetExpr": return expr.elements.some(e => exprContainsEscapingLambda(e, ctxVars, env, fnDecls, cache));
    case "MapExpr": return expr.entries.some(e => exprContainsEscapingLambda(e.value, ctxVars, env, fnDecls, cache));
    case "IfExpr": return exprContainsEscapingLambda(expr.then, ctxVars, env, fnDecls, cache) || exprContainsEscapingLambda(expr.else, ctxVars, env, fnDecls, cache);
    case "CallExpr": return expr.args.some(a => exprContainsEscapingLambda("kind" in a ? a : a.value, ctxVars, env, fnDecls, cache));
    case "IsExpr": return exprContainsEscapingLambda(expr.expr, ctxVars, env, fnDecls, cache);
    default: return false;
  }
}
