// Pass 2: Infer Types
// Main type inference and validation pass
import * as AST from "../../../parser/ast";
import type { TypeEnvironment } from "../../environment";
import { TypeCheckError } from "../../errors";
import { createInferContext, error } from "./context";
import { checkStatement, checkBlock } from "./check-stmt";

export interface InferInput {
  program: AST.Program;
  env: TypeEnvironment;
  fnDecls: Map<string, AST.FnDecl>;
}

export interface InferOutput {
  errors: TypeCheckError[];
  warnings: string[];
}

export function inferTypes(input: InferInput): InferOutput {
  const { program, env, fnDecls } = input;
  const ctx = createInferContext(env, fnDecls);

  // Check all statements
  for (const stmt of program.body) {
    checkStatement(ctx, stmt);
  }

  // Check for unawaited spawns at top level
  for (const [name, loc] of ctx.unawaitedSpawns) {
    error(ctx,
      `spawn result '${name}' is never awaited (pass to race() or all())`,
      loc
    );
  }

  return {
    errors: ctx.errors,
    warnings: ctx.warnings,
  };
}

// Re-export sub-modules for direct access if needed
export { checkStatement, checkBlock } from "./check-stmt";
export { inferExpr } from "./infer-expr";
export { checkPattern, bindPattern } from "./check-pattern";
export { createInferContext, type InferContext } from "./context";
