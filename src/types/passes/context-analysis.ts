// Pass 3: Context Analysis - Checks for context-dependent code escaping 'with' blocks
import * as AST from "../../parser/ast";
import type { FunctionType } from "../types";
import type { TypeEnvironment } from "../environment";
import { TypeCheckError } from "../errors";
import { exprReferences } from "../ast-visitor";

export interface ContextAnalysisInput {
  program: AST.Program;
  env: TypeEnvironment;
  fnDecls: Map<string, AST.FnDecl>;
}

export interface ContextAnalysisOutput {
  errors: TypeCheckError[];
}

type AliasMap = Map<string, Set<string>>;

export function analyzeContext(input: ContextAnalysisInput): ContextAnalysisOutput {
  const { program, env, fnDecls } = input;
  const errors: TypeCheckError[] = [];
  const cache = new Map<string, boolean>();

  const addError = (msg: string, loc: AST.SourceLocation, hint?: string) => {
    errors.push(new TypeCheckError(msg, loc, hint));
  };

  for (const stmt of program.body) {
    analyzeStmt(stmt, env, fnDecls, cache, new Set(), new Map(), addError);
  }

  return { errors };
}

function analyzeStmt(
  stmt: AST.Statement,
  env: TypeEnvironment,
  fnDecls: Map<string, AST.FnDecl>,
  cache: Map<string, boolean>,
  ctxVars: Set<string>,
  aliases: AliasMap,
  addError: (msg: string, loc: AST.SourceLocation, hint?: string) => void
): void {
  switch (stmt.kind) {
    case "FnDecl":
      analyzeBlock(stmt.body, env, fnDecls, cache, ctxVars, aliases, addError);
      break;
    case "WithStmt": {
      const newVars = new Set(ctxVars);
      for (const ctx of stmt.contexts) if (ctx.name) newVars.add(ctx.name);
      analyzeBlock(stmt.body, env, fnDecls, cache, newVars, new Map(aliases), addError);
      break;
    }
    case "LetStmt": {
      const captured = findCapturedVars(stmt.value, ctxVars, aliases);
      if (captured.size > 0 && stmt.pattern.kind === "IdentifierPattern") {
        aliases.set(stmt.pattern.name, captured);
      }
      break;
    }
    case "VarStmt": {
      const captured = findCapturedVars(stmt.value, ctxVars, aliases);
      if (captured.size > 0) aliases.set(stmt.name, captured);
      break;
    }
    case "IfStmt": {
      const then = stmt.then.kind === "Block" ? stmt.then : { statements: [stmt.then] } as AST.Block;
      analyzeBlock(then, env, fnDecls, cache, ctxVars, aliases, addError);
      for (const ei of stmt.elseIfs) analyzeBlock(ei.body, env, fnDecls, cache, ctxVars, aliases, addError);
      if (stmt.else) analyzeBlock(stmt.else, env, fnDecls, cache, ctxVars, aliases, addError);
      break;
    }
    case "ForStmt":
      analyzeBlock(stmt.body, env, fnDecls, cache, ctxVars, aliases, addError);
      break;
    case "TryStmt":
      analyzeBlock(stmt.body, env, fnDecls, cache, ctxVars, aliases, addError);
      if (stmt.catch) analyzeBlock(stmt.catch.body, env, fnDecls, cache, ctxVars, aliases, addError);
      break;
  }
}

function analyzeBlock(
  block: AST.Block,
  env: TypeEnvironment,
  fnDecls: Map<string, AST.FnDecl>,
  cache: Map<string, boolean>,
  ctxVars: Set<string>,
  aliases: AliasMap,
  addError: (msg: string, loc: AST.SourceLocation, hint?: string) => void
): void {
  for (const stmt of block.statements) {
    analyzeStmt(stmt, env, fnDecls, cache, ctxVars, aliases, addError);
  }
}

// Find all context variables captured by an expression
function findCapturedVars(expr: AST.Expr, ctxVars: Set<string>, aliases: AliasMap): Set<string> {
  const captured = new Set<string>();
  visitExpr(expr, e => {
    if (e.kind === "Identifier") {
      if (ctxVars.has(e.name)) captured.add(e.name);
      else if (aliases.has(e.name)) for (const v of aliases.get(e.name)!) captured.add(v);
    }
  });
  return captured;
}

// Generic expression visitor
function visitExpr(expr: AST.Expr, fn: (e: AST.Expr) => void): void {
  fn(expr);
  switch (expr.kind) {
    case "BinaryExpr": visitExpr(expr.left, fn); visitExpr(expr.right, fn); break;
    case "UnaryExpr": visitExpr(expr.operand, fn); break;
    case "CallExpr":
      visitExpr(expr.callee, fn);
      for (const arg of expr.args) visitExpr("kind" in arg ? arg : arg.value, fn);
      break;
    case "MemberExpr": visitExpr(expr.object, fn); break;
    case "IndexExpr": visitExpr(expr.object, fn); visitExpr(expr.index, fn); break;
    case "ListExpr":
      for (const el of expr.elements) visitExpr(el.kind === "SpreadElement" ? el.expr : el, fn);
      break;
    case "MapExpr": for (const e of expr.entries) visitExpr(e.value, fn); break;
    case "IfExpr": visitExpr(expr.condition, fn); visitExpr(expr.then, fn); visitExpr(expr.else, fn); break;
    case "PipeExpr": visitExpr(expr.left, fn); visitExpr(expr.right, fn); break;
  }
}

