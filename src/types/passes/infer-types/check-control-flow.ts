import * as AST from "../../../parser/ast";
import type { Type, ObjectType, ContextBinding } from "../../types";
import { Types, typeToString, isNullable, nonNull } from "../../types";
import { TypeErrors } from "../../../shared/errors";
import { astTypeToType, isAssignable, getIterableElementType, isIterable } from "../../type-utils";
import type { InferContext } from "./context";
import { error, warning, setExpectedType } from "./context";
import { checkPattern, bindPattern } from "./check-pattern";
import { consumeSpawnsInExpr } from "./infer-spawn";
import { exprContainsEscapingLambda } from "../context-analysis";

export function checkIfStmt(ctx: InferContext, stmt: AST.IfStmt): void {
  ctx.inferExpr(ctx, stmt.condition);

  const narrowedEnv = ctx.env.child();
  applyTypeNarrowing(ctx, stmt.condition, narrowedEnv, true);

  if (stmt.then.kind === "Block") {
    const savedEnv = ctx.env;
    ctx.env = narrowedEnv;
    for (const s of stmt.then.statements) ctx.checkStatement(ctx, s);
    ctx.env = savedEnv;
  } else {
    const savedEnv = ctx.env;
    ctx.env = narrowedEnv;
    ctx.checkStatement(ctx, stmt.then);
    ctx.env = savedEnv;
  }

  for (const elif of stmt.elseIfs) {
    ctx.inferExpr(ctx, elif.condition);
    const elifEnv = ctx.env.child();
    applyTypeNarrowing(ctx, elif.condition, elifEnv, true);
    const savedEnv = ctx.env;
    ctx.env = elifEnv;
    for (const s of elif.body.statements) ctx.checkStatement(ctx, s);
    ctx.env = savedEnv;
  }

  if (stmt.else) {
    const elseEnv = ctx.env.child();
    applyTypeNarrowing(ctx, stmt.condition, elseEnv, false);
    const savedEnv = ctx.env;
    ctx.env = elseEnv;
    for (const s of stmt.else.statements) ctx.checkStatement(ctx, s);
    ctx.env = savedEnv;
  }

  if (stmt.pattern && stmt.elseReturn) ctx.inferExpr(ctx, stmt.elseReturn);
}

