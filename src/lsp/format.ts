// Formatting utilities for IDE display — moved from src/types/type-utils.ts
import * as AST from "../parser/ast";
import type { Type, FunctionType, ParameterType, ObjectType, InterfaceType, MethodType } from "../types/types";
import { typeToString } from "../types/types";
import type { TypeEnvironment } from "../types/environment";
import { astTypeToType } from "../types/type-utils";
import { findTypeDecl } from "../types/ast-query";

// Format an AST type expression to string
export function formatAstType(t: AST.TypeExpr | undefined): string {
  if (!t) return "unknown";
  if (t.kind === "FunctionType") {
    const params = t.params.map(p => formatAstType(p)).join(", ");
    const ret = formatAstType(t.returnType);
    return `fn(${params}): ${ret}`;
  }
  try {
    return typeToString(astTypeToType(t));
  } catch {
    return "unknown";
  }
}

// Format function signature
export function formatFnSignature(fn: AST.FnDecl | AST.ExternFnDecl, isExtern = false): string {
  const params = fn.params.map(p => `${p.name}: ${formatAstType(p.type)}`).join(", ");
  const ret = formatAstType(fn.returnType) || "void";
  const typeParams = fn.typeParams?.length ? `[${fn.typeParams.map(t => t.name).join(", ")}]` : "";
  const prefix = isExtern ? "extern fn" : "fn";
  return `${prefix} ${fn.name}${typeParams}(${params}): ${ret}`;
}

export function formatFnSignatureFromAst(fn: AST.FnDecl): string {
  const params = fn.params.map(p => `${p.name}: ${formatAstType(p.type)}`).join(", ");
  const ret = formatAstType(fn.returnType);
  return `fn(${params}): ${ret}`;
}

// Format method signature
export function formatMethodSignature(m: AST.MethodDecl): string {
  const params = m.params.map(p => `${p.name}${p.optional ? "?" : ""}: ${formatAstType(p.type)}`).join(", ");
  const ret = formatAstType(m.returnType) || "void";
  return `fn ${m.name}(${params}): ${ret}`;
}

// Format type signature with fields
export function formatTypeSignature(t: AST.TypeDecl): { signature: string; fields: string[] } {
  const fields: string[] = [];
  for (const m of t.body?.members || []) {
    if (m.kind === "FieldDecl") {
      const opt = m.optional ? "?" : "";
      const def = m.defaultValue ? " = ..." : "";
      fields.push(`${m.name}${opt}: ${formatAstType(m.type)}${def}`);
    }
  }
  return { signature: t.name, fields };
}

export function formatInterfaceSignature(iface: AST.InterfaceDecl): { signature: string; methods: string[] } {
  const methods = (iface.body?.members || [])
    .filter((m): m is AST.MethodDecl => m.kind === "MethodDecl")
    .map(m => formatMethodSignature(m));
  return { signature: iface.name, methods };
}

export function formatFunctionType(type: Type): string {
  if (type.kind !== "function") return "fn()";
  const fnType = type as FunctionType;
  const params = fnType.params?.map((p: ParameterType) => `${p.name}: ${typeToString(p.type)}`).join(", ") || "";
  const ret = typeToString(fnType.returnType);
  return `fn(${params}): ${ret}`;
}

export function formatTypeSignatureFromObject(obj: ObjectType): { signature: string; fields: string[] } {
  const fields = obj.properties.map(p => `${p.name}: ${typeToString(p.type)}`);
  return { signature: obj.name ?? "", fields };
}

function resolveToKind<T extends Type>(type: Type, env: TypeEnvironment | undefined, kind: "object" | "interface"): T | null {
  if (type.kind === kind) return type as T;
  if (type.kind === "generic") return resolveToKind(type.base, env, kind);
  if (type.kind === "optional") return resolveToKind(type.inner, env, kind);
  if (type.kind === "union") {
    for (const t of type.types) {
      const r = resolveToKind(t, env, kind) as T | null;
      if (r) return r;
    }
  }
  if (type.kind === "ref" && env) {
    const resolved = env.lookupType(type.name);
    if (resolved?.kind === kind) return resolved as T;
  }
  return null;
}

function getRefName(type: Type): string | null {
  if (type.kind === "ref") return type.name;
  if (type.kind === "generic") return getRefName(type.base);
  if (type.kind === "optional") return getRefName(type.inner);
  if (type.kind === "union") {
    for (const t of type.types) {
      const n = getRefName(t);
      if (n) return n;
    }
  }
  return null;
}

export function resolveObjectType(program: AST.Program, type: Type, env?: TypeEnvironment): ObjectType | null {
  const direct = resolveToKind<ObjectType>(type, env, "object");
  if (direct) return direct;
  const refName = getRefName(type);
  if (refName) {
    const typeDecl = findTypeDecl(program, refName);
    if (typeDecl) {
      const props = (typeDecl.body?.members || [])
        .filter((m): m is AST.FieldDecl => m.kind === "FieldDecl")
        .map(m => ({
          name: m.name,
          type: { kind: "unknown" } as Type,
          optional: m.optional,
          computed: false,
          defaultValue: !!m.defaultValue,
        }));
      const methods: MethodType[] = (typeDecl.body?.members || [])
        .filter((m): m is AST.MethodDecl => m.kind === "MethodDecl")
        .map(m => ({ name: m.name, type: { kind: "function", params: [], returnType: { kind: "unknown" }, isGenerator: false, context: [] } as FunctionType }));
      return { kind: "object", name: typeDecl.name, properties: props, methods };
    }
  }
  return null;
}

export function resolveInterfaceType(program: AST.Program, type: Type, env?: TypeEnvironment): InterfaceType | null {
  return resolveToKind<InterfaceType>(type, env, "interface");
}
