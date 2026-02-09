// Completions - Provides completion items for code completion
import * as AST from "../parser/ast";
import type { ObjectType, InterfaceType } from "../types/types";
import { typeToString } from "../types/types";
import type { TypeEnvironment } from "../types/environment";
import type { TypeMemberInfo, BuiltinsSymbol } from "./builtin-symbols";
import { BUILTIN_PRIMITIVE_TYPES } from "../shared/constants";
import {
  formatFunctionType,
  formatFnSignatureFromAst,
  formatFnSignature,
  formatTypeSignature,
  formatInterfaceSignature,
  resolveObjectType,
  resolveInterfaceType,
} from "./format";
import { visit } from "../types/ast-visitor";

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

function isLocBeforeCursor(loc: AST.SourceLocation | undefined, line: number, col: number): boolean {
  if (!loc) return true;
  return loc.line < line || (loc.line === line && loc.column < col);
}

function isCursorBeforeLoc(line: number, col: number, loc: AST.SourceLocation | undefined): boolean {
  if (!loc) return false;
  return line < loc.line || (line === loc.line && col < loc.column);
}

function getScopeAtPosition(program: AST.Program, line: number, col: number): string {
  let scope = "";

  function walk(stmts: AST.Statement[]): boolean {
    for (const s of stmts) {
      if (isCursorBeforeLoc(line, col, s.loc)) return true;
      if (s.kind === "FnDecl") {
        scope = s.name;
        if (s.body?.statements && walk(s.body.statements)) return true;
      } else if (s.kind === "TypeDecl" && s.body?.members) {
        for (const m of s.body.members) {
          if (m.kind === "MethodDecl" && m.body?.statements && walk(m.body.statements)) return true;
        }
      } else if (s.kind === "TestDecl" && s.body?.statements && walk(s.body.statements)) return true;
    }
    return false;
  }
  walk(program.body);
  return scope;
}

function collectScopeCompletions(
  program: AST.Program,
  line: number,
  col: number,
  scope: string,
  out: CompletionInfo[]
): void {
  const before = (loc: AST.SourceLocation | undefined) => isLocBeforeCursor(loc, line, col);

  if (!scope) {
    for (const s of program.body) {
      if (s.kind === "FnDecl") {
        const fnType = s.resolvedType;
        const detail = fnType ? formatFunctionType(fnType) : formatFnSignatureFromAst(s);
        out.push({ label: s.name, kind: "function", detail });
      } else if (s.kind === "TypeDecl") {
        out.push({ label: s.name, kind: "type", detail: `type ${s.name}` });
      } else if (s.kind === "InterfaceDecl") {
        out.push({ label: s.name, kind: "type", detail: `interface ${s.name}` });
      } else if (s.kind === "LetStmt" && s.pattern?.kind === "IdentifierPattern" && before(s.loc)) {
        const varType = s.value.resolvedType;
        out.push({ label: s.pattern.name, kind: "variable", detail: varType ? typeToString(varType) : "unknown" });
      } else if (s.kind === "VarStmt" && before(s.loc)) {
        const varType = s.value.resolvedType;
        out.push({ label: s.name, kind: "variable", detail: varType ? typeToString(varType) : "unknown" });
      } else if (s.kind === "ImportDecl") {
        for (const { name, alias } of s.names) out.push({ label: alias ?? name, kind: "function" });
      }
    }
    return;
  }

  for (const s of program.body) {
    if (s.kind === "FnDecl") {
      const fnType = s.resolvedType;
      const detail = fnType ? formatFunctionType(fnType) : formatFnSignatureFromAst(s);
      out.push({ label: s.name, kind: "function", detail });
    } else if (s.kind === "TypeDecl") {
      out.push({ label: s.name, kind: "type", detail: `type ${s.name}` });
    } else if (s.kind === "InterfaceDecl") {
      out.push({ label: s.name, kind: "type", detail: `interface ${s.name}` });
    } else if (s.kind === "LetStmt" && s.pattern?.kind === "IdentifierPattern" && before(s.loc)) {
      const varType = s.value.resolvedType;
      out.push({ label: s.pattern.name, kind: "variable", detail: varType ? typeToString(varType) : "unknown" });
    } else if (s.kind === "VarStmt" && before(s.loc)) {
      const varType = s.value.resolvedType;
      out.push({ label: s.name, kind: "variable", detail: varType ? typeToString(varType) : "unknown" });
    } else if (s.kind === "ImportDecl") {
      for (const { name, alias } of s.names) out.push({ label: alias ?? name, kind: "function" });
    }
    if (s.kind === "FnDecl" && s.name === scope) {
      for (const p of s.params) {
        out.push({
          label: p.name,
          kind: "variable",
          detail: p.type ? formatAstType(p.type) : "unknown",
        });
      }
      if (s.body?.statements) {
        for (const st of s.body.statements) {
          if (st.kind === "LetStmt" && st.pattern?.kind === "IdentifierPattern" && before(st.loc)) {
            const varType = st.value.resolvedType;
            out.push({ label: st.pattern.name, kind: "variable", detail: varType ? typeToString(varType) : "unknown" });
          } else if (st.kind === "VarStmt" && before(st.loc)) {
            const varType = st.value.resolvedType;
            out.push({ label: st.name, kind: "variable", detail: varType ? typeToString(varType) : "unknown" });
          }
        }
      }
      break;
    }
  }
}

