// Pass 3: Context Analysis
// Checks for context-dependent lambdas escaping 'with' blocks
import * as AST from "../../parser/ast";
import type { Type, FunctionType } from "../types";
import type { TypeEnvironment } from "../environment";
import { TypeCheckError } from "../errors";
import { exprReferences, blockReferences, stmtReferences } from "../ast-visitor";

export interface ContextAnalysisInput {
  program: AST.Program;
  env: TypeEnvironment;
  fnDecls: Map<string, AST.FnDecl>;
}

export interface ContextAnalysisOutput {
  errors: TypeCheckError[];
}

export function analyzeContext(input: ContextAnalysisInput): ContextAnalysisOutput {
  const { program, env, fnDecls } = input;
  const errors: TypeCheckError[] = [];
  const needsContextCache = new Map<string, boolean>();

  const addError = (message: string, loc: AST.SourceLocation, hint?: string) => {
    errors.push(new TypeCheckError(message, loc, hint));
  };

  // Analyze each statement for context issues
  for (const stmt of program.body) {
    analyzeStmt(stmt, env, fnDecls, needsContextCache, new Set(), addError);
  }

  return { errors };
}

function analyzeStmt(
  stmt: AST.Statement,
  env: TypeEnvironment,
  fnDecls: Map<string, AST.FnDecl>,
  cache: Map<string, boolean>,
  withContextVars: Set<string>,
  addError: (msg: string, loc: AST.SourceLocation, hint?: string) => void
): void {
  switch (stmt.kind) {
    case "FnDecl":
      analyzeBlock(stmt.body, env, fnDecls, cache, withContextVars, addError);
      break;
    case "WithStmt": {
      // Track context variables
      const newWithVars = new Set(withContextVars);
      for (const ctx of stmt.contexts) {
        if (ctx.name) newWithVars.add(ctx.name);
      }
      analyzeBlock(stmt.body, env, fnDecls, cache, newWithVars, addError);
      break;
    }
    case "IfStmt": {
      if (stmt.then.kind === "Block") {
        analyzeBlock(stmt.then, env, fnDecls, cache, withContextVars, addError);
      } else {
        analyzeStmt(stmt.then, env, fnDecls, cache, withContextVars, addError);
      }
      for (const elseIf of stmt.elseIfs) {
        analyzeBlock(elseIf.body, env, fnDecls, cache, withContextVars, addError);
      }
      if (stmt.else) {
        analyzeBlock(stmt.else, env, fnDecls, cache, withContextVars, addError);
      }
      break;
    }
    case "ForStmt":
      analyzeBlock(stmt.body, env, fnDecls, cache, withContextVars, addError);
      break;
    case "TryStmt":
      analyzeBlock(stmt.body, env, fnDecls, cache, withContextVars, addError);
      if (stmt.catch) {
        analyzeBlock(stmt.catch.body, env, fnDecls, cache, withContextVars, addError);
      }
      break;
  }
}

function analyzeBlock(
  block: AST.Block,
  env: TypeEnvironment,
  fnDecls: Map<string, AST.FnDecl>,
  cache: Map<string, boolean>,
  withContextVars: Set<string>,
  addError: (msg: string, loc: AST.SourceLocation, hint?: string) => void
): void {
  for (const stmt of block.statements) {
    analyzeStmt(stmt, env, fnDecls, cache, withContextVars, addError);
  }
}

// Check if a function needs context (has using clause or calls functions that do)
function functionNeedsContext(
  fnName: string,
  env: TypeEnvironment,
  fnDecls: Map<string, AST.FnDecl>,
  cache: Map<string, boolean>
): boolean {
  if (cache.has(fnName)) return cache.get(fnName)!;

  // Prevent infinite recursion
  cache.set(fnName, false);

  // Check if function has using clause
  const symbol = env.lookup(fnName);
  if (symbol?.type.kind === "function" && (symbol.type as FunctionType).context.length > 0) {
    cache.set(fnName, true);
    return true;
  }

  // Check if function body calls any function that needs context
  const fnDecl = fnDecls.get(fnName);
  if (fnDecl?.body) {
    if (blockNeedsContext(fnDecl.body, env, fnDecls, cache)) {
      cache.set(fnName, true);
      return true;
    }
  }

  return false;
}

