// Statement Checking - Type checks all statement kinds
import * as AST from "../../../parser/ast";
import type { Type, FunctionType, ContextBinding } from "../../types";
import { Types, typeToString, isNullable, nonNull } from "../../types";
import { TypeErrors } from "../../../shared/errors";
import { astTypeToType, fnDeclToType, isAssignable, getIterableElementType, extendsType } from "../../type-utils";
import type { InferContext } from "./context";
import { error, warning, recordType } from "./context";
import { checkPattern, bindPattern } from "./check-pattern";
import { inferExpr, setCheckBlockFn, consumeSpawnsInExpr, exprContainsSpawn, transferSpawnTracking } from "./infer-expr";
import { exprContainsEscapingLambda } from "../context-analysis";

export function checkStatement(ctx: InferContext, stmt: AST.Statement): void {
  switch (stmt.kind) {
    case "LetStmt":
      checkLetStmt(ctx, stmt);
      break;
    case "VarStmt":
      checkVarStmt(ctx, stmt);
      break;
    case "AssignStmt":
      checkAssignStmt(ctx, stmt);
      break;
    case "IfStmt":
      checkIfStmt(ctx, stmt);
      break;
    case "ForStmt":
      checkForStmt(ctx, stmt);
      break;
    case "MatchStmt":
      checkMatchStmt(ctx, stmt);
      break;
    case "ReturnStmt":
      checkReturnStmt(ctx, stmt);
      break;
    case "YieldStmt":
      checkYieldStmt(ctx, stmt);
      break;
    case "BreakStmt":
    case "ContinueStmt":
      if (!ctx.inLoop) {
        const err = stmt.kind === "BreakStmt" ? TypeErrors.breakOutsideLoop() : TypeErrors.continueOutsideLoop();
        error(ctx, err.message, stmt.loc, err.hint);
      }
      break;
    case "DeferStmt":
      checkStatement(ctx, stmt.body);
      break;
    case "TryStmt":
      checkTryStmt(ctx, stmt);
      break;
    case "ThrowStmt":
      inferExpr(ctx, stmt.value);
      break;
    case "WithStmt":
      checkWithStmt(ctx, stmt);
      break;
    case "ExprStmt":
      if (stmt.expr.kind === "SpawnExpr") {
        error(ctx,
          "spawn result must be used (await, pass to all(), or assign to variable)",
          stmt.expr.loc
        );
      }
      inferExpr(ctx, stmt.expr);
      break;
    case "FnDecl":
      checkFnDecl(ctx, stmt);
      break;
    case "ExternFnDecl":
      break;
    case "TypeDecl":
      break;
    case "TestDecl":
      checkTestDecl(ctx, stmt);
      break;
    case "ImportDecl":
      break;
    case "KeywordDecl":
      break;
  }
}

function checkLetStmt(ctx: InferContext, stmt: AST.LetStmt): void {
  const valueType = inferExpr(ctx, stmt.value);
  const declaredType = stmt.type ? astTypeToType(stmt.type) : valueType;

  if (stmt.type && !isAssignable(valueType, declaredType, ctx.env)) {
    const err = TypeErrors.typeMismatch(typeToString(declaredType), typeToString(valueType));
    error(ctx, err.message, stmt.loc, err.hint);
  }

  if (stmt.pattern.kind === "IdentifierPattern") {
    const containsSpawn = exprContainsSpawn(ctx, stmt.value);
    const isConsumerResult = stmt.value.kind === "CallExpr" &&
      stmt.value.callee.kind === "Identifier" &&
      (stmt.value.callee.name === "race" || stmt.value.callee.name === "all");

    if (containsSpawn && !isConsumerResult) {
      ctx.unawaitedSpawns.set(stmt.pattern.name, stmt.loc);
      transferSpawnTracking(ctx, stmt.value);
    }
  }

  bindPattern(ctx, stmt.pattern, declaredType, false);
}

