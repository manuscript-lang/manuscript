// Pass 1: Collect Declarations
// Gathers type and function declarations into the type environment
import * as AST from "../../parser/ast";
import type { Type, ObjectType, FunctionType, ContextBinding } from "../types";
import { Types, typeToString } from "../types";
import type { TypeEnvironment } from "../environment";
import { TypeCheckError } from "../errors";
import { TypeErrors } from "../../shared/errors";
import { astTypeToType, methodToFunctionType, fnDeclToType, typesEqual, paramsMatch, contextMatch } from "../type-utils";

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
    switch (stmt.kind) {
      case "TypeDecl":
        collectTypeDecl(stmt, env, addError);
        break;
      case "FnDecl":
        collectFnDecl(stmt, env, fnDecls, addError);
        break;
    }
  }

  return { env, fnDecls, errors };
}

function collectTypeDecl(
  decl: AST.TypeDecl,
  env: TypeEnvironment,
  addError: (msg: string, loc: AST.SourceLocation, hint?: string) => void
): void {
  const type: ObjectType = {
    kind: "object",
    name: decl.name,
    properties: [],
    methods: [],
    typeParams: decl.typeParams?.map(p => ({
      name: p.name,
      constraint: p.constraint ? astTypeToType(p.constraint) : undefined
    })),
    extends: decl.extends?.map(e => astTypeToType(e)),
  };

  if (decl.body && decl.body.members.length > 0) {
    for (const member of decl.body.members) {
      if (member.kind === "FieldDecl") {
        type.properties.push({
          name: member.name,
          type: member.type ? astTypeToType(member.type) : Types.any,
          optional: member.optional,
          computed: member.computed,
          defaultValue: !!member.defaultValue,
        });
      } else if (member.kind === "MethodDecl") {
        const methodType = methodToFunctionType(member);
        type.methods.push({ name: member.name, type: methodType });

        // Validate method override signature if this type extends another
        if (decl.extends) {
          validateMethodOverride(decl.name, member.name, methodType, decl.extends, member.loc, env, addError);
        }
      } else if (member.kind === "InitDecl") {
        // Store init as a function type for constructor validation
        type.init = {
          kind: "function",
          params: member.params.map(p => ({
            name: p.name,
            type: p.type ? astTypeToType(p.type) : Types.any,
            optional: p.optional || !!p.defaultValue,
            rest: p.rest,
          })),
          returnType: { kind: "object", name: decl.name, properties: type.properties, methods: type.methods },
          isGenerator: false,
          context: [],
        };
      }
    }
  }

  try {
    env.defineType(decl.name, type);
  } catch (e) {
    const err = TypeErrors.typeAlreadyDefined(decl.name);
    addError(err.message, decl.loc, err.hint);
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

function validateMethodOverride(
  typeName: string,
  methodName: string,
  methodType: FunctionType,
  extendsTypes: AST.TypeExpr[],
  loc: AST.SourceLocation,
  env: TypeEnvironment,
  addError: (msg: string, loc: AST.SourceLocation, hint?: string) => void
): void {
  for (const extendExpr of extendsTypes) {
    const baseTypeName = extendExpr.kind === "NamedType" ? extendExpr.name : null;
    if (!baseTypeName) continue;

    const baseType = env.lookupType(baseTypeName);
    if (!baseType || baseType.kind !== "object") continue;

    const baseMethod = baseType.methods.find(m => m.name === methodName);
    if (!baseMethod) continue;

    if (!paramsMatch(methodType.params, baseMethod.type.params)) {
      const err = TypeErrors.methodOverrideParamMismatch(methodName, typeName, baseTypeName);
      addError(err.message, loc, err.hint);
      return;
    }

    if (!typesEqual(methodType.returnType, baseMethod.type.returnType)) {
      const err = TypeErrors.methodOverrideReturnMismatch(
        methodName, typeName, baseTypeName,
        typeToString(baseMethod.type.returnType),
        typeToString(methodType.returnType)
      );
      addError(err.message, loc, err.hint);
      return;
    }

    if (!contextMatch(methodType.context, baseMethod.type.context)) {
      const err = TypeErrors.methodOverrideUsingMismatch(methodName, typeName, baseTypeName);
      addError(err.message, loc, err.hint);
      return;
    }
  }
}