function blockNeedsContext(
  block: AST.Block,
  env: TypeEnvironment,
  fnDecls: Map<string, AST.FnDecl>,
  cache: Map<string, boolean>
): boolean {
  for (const stmt of block.statements) {
    if (stmtNeedsContext(stmt, env, fnDecls, cache)) return true;
  }
  return false;
}

function stmtNeedsContext(
  stmt: AST.Statement,
  env: TypeEnvironment,
  fnDecls: Map<string, AST.FnDecl>,
  cache: Map<string, boolean>
): boolean {
  switch (stmt.kind) {
    case "ExprStmt":
      return exprNeedsContext(stmt.expr, env, fnDecls, cache);
    case "LetStmt":
    case "VarStmt":
      return exprNeedsContext(stmt.value, env, fnDecls, cache);
    case "AssignStmt":
      return exprNeedsContext(stmt.value, env, fnDecls, cache);
    case "IfStmt": {
      const thenNeedsCtx = stmt.then.kind === "Block"
        ? blockNeedsContext(stmt.then, env, fnDecls, cache)
        : stmtNeedsContext(stmt.then, env, fnDecls, cache);
      const elseNeedsCtx = stmt.else ? blockNeedsContext(stmt.else, env, fnDecls, cache) : false;
      return exprNeedsContext(stmt.condition, env, fnDecls, cache) || thenNeedsCtx || elseNeedsCtx;
    }
    case "ForStmt":
      return (stmt.iterable ? exprNeedsContext(stmt.iterable, env, fnDecls, cache) : false) ||
        blockNeedsContext(stmt.body, env, fnDecls, cache);
    case "ReturnStmt":
      return stmt.value ? exprNeedsContext(stmt.value, env, fnDecls, cache) : false;
    case "WithStmt":
      return blockNeedsContext(stmt.body, env, fnDecls, cache);
    default:
      return false;
  }
}

function exprNeedsContext(
  expr: AST.Expr,
  env: TypeEnvironment,
  fnDecls: Map<string, AST.FnDecl>,
  cache: Map<string, boolean>
): boolean {
  switch (expr.kind) {
    case "CallExpr":
      if (expr.callee.kind === "Identifier") {
        if (functionNeedsContext(expr.callee.name, env, fnDecls, cache)) return true;
      }
      for (const arg of expr.args) {
        const argExpr = "kind" in arg ? arg : arg.value;
        if (exprNeedsContext(argExpr, env, fnDecls, cache)) return true;
      }
      return false;
    case "LambdaExpr":
      return lambdaNeedsContext(expr, env, fnDecls, cache);
    case "BinaryExpr":
      return exprNeedsContext(expr.left, env, fnDecls, cache) || exprNeedsContext(expr.right, env, fnDecls, cache);
    case "UnaryExpr":
      return exprNeedsContext(expr.operand, env, fnDecls, cache);
    case "IfExpr":
      return exprNeedsContext(expr.condition, env, fnDecls, cache) ||
        exprNeedsContext(expr.then, env, fnDecls, cache) ||
        exprNeedsContext(expr.else, env, fnDecls, cache);
    case "ListExpr":
      return expr.elements.some(e =>
        e.kind === "SpreadElement" ? exprNeedsContext(e.expr, env, fnDecls, cache) : exprNeedsContext(e, env, fnDecls, cache)
      );
    case "MapExpr":
      return expr.entries.some(e => exprNeedsContext(e.value, env, fnDecls, cache));
    case "MemberExpr":
      return exprNeedsContext(expr.object, env, fnDecls, cache);
    case "IndexExpr":
      return exprNeedsContext(expr.object, env, fnDecls, cache) || exprNeedsContext(expr.index, env, fnDecls, cache);
    case "PipeExpr":
      return exprNeedsContext(expr.left, env, fnDecls, cache) || exprNeedsContext(expr.right, env, fnDecls, cache);
    default:
      return false;
  }
}

function lambdaNeedsContext(
  lambda: AST.LambdaExpr,
  env: TypeEnvironment,
  fnDecls: Map<string, AST.FnDecl>,
  cache: Map<string, boolean>
): boolean {
  if (lambda.body.kind === "Block") {
    return blockNeedsContext(lambda.body, env, fnDecls, cache);
  } else {
    return exprNeedsContext(lambda.body, env, fnDecls, cache);
  }
}

