import type * as AST from "../../../parser/ast";
import type { ObjectType, PromiseType } from "../../types";
import { Types, typeToString } from "../../types";
import { TypeErrors } from "../../../shared/errors";
import { astTypeToType, fnDeclToType, isAssignable } from "../../type-utils";
import type { InferContext } from "./context";
import { error, recordType, setExpectedType } from "./context";
import { consumeSpawnsInExpr } from "./infer-spawn";
import { exprContainsEscapingLambda } from "../context-analysis";

export function checkFnDecl(ctx: InferContext, decl: AST.FnDecl): void {
  const fnType = fnDeclToType(decl);
  const fnEnv = ctx.env.child();

  if (fnType.typeParams?.length) {
    for (const tp of fnType.typeParams) fnEnv.bindTypeParam(tp.name, Types.typevar(tp.name));
  }

  for (const param of decl.params) {
    fnEnv.define(param.name, param.type ? astTypeToType(param.type) : Types.unknown);
  }

  if (decl.using) {
    validateUsingClause(ctx, decl.using);
    for (const binding of decl.using.bindings) {
      if (binding.name) fnEnv.define(binding.name, astTypeToType(binding.type));
    }
  }

  const savedEnv = ctx.env;
  const savedFn = ctx.currentFunction;
  const savedSpawns = ctx.unawaitedSpawns;
  ctx.unawaitedSpawns = new Map();
  ctx.env = fnEnv;
  ctx.currentFunction = fnType;

  const bodyEnv = ctx.env.child();
  ctx.env = bodyEnv;
  for (const stmt of decl.body.statements) ctx.checkStatement(ctx, stmt);

  const lastStmt = decl.body.statements[decl.body.statements.length - 1];
  if (lastStmt?.kind === "ExprStmt") {
    consumeSpawnsInExpr(ctx, lastStmt.expr);
    if (ctx.functionWithDepth > 0 && exprContainsEscapingLambda(lastStmt.expr, ctx.withContextVars, ctx.env, ctx.fnDecls, ctx.needsContextCache)) {
      error(ctx,
        `Cannot return closure that depends on context from 'with' block - it would outlive the context scope`,
        lastStmt.loc,
        `Context is cleaned up when 'with' block exits, but the returned closure needs it to execute`
      );
    }
    if (decl.returnType && fnType.returnType.kind !== "promise" && fnType.returnType.kind !== "unknown") {
      const implicitReturnType = (lastStmt.expr as AST.BaseNode).resolvedType ?? Types.unknown;
      const declaredReturnType = fnType.returnType;
      const resolved = implicitReturnType.kind === "promise" ? (implicitReturnType as PromiseType).resolveType : implicitReturnType;
      if (!isAssignable(resolved, declaredReturnType, ctx.env)) {
        const err = TypeErrors.typeMismatch(typeToString(declaredReturnType), typeToString(resolved));
        error(ctx, err.message, lastStmt.loc, err.hint);
      }
    }
  }

  for (const [name, loc] of ctx.unawaitedSpawns) {
    error(ctx, `spawn result '${name}' is never awaited (pass to race() or all() before function returns)`, loc);
  }

  ctx.unawaitedSpawns = savedSpawns;
  ctx.env = savedEnv;
  ctx.currentFunction = savedFn;
  recordType(ctx, decl, fnType);
}

