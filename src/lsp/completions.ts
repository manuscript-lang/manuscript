// Completions - Provides completion items for code completion
import * as AST from "../parser/ast";
import type { Type, ObjectType, InterfaceType } from "../types/types";
import { typeToString } from "../types/types";
import type { TypeMemberInfo } from "../builtin/extractor";
import { formatAstType, formatFunctionType, resolveObjectType, resolveInterfaceType } from "../types/type-utils";

export type CompletionKind = "function" | "type" | "variable" | "property" | "method" | "keyword";

export interface CompletionInfo {
  label: string;
  kind: CompletionKind;
  detail?: string;
  doc?: string;
}

// Get completions for type members (builtin types like string, list, map, set)
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

// Get completions for interface members (methods only)
export function getInterfaceMemberCompletions(iface: InterfaceType): CompletionInfo[] {
  return iface.methods.map(m => ({
    label: m.name,
    kind: "method" as const,
    detail: typeToString(m.type),
  }));
}

// Get completions for variables/functions in scope
export function getScopeCompletions(
  program: AST.Program,
  line: number
): CompletionInfo[] {
  const completions: CompletionInfo[] = [];
  
  for (const s of program.body) {
    if (s.kind === "FnDecl") {
      const fnType = s.resolvedType;
      const detail = fnType ? formatFunctionType(fnType) : formatFnSignatureShort(s);
      completions.push({ label: s.name, kind: "function", detail });
    } else if (s.kind === "TypeDecl") {
      completions.push({ label: s.name, kind: "type", detail: `type ${s.name}` });
    } else if (s.kind === "InterfaceDecl") {
      completions.push({ label: s.name, kind: "type", detail: `interface ${s.name}` });
    } else if (s.kind === "LetStmt" && s.pattern?.kind === "IdentifierPattern" && s.loc.line < line) {
      const varType = s.value.resolvedType;
      completions.push({
        label: s.pattern.name,
        kind: "variable",
        detail: varType ? typeToString(varType) : "unknown",
      });
    } else if (s.kind === "VarStmt" && s.loc.line < line) {
      const varType = s.value.resolvedType;
      completions.push({
        label: s.name,
        kind: "variable",
        detail: varType ? typeToString(varType) : "unknown",
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

import type { BuiltinsSymbol } from "../builtin/extractor";

const BUILTIN_PRIMITIVE_TYPES = ["number", "string", "bool", "null", "bytes", "unknown", "never", "void"];

// Completions after `:` — type annotation context
export function getTypeAnnotationCompletions(
  builtinsSymbols: Map<string, BuiltinsSymbol>,
  program?: AST.Program
): CompletionInfo[] {
  const items: CompletionInfo[] = BUILTIN_PRIMITIVE_TYPES.map(t => ({
    label: t,
    kind: "type" as const,
  }));
  for (const [name, sym] of builtinsSymbols) {
    if (sym.kind === "type") items.push({ label: name, kind: "type" });
  }
  if (program) {
    for (const s of program.body) {
      if (s.kind === "TypeDecl" || s.kind === "InterfaceDecl") {
        items.push({ label: s.name, kind: "type" });
      }
    }
  }
  return items;
}

// Default completions: keywords, builtins, scope
export function getDefaultCompletions(
  program: AST.Program | undefined,
  keywords: string[],
  stdlibFunctions: Set<string>,
  builtinsSymbols: Map<string, BuiltinsSymbol>
): CompletionInfo[] {
  const items: CompletionInfo[] = [
    ...keywords.map(k => ({ label: k, kind: "keyword" as const })),
    ...[...stdlibFunctions].map(f => ({ label: f, kind: "function" as const, doc: builtinsSymbols.get(f)?.doc })),
  ];

  if (program) {
    for (const s of program.body) {
      if (s.kind === "FnDecl") {
        items.push({ label: s.name, kind: "function" });
      } else if (s.kind === "TypeDecl") {
        items.push({ label: s.name, kind: "type", detail: `type ${s.name}` });
      } else if (s.kind === "InterfaceDecl") {
        items.push({ label: s.name, kind: "type", detail: `interface ${s.name}` });
      } else if (s.kind === "LetStmt" || s.kind === "VarStmt") {
        const name = (s as any).name || (s as any).pattern?.name;
        if (name) items.push({ label: name, kind: "variable" });
      } else if (s.kind === "ImportDecl") {
        for (const { name, alias } of s.names) {
          items.push({ label: alias ?? name, kind: "function" });
        }
      }
    }
  }

  return items;
}

// Re-export for use by server
export { resolveObjectType, resolveInterfaceType } from "../types/type-utils";