function applyTypeNarrowing(ctx: InferContext, condition: AST.Expr, env: any, truthyBranch: boolean): void {
  if (condition.kind === "BinaryExpr" && condition.op === "is") {
    if (condition.left.kind === "Identifier" && condition.right.kind === "Identifier") {
      const varName = condition.left.name;
      const typeName = condition.right.name;
      const symbol = ctx.env.lookup(varName);
      if (symbol) {
        if (truthyBranch) {
          env.define(varName, ctx.env.lookupType(typeName) ?? Types.ref(typeName), symbol.mutable);
        } else if (symbol.type.kind === "union") {
          const remaining = symbol.type.types.filter((t: Type) => {
            if (t.kind === "ref") return t.name !== typeName;
            if (t.kind === "object") return (t as any).name !== typeName;
            return typeToString(t) !== typeName;
          });
          if (remaining.length === 1) env.define(varName, remaining[0]!, symbol.mutable);
          else if (remaining.length > 1) env.define(varName, Types.union(...remaining), symbol.mutable);
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
      if (isNotNull) env.define(varName, nonNull(symbol.type), symbol.mutable);
    }
  } else if (condition.kind === "BinaryExpr" &&
             (condition.op === "==" || condition.op === "!=") &&
             condition.left.kind === "Identifier" &&
             condition.right.kind === "Literal") {
    const varName = condition.left.name;
    const symbol = ctx.env.lookup(varName);
    if (symbol) {
      const isEqual = (condition.op === "==" && truthyBranch) || (condition.op === "!=" && !truthyBranch);
      if (isEqual) {
        env.define(varName, Types.literal(condition.right.value as string | number | boolean), symbol.mutable);
      } else if (symbol.type.kind === "union") {
        const literalStr = JSON.stringify(condition.right.value);
        const remaining = symbol.type.types.filter((t: Type) => {
          if (t.kind === "literal") return JSON.stringify(t.value) !== literalStr;
          return true;
        });
        if (remaining.length === 1) env.define(varName, remaining[0]!, symbol.mutable);
        else if (remaining.length > 1) env.define(varName, Types.union(...remaining), symbol.mutable);
      }
    }
  } else if (condition.kind === "BinaryExpr" &&
             (condition.op === "==" || condition.op === "!=") &&
             condition.left.kind === "MemberExpr" &&
             condition.right.kind === "Literal") {
    const memberExpr = condition.left as AST.MemberExpr;
    if (memberExpr.object.kind === "Identifier") {
      const varName = memberExpr.object.name;
      const propName = memberExpr.property;
      const symbol = ctx.env.lookup(varName);

      if (symbol && symbol.type.kind === "union") {
        const isEqual = (condition.op === "==" && truthyBranch) || (condition.op === "!=" && !truthyBranch);
        const literalValue = condition.right.value;
        const matching: Type[] = [];
        const nonMatching: Type[] = [];

        for (const t of symbol.type.types) {
          const resolved = t.kind === "ref" ? ctx.env.resolveType(t) : t;
          if (resolved.kind === "object") {
            const prop = (resolved as ObjectType).properties.find(p => p.name === propName);
            if (prop && prop.type.kind === "literal" && prop.type.value === literalValue) matching.push(t);
            else nonMatching.push(t);
          } else nonMatching.push(t);
        }

        if (isEqual && matching.length > 0) {
          if (matching.length === 1) env.define(varName, matching[0]!, symbol.mutable);
          else env.define(varName, Types.union(...matching), symbol.mutable);
        } else if (!isEqual && nonMatching.length > 0) {
          if (nonMatching.length === 1) env.define(varName, nonMatching[0]!, symbol.mutable);
          else env.define(varName, Types.union(...nonMatching), symbol.mutable);
        }
      }
    }
  } else if (condition.kind === "BinaryExpr" && condition.op === "and") {
    applyTypeNarrowing(ctx, condition.left, env, truthyBranch);
    applyTypeNarrowing(ctx, condition.right, env, truthyBranch);
  } else if (condition.kind === "BinaryExpr" &&
             (condition.op === "==" || condition.op === "!=") &&
             condition.left.kind === "CallExpr") {
    const call = condition.left as AST.CallExpr;
    const callee = call.callee;
    const typeStr = condition.right.kind === "Literal" && typeof condition.right.value === "string" ? condition.right.value : null;
    if (callee.kind === "Identifier" && callee.name === "typeof" && call.args.length === 1 && typeStr) {
      const raw = call.args[0];
      const argExpr: AST.Expr | undefined = raw && "value" in raw ? (raw as { value: AST.Expr }).value : (raw as AST.Expr);
      if (argExpr?.kind === "Identifier") {
        const varName = (argExpr as AST.Identifier).name;
        const symbol = ctx.env.lookup(varName);
        if (symbol) {
          let narrowedType: Type | null = null;
          if (typeStr === "number") narrowedType = Types.number;
          else if (typeStr === "string") narrowedType = Types.string;
          else if (typeStr === "boolean") narrowedType = Types.bool;
          else if (typeStr === "null") narrowedType = Types.null;
          if (narrowedType) {
            const isEqual = (condition.op === "==" && truthyBranch) || (condition.op === "!=" && !truthyBranch);
            if (isEqual) env.define(varName, narrowedType, symbol.mutable);
          }
        }
      }
    }
  } else if (condition.kind === "UnaryExpr" && (condition.op === "not" || condition.op === "!")) {
    applyTypeNarrowing(ctx, condition.operand, env, !truthyBranch);
  }
}

export function checkForStmt(ctx: InferContext, stmt: AST.ForStmt): void {
  const prevInLoop = ctx.inLoop;
  ctx.inLoop = true;

  const bodyEnv = ctx.env.child();
  if (stmt.pattern && stmt.iterable) {
    const iterableType = ctx.inferExpr(ctx, stmt.iterable);
    if (!isIterable(iterableType)) {
      const err = TypeErrors.nonIterableForLoop(typeToString(iterableType));
      error(ctx, err.message, stmt.iterable.loc, err.hint);
    }
    const elementType = getIterableElementType(iterableType);
    const savedEnv = ctx.env;
    ctx.env = bodyEnv;
    bindPattern(ctx, stmt.pattern, elementType, false);
    ctx.env = savedEnv;
  }

  const savedEnv = ctx.env;
  ctx.env = bodyEnv;
  ctx.checkBlock(ctx, stmt.body);
  ctx.env = savedEnv;
  ctx.inLoop = prevInLoop;
}

export function checkMatchStmt(ctx: InferContext, stmt: AST.MatchStmt): void {
  const valueType = ctx.inferExpr(ctx, stmt.value);

  for (const arm of stmt.arms) {
    const armEnv = ctx.env.child();
    const savedEnv = ctx.env;
    ctx.env = armEnv;
    checkPattern(ctx, arm.pattern, valueType);
    if (arm.guard) {
      const guardType = ctx.inferExpr(ctx, arm.guard);
      if (guardType.kind !== "bool") {
        const err = TypeErrors.guardMustBeBool(typeToString(guardType));
        error(ctx, err.message, arm.guard.loc, err.hint);
      }
    }
    if (arm.body.kind === "Block") ctx.checkBlock(ctx, arm.body as AST.Block);
    else ctx.inferExpr(ctx, arm.body as AST.Expr);
    ctx.env = savedEnv;
  }

  checkMatchExhaustiveness(ctx, valueType, stmt.arms, stmt.loc);
}

function checkMatchExhaustiveness(ctx: InferContext, valueType: Type, arms: AST.MatchArm[], loc: AST.SourceLocation): void {
  const hasCatchAll = arms.some(arm =>
    arm.pattern.kind === "WildcardPattern" || (arm.pattern.kind === "IdentifierPattern" && !arm.guard));
  if (hasCatchAll) return;

  if (valueType.kind === "union") {
    const coveredTypes = new Set<string>();
    for (const arm of arms) {
      if (arm.guard) continue;
      if (arm.pattern.kind === "TypePattern") {
        coveredTypes.add(arm.pattern.type.kind === "NamedType"
          ? arm.pattern.type.name : typeToString(astTypeToType(arm.pattern.type)));
      } else if (arm.pattern.kind === "LiteralPattern" && arm.pattern.value === null) {
        coveredTypes.add("null");
      }
    }
    const uncovered: string[] = [];
    for (const t of valueType.types) {
      const typeName = t.kind === "ref" ? t.name :
        t.kind === "object" && (t as any).name ? (t as any).name : typeToString(t);
      if (!coveredTypes.has(typeName)) uncovered.push(typeName);
    }
    if (uncovered.length > 0) {
      const err = TypeErrors.matchNotExhaustive(uncovered);
      error(ctx, err.message, loc, err.hint);
    }
  }

  if (valueType.kind === "optional") {
    const hasNullCase = arms.some(arm => arm.pattern.kind === "LiteralPattern" && arm.pattern.value === null);
    const hasValueCase = arms.some(arm => arm.pattern.kind === "TypePattern" || arm.pattern.kind === "IdentifierPattern");
    const missing: string[] = [];
    if (!hasNullCase) missing.push("null");
    if (!hasValueCase) missing.push(typeToString(valueType.inner));
    if (missing.length > 0) {
      const err = TypeErrors.matchNotExhaustive(missing);
      error(ctx, err.message, loc, err.hint);
    }
  }

  if (valueType.kind === "bool") {
    const hasTrue = arms.some(arm => arm.pattern.kind === "LiteralPattern" && arm.pattern.value === true);
    const hasFalse = arms.some(arm => arm.pattern.kind === "LiteralPattern" && arm.pattern.value === false);
    const missing: string[] = [];
    if (!hasTrue) missing.push("true");
    if (!hasFalse) missing.push("false");
    if (missing.length > 0) {
      const err = TypeErrors.matchNotExhaustive(missing);
      error(ctx, err.message, loc, err.hint);
    }
  }
}

export function checkReturnStmt(ctx: InferContext, stmt: AST.ReturnStmt): void {
  if (!ctx.currentFunction) {
    const err = TypeErrors.returnOutsideFunction();
    error(ctx, err.message, stmt.loc, err.hint);
    return;
  }

  if (stmt.value) {
    setExpectedType(stmt.value, ctx.currentFunction.returnType);
    const returnType = ctx.inferExpr(ctx, stmt.value);
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

export function checkYieldStmt(ctx: InferContext, stmt: AST.YieldStmt): void {
  if (!ctx.currentFunction || !ctx.currentFunction.isGenerator) {
    const err = TypeErrors.yieldOutsideGenerator();
    error(ctx, err.message, stmt.loc, err.hint);
    return;
  }
  setExpectedType(stmt.value, ctx.currentFunction.returnType);
  ctx.inferExpr(ctx, stmt.value);
}

export function checkTryStmt(ctx: InferContext, stmt: AST.TryStmt): void {
  ctx.checkBlock(ctx, stmt.body);
  if (stmt.catch) {
    const catchEnv = ctx.env.child();
    catchEnv.define(stmt.catch.name, Types.ref("Error"));
    const savedEnv = ctx.env;
    ctx.env = catchEnv;
    ctx.checkBlock(ctx, stmt.catch.body);
    ctx.env = savedEnv;
  }
}

export function checkWithStmt(ctx: InferContext, stmt: AST.WithStmt): void {
  const bindings: ContextBinding[] = [];
  const isFunctionLevel = ctx.currentFunction !== null;
  const savedWithContextVars = new Set(ctx.withContextVars);

  const closableType = ctx.env.lookupType("Closable") ?? null;
  if (!closableType) {
    error(ctx, "Closable interface not found (stdlib required)", stmt.loc);
    return;
  }

  for (const ctxBinding of stmt.contexts) {
    const ctxType = ctx.inferExpr(ctx, ctxBinding.expr);
    if (!isAssignable(ctxType, closableType, ctx.env)) {
      error(ctx,
        `Expression in 'with' must satisfy Closable (must have close(): void)`,
        ctxBinding.expr.loc,
        `Type '${typeToString(ctxType)}' does not have close(): void`
      );
    }
    if (ctxBinding.name) {
      bindings.push({ name: ctxBinding.name, type: ctxType });
      if (isFunctionLevel) ctx.withContextVars.add(ctxBinding.name);
    }
  }

  const withEnv = ctx.env.withContext(bindings);
  const savedEnv = ctx.env;
  ctx.env = withEnv;
  ctx.withBlockDepth++;
  ctx.insideWithContext = true;

  let savedContextDependent: Set<string> | null = null;
  if (isFunctionLevel) {
    ctx.functionWithDepth++;
    savedContextDependent = ctx.contextDependentSpawnsInWith;
    ctx.contextDependentSpawnsInWith = new Set();
  }

  ctx.checkBlock(ctx, stmt.body);

  if (isFunctionLevel) {
    const lastStmt = stmt.body.statements[stmt.body.statements.length - 1];
    if (lastStmt?.kind === "ExprStmt" && exprContainsEscapingLambda(lastStmt.expr, ctx.withContextVars, ctx.env, ctx.fnDecls, ctx.needsContextCache)) {
      error(ctx,
        `Cannot return closure that depends on context from 'with' block - it would outlive the context scope`,
        lastStmt.loc,
        `Context is cleaned up when 'with' block exits, but the returned closure needs it to execute`
      );
    }
    for (const name of ctx.contextDependentSpawnsInWith!) {
      const loc = ctx.unawaitedSpawns.get(name);
      if (loc) {
        error(ctx,
          `Cannot use 'spawn' inside function-level 'with' block - spawned task may outlive context scope`,
          loc,
          `Add e.g. \`let _ = race([${name}])\` or \`all_settled([${name}])\` before the block ends, or spawn a task that does not use the context`
        );
        ctx.unawaitedSpawns.delete(name);
      }
    }
    ctx.contextDependentSpawnsInWith = savedContextDependent;
    ctx.functionWithDepth--;
  }

  ctx.env = savedEnv;
  ctx.withBlockDepth--;
  ctx.insideWithContext = ctx.withBlockDepth > 0;
  ctx.withContextVars = savedWithContextVars;
}
