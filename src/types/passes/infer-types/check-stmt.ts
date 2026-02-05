// Statement Checking - Type checks all statement kinds
import * as AST from "../../../parser/ast";
import type { Type, FunctionType, ContextBinding, ObjectType } from "../../types";
import { Types, typeToString, isNullable, nonNull } from "../../types";
import { TypeErrors } from "../../../shared/errors";
import { astTypeToType, fnDeclToType, isAssignable, getIterableElementType, isIterable, typeIsContext } from "../../type-utils";
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
      checkTypeDecl(ctx, stmt);
      break;
    case "TestDecl":
      checkTestDecl(ctx, stmt);
      break;
    case "ImportDecl":
      break;
    case "KeywordDecl":
      // Keyword declarations are processed in collect-declarations pass
      break;
    case "KeywordTypeUse":
      // KeywordTypeUse is processed in collect-declarations pass
      // Here we just type-check the body like a regular type
      checkKeywordTypeUse(ctx, stmt);
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
      if (stmt.value.kind === "SpawnExpr" && ctx.lastSpawnInWithWasContextDependent && ctx.contextDependentSpawnsInWith) {
        ctx.contextDependentSpawnsInWith.add(stmt.pattern.name);
      }
      ctx.lastSpawnInWithWasContextDependent = false;
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
    // Null check narrowing: x == null or x != null
    const varName = condition.left.name;
    const symbol = ctx.env.lookup(varName);
    if (symbol && isNullable(symbol.type)) {
      const isNotNull = (condition.op === "!=" && truthyBranch) || (condition.op === "==" && !truthyBranch);
      if (isNotNull) {
        env.define(varName, nonNull(symbol.type), symbol.mutable);
      }
    }
  } else if (condition.kind === "BinaryExpr" &&
             (condition.op === "==" || condition.op === "!=") &&
             condition.left.kind === "Identifier" &&
             condition.right.kind === "Literal") {
    // Literal narrowing: x == "value" or x == 42
    const varName = condition.left.name;
    const symbol = ctx.env.lookup(varName);
    if (symbol) {
      const isEqual = (condition.op === "==" && truthyBranch) || (condition.op === "!=" && !truthyBranch);
      if (isEqual) {
        // Narrow to the literal type
        const literalType = Types.literal(condition.right.value as string | number | boolean);
        env.define(varName, literalType, symbol.mutable);
      } else if (symbol.type.kind === "union") {
        // Remove the literal from union if not equal
        const literalStr = JSON.stringify(condition.right.value);
        const remaining = symbol.type.types.filter((t: Type) => {
          if (t.kind === "literal") return JSON.stringify(t.value) !== literalStr;
          return true;
        });
        if (remaining.length === 1) {
          env.define(varName, remaining[0]!, symbol.mutable);
        } else if (remaining.length > 1) {
          env.define(varName, Types.union(...remaining), symbol.mutable);
        }
      }
    }
  } else if (condition.kind === "BinaryExpr" &&
             (condition.op === "==" || condition.op === "!=") &&
             condition.left.kind === "MemberExpr" &&
             condition.right.kind === "Literal") {
    // Discriminated union narrowing: x.kind == "value"
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
            if (prop) {
              // Check if this type's property matches the literal
              const propMatches = prop.type.kind === "literal" && prop.type.value === literalValue;
              if (propMatches) {
                matching.push(t);
              } else {
                nonMatching.push(t);
              }
            } else {
              nonMatching.push(t);
            }
          } else {
            nonMatching.push(t);
          }
        }
        
        if (isEqual && matching.length > 0) {
          // Narrow to matching types
          if (matching.length === 1) {
            env.define(varName, matching[0]!, symbol.mutable);
          } else {
            env.define(varName, Types.union(...matching), symbol.mutable);
          }
        } else if (!isEqual && nonMatching.length > 0) {
          // Narrow to non-matching types
          if (nonMatching.length === 1) {
            env.define(varName, nonMatching[0]!, symbol.mutable);
          } else {
            env.define(varName, Types.union(...nonMatching), symbol.mutable);
          }
        }
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
      const guardType = inferExpr(ctx, arm.guard);
      if (guardType.kind !== "bool" && guardType.kind !== "any") {
        const err = TypeErrors.guardMustBeBool(typeToString(guardType));
        error(ctx, err.message, arm.guard.loc, err.hint);
      }
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
      const err = TypeErrors.matchNotExhaustive(uncovered);
      error(ctx, err.message, loc, err.hint);
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

    const missing: string[] = [];
    if (!hasNullCase) missing.push("null");
    if (!hasValueCase) missing.push(typeToString(valueType.inner));
    
    if (missing.length > 0) {
      const err = TypeErrors.matchNotExhaustive(missing);
      error(ctx, err.message, loc, err.hint);
    }
  }

  if (valueType.kind === "bool") {
    const hasTrue = arms.some(arm =>
      arm.pattern.kind === "LiteralPattern" && arm.pattern.value === true
    );
    const hasFalse = arms.some(arm =>
      arm.pattern.kind === "LiteralPattern" && arm.pattern.value === false
    );

    const missing: string[] = [];
    if (!hasTrue) missing.push("true");
    if (!hasFalse) missing.push("false");
    
    if (missing.length > 0) {
      const err = TypeErrors.matchNotExhaustive(missing);
      error(ctx, err.message, loc, err.hint);
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
  ctx.withBlockDepth++;
  ctx.insideWithContext = true;

  let savedContextDependent: Set<string> | null = null;
  if (isFunctionLevel) {
    ctx.functionWithDepth++;
    savedContextDependent = ctx.contextDependentSpawnsInWith;
    ctx.contextDependentSpawnsInWith = new Set();
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

function checkTypeDecl(ctx: InferContext, decl: AST.TypeDecl): void {
  // Get the type from environment (already registered by collect-declarations pass)
  const typeObj = ctx.env.lookupType(decl.name);
  if (!typeObj || typeObj.kind !== "object") return;

  // Set current type context for private member access
  const savedTypeName = ctx.currentTypeName;
  ctx.currentTypeName = decl.name;

  // Create an environment with all fields available (for computed fields and methods)
  const typeEnv = ctx.env.child();
  for (const prop of (typeObj as ObjectType).properties) {
    typeEnv.define(prop.name, prop.type, true);  // mutable = true
  }

  // Check field default values (including computed fields which may reference other fields)
  for (const member of decl.body.members) {
    if (member.kind === "FieldDecl" && member.defaultValue) {
      const savedEnv = ctx.env;
      ctx.env = typeEnv;
      const valueType = inferExpr(ctx, member.defaultValue);
      ctx.env = savedEnv;
      
      if (member.type) {
        const declaredType = astTypeToType(member.type);
        if (!isAssignable(valueType, declaredType, ctx.env)) {
          const err = TypeErrors.typeMismatch(typeToString(declaredType), typeToString(valueType));
          error(ctx, err.message, member.loc, err.hint);
        }
      }
    }
  }

  // Check method bodies
  for (const member of decl.body.members) {
    if (member.kind === "MethodDecl" && member.body) {
      checkMethodDecl(ctx, decl, member, typeObj as ObjectType);
    }
  }
  
  // Restore type context
  ctx.currentTypeName = savedTypeName;
}

function checkKeywordTypeUse(ctx: InferContext, use: AST.KeywordTypeUse): void {
  // Get the type from environment (already registered by collect-declarations pass)
  const typeObj = ctx.env.lookupType(use.name);
  if (!typeObj || typeObj.kind !== "object") return;

  // Set current type context for member access
  const savedTypeName = ctx.currentTypeName;
  ctx.currentTypeName = use.name;

  // Create an environment with all fields available
  const typeEnv = ctx.env.child();
  for (const prop of (typeObj as ObjectType).properties) {
    typeEnv.define(prop.name, prop.type, true);
  }

  // Check field values
  for (const member of use.body.members) {
    if (member.kind === "FieldDecl" && member.defaultValue) {
      const savedEnv = ctx.env;
      ctx.env = typeEnv;
      const valueType = inferExpr(ctx, member.defaultValue);
      ctx.env = savedEnv;
      
      if (member.type) {
        const declaredType = astTypeToType(member.type);
        if (!isAssignable(valueType, declaredType, ctx.env)) {
          const err = TypeErrors.typeMismatch(typeToString(declaredType), typeToString(valueType));
          error(ctx, err.message, member.loc, err.hint);
        }
      }
    }
  }

  // Check method bodies (user-defined methods, not keyword methods)
  for (const member of use.body.members) {
    if (member.kind === "MethodDecl" && member.body) {
      checkKeywordTypeMethod(ctx, use, member, typeObj as ObjectType);
    }
  }
  
  ctx.currentTypeName = savedTypeName;
}

function checkKeywordTypeMethod(ctx: InferContext, use: AST.KeywordTypeUse, method: AST.MethodDecl, typeObj: ObjectType): void {
  const typeFieldsEnv = ctx.env.child();

  for (const prop of typeObj.properties) {
    typeFieldsEnv.define(prop.name, prop.type, true);
  }
  
  for (const m of typeObj.methods) {
    typeFieldsEnv.define(m.name, m.type);
  }

  const methodEnv = typeFieldsEnv.child();

  for (const param of method.params) {
    const paramType = param.type ? astTypeToType(param.type) : Types.any;
    methodEnv.define(param.name, paramType);
  }

  const methodType = typeObj.methods.find(m => m.name === method.name);
  const fnType = methodType?.type || Types.fn([], Types.any);

  const savedEnv = ctx.env;
  const savedFn = ctx.currentFunction;
  const savedSpawns = ctx.unawaitedSpawns;
  ctx.unawaitedSpawns = new Map();
  ctx.env = methodEnv;
  ctx.currentFunction = fnType;

  for (const stmt of method.body!.statements) {
    checkStatement(ctx, stmt);
  }

  const lastStmt = method.body!.statements[method.body!.statements.length - 1];
  if (lastStmt?.kind === "ExprStmt" && method.returnType) {
    const implicitReturnType = inferExpr(ctx, lastStmt.expr);
    const declaredReturnType = fnType.returnType;
    if (!isAssignable(implicitReturnType, declaredReturnType, ctx.env)) {
      const err = TypeErrors.typeMismatch(typeToString(declaredReturnType), typeToString(implicitReturnType));
      error(ctx, err.message, lastStmt.loc, err.hint);
    }
  }

  for (const [name, loc] of ctx.unawaitedSpawns) {
    error(ctx,
      `spawn result '${name}' is never awaited`,
      loc
    );
  }

  ctx.unawaitedSpawns = savedSpawns;
  ctx.env = savedEnv;
  ctx.currentFunction = savedFn;
}

function checkMethodDecl(ctx: InferContext, typeDecl: AST.TypeDecl, method: AST.MethodDecl, typeObj: ObjectType): void {
  const typeFieldsEnv = ctx.env.child();

  // Add type fields to the method scope (mutable, so methods can assign to them)
  for (const prop of typeObj.properties) {
    typeFieldsEnv.define(prop.name, prop.type, true);  // mutable = true
  }
  
  // Add type methods to the method scope (for promoted method calls)
  for (const m of typeObj.methods) {
    typeFieldsEnv.define(m.name, m.type);
  }

  // Create a child env for parameters (so they can shadow fields)
  const methodEnv = typeFieldsEnv.child();

  // Add method parameters (can shadow fields)
  for (const param of method.params) {
    const paramType = param.type ? astTypeToType(param.type) : Types.any;
    methodEnv.define(param.name, paramType);
  }

  // Get the method's function type
  const methodType = typeObj.methods.find(m => m.name === method.name);
  const fnType = methodType?.type || Types.fn([], Types.any);

  const savedEnv = ctx.env;
  const savedFn = ctx.currentFunction;
  const savedSpawns = ctx.unawaitedSpawns;
  ctx.unawaitedSpawns = new Map();
  ctx.env = methodEnv;
  ctx.currentFunction = fnType;

  // Check method body
  for (const stmt of method.body!.statements) {
    checkStatement(ctx, stmt);
  }

  // Check return type
  const lastStmt = method.body!.statements[method.body!.statements.length - 1];
  if (lastStmt?.kind === "ExprStmt" && method.returnType) {
    const implicitReturnType = inferExpr(ctx, lastStmt.expr);
    const declaredReturnType = fnType.returnType;
    if (!isAssignable(implicitReturnType, declaredReturnType, ctx.env)) {
      const err = TypeErrors.typeMismatch(typeToString(declaredReturnType), typeToString(implicitReturnType));
      error(ctx, err.message, lastStmt.loc, err.hint);
    }
  }

  // Check for unawaited spawns
  for (const [name, loc] of ctx.unawaitedSpawns) {
    error(ctx,
      `spawn result '${name}' is never awaited (pass to race() or all() before method returns)`,
      loc
    );
  }

  ctx.unawaitedSpawns = savedSpawns;
  ctx.env = savedEnv;
  ctx.currentFunction = savedFn;
}

function validateUsingClause(ctx: InferContext, using: AST.UsingClause): void {
  for (const binding of using.bindings) {
    const bindingType = astTypeToType(binding.type);
    if (!typeIsContext(bindingType, ctx.env)) {
      const typeName = binding.type.kind === "NamedType" ? binding.type.name : "unknown";
      error(ctx,
        `Type '${typeName}' used in 'using' clause must be a context type`,
        binding.loc,
        `Use \`context ${typeName}\` to declare a context type`
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

// Check if a statement is a terminating statement (return, throw, break, continue)
function isTerminatingStatement(stmt: AST.Statement): boolean {
  switch (stmt.kind) {
    case "ReturnStmt":
    case "ThrowStmt":
    case "BreakStmt":
    case "ContinueStmt":
      return true;
    case "IfStmt":
      // If is terminating only if both branches are terminating
      if (!stmt.else) return false;
      const thenTerminates = stmt.then.kind === "Block" 
        ? blockTerminates(stmt.then)
        : isTerminatingStatement(stmt.then);
      const elseTerminates = blockTerminates(stmt.else);
      return thenTerminates && elseTerminates;
    case "MatchStmt":
      // Match is terminating only if all arms are terminating (and there's a catch-all)
      const hasCatchAll = stmt.arms.some(arm => 
        arm.pattern.kind === "WildcardPattern" || 
        (arm.pattern.kind === "IdentifierPattern" && !arm.guard)
      );
      if (!hasCatchAll) return false;
      return stmt.arms.every(arm => {
        if (arm.body.kind === "Block") return blockTerminates(arm.body);
        return false;
      });
    default:
      return false;
  }
}

// Check if a block terminates (all paths through it terminate)
function blockTerminates(block: AST.Block): boolean {
  for (const stmt of block.statements) {
    if (isTerminatingStatement(stmt)) return true;
  }
  return false;
}

export function checkBlock(ctx: InferContext, block: AST.Block): void {
  const blockEnv = ctx.env.child();
  const savedEnv = ctx.env;
  ctx.env = blockEnv;

  let seenTerminator = false;
  for (const stmt of block.statements) {
    if (seenTerminator) {
      // Warn about unreachable code
      const err = TypeErrors.unreachableCode();
      warning(ctx, `${err.message} at line ${stmt.loc.line}. ${err.hint}`);
    }
    
    checkStatement(ctx, stmt);
    
    if (isTerminatingStatement(stmt)) {
      seenTerminator = true;
    }
  }

  ctx.env = savedEnv;
}

// Initialize the circular dependency between infer-expr and check-stmt
setCheckBlockFn(checkBlock);