function checkVarStmt(ctx: InferContext, stmt: AST.VarStmt): void {
  const valueType = inferExpr(ctx, stmt.value);
  const declaredType = stmt.type ? astTypeToType(stmt.type) : valueType;

  if (stmt.type && !isAssignable(valueType, declaredType, ctx.env)) {
    const err = TypeErrors.typeMismatch(typeToString(declaredType), typeToString(valueType));
    error(ctx, err.message, stmt.loc, err.hint);
  }

  try {
    ctx.env.define(stmt.name, declaredType, true);
  } catch (e) {
    const err = TypeErrors.variableAlreadyDefined(stmt.name);
    error(ctx, err.message, stmt.loc, err.hint);
  }
}

function checkAssignStmt(ctx: InferContext, stmt: AST.AssignStmt): void {
  const targetType = inferExpr(ctx, stmt.target);
  const valueType = inferExpr(ctx, stmt.value);

  if (stmt.target.kind === "Identifier") {
    const symbol = ctx.env.lookup(stmt.target.name);
    if (symbol && !symbol.mutable) {
      const err = TypeErrors.cannotAssignToImmutable(stmt.target.name);
      error(ctx, err.message, stmt.loc, err.hint);
    }
  }

  if (!isAssignable(valueType, targetType, ctx.env)) {
    const err = TypeErrors.typeMismatch(typeToString(targetType), typeToString(valueType));
    error(ctx, err.message, stmt.loc, err.hint);
  }
}

function checkIfStmt(ctx: InferContext, stmt: AST.IfStmt): void {
  inferExpr(ctx, stmt.condition);

  const narrowedEnv = ctx.env.child();
  applyTypeNarrowing(ctx, stmt.condition, narrowedEnv, true);

  if (stmt.then.kind === "Block") {
    const savedEnv = ctx.env;
    ctx.env = narrowedEnv;
    for (const s of stmt.then.statements) {
      checkStatement(ctx, s);
    }
    ctx.env = savedEnv;
  } else {
    const savedEnv = ctx.env;
    ctx.env = narrowedEnv;
    checkStatement(ctx, stmt.then);
    ctx.env = savedEnv;
  }

  for (const elif of stmt.elseIfs) {
    inferExpr(ctx, elif.condition);
    const elifEnv = ctx.env.child();
    applyTypeNarrowing(ctx, elif.condition, elifEnv, true);
    const savedEnv = ctx.env;
    ctx.env = elifEnv;
    for (const s of elif.body.statements) {
      checkStatement(ctx, s);
    }
    ctx.env = savedEnv;
  }

  if (stmt.else) {
    const elseEnv = ctx.env.child();
    applyTypeNarrowing(ctx, stmt.condition, elseEnv, false);
    const savedEnv = ctx.env;
    ctx.env = elseEnv;
    for (const s of stmt.else.statements) {
      checkStatement(ctx, s);
    }
    ctx.env = savedEnv;
  }

  if (stmt.pattern && stmt.elseReturn) {
    inferExpr(ctx, stmt.elseReturn);
  }
}

