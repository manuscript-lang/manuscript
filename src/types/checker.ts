// Type Checker - Wrapper around PassManager for backward compatibility
import type * as AST from "../parser/ast";
import type { TypeEnvironment } from "./environment";
import { PassManager, type TypeCheckResult } from "./pass-manager";
import { createGlobalEnvironment } from "./environment";
import type { TypeCheckError } from "./errors";

export type { TypeCheckResult };

export type GetStdlibErrorsFn = (program: AST.Program, env: TypeEnvironment) => TypeCheckError[];

export function runSingleFileTypecheck(
  program: AST.Program,
  getStdlibErrors?: GetStdlibErrorsFn
): TypeCheckResult {
  const env = createGlobalEnvironment();
  const stdlibErrors = getStdlibErrors ? getStdlibErrors(program, env) : [];
  const result = PassManager.createDefault().runWithEnv(program, env);
  result.errors.unshift(...stdlibErrors);
  return result;
}

export class TypeChecker {
  check(program: AST.Program): TypeCheckResult {
    return runSingleFileTypecheck(program);
  }
}