function checkObjectTypeBody(
  ctx: InferContext,
  typeName: string,
  body: AST.TypeBody,
  objType: ObjectType,
  opts: { isExtern: boolean }
): void {
  if (!opts.isExtern) {
    for (const member of body.members) {
      if (member.kind === "MethodDecl" && !member.body) {
        const err = TypeErrors.methodRequiresBody(member.name, typeName);
        error(ctx, err.message, member.loc, err.hint);
      }
    }
  }

  const savedTypeName = ctx.currentTypeName;
  ctx.currentTypeName = typeName;

  const typeEnv = ctx.env.child();
  for (const prop of objType.properties) typeEnv.define(prop.name, prop.type, true);

  for (const member of body.members) {
    if (member.kind === "FieldDecl" && member.defaultValue) {
      const savedEnv = ctx.env;
      ctx.env = typeEnv;
      const declaredType = member.type ? astTypeToType(member.type) : undefined;
      if (declaredType) setExpectedType(member.defaultValue, declaredType);
      const valueType = ctx.inferExpr(ctx, member.defaultValue);
      if (!member.type && member.computed) {
        const prop = objType.properties.find(p => p.name === member.name);
        if (prop) prop.type = valueType;
      }
      ctx.env = savedEnv;
      if (member.type) {
        const expectedType = astTypeToType(member.type);
        if (!isAssignable(valueType, expectedType, ctx.env)) {
          const err = TypeErrors.typeMismatch(typeToString(expectedType), typeToString(valueType));
          error(ctx, err.message, member.loc, err.hint);
        }
      }
    }
  }

  for (const member of body.members) {
    if (member.kind === "MethodDecl" && member.body) checkMethodBody(ctx, member, objType);
  }

  ctx.currentTypeName = savedTypeName;
}

export function checkTypeDecl(ctx: InferContext, decl: AST.TypeDecl): void {
  const typeObj = ctx.env.lookupType(decl.name);
  if (!typeObj || typeObj.kind !== "object") return;
  checkObjectTypeBody(ctx, decl.name, decl.body, typeObj as ObjectType, {
    isExtern: !!decl.isExtern,
  });
}

function checkMethodBody(ctx: InferContext, method: AST.MethodDecl, typeObj: ObjectType): void {
  const typeFieldsEnv = ctx.env.child();
  for (const prop of typeObj.properties) typeFieldsEnv.define(prop.name, prop.type, true);
  for (const m of typeObj.methods) typeFieldsEnv.define(m.name, m.type);

  const methodEnv = typeFieldsEnv.child();
  for (const param of method.params) methodEnv.define(param.name, param.type ? astTypeToType(param.type) : Types.unknown);

  const methodType = typeObj.methods.find(m => m.name === method.name);
  const fnType = methodType?.type || Types.fn([], Types.unknown);

  const savedEnv = ctx.env;
  const savedFn = ctx.currentFunction;
  const savedSpawns = ctx.unawaitedSpawns;
  ctx.unawaitedSpawns = new Map();
  ctx.env = methodEnv;
  ctx.currentFunction = fnType;

  for (const stmt of method.body!.statements) ctx.checkStatement(ctx, stmt);

  const lastStmt = method.body!.statements[method.body!.statements.length - 1];
  if (lastStmt?.kind === "ExprStmt" && method.returnType) {
    const implicitReturnType = (lastStmt.expr as AST.BaseNode).resolvedType ?? Types.unknown;
    if (!isAssignable(implicitReturnType, fnType.returnType, ctx.env)) {
      const err = TypeErrors.typeMismatch(typeToString(fnType.returnType), typeToString(implicitReturnType));
      error(ctx, err.message, lastStmt.loc, err.hint);
    }
  }

  for (const [name, loc] of ctx.unawaitedSpawns) {
    error(ctx, `spawn result '${name}' is never awaited (pass to race() or all() before method returns)`, loc);
  }

  ctx.unawaitedSpawns = savedSpawns;
  ctx.env = savedEnv;
  ctx.currentFunction = savedFn;
}

function validateUsingClause(ctx: InferContext, using: AST.UsingClause): void {
  const closableType = ctx.env.lookupType("Closable") ?? null;
  if (!closableType) {
    error(ctx, "Closable interface not found (builtins required)", using.loc);
    return;
  }
  for (const binding of using.bindings) {
    const bindingType = astTypeToType(binding.type);
    if (!isAssignable(bindingType, closableType, ctx.env)) {
      const typeName = binding.type.kind === "NamedType" ? binding.type.name : "unknown";
      error(ctx,
        `Type '${typeName}' used in 'using' clause must satisfy Closable (must have close(): void)`,
        binding.loc,
        `Ensure the type has a close(): void method`
      );
    }
  }
}

export function checkTestDecl(ctx: InferContext, decl: AST.TestDecl): void {
  const testEnv = ctx.env.child();
  const savedEnv = ctx.env;
  ctx.env = testEnv;
  ctx.checkBlock(ctx, decl.body);
  ctx.env = savedEnv;
}
