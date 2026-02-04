// Pass 1: Collect Declarations
// Gathers type and function declarations into the type environment
import * as AST from "../../parser/ast";
import type { Type, ObjectType, FunctionType, PropertyType, MethodType } from "../types";
import { Types } from "../types";
import type { TypeEnvironment } from "../environment";
import { TypeCheckError } from "../errors";
import { TypeErrors } from "../../shared/errors";
import { astTypeToType, methodToFunctionType, fnDeclToType } from "../type-utils";

export interface CollectInput {
  program: AST.Program;
  env: TypeEnvironment;
}

export interface CollectOutput {
  env: TypeEnvironment;
  fnDecls: Map<string, AST.FnDecl>;
  keywordDecls: Map<string, AST.KeywordDecl>;
  errors: TypeCheckError[];
}

// Built-in keywords that are always available
const BUILTIN_KEYWORDS = ["enum", "agent", "context", "capabilities"];

function createBuiltinKeywordDecl(name: string): AST.KeywordDecl {
  const loc: AST.SourceLocation = { line: 0, column: 0, offset: 0 };
  return {
    kind: "KeywordDecl",
    name,
    expansion: "type",
    loc,
  };
}

export function collectDeclarations(input: CollectInput): CollectOutput {
  const { program, env } = input;
  const fnDecls = new Map<string, AST.FnDecl>();
  const keywordDecls = new Map<string, AST.KeywordDecl>();
  const errors: TypeCheckError[] = [];

  const addError = (message: string, loc: AST.SourceLocation, hint?: string) => {
    errors.push(new TypeCheckError(message, loc, hint));
  };

  // Pre-register built-in keywords
  for (const name of BUILTIN_KEYWORDS) {
    keywordDecls.set(name, createBuiltinKeywordDecl(name));
  }

  // Pass 0: collect keyword declarations (can override built-ins)
  for (const stmt of program.body) {
    if (stmt.kind === "KeywordDecl") {
      keywordDecls.set(stmt.name, stmt);
    }
  }

  // First pass: register all types (needed for embedded type lookup)
  for (const stmt of program.body) {
    if (stmt.kind === "TypeDecl") {
      registerType(stmt, env, addError);
    } else if (stmt.kind === "KeywordTypeUse") {
      registerKeywordTypeUse(stmt, keywordDecls, env, addError);
    }
  }

  // Second pass: resolve embedded types and promote members
  for (const stmt of program.body) {
    if (stmt.kind === "TypeDecl") {
      resolveEmbeddedTypes(stmt, env, addError);
    } else if (stmt.kind === "FnDecl") {
      collectFnDecl(stmt, env, fnDecls, addError);
    }
  }

  return { env, fnDecls, keywordDecls, errors };
}

function registerType(
  decl: AST.TypeDecl,
  env: TypeEnvironment,
  addError: (msg: string, loc: AST.SourceLocation, hint?: string) => void
): void {
  const properties: PropertyType[] = [];
  const methods: MethodType[] = [];

  if (decl.body && decl.body.members.length > 0) {
    for (const member of decl.body.members) {
      if (member.kind === "FieldDecl") {
        properties.push({
          name: member.name,
          type: member.type ? astTypeToType(member.type) : Types.any,
          optional: member.optional,
          computed: member.computed,
          defaultValue: !!member.defaultValue,
          embedded: member.embedded,
        });
      } else if (member.kind === "MethodDecl") {
        const methodType = methodToFunctionType(member);
        methods.push({ name: member.name, type: methodType });
      }
    }
  }

  const type: ObjectType = {
    kind: "object",
    name: decl.name,
    properties,
    methods,
    typeParams: decl.typeParams?.map(p => ({
      name: p.name,
      constraint: p.constraint ? astTypeToType(p.constraint) : undefined
    })),
    alias: decl.alias?.map(e => astTypeToType(e)),
  };

  try {
    env.defineType(decl.name, type);
  } catch (e) {
    const err = TypeErrors.typeAlreadyDefined(decl.name);
    addError(err.message, decl.loc, err.hint);
  }
}

function resolveEmbeddedTypes(
  decl: AST.TypeDecl,
  env: TypeEnvironment,
  addError: (msg: string, loc: AST.SourceLocation, hint?: string) => void
): void {
  const type = env.lookupType(decl.name);
  if (!type || type.kind !== "object") return;

  // Find embedded fields
  const embeddedFields = type.properties.filter(p => p.embedded);
  if (embeddedFields.length === 0) return;

  // Track own member names (these shadow promoted members)
  const ownNames = new Set([
    ...type.properties.filter(p => !p.embedded).map(p => p.name),
    ...type.methods.map(m => m.name),
  ]);

  // Track promoted member sources for ambiguity detection
  const promotedSources = new Map<string, string[]>();

  for (const embedded of embeddedFields) {
    const embeddedType = env.lookupType(embedded.name);
    if (!embeddedType || embeddedType.kind !== "object") {
      addError(
        `Cannot embed '${embedded.name}': type not found`,
        decl.loc,
        `Make sure '${embedded.name}' is defined before '${decl.name}'`
      );
      continue;
    }

    // Promote properties from embedded type
    for (const prop of embeddedType.properties) {
      if (ownNames.has(prop.name)) continue; // Shadowed by own member
      
      // Check for ambiguity
      const sources = promotedSources.get(prop.name) || [];
      sources.push(embedded.name);
      promotedSources.set(prop.name, sources);

      // Only add if not already promoted
      if (sources.length === 1) {
        type.properties.push({
          ...prop,
          promotedFrom: embedded.name,
        });
      }
    }

    // Promote methods from embedded type
    for (const method of embeddedType.methods) {
      if (ownNames.has(method.name)) continue; // Shadowed by own member
      
      const sources = promotedSources.get(method.name) || [];
      sources.push(embedded.name);
      promotedSources.set(method.name, sources);

      if (sources.length === 1) {
        type.methods.push({
          ...method,
          promotedFrom: embedded.name,
        });
      }
    }
  }

  // Report ambiguous accesses
  for (const [name, sources] of promotedSources) {
    if (sources.length > 1) {
      addError(
        `Ambiguous access to '${name}' - exists in: ${sources.join(", ")}`,
        decl.loc,
        `Use explicit access: obj.TypeName.${name}`
      );
    }
  }
}

