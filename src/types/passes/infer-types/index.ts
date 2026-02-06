import * as AST from "../../../parser/ast";
import type { TypeEnvironment } from "../../environment";
import { TypeCheckError } from "../../errors";
import { createInferContext, error } from "./context";
import { checkStatement, checkBlock } from "./check-stmt";
import { inferExpr } from "./infer-expr";

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
  const ctx = createInferContext(env, fnDecls, { inferExpr, checkStatement, checkBlock });

  for (const stmt of program.body) {
    checkStatement(ctx, stmt);
  }

  for (const [name, loc] of ctx.unawaitedSpawns) {
    error(ctx, `spawn result '${name}' is never awaited (pass to race() or all())`, loc);
  }

  return { errors: ctx.errors, warnings: ctx.warnings };
}

export { checkStatement, checkBlock } from "./check-stmt";
export { inferExpr } from "./infer-expr";
export { checkPattern, bindPattern } from "./check-pattern";
export { createInferContext, type InferContext } from "./context";