// Check if an expression contains a context-dependent lambda that would escape
export function exprContainsEscapingLambda(
  expr: AST.Expr,
  withContextVars: Set<string>,
  env: TypeEnvironment,
  fnDecls: Map<string, AST.FnDecl>,
  cache: Map<string, boolean>
): boolean {
  switch (expr.kind) {
    case "LambdaExpr":
      return lambdaNeedsContext(expr, env, fnDecls, cache);
    case "Identifier":
      return withContextVars.has(expr.name);
    case "ListExpr":
      return expr.elements.some(e =>
        e.kind === "SpreadElement"
          ? exprContainsEscapingLambda(e.expr, withContextVars, env, fnDecls, cache)
          : exprContainsEscapingLambda(e, withContextVars, env, fnDecls, cache)
      );
    case "MapExpr":
      return expr.entries.some(e => exprContainsEscapingLambda(e.value, withContextVars, env, fnDecls, cache));
    case "IfExpr":
      return exprContainsEscapingLambda(expr.then, withContextVars, env, fnDecls, cache) ||
        exprContainsEscapingLambda(expr.else, withContextVars, env, fnDecls, cache);
    case "CallExpr":
      for (const arg of expr.args) {
        const argExpr = "kind" in arg ? arg : arg.value;
        if (exprContainsEscapingLambda(argExpr, withContextVars, env, fnDecls, cache)) return true;
      }
      return false;
    default:
      return false;
  }
}

// Check if a parameter escapes within a function body
export function parameterEscapes(fnDecl: AST.FnDecl, paramName: string, fnDecls: Map<string, AST.FnDecl>): boolean {
  if (!fnDecl.body) return true; // Extern functions: assume escapes
  return paramEscapesInBlock(fnDecl.body, paramName, fnDecls);
}

function paramEscapesInBlock(block: AST.Block, paramName: string, fnDecls: Map<string, AST.FnDecl>): boolean {
  for (const stmt of block.statements) {
    if (paramEscapesInStmt(stmt, paramName, fnDecls)) return true;
  }
  return false;
}

function paramEscapesInStmt(stmt: AST.Statement, paramName: string, fnDecls: Map<string, AST.FnDecl>): boolean {
  switch (stmt.kind) {
    case "ReturnStmt":
      if (stmt.value && exprReferences(stmt.value, paramName)) return true;
      return false;
    case "LetStmt":
    case "VarStmt":
      return false;
    case "AssignStmt":
      if (stmt.target.kind !== "Identifier" && exprReferences(stmt.value, paramName)) {
        return true;
      }
      return false;
    case "ExprStmt":
      return paramEscapesInExpr(stmt.expr, paramName, fnDecls);
    case "IfStmt": {
      const thenEscapes = stmt.then.kind === "Block"
        ? paramEscapesInBlock(stmt.then, paramName, fnDecls)
        : paramEscapesInStmt(stmt.then, paramName, fnDecls);
      const elseEscapes = stmt.else ? paramEscapesInBlock(stmt.else, paramName, fnDecls) : false;
      return thenEscapes || elseEscapes;
    }
    case "ForStmt":
      return paramEscapesInBlock(stmt.body, paramName, fnDecls);
    default:
      return false;
  }
}

function paramEscapesInExpr(expr: AST.Expr, paramName: string, fnDecls: Map<string, AST.FnDecl>): boolean {
  switch (expr.kind) {
    case "CallExpr":
      for (let i = 0; i < expr.args.length; i++) {
        const arg = expr.args[i];
        const argExpr = arg && ("kind" in arg ? arg : arg.value);
        if (argExpr && exprReferences(argExpr, paramName)) {
          if (expr.callee.kind === "Identifier") {
            const calleeDecl = fnDecls.get(expr.callee.name);
            const calleeParam = calleeDecl?.params[i];
            if (calleeDecl && calleeParam) {
              const calleeParamName = calleeParam.name;
              if (parameterEscapes(calleeDecl, calleeParamName, fnDecls)) {
                return true;
              }
            } else if (!calleeDecl) {
              return true;
            }
          } else {
            return true;
          }
        }
      }
      if (paramEscapesInExpr(expr.callee, paramName, fnDecls)) return true;
      return false;
    case "MemberExpr":
      if (expr.property === "push" || expr.property === "unshift" ||
          expr.property === "set" || expr.property === "add") {
        return false;
      }
      return paramEscapesInExpr(expr.object, paramName, fnDecls);
    default:
      return false;
  }
}
