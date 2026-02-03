// Completions - Provides completion items for code completion
import * as AST from "../parser/ast";
import type { Type, ObjectType } from "../types/types";
import { typeToString } from "../types/types";
import type { TypeMemberInfo } from "../stdlib/extractor";
import { formatAstType, formatFunctionType, resolveObjectType } from "./utils";

export type CompletionKind = "function" | "type" | "variable" | "property" | "method" | "keyword";

export interface CompletionInfo {
  label: string;
  kind: CompletionKind;
  detail?: string;
  doc?: string;
}

// Get completions for type members (stdlib types like string, list, map, set)
export function getTypeMemberCompletions(
  typeMembers: Map<string, TypeMemberInfo[]>,
  typeName: string
): CompletionInfo[] {
  const members = typeMembers.get(typeName);
  if (!members) return [];
  return members.map(m => ({
    label: m.name,
    kind: m.kind === "field" ? "property" as const : "method" as const,
    detail: m.signature,
    doc: m.doc,
  }));
}

// Get completions for object members (user-defined types)
export function getObjectMemberCompletions(obj: ObjectType): CompletionInfo[] {
  return [
    ...obj.properties.map(p => ({
      label: p.name,
      kind: "property" as const,
      detail: typeToString(p.type),
    })),
    ...obj.methods.map(m => ({
      label: m.name,
      kind: "method" as const,
      detail: typeToString(m.type),
    })),
  ];
}

// Get completions for variables/functions in scope
export function getScopeCompletions(
  program: AST.Program,
  types: Map<AST.ASTNode, Type>,
  line: number
): CompletionInfo[] {
  const completions: CompletionInfo[] = [];
  
  for (const s of program.body) {
    if (s.kind === "FnDecl") {
      const fnType = types.get(s);
      const detail = fnType ? formatFunctionType(fnType) : formatFnSignatureShort(s);
      completions.push({ label: s.name, kind: "function", detail });
    } else if (s.kind === "TypeDecl") {
      completions.push({ label: s.name, kind: "type", detail: `type ${s.name}` });
    } else if (s.kind === "LetStmt" && s.pattern?.kind === "IdentifierPattern" && s.loc.line < line) {
      const varType = types.get(s.value);
      completions.push({
        label: s.pattern.name,
        kind: "variable",
        detail: varType ? typeToString(varType) : "any",
      });
    } else if (s.kind === "VarStmt" && s.loc.line < line) {
      const varType = types.get(s.value);
      completions.push({
        label: s.name,
        kind: "variable",
        detail: varType ? typeToString(varType) : "any",
      });
    }
  }
  
  return completions;
}

// Short signature without function name (for completion detail)
function formatFnSignatureShort(fn: AST.FnDecl): string {
  const params = fn.params.map(p => `${p.name}: ${formatAstType(p.type)}`).join(", ");
  const ret = formatAstType(fn.returnType);
  return `fn(${params}): ${ret}`;
}

// Re-export resolveObjectType for use by server
export { resolveObjectType } from "./utils";
