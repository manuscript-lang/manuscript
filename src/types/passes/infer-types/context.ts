// Shared context for type inference sub-modules
import * as AST from "../../../parser/ast";
import type { Type, FunctionType } from "../../types";
import type { TypeEnvironment } from "../../environment";
import { TypeCheckError } from "../../errors";

export interface InferContext {
  env: TypeEnvironment;
  types: Map<AST.ASTNode, Type>;
  errors: TypeCheckError[];
  warnings: string[];
  fnDecls: Map<string, AST.FnDecl>;
  
  // Current function context
  currentFunction: FunctionType | null;
  inLoop: boolean;
  
  // Spawn tracking
  unawaitedSpawns: Map<string, AST.SourceLocation>;
  
  // Context/with tracking for escape analysis
  functionWithDepth: number;
  withContextVars: Set<string>;
  insideWithContext: boolean;
  
  // Context requirement cache
  needsContextCache: Map<string, boolean>;
}

export function createInferContext(
  env: TypeEnvironment,
  fnDecls: Map<string, AST.FnDecl>
): InferContext {
  return {
    env,
    types: new Map(),
    errors: [],
    warnings: [],
    fnDecls,
    currentFunction: null,
    inLoop: false,
    unawaitedSpawns: new Map(),
    functionWithDepth: 0,
    withContextVars: new Set(),
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
  ctx.types.set(node, type);
}
