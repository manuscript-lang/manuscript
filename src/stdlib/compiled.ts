// Compiled stdlib from stdlib.ms
// This module compiles the Manuscript stdlib (types and pure functions) to JavaScript at load time

import { Parser } from "../parser";
import { CodeGenerator } from "../codegen/codegen";
import { stdlibSource } from "./index";

// Check if a type has extern methods (should be provided by runtime, not compiled)
function hasExternMethods(stmt: any): boolean {
  if (stmt.kind !== "TypeDecl" || !stmt.body?.members) return false;
  return stmt.body.members.some((m: any) => m.kind === "MethodDecl" && m.isExtern);
}

// Compile stdlib.ms - all constructs except extern declarations
function compileStdlib(): (runtime: any) => Record<string, any> {
  const ast = new Parser(stdlibSource).parse();
  const codegen = new CodeGenerator({ emitRuntimeImport: false });
  
  // Collect names to export (types and pure functions)
  const exportNames: string[] = [];
  
  // Generate code for all non-extern statements
  const code: string[] = [];
  for (const stmt of ast.body) {
    // Skip extern function declarations
    if (stmt.kind === "ExternFnDecl") continue;
    
    // Skip types with extern methods (provided by runtime)
    if (hasExternMethods(stmt)) continue;
    
    // Track names to export
    if (stmt.kind === "FnDecl" || stmt.kind === "TypeDecl" || stmt.kind === "EnumDecl") {
      exportNames.push((stmt as { name: string }).name);
    }
    
    // Generate code for this statement
    const singleProgram = { kind: "Program" as const, body: [stmt], loc: stmt.loc };
    const stmtCode = codegen.generate(singleProgram);
    code.push(stmtCode);
  }
  
  // Create a module that exports all constructs
  const moduleCode = `
    "use strict";
    ${code.join("\n")}
    return { ${exportNames.join(", ")} };
  `;
  
  // Create and return the factory function
  // Code needs __ms_runtime for extern calls like len, to_str, sort
  return new Function("__ms_runtime", moduleCode) as (runtime: any) => Record<string, any>;
}

// Cache the compiled stdlib
let compiledStdlib: Record<string, any> | null = null;

export function getCompiledStdlib(runtime: any): Record<string, any> {
  if (!compiledStdlib) {
    const factory = compileStdlib();
    compiledStdlib = factory(runtime);
  }
  return compiledStdlib;
}