function applyTypeNarrowing(ctx: InferContext, condition: AST.Expr, env: any, truthyBranch: boolean): void {
  if (condition.kind === "BinaryExpr" && condition.op === "is") {
    if (condition.left.kind === "Identifier" && condition.right.kind === "Identifier") {
      const varName = condition.left.name;
      const typeName = condition.right.name;
      const symbol = ctx.env.lookup(varName);
      if (symbol) {
        if (truthyBranch) {
          const narrowedType = ctx.env.lookupType(typeName) ?? Types.ref(typeName);
          env.define(varName, narrowedType, symbol.mutable);
        } else {
          if (symbol.type.kind === "union") {
            const remaining = symbol.type.types.filter((t: Type) => {
              if (t.kind === "ref") return t.name !== typeName;
              if (t.kind === "object") return (t as any).name !== typeName;
              return typeToString(t) !== typeName;
            });
            if (remaining.length === 1) {
              env.define(varName, remaining[0]!, symbol.mutable);
            } else if (remaining.length > 1) {
              env.define(varName, Types.union(...remaining), symbol.mutable);
            }
          }
        }
      }
    }
  } else if (condition.kind === "BinaryExpr" &&
             (condition.op === "!=" || condition.op === "==") &&
             condition.left.kind === "Identifier" &&
             condition.right.kind === "Literal" && condition.right.value === null) {
    const varName = condition.left.name;
    const symbol = ctx.env.lookup(varName);
    if (symbol && isNullable(symbol.type)) {
      const isNotNull = (condition.op === "!=" && truthyBranch) || (condition.op === "==" && !truthyBranch);
      if (isNotNull) {
        env.define(varName, nonNull(symbol.type), symbol.mutable);
      }
    }
  } else if (condition.kind === "UnaryExpr" && (condition.op === "not" || condition.op === "!")) {
    applyTypeNarrowing(ctx, condition.operand, env, !truthyBranch);
  }
}

function checkForStmt(ctx: InferContext, stmt: AST.ForStmt): void {
  const prevInLoop = ctx.inLoop;
  ctx.inLoop = true;

  const bodyEnv = ctx.env.child();

  if (stmt.pattern && stmt.iterable) {
    const iterableType = inferExpr(ctx, stmt.iterable);
    const elementType = getIterableElementType(iterableType);

    const savedEnv = ctx.env;
    ctx.env = bodyEnv;
    bindPattern(ctx, stmt.pattern, elementType, false);
    ctx.env = savedEnv;
  }

  const savedEnv = ctx.env;
  ctx.env = bodyEnv;
  checkBlock(ctx, stmt.body);
  ctx.env = savedEnv;

  ctx.inLoop = prevInLoop;
}

function checkMatchStmt(ctx: InferContext, stmt: AST.MatchStmt): void {
  const valueType = inferExpr(ctx, stmt.value);

  for (const arm of stmt.arms) {
    const armEnv = ctx.env.child();
    const savedEnv = ctx.env;
    ctx.env = armEnv;

    checkPattern(ctx, arm.pattern, valueType);

    if (arm.guard) {
      inferExpr(ctx, arm.guard);
    }

    if (arm.body.kind === "Block") {
      checkBlock(ctx, arm.body as AST.Block);
    } else {
      inferExpr(ctx, arm.body as AST.Expr);
    }

    ctx.env = savedEnv;
  }

  checkMatchExhaustiveness(ctx, valueType, stmt.arms, stmt.loc);
}

function checkMatchExhaustiveness(ctx: InferContext, valueType: Type, arms: AST.MatchArm[], loc: AST.SourceLocation): void {
  const hasCatchAll = arms.some(arm =>
    arm.pattern.kind === "WildcardPattern" ||
    (arm.pattern.kind === "IdentifierPattern" && !arm.guard)
  );
  if (hasCatchAll) return;

  if (valueType.kind === "union") {
    const coveredTypes = new Set<string>();

    for (const arm of arms) {
      if (arm.guard) continue;

      if (arm.pattern.kind === "TypePattern") {
        const typeName = arm.pattern.type.kind === "NamedType"
          ? arm.pattern.type.name
          : typeToString(astTypeToType(arm.pattern.type));
        coveredTypes.add(typeName);
      } else if (arm.pattern.kind === "LiteralPattern") {
        if (arm.pattern.value === null) {
          coveredTypes.add("null");
        }
      }
    }

    const uncovered: string[] = [];
    for (const t of valueType.types) {
      const typeName = t.kind === "ref" ? t.name :
                      t.kind === "object" && (t as any).name ? (t as any).name :
                      typeToString(t);
      if (!coveredTypes.has(typeName)) {
        uncovered.push(typeName);
      }
    }

    if (uncovered.length > 0) {
      warning(ctx, `Match may not be exhaustive. Missing cases: ${uncovered.join(", ")}`);
    }
  }

  if (valueType.kind === "optional") {
    const hasNullCase = arms.some(arm =>
      arm.pattern.kind === "LiteralPattern" && arm.pattern.value === null
    );
    const hasValueCase = arms.some(arm =>
      arm.pattern.kind === "TypePattern" ||
      arm.pattern.kind === "IdentifierPattern"
    );

    if (!hasNullCase || !hasValueCase) {
      warning(ctx, `Match on optional type may not be exhaustive`);
    }
  }

  if (valueType.kind === "bool") {
    const hasTrue = arms.some(arm =>
      arm.pattern.kind === "LiteralPattern" && arm.pattern.value === true
    );
    const hasFalse = arms.some(arm =>
      arm.pattern.kind === "LiteralPattern" && arm.pattern.value === false
    );

    if (!hasTrue || !hasFalse) {
      warning(ctx, `Match on bool may not be exhaustive`);
    }
  }
}

