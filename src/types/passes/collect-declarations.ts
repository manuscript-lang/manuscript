// Pass 1: Collect Declarations
import type * as AST from "../../parser/ast";
import type { ObjectType, InterfaceType, PropertyType, MethodType } from "../types";
import { Types } from "../types";
import type { TypeEnvironment } from "../environment";
import { TypeCheckError } from "../errors";
import type { Pass, PassContext } from "../pass-manager";
import { TypeErrors, RESERVED_PROPERTY_NAMES } from "../../shared/errors";
import { astTypeToType, methodToFunctionType, fnDeclToType } from "../type-utils";

export interface CollectInput {
  program: AST.Program;
  env: TypeEnvironment;
}

export interface CollectOutput {
  env: TypeEnvironment;
  fnDecls: Map<string, AST.FnDecl>;
  errors: TypeCheckError[];
}

export function collectDeclarations(input: CollectInput): CollectOutput {
  const { program, env } = input;
  const fnDecls = new Map<string, AST.FnDecl>();
  const errors: TypeCheckError[] = [];

  const addError = (message: string, loc: AST.SourceLocation, hint?: string) => {
    errors.push(new TypeCheckError(message, loc, hint));
  };

  for (const stmt of program.body) {
    if (stmt.kind === "TypeDecl") {
      registerType(stmt, env, addError);
    } else if (stmt.kind === "InterfaceDecl") {
      registerInterface(stmt, env, addError);
    }
  }

  for (const stmt of program.body) {
    if (stmt.kind === "TypeDecl") {
      resolveEmbeddedTypes(stmt, env, addError);
    } else if (stmt.kind === "InterfaceDecl") {
      resolveEmbeddedInterfaces(stmt, env, addError);
    } else if (stmt.kind === "FnDecl") {
      collectFnDecl(stmt, env, fnDecls, addError);
    }
  }

  return { env, fnDecls, errors };
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
        // Check for reserved property names
        if (RESERVED_PROPERTY_NAMES.has(member.name)) {
          const err = TypeErrors.reservedPropertyName(member.name);
          addError(err.message, member.loc, err.hint);
        }
        properties.push({
          name: member.name,
          type: member.type ? astTypeToType(member.type) : Types.unknown,
          optional: member.optional,
          computed: member.computed,
          defaultValue: !!member.defaultValue,
          embedded: member.embedded,
        });
      } else if (member.kind === "MethodDecl") {
        // Check for reserved method names
        if (RESERVED_PROPERTY_NAMES.has(member.name)) {
          const err = TypeErrors.reservedPropertyName(member.name);
          addError(err.message, member.loc, err.hint);
        }
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
  } catch {
    const err = TypeErrors.typeAlreadyDefined(decl.name);
    addError(err.message, decl.loc, err.hint);
  }
}

function registerInterface(
  decl: AST.InterfaceDecl,
  env: TypeEnvironment,
  addError: (msg: string, loc: AST.SourceLocation, hint?: string) => void
): void {
  const methods: MethodType[] = [];
  for (const member of decl.body.members) {
    if (member.kind === "MethodDecl") {
      if (RESERVED_PROPERTY_NAMES.has(member.name)) {
        const err = TypeErrors.reservedPropertyName(member.name);
        addError(err.message, member.loc, err.hint);
      }
      methods.push({ name: member.name, type: methodToFunctionType(member) });
    }
  }
  const iface: InterfaceType = {
    kind: "interface",
    name: decl.name,
    methods,
    typeParams: decl.typeParams?.map(p => ({
      name: p.name,
      constraint: p.constraint ? astTypeToType(p.constraint) : undefined,
    })),
  };
  try {
    env.defineType(decl.name, iface);
  } catch {
    const err = TypeErrors.typeAlreadyDefined(decl.name);
    addError(err.message, decl.loc, err.hint);
  }
}

function resolveEmbeddedInterfaces(
  decl: AST.InterfaceDecl,
  env: TypeEnvironment,
  addError: (msg: string, loc: AST.SourceLocation, hint?: string) => void
): void {
  const iface = env.lookupType(decl.name);
  if (!iface || iface.kind !== "interface") return;

  const ownNames = new Set(iface.methods.map(m => m.name));
  const promotedSources = new Map<string, string[]>();

  for (const member of decl.body.members) {
    if (member.kind !== "EmbeddedInterfaceDecl") continue;
    const embedded = env.lookupType(member.name);
    if (!embedded) {
      addError(
        `Cannot embed '${member.name}': interface not found`,
        member.loc,
        `Make sure '${member.name}' is defined before '${decl.name}'`
      );
      continue;
    }
    if (embedded.kind !== "interface") {
      addError(
        `Cannot embed '${member.name}': not an interface`,
        member.loc,
        `Only interfaces can be embedded in an interface`
      );
      continue;
    }
    for (const method of embedded.methods) {
      if (ownNames.has(method.name)) continue;
      const sources = promotedSources.get(method.name) || [];
      sources.push(member.name);
      promotedSources.set(method.name, sources);
      if (sources.length === 1) {
        iface.methods.push({ ...method, promotedFrom: member.name });
      }
    }
  }

  for (const [name, sources] of promotedSources) {
    if (sources.length > 1) {
      addError(
        `Ambiguous access to '${name}' - exists in: ${sources.join(", ")}`,
        decl.loc,
        `Use explicit access or define own method to disambiguate`
      );
    }
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
  } catch {
    const err = TypeErrors.functionAlreadyDefined(decl.name);
    addError(err.message, decl.loc, err.hint);
  }
}

export class CollectDeclarationsPass implements Pass {
  name = "collect-declarations";
  run(ctx: PassContext): void {
    const result = collectDeclarations({ program: ctx.program, env: ctx.env });
    ctx.env = result.env;
    ctx.fnDecls = result.fnDecls;
    ctx.errors.push(...result.errors);
  }
}
