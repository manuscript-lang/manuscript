// Pass Manager - Configurable pipeline for type checking passes
import type * as AST from "../parser/ast";
import { createGlobalEnvironment, type TypeEnvironment } from "./environment";
import { type TypeCheckError } from "./errors";
import { CollectDeclarationsPass } from "./passes/collect-declarations";
import { InferTypesPass } from "./passes/infer-types";

// ============================================
// Pass Context - Shared state between passes
// ============================================

export interface PassContext {
  program: AST.Program;
  env: TypeEnvironment;
  fnDecls: Map<string, AST.FnDecl>;
  errors: TypeCheckError[];
  warnings: string[];
}

// ============================================
// Pass Interface
// ============================================

export interface Pass {
  name: string;
  run(ctx: PassContext): void;
}

export { CollectDeclarationsPass, InferTypesPass };

// ============================================
// Type Check Result
// ============================================

export interface TypeCheckResult {
  program: AST.Program;
  env: TypeEnvironment;
  errors: TypeCheckError[];
  warnings: string[];
}

// ============================================
// Pass Manager
// ============================================

export class PassManager {
  private passes: Pass[] = [];

  /**
   * Create a PassManager with default passes pre-registered
   */
  static createDefault(): PassManager {
    const mgr = new PassManager();
    mgr.addPass(new CollectDeclarationsPass());
    mgr.addPass(new InferTypesPass());
    return mgr;
  }

  /**
   * Add a pass to the end of the pipeline
   */
  addPass(pass: Pass): this {
    this.passes.push(pass);
    return this;
  }

  /**
   * Remove a pass by name
   */
  removePass(name: string): this {
    this.passes = this.passes.filter(p => p.name !== name);
    return this;
  }

  /**
   * Insert a pass before an existing pass
   */
  insertBefore(existingName: string, pass: Pass): this {
    const idx = this.passes.findIndex(p => p.name === existingName);
    if (idx === -1) {
      this.passes.push(pass);
    } else {
      this.passes.splice(idx, 0, pass);
    }
    return this;
  }

  /**
   * Insert a pass after an existing pass
   */
  insertAfter(existingName: string, pass: Pass): this {
    const idx = this.passes.findIndex(p => p.name === existingName);
    if (idx === -1) {
      this.passes.push(pass);
    } else {
      this.passes.splice(idx + 1, 0, pass);
    }
    return this;
  }

  /**
   * Get all registered pass names
   */
  getPassNames(): string[] {
    return this.passes.map(p => p.name);
  }

  /**
   * Run all passes on the program
   */
  run(program: AST.Program): TypeCheckResult {
    return this.runWithEnv(program, createGlobalEnvironment());
  }

  /**
   * Run all passes with a pre-seeded environment (e.g. for project compile with imports).
   */
  runWithEnv(program: AST.Program, initialEnv: TypeEnvironment): TypeCheckResult {
    const ctx: PassContext = {
      program,
      env: initialEnv,
      fnDecls: new Map(),
      errors: [],
      warnings: [],
    };

    for (const pass of this.passes) {
      pass.run(ctx);
    }

    return {
      program: ctx.program,
      env: ctx.env,
      errors: ctx.errors,
      warnings: ctx.warnings,
    };
  }
}