function checkReturnStmt(ctx: InferContext, stmt: AST.ReturnStmt): void {
  if (!ctx.currentFunction) {
    const err = TypeErrors.returnOutsideFunction();
    error(ctx, err.message, stmt.loc, err.hint);
    return;
  }

  if (stmt.value) {
    const returnType = inferExpr(ctx, stmt.value);
    if (!isAssignable(returnType, ctx.currentFunction.returnType, ctx.env)) {
      const err = TypeErrors.typeMismatch(typeToString(ctx.currentFunction.returnType), typeToString(returnType));
      error(ctx, err.message, stmt.loc, err.hint);
    }
    consumeSpawnsInExpr(ctx, stmt.value);

    if (ctx.functionWithDepth > 0 && exprContainsEscapingLambda(stmt.value, ctx.withContextVars, ctx.env, ctx.fnDecls, ctx.needsContextCache)) {
      error(ctx,
        `Cannot return closure that depends on context from 'with' block - it would outlive the context scope`,
        stmt.loc,
        `Context is cleaned up when 'with' block exits, but the returned closure needs it to execute`
      );
    }
  } else if (ctx.currentFunction.returnType.kind !== "void") {
    const err = TypeErrors.returnMissingValue(typeToString(ctx.currentFunction.returnType));
    error(ctx, err.message, stmt.loc, err.hint);
  }
}

function checkYieldStmt(ctx: InferContext, stmt: AST.YieldStmt): void {
  if (!ctx.currentFunction || !ctx.currentFunction.isGenerator) {
    const err = TypeErrors.yieldOutsideGenerator();
    error(ctx, err.message, stmt.loc, err.hint);
    return;
  }

  inferExpr(ctx, stmt.value);
}

function checkTryStmt(ctx: InferContext, stmt: AST.TryStmt): void {
  checkBlock(ctx, stmt.body);

  if (stmt.catch) {
    const catchEnv = ctx.env.child();
    catchEnv.define(stmt.catch.name, Types.ref("Error"));
    const savedEnv = ctx.env;
    ctx.env = catchEnv;
    checkBlock(ctx, stmt.catch.body);
    ctx.env = savedEnv;
  }
}