function formatAstType(type: AST.TypeExpr): string {
  switch (type.kind) {
    case "NamedType": return type.name;
    case "GenericType": return `${type.name}[${type.args.map(formatAstType).join(", ")}]`;
    default: return "unknown";
  }
}

// Get completions for variables/functions in scope. With cursor (line, col) in 1-based coords uses scope at position; else line caps Let/Var visibility.
export function getScopeCompletions(
  program: AST.Program,
  line: number = Infinity,
  col?: number
): CompletionInfo[] {
  const completions: CompletionInfo[] = [];
  if (col !== undefined && col >= 0 && line !== Infinity && Number.isFinite(line) && line >= 1) {
    const scope = getScopeAtPosition(program, line, col);
    collectScopeCompletions(program, line, col, scope, completions);
    return completions;
  }
  const lineCap = line;
  for (const s of program.body) {
    if (s.kind === "FnDecl") {
      const fnType = s.resolvedType;
      const detail = fnType ? formatFunctionType(fnType) : formatFnSignatureFromAst(s);
      completions.push({ label: s.name, kind: "function", detail });
    } else if (s.kind === "TypeDecl") {
      completions.push({ label: s.name, kind: "type", detail: `type ${s.name}` });
    } else if (s.kind === "InterfaceDecl") {
      completions.push({ label: s.name, kind: "type", detail: `interface ${s.name}` });
    } else if (s.kind === "LetStmt" && s.pattern?.kind === "IdentifierPattern" && (s.loc?.line ?? 0) < lineCap) {
      const varType = s.value.resolvedType;
      completions.push({
        label: s.pattern.name,
        kind: "variable",
        detail: varType ? typeToString(varType) : "unknown",
      });
    } else if (s.kind === "VarStmt" && (s.loc?.line ?? 0) < lineCap) {
      const varType = s.value.resolvedType;
      completions.push({
        label: s.name,
        kind: "variable",
        detail: varType ? typeToString(varType) : "unknown",
      });
    } else if (s.kind === "ImportDecl") {
      for (const { name, alias } of s.names) {
        completions.push({ label: alias ?? name, kind: "function" });
      }
    }
  }
  return completions;
}

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

// Default completions: keywords, stdlib, and scope (via getScopeCompletions). Pass cursor (1-based line, 1-based col) for scope-aware completions.
export function getDefaultCompletions(
  program: AST.Program | undefined,
  keywords: string[],
  stdlibFunctions: Set<string>,
  builtinsSymbols: Map<string, BuiltinsSymbol>,
  cursorLine?: number,
  cursorCol?: number
): CompletionInfo[] {
  const items: CompletionInfo[] = [
    ...keywords.map(k => ({ label: k, kind: "keyword" as const })),
    ...[...stdlibFunctions].map(f => ({ label: f, kind: "function" as const, doc: builtinsSymbols.get(f)?.doc })),
  ];
  if (program) {
    const scopeItems =
      cursorLine !== undefined && cursorCol !== undefined
        ? getScopeCompletions(program, cursorLine, cursorCol)
        : getScopeCompletions(program, Infinity);
    items.push(...scopeItems);
  }
  return items;
}

// Get member completions at a dot-position by walking the AST to find the receiver expression
export function getMemberCompletionsAtPosition(
  program: AST.Program,
  env: TypeEnvironment,
  line: number,
  col: number,
  builtinsTypeMembers: Map<string, TypeMemberInfo[]>
): CompletionInfo[] {
  let bestExpr: AST.Expr | null = null;
  visit(program, {
    expr(e) {
      if (!e?.loc || e.loc.line !== line) return;
      if (e.loc.column <= col) bestExpr = e;
    },
  });
  const expr = bestExpr as AST.Expr | null;
  const type =
    expr?.kind === "MemberExpr"
      ? expr.object.resolvedType
      : expr?.resolvedType;
  if (!type) return [];
  const builtinCompletions = getTypeMemberCompletions(builtinsTypeMembers, type.kind);
  if (builtinCompletions.length > 0) return builtinCompletions;
  const obj = resolveObjectType(program, type, env);
  if (obj) return getObjectMemberCompletions(obj);
  const iface = resolveInterfaceType(program, type, env);
  if (iface) return getInterfaceMemberCompletions(iface);
  return [];
}

// Resolve completion detail for a declaration in a program
export function resolveCompletionDetail(
  program: AST.Program,
  name: string,
  kind: "fn" | "type" | "interface"
): { detail: string; doc?: string } | null {
  for (const s of program.body) {
    if (kind === "fn" && s.kind === "FnDecl" && s.name === name) {
      return { detail: formatFnSignature(s), doc: s.doc };
    }
    if (kind === "type" && s.kind === "TypeDecl" && s.name === name) {
      const { signature, fields } = formatTypeSignature(s);
      const doc = s.doc ?? (fields.length ? `**Fields:**\n${fields.map(f => `- \`${f}\``).join("\n")}` : undefined);
      return { detail: signature, doc };
    }
    if (kind === "interface" && s.kind === "InterfaceDecl" && s.name === name) {
      const { signature, methods } = formatInterfaceSignature(s);
      const doc = s.doc ?? (methods.length ? `**Methods:**\n${methods.map(m => `- \`${m}\``).join("\n")}` : undefined);
      return { detail: `interface ${signature}`, doc };
    }
  }
  return null;
}
