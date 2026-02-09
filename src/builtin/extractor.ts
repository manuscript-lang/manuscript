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