function checkWithStmt(ctx: InferContext, stmt: AST.WithStmt): void {
  const bindings: ContextBinding[] = [];
  const isFunctionLevel = ctx.currentFunction !== null;

  const savedWithContextVars = new Set(ctx.withContextVars);

  for (const ctxBinding of stmt.contexts) {
    ctx.insideWithContext = true;
    const ctxType = inferExpr(ctx, ctxBinding.expr);
    ctx.insideWithContext = false;

    if (ctxBinding.name) {
      bindings.push({ name: ctxBinding.name, type: ctxType });
      if (isFunctionLevel) {
        ctx.withContextVars.add(ctxBinding.name);
      }
    }
  }

  const withEnv = ctx.env.withContext(bindings);
  const savedEnv = ctx.env;
  ctx.env = withEnv;

  if (isFunctionLevel) {
    ctx.functionWithDepth++;
  }

  checkBlock(ctx, stmt.body);

  if (isFunctionLevel) {
    const lastStmt = stmt.body.statements[stmt.body.statements.length - 1];
    if (lastStmt?.kind === "ExprStmt" && exprContainsEscapingLambda(lastStmt.expr, ctx.withContextVars, ctx.env, ctx.fnDecls, ctx.needsContextCache)) {
      error(ctx,
        `Cannot return closure that depends on context from 'with' block - it would outlive the context scope`,
        lastStmt.loc,
        `Context is cleaned up when 'with' block exits, but the returned closure needs it to execute`
      );
    }
  }

  if (isFunctionLevel) {
    ctx.functionWithDepth--;
  }

  ctx.env = savedEnv;
  ctx.withContextVars = savedWithContextVars;
}

function checkFnDecl(ctx: InferContext, decl: AST.FnDecl): void {
  const fnType = fnDeclToType(decl);
  const fnEnv = ctx.env.child();

  for (const param of decl.params) {
    const paramType = param.type ? astTypeToType(param.type) : Types.any;
    fnEnv.define(param.name, paramType);
  }

  if (decl.using) {
    validateUsingClause(ctx, decl.using);

    for (const binding of decl.using.bindings) {
      const bindingType = astTypeToType(binding.type);
      if (binding.name) {
        fnEnv.define(binding.name, bindingType);
      }
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
  for (const stmt of decl.body.statements) {
    checkStatement(ctx, stmt);
  }

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

    if (decl.returnType && fnType.returnType.kind !== "promise" && fnType.returnType.kind !== "any") {
      let implicitReturnType = inferExpr(ctx, lastStmt.expr);
      const declaredReturnType = fnType.returnType;
      if (implicitReturnType.kind === "promise") {
        implicitReturnType = (implicitReturnType as any).resolveType;
      }
      if (!isAssignable(implicitReturnType, declaredReturnType, ctx.env)) {
        const err = TypeErrors.typeMismatch(typeToString(declaredReturnType), typeToString(implicitReturnType));
        error(ctx, err.message, lastStmt.loc, err.hint);
      }
    }
  }

  for (const [name, loc] of ctx.unawaitedSpawns) {
    error(ctx,
      `spawn result '${name}' is never awaited (pass to race() or all() before function returns)`,
      loc
    );
  }

  ctx.unawaitedSpawns = savedSpawns;
  ctx.env = savedEnv;
  ctx.currentFunction = savedFn;

  recordType(ctx, decl, fnType);
}

function validateUsingClause(ctx: InferContext, using: AST.UsingClause): void {
  for (const binding of using.bindings) {
    const bindingType = astTypeToType(binding.type);
    if (!extendsType(bindingType, "Context", ctx.env)) {
      const typeName = binding.type.kind === "NamedType" ? binding.type.name : "unknown";
      error(ctx,
        `Type '${typeName}' used in 'using' clause must extend Context`,
        binding.loc,
        `Add 'extends Context' to the type definition`
      );
    }
  }
}

function checkTestDecl(ctx: InferContext, decl: AST.TestDecl): void {
  const testEnv = ctx.env.child();
  const savedEnv = ctx.env;
  ctx.env = testEnv;
  checkBlock(ctx, decl.body);
  ctx.env = savedEnv;
}

export function checkBlock(ctx: InferContext, block: AST.Block): void {
  const blockEnv = ctx.env.child();
  const savedEnv = ctx.env;
  ctx.env = blockEnv;

  for (const stmt of block.statements) {
    checkStatement(ctx, stmt);
  }

  ctx.env = savedEnv;
}

// Initialize the circular dependency between infer-expr and check-stmt
setCheckBlockFn(checkBlock);
