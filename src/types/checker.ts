// Type Checker - Wrapper around PassManager for backward compatibility
import type * as AST from "../parser/ast";
import { PassManager, type TypeCheckResult } from "./pass-manager";

export type { TypeCheckResult };

export class TypeChecker {
  private manager: PassManager;

  constructor() {
    this.manager = PassManager.createDefault();
  }

  check(program: AST.Program): TypeCheckResult {
    return this.manager.run(program);
  }
}
