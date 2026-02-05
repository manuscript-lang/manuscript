// Hover Info - Provides hover information for symbols (uses type checker env when available)
import * as AST from "../parser/ast";
import type { Type, FunctionType, ObjectType } from "../types/types";
import { typeToString } from "../types/types";
import type { TypeEnvironment } from "../types/environment";
import type { SymbolTable, SymbolDef } from "./symbols";
import {
  isDefLocationMatch,
  findFnDecl,
  findTypeDecl,
  findInterfaceDecl,
  formatAstType,
  formatFnSignature,
  formatFunctionType,
  formatTypeSignature,
  formatTypeSignatureFromObject,
  formatInterfaceSignature,
  parseMemberQualifiedName,
  parseQualifiedName,
} from "./utils";

export interface HoverInfo {
  signature: string;
  doc?: string;
}

export function getHoverForSymbol(
  symbols: SymbolTable,
  program: AST.Program,
  line: number,
  column: number,
  env?: TypeEnvironment
): HoverInfo | null {
  for (const def of symbols.getAllDefinitions()) {
    if (isDefLocationMatch(def, line, column)) {
      return getHoverForDefinition(def, program, env);
    }
  }
  for (const ref of symbols.getAllReferences()) {
    const def = symbols.getDefinitionById(ref.symbolId);
    if (def && ref.loc.line === line && column >= ref.loc.column && column <= ref.loc.column + def.name.length) {
      return getHoverForDefinition(def, program, env);
    }
  }
  return null;
}