// Check if function needs context
function fnNeedsContext(name: string, env: TypeEnvironment, fnDecls: Map<string, AST.FnDecl>, cache: Map<string, boolean>): boolean {
  if (cache.has(name)) return cache.get(name)!;
  cache.set(name, false);

  const symbol = env.lookup(name);
  if (symbol?.type.kind === "function" && (symbol.type as FunctionType).context.length > 0) {
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

function exprNeedsContext(expr: AST.Expr, env: TypeEnvironment, fnDecls: Map<string, AST.FnDecl>, cache: Map<string, boolean>): boolean {
  switch (expr.kind) {
    case "CallExpr":
      if (expr.callee.kind === "Identifier" && fnNeedsContext(expr.callee.name, env, fnDecls, cache)) return true;
      return expr.args.some(a => exprNeedsContext("kind" in a ? a : a.value, env, fnDecls, cache));
    case "LambdaExpr": return expr.body.kind === "Block" ? blockNeedsContext(expr.body, env, fnDecls, cache) : exprNeedsContext(expr.body, env, fnDecls, cache);
    case "BinaryExpr": return exprNeedsContext(expr.left, env, fnDecls, cache) || exprNeedsContext(expr.right, env, fnDecls, cache);
    case "UnaryExpr": return exprNeedsContext(expr.operand, env, fnDecls, cache);
    case "IfExpr": return exprNeedsContext(expr.condition, env, fnDecls, cache) || exprNeedsContext(expr.then, env, fnDecls, cache) || exprNeedsContext(expr.else, env, fnDecls, cache);
    case "ListExpr": return expr.elements.some(e => exprNeedsContext(e.kind === "SpreadElement" ? e.expr : e, env, fnDecls, cache));
    case "MapExpr": return expr.entries.some(e => exprNeedsContext(e.value, env, fnDecls, cache));
    case "MemberExpr": return exprNeedsContext(expr.object, env, fnDecls, cache);
    case "IndexExpr": return exprNeedsContext(expr.object, env, fnDecls, cache) || exprNeedsContext(expr.index, env, fnDecls, cache);
    case "PipeExpr": return exprNeedsContext(expr.left, env, fnDecls, cache) || exprNeedsContext(expr.right, env, fnDecls, cache);
    default: return false;
  }
}

// Check if expression contains escaping lambda
export function exprContainsEscapingLambda(expr: AST.Expr, ctxVars: Set<string>, env: TypeEnvironment, fnDecls: Map<string, AST.FnDecl>, cache: Map<string, boolean>): boolean {
  switch (expr.kind) {
    case "LambdaExpr": return expr.body.kind === "Block" ? blockNeedsContext(expr.body, env, fnDecls, cache) : exprNeedsContext(expr.body, env, fnDecls, cache);
    case "Identifier": return ctxVars.has(expr.name);
    case "ListExpr": return expr.elements.some(e => exprContainsEscapingLambda(e.kind === "SpreadElement" ? e.expr : e, ctxVars, env, fnDecls, cache));
    case "MapExpr": return expr.entries.some(e => exprContainsEscapingLambda(e.value, ctxVars, env, fnDecls, cache));
    case "IfExpr": return exprContainsEscapingLambda(expr.then, ctxVars, env, fnDecls, cache) || exprContainsEscapingLambda(expr.else, ctxVars, env, fnDecls, cache);
    case "CallExpr": return expr.args.some(a => exprContainsEscapingLambda("kind" in a ? a : a.value, ctxVars, env, fnDecls, cache));
    default: return false;
  }
}

// Check if a parameter escapes from function body
export function parameterEscapes(fn: AST.FnDecl, paramName: string, fnDecls: Map<string, AST.FnDecl>): boolean {
  if (!fn.body) return true;
  return paramEscapesInBlock(fn.body, paramName, fnDecls);
}

function paramEscapesInBlock(block: AST.Block, param: string, fnDecls: Map<string, AST.FnDecl>): boolean {
  return block.statements.some(s => paramEscapesInStmt(s, param, fnDecls));
}

function paramEscapesInStmt(stmt: AST.Statement, param: string, fnDecls: Map<string, AST.FnDecl>): boolean {
  switch (stmt.kind) {
    case "ReturnStmt": return stmt.value ? exprReferences(stmt.value, param) : false;
    case "AssignStmt": return stmt.target.kind !== "Identifier" && exprReferences(stmt.value, param);
    case "ExprStmt": return paramEscapesInExpr(stmt.expr, param, fnDecls);
    case "IfStmt": {
      const then = stmt.then.kind === "Block" ? paramEscapesInBlock(stmt.then, param, fnDecls) : paramEscapesInStmt(stmt.then, param, fnDecls);
      return then || (stmt.else ? paramEscapesInBlock(stmt.else, param, fnDecls) : false);
    }
    case "ForStmt": return paramEscapesInBlock(stmt.body, param, fnDecls);
    default: return false;
  }
}

function paramEscapesInExpr(expr: AST.Expr, param: string, fnDecls: Map<string, AST.FnDecl>): boolean {
  if (expr.kind !== "CallExpr") return false;
  
  for (let i = 0; i < expr.args.length; i++) {
    const arg = expr.args[i];
    const argExpr = arg && ("kind" in arg ? arg : arg.value);
    if (argExpr && exprReferences(argExpr, param)) {
      if (expr.callee.kind === "Identifier") {
        const decl = fnDecls.get(expr.callee.name);
        const calleeParam = decl?.params[i];
        if (decl && calleeParam && parameterEscapes(decl, calleeParam.name, fnDecls)) return true;
        if (!decl) return true;
      } else {
        return true;
      }
    }
  }
  
  if (expr.callee.kind !== "Identifier" && expr.callee.kind !== "MemberExpr") {
    return paramEscapesInExpr(expr.callee, param, fnDecls);
  }
  return false;
}