function collectFnDecl(
  decl: AST.FnDecl,
  env: TypeEnvironment,
  fnDecls: Map<string, AST.FnDecl>,
  addError: (msg: string, loc: AST.SourceLocation, hint?: string) => void
): void {
  const fnType = fnDeclToType(decl);
  try {
    env.define(decl.name, fnType);
    fnDecls.set(decl.name, decl);
  } catch (e) {
    const err = TypeErrors.functionAlreadyDefined(decl.name);
    addError(err.message, decl.loc, err.hint);
  }
}

// Register a keyword type use (e.g., "workflow DataPipeline")
function registerKeywordTypeUse(
  use: AST.KeywordTypeUse,
  keywordDecls: Map<string, AST.KeywordDecl>,
  env: TypeEnvironment,
  addError: (msg: string, loc: AST.SourceLocation, hint?: string) => void
): void {
  const keywordDecl = keywordDecls.get(use.keyword);
  
  if (!keywordDecl) {
    addError(
      `Unknown keyword '${use.keyword}'`,
      use.loc,
      `Define it with: keyword ${use.keyword} = type`
    );
    return;
  }

  if (keywordDecl.expansion !== "type") {
    addError(
      `Keyword '${use.keyword}' is not a type keyword`,
      use.loc,
      `'${use.keyword}' expands to '${keywordDecl.expansion}', not 'type'`
    );
    return;
  }

  // Collect properties from keyword declaration
  const properties: PropertyType[] = [];
  const methods: MethodType[] = [];
  const keywordMethodNames = new Set<string>();

  // Add fields from keyword declaration
  if (keywordDecl.body) {
    for (const member of keywordDecl.body.members) {
      if (member.kind === "KeywordField") {
        properties.push({
          name: member.name,
          type: astTypeToType(member.type),
          optional: member.optional,
          computed: member.computed,
          defaultValue: !!member.defaultValue,
        });
      } else if (member.kind === "MethodDecl") {
        const methodType = methodToFunctionType(member);
        methods.push({ name: member.name, type: methodType });
        keywordMethodNames.add(member.name);
      }
    }
  }

  // Add fields from user's type body (validate no method collision)
  for (const member of use.body.members) {
    if (member.kind === "FieldDecl") {
      // Check if this overrides a keyword field (allowed for providing values)
      const existingIdx = properties.findIndex(p => p.name === member.name);
      if (existingIdx >= 0) {
        // User is providing value for keyword field - keep keyword's type, mark as provided
        properties[existingIdx] = {
          ...properties[existingIdx]!,
          defaultValue: true,  // Mark as having a value
        };
      } else {
        // User's additional field
        properties.push({
          name: member.name,
          type: member.type ? astTypeToType(member.type) : Types.any,
          optional: member.optional,
          computed: member.computed,
          defaultValue: !!member.defaultValue,
        });
      }
    } else if (member.kind === "MethodDecl") {
      // Check for collision with keyword methods (not allowed)
      if (keywordMethodNames.has(member.name)) {
        addError(
          `Cannot override keyword method '${member.name}'`,
          member.loc,
          `Keyword '${use.keyword}' defines sealed method '${member.name}'. Use hooks for customization.`
        );
        continue;
      }
      const methodType = methodToFunctionType(member);
      methods.push({ name: member.name, type: methodType });
    }
  }

  // Check required fields are provided
  if (keywordDecl.body) {
    for (const member of keywordDecl.body.members) {
      if (member.kind === "KeywordField" && !member.optional && !member.defaultValue) {
        const prop = properties.find(p => p.name === member.name);
        if (!prop || !prop.defaultValue) {
          addError(
            `Missing required field '${member.name}' for keyword '${use.keyword}'`,
            use.loc,
            `'${use.keyword}' requires field '${member.name}: ${member.type ? astTypeToType(member.type).kind : 'unknown'}'`
          );
        }
      }
    }
  }

  const type: ObjectType = {
    kind: "object",
    name: use.name,
    properties,
    methods,
  };

  try {
    env.defineType(use.name, type);
  } catch (e) {
    const err = TypeErrors.typeAlreadyDefined(use.name);
    addError(err.message, use.loc, err.hint);
  }
}
