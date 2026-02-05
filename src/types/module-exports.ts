import type * as AST from "../parser/ast";
import type { Type } from "./types";
import type { TypeEnvironment } from "./environment";

function isExportedName(name: string): boolean {
  return !name.startsWith("_");
}

function getDeclName(stmt: AST.Statement): string | null {
  switch (stmt.kind) {
    case "FnDecl":
      return stmt.name;
    case "TypeDecl":
      return stmt.name;
    case "KeywordTypeUse":
      return stmt.name;
    default:
      return null;
  }
}

export interface GetModuleExportsResult {
  exports: Map<string, Type>;
  errors: { message: string; loc: AST.SourceLocation }[];
}

export function getModuleExports(
  program: AST.Program,
  env: TypeEnvironment
): GetModuleExportsResult {
  const exports = new Map<string, Type>();
  const errors: { message: string; loc: AST.SourceLocation }[] = [];

  for (const stmt of program.body) {
    const name = getDeclName(stmt);
    if (name === null || !isExportedName(name)) continue;

    let type: Type | undefined;
    if (stmt.kind === "FnDecl") {
      type = env.getType(name);
    } else if (stmt.kind === "TypeDecl" || stmt.kind === "KeywordTypeUse") {
      type = env.lookupType(name);
    }
    if (type === undefined) continue;

    if (exports.has(name)) {
      errors.push({
        message: `Duplicate export: ${name}`,
        loc: stmt.loc,
      });
      continue;
    }
    exports.set(name, type);
  }

  return { exports, errors };
}
