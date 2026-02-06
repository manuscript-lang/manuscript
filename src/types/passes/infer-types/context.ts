import * as AST from "../../../parser/ast";
import type { Type, FunctionType } from "../../types";
import type { TypeEnvironment } from "../../environment";
import { TypeCheckError } from "../../errors";

export interface Dispatch {
  inferExpr: (ctx: InferContext, expr: AST.Expr) => Type;
  checkStatement: (ctx: InferContext, stmt: AST.Statement) => void;
  checkBlock: (ctx: InferContext, block: AST.Block) => void;
}

export interface InferContext {
  env: TypeEnvironment;
  errors: TypeCheckError[];
  warnings: string[];
  fnDecls: Map<string, AST.FnDecl>;

  inferExpr: (ctx: InferContext, expr: AST.Expr) => Type;
  checkStatement: (ctx: InferContext, stmt: AST.Statement) => void;
  checkBlock: (ctx: InferContext, block: AST.Block) => void;

  currentFunction: FunctionType | null;
  inLoop: boolean;
  currentTypeName: string | null;
  unawaitedSpawns: Map<string, AST.SourceLocation>;
  lastSpawnInWithWasContextDependent: boolean;
  contextDependentSpawnsInWith: Set<string> | null;
  functionWithDepth: number;
  withContextVars: Set<string>;
  withBlockDepth: number;
  insideWithContext: boolean;
  needsContextCache: Map<string, boolean>;
}

export function createInferContext(
  env: TypeEnvironment,
  fnDecls: Map<string, AST.FnDecl>,
  dispatch: Dispatch
): InferContext {
  return {
    env,
    errors: [],
    warnings: [],
    fnDecls,
    ...dispatch,
    currentFunction: null,
    inLoop: false,
    currentTypeName: null,
    unawaitedSpawns: new Map(),
    lastSpawnInWithWasContextDependent: false,
    contextDependentSpawnsInWith: null,
    functionWithDepth: 0,
    withContextVars: new Set(),
    withBlockDepth: 0,
    insideWithContext: false,
    needsContextCache: new Map(),
  };
}

export function error(ctx: InferContext, message: string, loc: AST.SourceLocation, hint?: string): void {
  ctx.errors.push(new TypeCheckError(message, loc, hint));
}

export function warning(ctx: InferContext, message: string): void {
  ctx.warnings.push(message);
}

export function recordType(ctx: InferContext, node: AST.ASTNode, type: Type): void {
  (node as AST.BaseNode).resolvedType = type;
}

export function getExpectedType(node: AST.ASTNode): Type | undefined {
  return (node as AST.BaseNode).expectedType;
}

export function setExpectedType(node: AST.ASTNode, type: Type): void {
  (node as AST.BaseNode).expectedType = type;
}
