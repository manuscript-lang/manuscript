// Type extraction from stdlib AST
import type * as AST from "../parser/ast";
import type { Type, FunctionType, ObjectType, PropertyType, MethodType } from "../types/types";
import { Types } from "../types/types";

export interface StdlibTypes {
  functions: Map<string, FunctionType>;
  types: Map<string, ObjectType>;
}

// Convert AST TypeExpr to internal Type
function astTypeToType(typeExpr: AST.TypeExpr | undefined): Type {
  if (!typeExpr) return Types.any;

  switch (typeExpr.kind) {
    case "NamedType":
      return nameToType(typeExpr.name);

    case "GenericType": {
      const base = nameToType(typeExpr.name);
      const args = typeExpr.args.map(astTypeToType);
      
      // Handle built-in generic types specially
      if (typeExpr.name === "list" && args.length === 1) {
        return Types.list(args[0]!);
      }
      if (typeExpr.name === "map" && args.length === 2) {
        return Types.map(args[0]!, args[1]!);
      }
      if (typeExpr.name === "set" && args.length === 1) {
        return Types.set(args[0]!);
      }
      if (typeExpr.name === "promise" && args.length === 1) {
        return Types.promise(args[0]!);
      }
      if (typeExpr.name === "channel" && args.length === 1) {
        return Types.channel(args[0]!);
      }
      if (typeExpr.name === "stream" && args.length === 1) {
        return Types.stream(args[0]!);
      }
      if (typeExpr.name === "Result" && args.length === 2) {
        return Types.result(args[0]!, args[1]!);
      }
      
      return Types.generic(base, args);
    }

    case "FunctionType": {
      const params = typeExpr.params.map((p, i) => 
        Types.param(`arg${i}`, astTypeToType(p))
      );
      return Types.fn(params, astTypeToType(typeExpr.returnType));
    }

    case "UnionType":
      return Types.union(...typeExpr.types.map(astTypeToType));

    case "OptionalType":
      return Types.optional(astTypeToType(typeExpr.inner));

    case "ListType":
      return Types.list(astTypeToType(typeExpr.elementType));

    case "MapType":
      return Types.map(astTypeToType(typeExpr.keyType), astTypeToType(typeExpr.valueType));

    default:
      return Types.any;
  }
}

function nameToType(name: string): Type {
  switch (name) {
    case "number": return Types.number;
    case "string": return Types.string;
    case "bool": return Types.bool;
    case "null": return Types.null;
    case "bytes": return Types.bytes;
    case "any": return Types.any;
    case "never": return Types.never;
    case "void": return Types.void;
    default: return Types.ref(name);
  }
}

// Extract function type from FnDecl or ExternFnDecl
function extractFunctionType(decl: AST.FnDecl | AST.ExternFnDecl): FunctionType {
  const typeParams = decl.typeParams?.map(p => ({
    name: p.name,
    constraint: p.constraint ? astTypeToType(p.constraint) : undefined,
  }));
  const params = decl.params.map(p => 
    Types.param(p.name, astTypeToType(p.type), p.optional, p.rest)
  );
  const returnType = astTypeToType(decl.returnType);
  const isGenerator = decl.kind === "FnDecl" ? decl.isGenerator : false;
  
  return {
    kind: "function",
    typeParams,
    params,
    returnType,
    isGenerator,
    context: [],
  };
}

// Extract object type from TypeDecl
function extractObjectType(decl: AST.TypeDecl): ObjectType {
  const properties: PropertyType[] = [];
  const methods: MethodType[] = [];

  for (const member of decl.body?.members || []) {
    if (member.kind === "FieldDecl") {
      properties.push({
        name: member.name,
        type: astTypeToType(member.type),
        optional: member.optional,
        readonly: false,
        computed: member.computed,
        defaultValue: !!member.defaultValue,
      });
    } else if (member.kind === "MethodDecl") {
      const methodParams = member.params.map(p => 
        Types.param(p.name, astTypeToType(p.type), p.optional, p.rest)
      );
      methods.push({
        name: member.name,
        type: Types.fn(methodParams, astTypeToType(member.returnType)),
      });
    }
  }

  return {
    kind: "object",
    name: decl.name,
    properties,
    methods,
  };
}

// Primitive types that are built-in (skip in type extraction)
const BUILTIN_PRIMITIVE_TYPES = new Set(["string", "list", "map", "set"]);

// Extract all types from stdlib AST
export function extractStdlibTypes(program: AST.Program): StdlibTypes {
  const functions = new Map<string, FunctionType>();
  const types = new Map<string, ObjectType>();

  for (const stmt of program.body) {
    switch (stmt.kind) {
      case "FnDecl":
        functions.set(stmt.name, extractFunctionType(stmt));
        break;
      case "ExternFnDecl":
        functions.set(stmt.name, extractFunctionType(stmt));
        break;
      case "TypeDecl":
        // Skip extern types for built-in primitives - they're for IDE tooling only
        if (stmt.isExtern && BUILTIN_PRIMITIVE_TYPES.has(stmt.name)) {
          break;
        }
        types.set(stmt.name, extractObjectType(stmt));
        break;
    }
  }

  return { functions, types };
}

// Get set of function names for codegen
export function getStdlibFunctionNames(program: AST.Program): Set<string> {
  const result = new Set<string>();
  for (const stmt of program.body) {
    if (stmt.kind === "FnDecl" || stmt.kind === "ExternFnDecl") {
      result.add(stmt.name);
    }
  }
  return result;
}

// Get set of extern function names (need runtime implementation)
export function getExternFunctionNames(program: AST.Program): Set<string> {
  const result = new Set<string>();
  for (const stmt of program.body) {
    if (stmt.kind === "ExternFnDecl") {
      result.add(stmt.name);
    }
  }
  return result;
}

// Get set of pure function names (implemented in Manuscript)
export function getPureFunctionNames(program: AST.Program): Set<string> {
  const result = new Set<string>();
  for (const stmt of program.body) {
    if (stmt.kind === "FnDecl") {
      result.add(stmt.name);
    }
  }
  return result;
}

// ============================================
// IDE Symbol Extraction
// ============================================

import { formatAstType, formatMethodSignature, getDocstring } from "../types/type-utils";

// Stdlib symbol info (with signatures for IDE)
export interface StdlibSymbol {
  name: string;
  kind: "function" | "extern" | "type";
  loc: AST.SourceLocation;
  signature?: string;
  doc?: string;
}

// Collect symbols from stdlib program (for completions/hover)
export function collectStdlibSymbols(program: AST.Program): Map<string, StdlibSymbol> {
  const syms = new Map<string, StdlibSymbol>();

  for (const stmt of program.body) {
    if (stmt.kind === "FnDecl") {
      const params = stmt.params.map(p => `${p.name}: ${formatAstType(p.type)}`).join(", ");
      const ret = formatAstType(stmt.returnType) || "void";
      const typeParams = stmt.typeParams?.length ? `[${stmt.typeParams.map(t => t.name).join(", ")}]` : "";
      const signature = `fn ${stmt.name}${typeParams}(${params}): ${ret}`;
      const doc = getDocstring(stmt.body);
      syms.set(stmt.name, { name: stmt.name, kind: "function", loc: stmt.loc, signature, doc });
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
      const doc = fields.length ? `**Fields:**\n${fields.map(f => `- \`${f}\``).join("\n")}` : undefined;
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
        loc: m.loc,
      });
    } else if (m.kind === "MethodDecl") {
      members.push({
        name: m.name,
        kind: "method",
        signature: formatMethodSignature(m),
        doc: m.body ? getDocstring(m.body) : undefined,
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
