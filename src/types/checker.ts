// Type Checker - Wrapper around PassManager for backward compatibility
import type * as AST from "../parser/ast";
import { PassManager, type TypeCheckResult } from "./pass-manager";
import { createGlobalEnvironment } from "./environment";
import { resolveStdlibImports } from "../stdlib/loader";

export type { TypeCheckResult };

export class TypeChecker {
  private manager: PassManager;

  constructor() {
    this.manager = PassManager.createDefault();
  }

  check(program: AST.Program): TypeCheckResult {
    const env = createGlobalEnvironment();
    const stdlibErrors = resolveStdlibImports(program, env);
    const result = this.manager.runWithEnv(program, env);
    result.errors.unshift(...stdlibErrors);
    return result;
  }
}
