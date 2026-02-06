// Type extraction from builtins AST
import type * as AST from "../parser/ast";
import { Parser } from "../parser";
import type { Type, FunctionType, ObjectType, InterfaceType, PropertyType, MethodType, TypeParameter } from "../types/types";
import { Types } from "../types/types";
import { type BuiltinMethodRegistry, type BuiltinMemberInfo } from "../types/primitives";
import { astTypeToType, fnDeclToType, methodToFunctionType } from "../types/type-utils";

export interface BuiltinsTypes {
  functions: Map<string, FunctionType>;
  types: Map<string, ObjectType | InterfaceType>;
  externTypes: Set<string>;
  builtinMethods: BuiltinMethodRegistry;
}

// Parse source and extract types in one step
export function parseAndExtractTypes(source: string): { ast: AST.Program; types: BuiltinsTypes } {
  const ast = new Parser(source).parse();
  const types = extractBuiltinsTypes(ast);
  return { ast, types };
}

function toType(e: AST.TypeExpr | undefined): Type {
  return e ? astTypeToType(e) : Types.unknown;
}

function extractFunctionType(decl: AST.FnDecl | AST.ExternFnDecl): FunctionType {
  if (decl.kind === "FnDecl") return fnDeclToType(decl);
  const typeParams = decl.typeParams?.map(p => ({
    name: p.name,
    constraint: p.constraint ? astTypeToType(p.constraint) : undefined,
  }));
  const params = decl.params.map(p => Types.param(p.name, toType(p.type), p.optional, p.rest));
  return {
    kind: "function",
    typeParams,
    params,
    returnType: toType(decl.returnType),
    isGenerator: false,
    context: [],
  };
}

function extractObjectType(decl: AST.TypeDecl): ObjectType {
  const properties: PropertyType[] = [];
  const methods: MethodType[] = [];

  for (const member of decl.body?.members || []) {
    if (member.kind === "FieldDecl") {
      properties.push({
        name: member.name,
        type: toType(member.type),
        optional: member.optional,
        computed: member.computed,
        defaultValue: !!member.defaultValue,
      });
    } else if (member.kind === "MethodDecl") {
      const fnType = methodToFunctionType(member);
      methods.push({ name: member.name, type: fnType });
    }
  }

  const typeParams: TypeParameter[] | undefined = decl.typeParams?.map(p => ({
    name: p.name,
    constraint: p.constraint ? astTypeToType(p.constraint) : undefined,
  }));
  const aliasTypes = decl.alias?.map(e => astTypeToType(e));

  return {
    kind: "object",
    name: decl.name,
    properties,
    methods,
    typeParams,
    alias: aliasTypes,
  };
}

// Type kind to extern type name mapping for builtin methods
const BUILTIN_TYPE_KIND_MAP: Record<string, string> = {
  "string": "string",
  "list": "list",
  "map": "map",
  "set": "set",
};

// Extract all types from builtins AST
export function extractBuiltinsTypes(program: AST.Program): BuiltinsTypes {
  const functions = new Map<string, FunctionType>();
  const types = new Map<string, ObjectType | InterfaceType>();
  const externTypes = new Set<string>();
  const builtinMethods: BuiltinMethodRegistry = new Map();

  for (const stmt of program.body) {
    switch (stmt.kind) {
      case "FnDecl":
        functions.set(stmt.name, extractFunctionType(stmt));
        break;
      case "ExternFnDecl":
        functions.set(stmt.name, extractFunctionType(stmt));
        break;
      case "InterfaceDecl": {
        const methods: MethodType[] = [];
        for (const member of stmt.body.members) {
          if (member.kind === "MethodDecl") methods.push({ name: member.name, type: methodToFunctionType(member) });
        }
        const iface: InterfaceType = {
          kind: "interface",
          name: stmt.name,
          methods,
          typeParams: stmt.typeParams?.map(p => ({
            name: p.name,
            constraint: p.constraint ? astTypeToType(p.constraint) : undefined,
          })),
        };
        types.set(stmt.name, iface);
        break;
      }
      case "TypeDecl": {
        const objType = extractObjectType(stmt);
        types.set(stmt.name, objType);
        
        // Track extern types for codegen
        if (stmt.isExtern) {
          externTypes.add(stmt.name);
          
          // Extract builtin methods for primitive types
          const typeKind = BUILTIN_TYPE_KIND_MAP[stmt.name];
          if (typeKind) {
            const memberMap = new Map<string, BuiltinMemberInfo>();
            
            // Add properties
            for (const prop of objType.properties) {
              memberMap.set(prop.name, {
                type: prop.type,
                isProperty: true,
              });
            }
            
            // Add methods
            for (const method of objType.methods) {
              memberMap.set(method.name, {
                type: method.type,
                isProperty: false,
              });
            }
            
            builtinMethods.set(typeKind, memberMap);
          }
        }
        break;
      }
    }
  }

  return { functions, types, externTypes, builtinMethods };
}


// ============================================
// IDE Symbol Extraction
// ============================================

import { formatAstType, formatMethodSignature } from "../types/type-utils";

// Stdlib symbol info (with signatures for IDE)
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
