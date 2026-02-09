// Import binding utilities for LSP
import type * as AST from "../parser/ast";

export function getImportBindingOnLine(
  program: AST.Program,
  line: number,
  word: string
): { specifier: string; exportedName: string } | null {
  for (const stmt of program.body) {
    if (stmt.kind !== "ImportDecl" || stmt.loc?.line !== line) continue;
    for (const { name, alias } of stmt.names) {
      if ((alias ?? name) === word) return { specifier: stmt.source, exportedName: name };
    }
  }
  return null;
}
