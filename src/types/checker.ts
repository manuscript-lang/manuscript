// Type Checker - Wrapper around PassManager for backward compatibility
import type * as AST from "../parser/ast";
import { PassManager, type TypeCheckResult } from "./pass-manager";
import { createGlobalEnvironment } from "./environment";
import { resolveStdlibImports } from "../stdlib/loader";

export type { TypeCheckResult };

export function runSingleFileTypecheck(program: AST.Program): TypeCheckResult {
  const env = createGlobalEnvironment();
  const stdlibErrors = resolveStdlibImports(program, env);
  const result = PassManager.createDefault().runWithEnv(program, env);
  result.errors.unshift(...stdlibErrors);
  return result;
}

export class TypeChecker {
  check(program: AST.Program): TypeCheckResult {
    return runSingleFileTypecheck(program);
  }
}
