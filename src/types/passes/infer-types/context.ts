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
  
  // Current type context (for private member access)
  currentTypeName: string | null;
  
  // Spawn tracking
  unawaitedSpawns: Map<string, AST.SourceLocation>;
  lastSpawnInWithWasContextDependent: boolean;
  contextDependentSpawnsInWith: Set<string> | null;

  // Context/with tracking for escape analysis
  functionWithDepth: number;
  withContextVars: Set<string>;
  withBlockDepth: number;
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
  ctx.types.set(node, type);
}