function getHoverForDefinition(
  def: SymbolDef,
  program: AST.Program,
  env?: TypeEnvironment
): HoverInfo | null {
  switch (def.id.kind) {
    case "function": {
      const fn = findFnDecl(program, def.name);
      if (fn) {
        const fnType = fn.resolvedType as FunctionType | undefined;
        if (fnType?.kind === "function") {
          const params = fnType.params.map((p: any) => `${p.name}: ${typeToString(p.type)}`).join(", ");
          const ret = typeToString(fnType.returnType);
          return { signature: `fn ${def.name}(${params}): ${ret}`, doc: fn.doc };
        }
        return { signature: formatFnSignature(fn), doc: fn.doc };
      }
      break;
    }
    case "type": {
      if (env) {
        const looked = env.lookupType(def.name);
        if (looked?.kind === "interface") {
          const iface = findInterfaceDecl(program, def.name);
          if (iface) {
            const { signature, methods } = formatInterfaceSignature(iface);
            const doc = iface.doc ?? (methods.length ? `**Methods:**\n${methods.map(m => `- \`${m}\``).join("\n")}` : undefined);
            return { signature: `interface ${signature}`, doc };
          }
        }
        if (looked?.kind === "object") {
          const { signature, fields } = formatTypeSignatureFromObject(looked as ObjectType);
          const doc = fields.length ? `**Fields:**\n${fields.map(f => `- \`${f}\``).join("\n")}` : undefined;
          return { signature: `type ${signature}`, doc };
        }
      }
      const iface = findInterfaceDecl(program, def.name);
      if (iface) {
        const { signature, methods } = formatInterfaceSignature(iface);
        const doc = iface.doc ?? (methods.length ? `**Methods:**\n${methods.map(m => `- \`${m}\``).join("\n")}` : undefined);
        return { signature: `interface ${signature}`, doc };
      }
      const typeDecl = findTypeDecl(program, def.name);
      if (typeDecl) {
        const { signature, fields } = formatTypeSignature(typeDecl);
        const doc = typeDecl.doc ?? (fields.length ? `**Fields:**\n${fields.map(f => `- \`${f}\``).join("\n")}` : undefined);
        return { signature: `type ${signature}`, doc };
      }
      break;
    }
    case "field": {
      const parsed = parseMemberQualifiedName(def.id.qualifiedName);
      if (parsed && env) {
        const obj = env.lookupType(parsed.typeName);
        if (obj?.kind === "object") {
          const prop = (obj as ObjectType).properties.find(p => p.name === parsed.memberName);
          if (prop) return { signature: `(field) ${parsed.memberName}: ${typeToString(prop.type)}` };
        }
      }
      if (parsed) {
        const typeDecl = findTypeDecl(program, parsed.typeName);
        if (typeDecl) {
          for (const m of typeDecl.body?.members || []) {
            if (m.kind === "FieldDecl" && m.name === parsed.memberName) {
              return { signature: `(field) ${parsed.memberName}: ${formatAstType(m.type)}` };
            }
          }
        }
      }
      break;
    }
    case "method": {
      const parsed = parseMemberQualifiedName(def.id.qualifiedName);
      if (parsed && env) {
        const looked = env.lookupType(parsed.typeName);
        if (looked?.kind === "object") {
          const o = looked as ObjectType;
          const method = o.methods.find(m => m.name === parsed.memberName);
          if (method) {
            const ft = method.type;
            const params = ft.params.map((p: any) => `${p.name}: ${typeToString(p.type)}`).join(", ");
            const ret = typeToString(ft.returnType);
            const methodMember = findTypeDecl(program, parsed.typeName)?.body?.members?.find((m): m is AST.MethodDecl => m.kind === "MethodDecl" && m.name === parsed.memberName);
            return { signature: `(method) fn ${parsed.memberName}(${params}): ${ret}`, doc: methodMember?.doc };
          }
        }
        if (looked?.kind === "interface") {
          const method = (looked as any).methods?.find((m: any) => m.name === parsed.memberName);
          if (method) {
            const ft = method.type;
            const params = ft.params?.map((p: any) => `${p.name}: ${typeToString(p.type)}`).join(", ") ?? "";
            const ret = typeToString(ft.returnType);
            const methodMember = findInterfaceDecl(program, parsed.typeName)?.body?.members?.find((m): m is AST.MethodDecl => m.kind === "MethodDecl" && m.name === parsed.memberName);
            return { signature: `(method) fn ${parsed.memberName}(${params}): ${ret}`, doc: methodMember?.doc };
          }
        }
      }
      if (parsed) {
        const typeDecl = findTypeDecl(program, parsed.typeName);
        if (typeDecl) {
          for (const m of typeDecl.body?.members || []) {
            if (m.kind === "MethodDecl" && m.name === parsed.memberName) {
              const params = m.params.map(p => `${p.name}: ${formatAstType(p.type)}`).join(", ");
              const ret = formatAstType(m.returnType);
              return { signature: `(method) fn ${parsed.memberName}(${params}): ${ret}`, doc: m.doc };
            }
          }
        }
        const iface = findInterfaceDecl(program, parsed.typeName);
        if (iface) {
          for (const m of iface.body?.members || []) {
            if (m.kind === "MethodDecl" && m.name === parsed.memberName) {
              const params = m.params.map(p => `${p.name}: ${formatAstType(p.type)}`).join(", ");
              const ret = formatAstType(m.returnType);
              return { signature: `(method) fn ${parsed.memberName}(${params}): ${ret}`, doc: m.doc };
            }
          }
        }
      }
      break;
    }
    case "variable": {
      const varType = findVariableType(program, def);
      const prefix = def.loc.column === 5 ? "(let)" : "(var)";
      return { signature: `${prefix} ${def.name}: ${varType ? typeToString(varType) : "any"}` };
    }
    case "parameter": {
      const parsed = parseQualifiedName(def.id.qualifiedName);
      if (parsed) {
        const paramType = findParameterType(program, parsed.parent, parsed.name);
        return { signature: `(parameter) ${parsed.name}: ${paramType ? formatAstType(paramType) : "any"}` };
      }
      return { signature: `(parameter) ${def.name}: any` };
    }
  }
  return null;
}

function findVariableType(program: AST.Program, def: SymbolDef): Type | null {
  function searchStatements(stmts: AST.Statement[]): Type | null {
    for (const s of stmts) {
      if (s.kind === "LetStmt" && s.pattern?.kind === "IdentifierPattern" && s.pattern.name === def.name && s.loc.line === def.loc.line) {
        return s.value.resolvedType || null;
      }
      if (s.kind === "VarStmt" && s.name === def.name && s.loc.line === def.loc.line) {
        return s.value.resolvedType || null;
      }
      if (s.kind === "FnDecl" && s.body) {
        const result = searchStatements(s.body.statements);
        if (result) return result;
      }
      if (s.kind === "TypeDecl") {
        for (const m of s.body?.members || []) {
          if (m.kind === "MethodDecl" && m.body) {
            const result = searchStatements(m.body.statements);
            if (result) return result;
          }
        }
      }
    }
    return null;
  }
  return searchStatements(program.body);
}

function findParameterType(program: AST.Program, scope: string, paramName: string): AST.TypeExpr | null {
  if (scope.includes(".")) {
    const dotIdx = scope.indexOf(".");
    const typeName = scope.slice(0, dotIdx);
    const methodName = scope.slice(dotIdx + 1);
    const typeDecl = findTypeDecl(program, typeName);
    if (typeDecl) {
      for (const m of typeDecl.body?.members || []) {
        if (m.kind === "MethodDecl" && m.name === methodName) {
          for (const p of m.params) {
            if (p.name === paramName) return p.type ?? null;
          }
        }
      }
    }
    const iface = findInterfaceDecl(program, typeName);
    if (iface) {
      for (const m of iface.body?.members || []) {
        if (m.kind === "MethodDecl" && m.name === methodName) {
          for (const p of m.params) {
            if (p.name === paramName) return p.type ?? null;
          }
        }
      }
    }
  } else {
    const fn = findFnDecl(program, scope);
    if (fn) {
      for (const p of fn.params) {
        if (p.name === paramName) return p.type ?? null;
      }
    }
  }
  return null;
}
