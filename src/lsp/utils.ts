// LSP Utilities - Shared helpers for LSP features
import * as AST from "../parser/ast";
import type { Type, ObjectType, MethodType } from "../types/types";
import { typeToString } from "../types/types";
import type { TypeEnvironment } from "../types/environment";
import { visit } from "../types/ast-visitor";
import type { SymbolDef } from "./symbols";

// ============================================
// Location Matching
// ============================================

export function isLocationMatch(
  loc: { line: number; column: number },
  nameOffset: number,
  nameLength: number,
  line: number,
  column: number
): boolean {
  if (loc.line !== line) return false;
  const start = loc.column + nameOffset;
  const end = start + nameLength;
  return column >= start && column <= end;
}

export function isDefLocationMatch(def: SymbolDef, line: number, column: number): boolean {
  return isLocationMatch(def.loc, def.nameOffset, def.name.length, line, column);
}

// ============================================
// AST Lookups
// ============================================

export function findFnDecl(program: AST.Program, name: string): AST.FnDecl | null {
  for (const s of program.body) {
    if (s.kind === "FnDecl" && s.name === name) return s;
  }
  return null;
}

export function findTypeDecl(program: AST.Program, name: string): AST.TypeDecl | null {
  for (const s of program.body) {
    if (s.kind === "TypeDecl" && s.name === name) return s;
  }
  return null;
}

export function findTypeMember(program: AST.Program, typeName: string, memberName: string): AST.FieldDecl | AST.MethodDecl | AST.InitDecl | null {
  const typeDecl = findTypeDecl(program, typeName);
  if (!typeDecl) return null;
  for (const m of typeDecl.body?.members || []) {
    if (m.kind === "InitDecl" && memberName === "init") return m;
    if ((m.kind === "FieldDecl" || m.kind === "MethodDecl") && m.name === memberName) return m;
  }
  return null;
}

/** If (line, col) is on the callee of a constructor call TypeName(...), return the type name. */
export function findConstructorCalleeAt(program: AST.Program, line: number, col: number): string | null {
  let result: string | null = null;
  visit(program, {
    expr(e) {
      if (e.kind === "CallExpr" && e.callee.kind === "Identifier") {
        const loc = e.callee.loc;
        const endCol = loc.column + e.callee.name.length;
        if (loc.line === line && loc.column <= col && col <= endCol) result = e.callee.name;
      }
    },
  });
  return result;
}

// ============================================
// Type Formatting
// ============================================

export function formatAstType(type: AST.TypeExpr | undefined): string {
  if (!type) return "any";
  switch (type.kind) {
    case "NamedType": return type.name;
    case "GenericType": return `${type.name}[${type.args.map(formatAstType).join(", ")}]`;
    case "FunctionType": return `fn(${type.params.map(formatAstType).join(", ")}): ${formatAstType(type.returnType)}`;
    case "UnionType": return type.types.map(formatAstType).join(" | ");
    case "OptionalType": return `${formatAstType(type.inner)}?`;
    case "ListType": return `list[${formatAstType(type.elementType)}]`;
    default: return "any";
  }
}

export function formatFnSignature(fn: AST.FnDecl): string {
  const params = fn.params.map(p => `${p.name}: ${formatAstType(p.type)}`).join(", ");
  const ret = formatAstType(fn.returnType);
  return `fn ${fn.name}(${params}): ${ret}`;
}

export function formatMethodSignature(m: AST.MethodDecl): string {
  const params = m.params.map(p => `${p.name}: ${formatAstType(p.type)}`).join(", ");
  const ret = formatAstType(m.returnType);
  return `fn ${m.name}(${params}): ${ret}`;
}

export function formatTypeSignature(t: AST.TypeDecl): { signature: string; fields: string[] } {
  const fields: string[] = [];
  for (const m of t.body?.members || []) {
    if (m.kind === "FieldDecl") {
      fields.push(`${m.name}: ${formatAstType(m.type)}`);
    }
  }
  return { signature: t.name, fields };
}

export function formatFunctionType(type: Type): string {
  if (type.kind !== "function") return "fn()";
  const fnType = type as any;
  const params = fnType.params?.map((p: any) => `${p.name}: ${typeToString(p.type)}`).join(", ") || "";
  const ret = typeToString(fnType.returnType);
  return `fn(${params}): ${ret}`;
}

// ============================================
// Docstring Extraction (legacy - comments now in AST)
// ============================================

export function getDocstring(block: AST.Block | undefined): string | undefined {
  if (!block?.statements?.length) return undefined;
  const first = block.statements[0];
  if (!first || first.kind !== "ExprStmt") return undefined;
  const expr = first.expr;
  if (expr.kind !== "Literal" || typeof expr.value !== "string") return undefined;
  return expr.value;
}

// ============================================
// Type Resolution
// ============================================

export function resolveObjectType(program: AST.Program, type: Type, env?: TypeEnvironment): ObjectType | null {
  if (type.kind === "object") return type;
  if (type.kind === "optional") return resolveObjectType(program, (type as any).inner, env);
  if (type.kind === "union") {
    for (const t of (type as any).types) {
      const o = resolveObjectType(program, t, env);
      if (o) return o;
    }
  }
  if (type.kind === "ref") {
    if (env) {
      const resolved = env.lookupType(type.name);
      if (resolved?.kind === "object") return resolved as ObjectType;
    }
    const typeDecl = findTypeDecl(program, type.name);
    if (typeDecl) {
      const props = (typeDecl.body?.members || [])
        .filter((m): m is AST.FieldDecl => m.kind === "FieldDecl")
        .map(m => ({
          name: m.name,
          type: { kind: "any" } as Type,
          optional: m.optional,
          computed: false,
          defaultValue: !!m.defaultValue,
        }));
      const methods: MethodType[] = (typeDecl.body?.members || [])
        .filter((m): m is AST.MethodDecl => m.kind === "MethodDecl")
        .map(m => ({
          name: m.name,
          type: { kind: "function", params: [], returnType: { kind: "any" } } as any,
        }));
      return { kind: "object", name: typeDecl.name, properties: props, methods };
    }
  }
  return null;
}

export function formatTypeSignatureFromObject(obj: ObjectType): { signature: string; fields: string[] } {
  const fields = obj.properties.map(p => `${p.name}: ${typeToString(p.type)}`);
  return { signature: obj.name ?? "", fields };
}

// ============================================
// Qualified Name Parsing
// ============================================

export function parseQualifiedName(qn: string): { parent: string; name: string } | null {
  const lastDot = qn.lastIndexOf(".");
  if (lastDot < 0) return null;
  return { parent: qn.slice(0, lastDot), name: qn.slice(lastDot + 1) };
}

export function parseMemberQualifiedName(qn: string): { typeName: string; memberName: string } | null {
  const dotIdx = qn.indexOf(".");
  if (dotIdx < 0) return null;
  return { typeName: qn.slice(0, dotIdx), memberName: qn.slice(dotIdx + 1) };
}
