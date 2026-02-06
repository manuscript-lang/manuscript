// Hover Info - Uses type checker output (env + AST resolvedType) as single source of truth
import * as AST from "../parser/ast";
import type { Type, FunctionType, ObjectType, MethodType, InterfaceType } from "../types/types";
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
  formatTypeSignature,
  formatTypeSignatureFromObject,
  formatInterfaceSignature,
  parseMemberQualifiedName,
  parseQualifiedName,
  getReceiverTypeAtPosition,
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
      return getHoverForDefinition(def, program, env, line, column);
    }
  }
  for (const ref of symbols.getAllReferences()) {
    const def = symbols.getDefinitionById(ref.symbolId);
    if (def && ref.loc.line === line && column >= ref.loc.column && column <= ref.loc.column + def.name.length) {
      return getHoverForDefinition(def, program, env, line, column);
    }
  }
  return null;
}

function getHoverForDefinition(
  def: SymbolDef,
  program: AST.Program,
  env?: TypeEnvironment,
  hoverLine?: number,
  hoverCol?: number
): HoverInfo | null {
  switch (def.id.kind) {
    case "function": {
      const fn = findFnDecl(program, def.name);
      if (!fn) break;
      const fnType = fn.resolvedType as FunctionType | undefined;
      if (fnType?.kind === "function") {
        const params = fnType.params.map((p: any) => `${p.name}: ${typeToString(p.type)}`).join(", ");
        return { signature: `fn ${def.name}(${params}): ${typeToString(fnType.returnType)}`, doc: fn.doc };
      }
      return { signature: formatFnSignature(fn), doc: fn.doc };
    }
    case "type": {
      const fromEnv = env && getTypeOrInterfaceFromEnv(env, def.name);
      if (fromEnv?.kind === "interface") {
        const iface = findInterfaceDecl(program, def.name);
        const { signature, methods } = iface ? formatInterfaceSignature(iface) : { signature: def.name, methods: [] };
        const doc = iface?.doc ?? (methods.length ? `**Methods:**\n${methods.map(m => `- \`${m}\``).join("\n")}` : undefined);
        return { signature: `interface ${signature}`, doc };
      }
      if (fromEnv?.kind === "object") {
        const { signature, fields } = formatTypeSignatureFromObject(fromEnv as ObjectType);
        return { signature: `type ${signature}`, doc: fields.length ? `**Fields:**\n${fields.map(f => `- \`${f}\``).join("\n")}` : undefined };
      }
      const iface = findInterfaceDecl(program, def.name);
      if (iface) {
        const { signature } = formatInterfaceSignature(iface);
        return { signature: `interface ${signature}`, doc: iface.doc };
      }
      const typeDecl = findTypeDecl(program, def.name);
      if (typeDecl) {
        const { signature, fields } = formatTypeSignature(typeDecl);
        return { signature: `type ${signature}`, doc: typeDecl.doc };
      }
      break;
    }
    case "field": {
      const parsed = parseMemberQualifiedName(def.id.qualifiedName);
      if (!parsed) break;
      const objType = env && getObjectTypeForMember(env, program, parsed.typeName, hoverLine, hoverCol, parsed.memberName);
      const prop = objType?.properties.find(p => p.name === parsed.memberName);
      if (prop) return { signature: `(field) ${parsed.memberName}: ${typeToString(prop.type)}` };
      const typeDecl = findTypeDecl(program, parsed.typeName);
      const fieldMember = typeDecl?.body?.members?.find((m): m is AST.FieldDecl => m.kind === "FieldDecl" && m.name === parsed.memberName);
      if (fieldMember) return { signature: `(field) ${parsed.memberName}: ${formatAstType(fieldMember.type)}` };
      break;
    }
    case "method": {
      const parsed = parseMemberQualifiedName(def.id.qualifiedName);
      if (!parsed) break;
      const resolvedType = env && getObjectOrInterfaceForMember(env, program, parsed.typeName, hoverLine, hoverCol, parsed.memberName);
      const method = resolvedType && getMethodFromResolved(resolvedType, parsed.memberName);
      if (method) {
        const params = method.type.params.map((p: any) => `${p.name}: ${typeToString(p.type)}`).join(", ");
        const sig = `(method) fn ${parsed.memberName}(${params}): ${typeToString(method.type.returnType)}`;
        const decl = findTypeDecl(program, resolvedType.name ?? parsed.typeName) ?? findInterfaceDecl(program, (resolvedType as InterfaceType).name ?? parsed.typeName);
        const methodDecl = decl?.body?.members?.find((m): m is AST.MethodDecl => m.kind === "MethodDecl" && m.name === parsed.memberName);
        return { signature: sig, doc: methodDecl?.doc };
      }
      const typeDecl = findTypeDecl(program, parsed.typeName);
      const iface = findInterfaceDecl(program, parsed.typeName);
      const methodMember = (typeDecl?.body?.members ?? iface?.body?.members ?? []).find((m): m is AST.MethodDecl => m.kind === "MethodDecl" && m.name === parsed.memberName);
      if (methodMember) {
        const params = methodMember.params.map(p => `${p.name}: ${formatAstType(p.type)}`).join(", ");
        return { signature: `(method) fn ${parsed.memberName}(${params}): ${formatAstType(methodMember.returnType)}`, doc: methodMember.doc };
      }
      break;
    }
    case "variable": {
      const varType = env?.getType(def.name) ?? findVariableType(program, def);
      const prefix = def.loc.column === 5 ? "(let)" : "(var)";
      return { signature: `${prefix} ${def.name}: ${varType ? typeToString(varType) : "any"}` };
    }
    case "parameter": {
      const parsed = parseQualifiedName(def.id.qualifiedName);
      const paramType = parsed ? findParameterType(program, parsed.parent, parsed.name) : null;
      return { signature: `(parameter) ${parsed?.name ?? def.name}: ${paramType ? formatAstType(paramType) : "any"}` };
    }
  }
  return null;
}

function getTypeOrInterfaceFromEnv(env: TypeEnvironment, name: string): ObjectType | InterfaceType | null {
  const t = env.lookupType(name);
  if (t?.kind === "object" || t?.kind === "interface") return t as ObjectType | InterfaceType;
  return null;
}

function getObjectTypeForMember(env: TypeEnvironment, program: AST.Program, typeName: string, line?: number, col?: number, memberName?: string): ObjectType | null {
  if (line !== undefined && col !== undefined && memberName) {
    const receiverType = getReceiverTypeAtPosition(program, line, col, memberName);
    if (receiverType) {
      const resolved = env.resolveType(receiverType);
      if (resolved.kind === "object") return resolved as ObjectType;
    }
  }
  const t = env.lookupType(typeName);
  if (t?.kind === "object") return t as ObjectType;
  return null;
}

function getObjectOrInterfaceForMember(env: TypeEnvironment, program: AST.Program, typeName: string, line?: number, col?: number, memberName?: string): ObjectType | InterfaceType | null {
  if (line !== undefined && col !== undefined && memberName) {
    const receiverType = getReceiverTypeAtPosition(program, line, col, memberName);
    if (receiverType) {
      const resolved = env.resolveType(receiverType);
      if (resolved.kind === "object" || resolved.kind === "interface") return resolved as ObjectType | InterfaceType;
    }
  }
  const t = env.lookupType(typeName);
  if (t?.kind === "object" || t?.kind === "interface") return t as ObjectType | InterfaceType;
  return null;
}

function getMethodFromResolved(resolved: ObjectType | InterfaceType, name: string): MethodType | null {
  const methods = (resolved as ObjectType).methods ?? (resolved as InterfaceType).methods;
  return methods?.find(m => m.name === name) ?? null;
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
      if (s.kind === "WithStmt") {
        for (const c of s.contexts) {
          if (c.name === def.name) return c.expr.resolvedType ?? null;
        }
        const inBody = searchStatements(s.body.statements);
        if (inBody) return inBody;
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
