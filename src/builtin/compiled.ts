// Compiled builtins from builtins.ms and stdlib modules

import { Parser } from "../parser";
import type * as AST from "../parser/ast";
import { CodeGenerator } from "../codegen/codegen";
import { TypeChecker } from "../types/checker";
import { builtinsSource } from "./index";
import { getAllStdlibSources } from "../stdlib/loader";

function hasExternMethods(stmt: AST.Statement): boolean {
  if (stmt.kind !== "TypeDecl" || !stmt.body?.members) return false;
  return stmt.body.members.some((m) => m.kind === "MethodDecl" && (m as AST.MethodDecl).isExtern);
}

function compileSource(source: string): { code: string[]; exportNames: string[] } {
  const ast = new Parser(source).parse();
  new TypeChecker().check(ast);
  const codegen = new CodeGenerator({ emitRuntimeImport: false });
  const exportNames: string[] = [];
  const code: string[] = [];

  for (const stmt of ast.body) {
    if (stmt.kind === "ExternFnDecl") continue;
    if (hasExternMethods(stmt)) continue;
    const name = stmt.kind === "FnDecl" || stmt.kind === "TypeDecl" ? stmt.name : undefined;
    if ((stmt.kind === "FnDecl" || stmt.kind === "TypeDecl") && name && !name.startsWith("_")) {
      exportNames.push(name);
    }
    const singleProgram = { kind: "Program" as const, body: [stmt], loc: stmt.loc };
    const stmtCode = codegen.generate(singleProgram);
    code.push(stmtCode);
  }

  return { code, exportNames };
}

function compileAll(): (runtime: Record<string, unknown>) => Record<string, unknown> {
  const allCode: string[] = [];
  const allExports: string[] = [];

  // Compile builtins
  const builtins = compileSource(builtinsSource);
  allCode.push(...builtins.code);
  allExports.push(...builtins.exportNames);

  // Compile all stdlib modules (discovered dynamically)
  for (const [, source] of getAllStdlibSources()) {
    const result = compileSource(source);
    allCode.push(...result.code);
    allExports.push(...result.exportNames);
  }

  const moduleCode = `
    "use strict";
    ${allCode.join("\n")}
    return { ${allExports.join(", ")} };
  `;

  return new Function("__ms_runtime", moduleCode) as (runtime: Record<string, unknown>) => Record<string, unknown>;
}

let compiledBuiltins: Record<string, unknown> | null = null;

export function getCompiledBuiltins(runtime: Record<string, unknown>): Record<string, unknown> {
  if (!compiledBuiltins) {
    const factory = compileAll();
    compiledBuiltins = factory(runtime);
  }
  return compiledBuiltins;
}
