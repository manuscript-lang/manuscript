// IDE symbol extraction from builtins AST
// Moved from builtin/extractor.ts — this is LSP/IDE-specific, not core builtin logic.

import type * as AST from "../parser/ast";
import { formatAstType, formatMethodSignature } from "./format";

// Builtin symbol info (with signatures for IDE)
export interface BuiltinsSymbol {
  name: string;
  kind: "function" | "extern" | "type";
  loc: AST.SourceLocation;
  signature?: string;
  doc?: string;
}

// Collect symbols from builtins program (for completions/hover)
export function collectBuiltinsSymbols(program: AST.Program): Map<string, BuiltinsSymbol> {
  const syms = new Map<string, BuiltinsSymbol>();

  for (const stmt of program.body) {
    if (stmt.kind === "FnDecl") {
      const params = stmt.params.map(p => `${p.name}: ${formatAstType(p.type)}`).join(", ");
      const ret = formatAstType(stmt.returnType) || "void";
      const typeParams = stmt.typeParams?.length ? `[${stmt.typeParams.map(t => t.name).join(", ")}]` : "";
      const signature = `fn ${stmt.name}${typeParams}(${params}): ${ret}`;
      syms.set(stmt.name, { name: stmt.name, kind: "function", loc: stmt.loc, signature, doc: stmt.doc });
    } else if (stmt.kind === "ExternFnDecl") {
      const params = stmt.params.map(p => `${p.name}: ${formatAstType(p.type)}`).join(", ");
      const ret = formatAstType(stmt.returnType) || "void";
      const typeParams = stmt.typeParams?.length ? `[${stmt.typeParams.map(t => t.name).join(", ")}]` : "";
      const signature = `extern fn ${stmt.name}${typeParams}(${params}): ${ret}`;
      syms.set(stmt.name, { name: stmt.name, kind: "extern", loc: stmt.loc, signature, doc: stmt.doc });
    } else if (stmt.kind === "TypeDecl") {
      const fields: string[] = [];
      for (const m of stmt.body?.members || []) {
        if (m.kind === "FieldDecl") {
          const opt = m.optional ? "?" : "";
          fields.push(`${m.name}${opt}: ${formatAstType(m.type)}`);
        }
      }
      const sig = fields.length ? `${stmt.name}(${fields.join(", ")})` : stmt.name;
      const doc = stmt.doc || (fields.length ? `**Fields:**\n${fields.map(f => `- \`${f}\``).join("\n")}` : undefined);
      syms.set(stmt.name, { name: stmt.name, kind: "type", loc: stmt.loc, signature: `type ${sig}`, doc });
    }
  }

  return syms;
}

// Type member info for completions
export interface TypeMemberInfo {
  name: string;
  kind: "field" | "method";
  signature: string;
  doc?: string;
  loc: AST.SourceLocation;
}

// Extract type members from a type declaration
export function extractTypeMembers(t: AST.TypeDecl): TypeMemberInfo[] {
  const members: TypeMemberInfo[] = [];
  for (const m of t.body?.members || []) {
    if (m.kind === "FieldDecl") {
      members.push({
        name: m.name,
        kind: "field",
        signature: formatAstType(m.type),
        doc: m.doc,
        loc: m.loc,
      });
    } else if (m.kind === "MethodDecl") {
      members.push({
        name: m.name,
        kind: "method",
        signature: formatMethodSignature(m),
        doc: m.doc,
        loc: m.loc,
      });
    }
  }
  return members;
}

// Collect all type members from a program
export function collectTypeMembersFromProgram(program: AST.Program): Map<string, TypeMemberInfo[]> {
  const result = new Map<string, TypeMemberInfo[]>();
  for (const stmt of program.body) {
    if (stmt.kind === "TypeDecl") {
      const members = extractTypeMembers(stmt);
      if (members.length > 0) {
        result.set(stmt.name, members);
      }
    }
  }
  return result;
}
