// Hover Info - Uses type checker output (env + AST resolvedType) as single source of truth
import * as AST from "../parser/ast";
import type { Type, FunctionType, ObjectType, MethodType, InterfaceType } from "../types/types";
import { typeToString } from "../types/types";
import type { TypeEnvironment } from "../types/environment";
import type { SymbolTable, SymbolDef } from "./symbols";
import { resolveDefinition } from "./resolver";
import { parseMemberQualifiedName, parseQualifiedName } from "./utils";
import {
  formatAstType,
  formatFnSignature,
  formatFunctionType,
  formatTypeSignature,
  formatTypeSignatureFromObject,
  formatInterfaceSignature,
} from "./format";
import { findFnDecl, findTypeDecl, findInterfaceDecl } from "../types/ast-query";
import { findVariableType, findParameterType, getReceiverTypeAtPosition } from "./ast-utils";

export interface HoverInfo {
  signature: string;
  doc?: string;
}

export function getHoverForDecl(decl: AST.FnDecl | AST.ExternFnDecl | AST.TypeDecl | AST.InterfaceDecl): HoverInfo {
  if (decl.kind === "FnDecl" || decl.kind === "ExternFnDecl") {
    return { signature: formatFnSignature(decl as AST.FnDecl), doc: (decl as AST.FnDecl).doc };
  }
  if (decl.kind === "TypeDecl") {
    const { signature, fields } = formatTypeSignature(decl);
    const doc = decl.doc ?? (fields.length ? `**Fields:**\n${fields.map((f) => `- \`${f}\``).join("\n")}` : undefined);
    return { signature: `type ${signature}`, doc };
  }
  const { signature, methods } = formatInterfaceSignature(decl as AST.InterfaceDecl);
  const iface = decl as AST.InterfaceDecl;
  const doc = iface.doc ?? (methods.length ? `**Methods:**\n${methods.map((m) => `- \`${m}\``).join("\n")}` : undefined);
  return { signature: `interface ${signature}`, doc };
}

export function getHoverForType(
  name: string,
  type: FunctionType | ObjectType | InterfaceType
): HoverInfo {
  if (type.kind === "function") {
    const fn = formatFunctionType(type);
    return { signature: fn.startsWith("fn(") ? `fn ${name}${fn.slice(2)}` : `fn ${name}(): unknown` };
  }
  if (type.kind === "object") {
    const { signature, fields } = formatTypeSignatureFromObject(type as ObjectType);
    const doc = fields.length ? `**Fields:**\n${fields.map((f) => `- \`${f}\``).join("\n")}` : undefined;
    return { signature: `type ${signature}`, doc };
  }
  const iface = type as InterfaceType;
  const methods = (iface.methods ?? []).map(
    (m) => `fn ${m.name}${formatFunctionType(m.type).slice(2)}`
  );
  const doc = methods.length ? `**Methods:**\n${methods.map((m) => `- \`${m}\``).join("\n")}` : undefined;
  return { signature: `interface ${iface.name}`, doc };
}

export function getHoverForSymbol(
  symbols: SymbolTable,
  program: AST.Program,
  line: number,
  column: number,
  env?: TypeEnvironment
): HoverInfo | null {
  const def = resolveDefinition(symbols, line, column);
  if (!def) return null;
  return getHoverForDefinition(def, program, env, line, column);
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
        const params = fnType.params.map((p) => `${p.name}: ${typeToString(p.type)}`).join(", ");
        return { signature: `fn ${def.name}(${params}): ${typeToString(fnType.returnType)}`, doc: fn.doc };
      }
      return getHoverForDecl(fn);
    }
    case "type": {
      const fromEnv = env && getTypeOrInterfaceFromEnv(env, def.name);
      if (fromEnv?.kind === "interface") {
        const iface = findInterfaceDecl(program, def.name);
        return iface ? getHoverForDecl(iface) : { signature: `interface ${def.name}`, doc: undefined };
      }
      if (fromEnv?.kind === "object") {
        const { signature, fields } = formatTypeSignatureFromObject(fromEnv as ObjectType);
        return { signature: `type ${signature}`, doc: fields.length ? `**Fields:**\n${fields.map(f => `- \`${f}\``).join("\n")}` : undefined };
      }
      const iface = findInterfaceDecl(program, def.name);
      if (iface) return getHoverForDecl(iface);
      const typeDecl = findTypeDecl(program, def.name);
      if (typeDecl) return getHoverForDecl(typeDecl);
      break;
    }
    case "field": {
      const parsed = parseMemberQualifiedName(def.id.qualifiedName);
      if (!parsed) break;
      const receiver = env && getReceiverTypeForMember(env, program, parsed.typeName, hoverLine, hoverCol, parsed.memberName);
      const objType = receiver?.kind === "object" ? receiver : null;
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
      const resolvedType = env && getReceiverTypeForMember(env, program, parsed.typeName, hoverLine, hoverCol, parsed.memberName);
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
      const varType = env?.getType(def.name) ?? findVariableType(program, def.name, def.loc.line);
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

function getReceiverTypeForMember(env: TypeEnvironment, program: AST.Program, typeName: string, line?: number, col?: number, memberName?: string): ObjectType | InterfaceType | null {
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
