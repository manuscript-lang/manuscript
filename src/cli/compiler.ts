// Manuscript Compiler Pipeline
// Combines lexer, parser, type checker, and code generator

import { Parser } from "../parser";
import { TypeChecker } from "../types";
import { CodeGenerator } from "../codegen";
import type * as AST from "../parser/ast";

export interface CompileResult {
  success: boolean;
  code?: string;
  ast?: AST.Program;
  errors: CompileError[];
  warnings: CompileWarning[];
}

export interface CompileError {
  message: string;
  hint?: string;
  line?: number;
  column?: number;
  file?: string;
  phase: "lexer" | "parser" | "typecheck" | "codegen";
}

export interface CompileWarning {
  message: string;
  line?: number;
  column?: number;
  file?: string;
}

export interface CompileOptions {
  filename?: string;
  typeCheck?: boolean;
  emitRuntimeImport?: boolean; // Emit import { __ms_runtime } (default: true, set to false for eval)
}

/**
 * Compile Manuscript source code to JavaScript
 */
export function compile(source: string, options: CompileOptions = {}): CompileResult {
  const errors: CompileError[] = [];
  const warnings: CompileWarning[] = [];
  const filename = options.filename || "<anonymous>";

  // Phase 1 & 2: Parse (lexing is done internally by Parser)
  let ast: AST.Program;
  try {
    const parser = new Parser(source);
    ast = parser.parse();
  } catch (error: any) {
    // Determine phase from error type
    const phase = error.name === "LexerError" ? "lexer" : "parser";
    errors.push({
      message: error.message,
      hint: error.hint,
      line: error.token?.loc?.line ?? error.loc?.line,
      column: error.token?.loc?.column ?? error.loc?.column,
      file: filename,
      phase,
    });
    return { success: false, errors, warnings };
  }

  // Phase 3: Type Checking (optional, enabled by default)
  if (options.typeCheck !== false) {
    try {
      const checker = new TypeChecker();
      const result = checker.check(ast);
      
      for (const typeError of result.errors) {
        errors.push({
          message: typeError.message,
          hint: typeError.hint,
          line: typeError.loc?.line,
          column: typeError.loc?.column,
          file: filename,
          phase: "typecheck",
        });
      }
      
      if (errors.length > 0) {
        return { success: false, ast, errors, warnings };
      }
    } catch (error: any) {
      errors.push({
        message: error.message,
        file: filename,
        phase: "typecheck",
      });
      return { success: false, ast, errors, warnings };
    }
  }

  // Phase 4: Code Generation
  let code: string;
  try {
    const generator = new CodeGenerator({
      emitRuntimeImport: options.emitRuntimeImport !== false,
    });
    code = generator.generate(ast);
  } catch (error: any) {
    errors.push({
      message: error.message,
      file: filename,
      phase: "codegen",
    });
    return { success: false, ast, errors, warnings };
  }

  return { success: true, code, ast, errors, warnings };
}

/**
 * Type check Manuscript source code without generating code
 */
export function check(source: string, options: CompileOptions = {}): CompileResult {
  const errors: CompileError[] = [];
  const warnings: CompileWarning[] = [];
  const filename = options.filename || "<anonymous>";

  // Phase 1 & 2: Parse (lexing is done internally by Parser)
  let ast: AST.Program;
  try {
    const parser = new Parser(source);
    ast = parser.parse();
  } catch (error: any) {
    const phase = error.name === "LexerError" ? "lexer" : "parser";
    errors.push({
      message: error.message,
      hint: error.hint,
      line: error.token?.loc?.line ?? error.loc?.line,
      column: error.token?.loc?.column ?? error.loc?.column,
      file: filename,
      phase,
    });
    return { success: false, errors, warnings };
  }

  // Phase 3: Type Checking
  try {
    const checker = new TypeChecker();
    const result = checker.check(ast);
    
    for (const typeError of result.errors) {
      errors.push({
        message: typeError.message,
        hint: typeError.hint,
        line: typeError.loc?.line,
        column: typeError.loc?.column,
        file: filename,
        phase: "typecheck",
      });
    }
  } catch (error: any) {
    errors.push({
      message: error.message,
      hint: error.hint,
      file: filename,
      phase: "typecheck",
    });
  }

  return { 
    success: errors.length === 0, 
    ast, 
    errors, 
    warnings 
  };
}

/**
 * Parse Manuscript source code and return AST
 */
export function parse(source: string, options: CompileOptions = {}): CompileResult {
  const errors: CompileError[] = [];
  const warnings: CompileWarning[] = [];
  const filename = options.filename || "<anonymous>";

  // Phase 1 & 2: Parse (lexing is done internally by Parser)
  let ast: AST.Program;
  try {
    const parser = new Parser(source);
    ast = parser.parse();
  } catch (error: any) {
    const phase = error.name === "LexerError" ? "lexer" : "parser";
    errors.push({
      message: error.message,
      hint: error.hint,
      line: error.token?.loc?.line ?? error.loc?.line,
      column: error.token?.loc?.column ?? error.loc?.column,
      file: filename,
      phase,
    });
    return { success: false, errors, warnings };
  }

  return { success: true, ast, errors, warnings };
}

/**
 * Format compile errors for display (LLM-friendly format)
 */
export function formatErrors(errors: CompileError[], source?: string): string {
  const lines = source?.split("\n") || [];
  
  return errors.map(error => {
    let msg = `[${error.phase}] ${error.message}`;
    
    if (error.file) {
      msg = `${error.file}: ${msg}`;
    }
    
    if (error.line !== undefined) {
      msg += `\n  at line ${error.line}`;
      if (error.column !== undefined) {
        msg += `, column ${error.column}`;
      }
      
      // Show source context if available
      if (lines[error.line - 1]) {
        const line = lines[error.line - 1];
        msg += `\n\n  ${error.line} | ${line}`;
        if (error.column !== undefined) {
          const padding = " ".repeat(String(error.line).length + 3 + error.column - 1);
          msg += `\n  ${padding}^`;
        }
      }
    }
    
    // Add hint for fixing the problem
    if (error.hint) {
      msg += `\n\n  Hint: ${error.hint}`;
    }
    
    return msg;
  }).join("\n\n");
}
