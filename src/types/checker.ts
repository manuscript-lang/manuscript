// Type Checker - Validates types and infers missing annotations
import * as AST from "../parser/ast";
import type { Type, FunctionType, ObjectType, ContextBinding, ParameterType } from "./types";
import { Types, typeToString, isNullable, nonNull } from "./types";
import { TypeEnvironment, createGlobalEnvironment } from "./environment";
import { TypeErrors } from "../shared/errors";

// ============================================
// Type Error
// ============================================

export class TypeCheckError extends Error {
  constructor(
    message: string,
    public loc: AST.SourceLocation,
    public hint?: string
  ) {
    super(`${message} at line ${loc.line}, column ${loc.column}`);
    this.name = "TypeCheckError";
  }
}

// ============================================
// Type Checker Result
// ============================================

export interface TypeCheckResult {
  program: AST.Program;
  types: Map<AST.ASTNode, Type>;  // Inferred types for all nodes
  errors: TypeCheckError[];
  warnings: string[];
}

// ============================================
// Type Checker
// ============================================

export class TypeChecker {
  private env: TypeEnvironment;
  private types: Map<AST.ASTNode, Type> = new Map();
  private errors: TypeCheckError[] = [];
  private warnings: string[] = [];
  private currentFunction: FunctionType | null = null;
  private inLoop: boolean = false;
  private insideWithContext: boolean = false;  // Track if we're checking a with context expr
  // Track spawn variables that haven't been awaited (via race/all)
  private unawaitedSpawns: Map<string, AST.SourceLocation> = new Map();
  // Track function-level with blocks for escape analysis
  private functionWithDepth: number = 0;
  private withContextVars: Set<string> = new Set();
  // Track which functions need context (have using or call functions that do)
  private needsContextCache: Map<string, boolean> = new Map();
  // Store function declarations for escape analysis
  private fnDecls: Map<string, AST.FnDecl> = new Map();

  constructor() {
    this.env = createGlobalEnvironment();
  }

  /**
   * Type check a program
   */
  check(program: AST.Program): TypeCheckResult {
    // First pass: collect type declarations
    this.collectDeclarations(program);

    // Second pass: check all statements (track top-level spawns)
    this.unawaitedSpawns.clear();
    for (const stmt of program.body) {
      this.checkStatement(stmt);
    }

    // Error for any unawaited spawns at top level
    for (const [name, loc] of this.unawaitedSpawns) {
      this.error(
        `spawn result '${name}' is never awaited (pass to race() or all())`,
        loc
      );
    }

    return {
      program,
      types: this.types,
      errors: this.errors,
      warnings: this.warnings,
    };
  }

  // ============================================
  // Declaration Collection (First Pass)
  // ============================================

  private collectDeclarations(program: AST.Program): void {
    for (const stmt of program.body) {
      switch (stmt.kind) {
        case "TypeDecl":
          this.collectTypeDecl(stmt);
          break;
        case "FnDecl":
          this.collectFnDecl(stmt);
          break;
      }
    }
  }

  private collectTypeDecl(decl: AST.TypeDecl): void {
    // For now, create a simple object type
    const type: ObjectType = {
      kind: "object",
      name: decl.name,
      properties: [],
      methods: [],
      typeParams: decl.typeParams?.map(p => ({ name: p.name, constraint: p.constraint ? this.astTypeToType(p.constraint) : undefined })),
      extends: decl.extends?.map(e => this.astTypeToType(e)),
    };

    if (decl.body && decl.body.members.length > 0) {
      for (const member of decl.body.members) {
        if (member.kind === "FieldDecl") {
          type.properties.push({
            name: member.name,
            type: member.type ? this.astTypeToType(member.type) : Types.any,
            optional: member.optional,
            readonly: false,
            computed: member.computed,
            defaultValue: !!member.defaultValue,
          });
        } else if (member.kind === "MethodDecl") {
          const methodType = this.methodToFunctionType(member);
          type.methods.push({ name: member.name, type: methodType });
          
          // Validate method override signature if this type extends another
          if (decl.extends) {
            this.validateMethodOverride(decl.name, member.name, methodType, decl.extends, member.loc);
          }
        }
      }
    }

    try {
      this.env.defineType(decl.name, type);
    } catch (e) {
      const err = TypeErrors.typeAlreadyDefined(decl.name);
      this.error(err.message, decl.loc, err.hint);
    }
  }

  private collectFnDecl(decl: AST.FnDecl): void {
    const fnType = this.fnDeclToType(decl);
    try {
      this.env.define(decl.name, fnType);
      // Store declaration for escape analysis
      this.fnDecls.set(decl.name, decl);
    } catch (e) {
      const err = TypeErrors.functionAlreadyDefined(decl.name);
      this.error(err.message, decl.loc, err.hint);
    }
  }

  // ============================================
  // Statement Checking
  // ============================================

  private checkStatement(stmt: AST.Statement): void {
    switch (stmt.kind) {
      case "LetStmt":
        this.checkLetStmt(stmt);
        break;
      case "VarStmt":
        this.checkVarStmt(stmt);
        break;
      case "AssignStmt":
        this.checkAssignStmt(stmt);
        break;
      case "IfStmt":
        this.checkIfStmt(stmt);
        break;
      case "ForStmt":
        this.checkForStmt(stmt);
        break;
      case "MatchStmt":
        this.checkMatchStmt(stmt);
        break;
      case "ReturnStmt":
        this.checkReturnStmt(stmt);
        break;
      case "YieldStmt":
        this.checkYieldStmt(stmt);
        break;
      case "BreakStmt":
      case "ContinueStmt":
        if (!this.inLoop) {
          const err = stmt.kind === "BreakStmt" ? TypeErrors.breakOutsideLoop() : TypeErrors.continueOutsideLoop();
          this.error(err.message, stmt.loc, err.hint);
        }
        break;
      case "DeferStmt":
        this.checkStatement(stmt.body);
        break;
      case "TryStmt":
        this.checkTryStmt(stmt);
        break;
      case "ThrowStmt":
        this.inferExpr(stmt.value);
        break;
      case "WithStmt":
        this.checkWithStmt(stmt);
        break;
      case "ExprStmt":
        // Check for discarded spawn result - this is likely a bug
        if (stmt.expr.kind === "SpawnExpr") {
          this.error(
            "spawn result must be used (await, pass to all(), or assign to variable)",
            stmt.expr.loc
          );
        }
        this.inferExpr(stmt.expr);
        break;
      case "FnDecl":
        this.checkFnDecl(stmt);
        break;
      case "ExternFnDecl":
        // Extern functions have no body to check, types registered via stdlib
        break;
      case "TypeDecl":
        // Already collected in first pass
        break;
      case "TestDecl":
        this.checkTestDecl(stmt);
        break;
      case "ImportDecl":
        // TODO: Handle imports
        break;
      case "KeywordDecl":
        // TODO: Register keyword expansions
        break;
    }
  }

  private checkLetStmt(stmt: AST.LetStmt): void {
    const valueType = this.inferExpr(stmt.value);
    const declaredType = stmt.type ? this.astTypeToType(stmt.type) : valueType;

    // Check type compatibility
    if (stmt.type && !this.isAssignable(valueType, declaredType)) {
      const err = TypeErrors.typeMismatch(typeToString(declaredType), typeToString(valueType));
      this.error(err.message, stmt.loc, err.hint);
    }

    // Track spawn-derived values:
    // Only track values that derive from spawn expressions (not general Promise-returning calls)
    // This ensures spawns are tracked from construction to consumption
    if (stmt.pattern.kind === "IdentifierPattern") {
      const containsSpawn = this.exprContainsSpawn(stmt.value, valueType);
      // Don't track race/all results - they're already consumed
      const isConsumerResult = stmt.value.kind === "CallExpr" && 
        stmt.value.callee.kind === "Identifier" &&
        (stmt.value.callee.name === "race" || stmt.value.callee.name === "all");
      
      if (containsSpawn && !isConsumerResult) {
        this.unawaitedSpawns.set(stmt.pattern.name, stmt.loc);
        // Transfer tracking from any source variables
        this.transferSpawnTracking(stmt.value);
      }
    }

    // Bind pattern
    this.bindPattern(stmt.pattern, declaredType, false);
  }

  private checkVarStmt(stmt: AST.VarStmt): void {
    const valueType = this.inferExpr(stmt.value);
    const declaredType = stmt.type ? this.astTypeToType(stmt.type) : valueType;

    if (stmt.type && !this.isAssignable(valueType, declaredType)) {
      const err = TypeErrors.typeMismatch(typeToString(declaredType), typeToString(valueType));
      this.error(err.message, stmt.loc, err.hint);
    }

    try {
      this.env.define(stmt.name, declaredType, true);
    } catch (e) {
      const err = TypeErrors.variableAlreadyDefined(stmt.name);
      this.error(err.message, stmt.loc, err.hint);
    }
  }

  private checkAssignStmt(stmt: AST.AssignStmt): void {
    const targetType = this.inferExpr(stmt.target);
    const valueType = this.inferExpr(stmt.value);

    // Check mutability
    if (stmt.target.kind === "Identifier") {
      const symbol = this.env.lookup(stmt.target.name);
      if (symbol && !symbol.mutable) {
        const err = TypeErrors.cannotAssignToImmutable(stmt.target.name);
        this.error(err.message, stmt.loc, err.hint);
      }
    }

    // Check type compatibility
    if (!this.isAssignable(valueType, targetType)) {
      const err = TypeErrors.typeMismatch(typeToString(targetType), typeToString(valueType));
      this.error(err.message, stmt.loc, err.hint);
    }
  }

  private checkIfStmt(stmt: AST.IfStmt): void {
    const condType = this.inferExpr(stmt.condition);

    // Check then branch with potential type narrowing
    const narrowedEnv = this.env.child();
    this.applyTypeNarrowing(stmt.condition, narrowedEnv, true);

    if (stmt.then.kind === "Block") {
      const savedEnv = this.env;
      this.env = narrowedEnv;
      for (const s of stmt.then.statements) {
        this.checkStatement(s);
      }
      this.env = savedEnv;
    } else {
      const savedEnv = this.env;
      this.env = narrowedEnv;
      this.checkStatement(stmt.then);
      this.env = savedEnv;
    }

    // Check else-if branches
    for (const elif of stmt.elseIfs) {
      this.inferExpr(elif.condition);
      const elifEnv = this.env.child();
      this.applyTypeNarrowing(elif.condition, elifEnv, true);
      const savedEnv = this.env;
      this.env = elifEnv;
      for (const s of elif.body.statements) {
        this.checkStatement(s);
      }
      this.env = savedEnv;
    }

    // Check else branch (with inverted narrowing from condition)
    if (stmt.else) {
      const elseEnv = this.env.child();
      this.applyTypeNarrowing(stmt.condition, elseEnv, false);
      const savedEnv = this.env;
      this.env = elseEnv;
      for (const s of stmt.else.statements) {
        this.checkStatement(s);
      }
      this.env = savedEnv;
    }

    // Handle guard form
    if (stmt.pattern && stmt.elseReturn) {
      this.inferExpr(stmt.elseReturn);
    }
  }

  /**
   * Apply type narrowing based on a condition
   */
  private applyTypeNarrowing(condition: AST.Expr, env: TypeEnvironment, truthyBranch: boolean): void {
    // Handle `x is Type` narrowing
    if (condition.kind === "BinaryExpr" && condition.op === "is") {
      if (condition.left.kind === "Identifier" && condition.right.kind === "Identifier") {
        const varName = condition.left.name;
        const typeName = condition.right.name;
        const symbol = this.env.lookup(varName);
        if (symbol) {
          if (truthyBranch) {
            // Narrow to the specified type
            const narrowedType = this.env.lookupType(typeName) ?? Types.ref(typeName);
            env.define(varName, narrowedType, symbol.mutable);
          } else {
            // In else branch, exclude the type from union if possible
            if (symbol.type.kind === "union") {
              const remaining = symbol.type.types.filter(t => {
                if (t.kind === "ref") return t.name !== typeName;
                if (t.kind === "object") return t.name !== typeName;
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
    }
    // Handle `x != null` or `x == null` narrowing
    else if (condition.kind === "BinaryExpr" && 
             (condition.op === "!=" || condition.op === "==") &&
             condition.left.kind === "Identifier" &&
             condition.right.kind === "Literal" && condition.right.value === null) {
      const varName = condition.left.name;
      const symbol = this.env.lookup(varName);
      if (symbol && isNullable(symbol.type)) {
        const isNotNull = (condition.op === "!=" && truthyBranch) || (condition.op === "==" && !truthyBranch);
        if (isNotNull) {
          env.define(varName, nonNull(symbol.type), symbol.mutable);
        }
      }
    }
    // Handle negation: `not condition` or `!condition`
    else if (condition.kind === "UnaryExpr" && (condition.op === "not" || condition.op === "!")) {
      this.applyTypeNarrowing(condition.operand, env, !truthyBranch);
    }
  }

  private checkForStmt(stmt: AST.ForStmt): void {
    const prevInLoop = this.inLoop;
    this.inLoop = true;

    const bodyEnv = this.env.child();

    if (stmt.pattern && stmt.iterable) {
      const iterableType = this.inferExpr(stmt.iterable);
      const elementType = this.getIterableElementType(iterableType);

      // Bind pattern in body scope
      const savedEnv = this.env;
      this.env = bodyEnv;
      this.bindPattern(stmt.pattern, elementType, false);
      this.env = savedEnv;
    }

    // Check body in new scope
    const savedEnv = this.env;
    this.env = bodyEnv;
    this.checkBlock(stmt.body);
    this.env = savedEnv;

    this.inLoop = prevInLoop;
  }

  private checkMatchStmt(stmt: AST.MatchStmt): void {
    const valueType = this.inferExpr(stmt.value);

    for (const arm of stmt.arms) {
      const armEnv = this.env.child();
      const savedEnv = this.env;
      this.env = armEnv;

      // Check pattern and bind variables
      this.checkPattern(arm.pattern, valueType);

      // Check guard
      if (arm.guard) {
        this.inferExpr(arm.guard);
      }

      // Check body
      if (arm.body.kind === "Block") {
        this.checkBlock(arm.body as AST.Block);
      } else {
        this.inferExpr(arm.body as AST.Expr);
      }

      this.env = savedEnv;
    }

    // Check exhaustiveness
    this.checkMatchExhaustiveness(valueType, stmt.arms, stmt.loc);
  }

  /**
   * Check if match arms exhaustively cover the value type
   */
  private checkMatchExhaustiveness(valueType: Type, arms: AST.MatchArm[], loc: AST.SourceLocation): void {
    // Check for wildcard or identifier pattern (catches all)
    const hasCatchAll = arms.some(arm => 
      arm.pattern.kind === "WildcardPattern" || 
      (arm.pattern.kind === "IdentifierPattern" && !arm.guard)
    );
    if (hasCatchAll) return;

    // For union types, check all variants are covered
    if (valueType.kind === "union") {
      const coveredTypes = new Set<string>();
      
      for (const arm of arms) {
        if (arm.guard) continue; // Guarded arms don't guarantee coverage
        
        if (arm.pattern.kind === "TypePattern") {
          const typeName = arm.pattern.type.kind === "NamedType" 
            ? arm.pattern.type.name 
            : typeToString(this.astTypeToType(arm.pattern.type));
          coveredTypes.add(typeName);
        } else if (arm.pattern.kind === "LiteralPattern") {
          // Literal patterns cover their literal type
          if (arm.pattern.value === null) {
            coveredTypes.add("null");
          }
        }
      }

      const uncovered: string[] = [];
      for (const t of valueType.types) {
        const typeName = t.kind === "ref" ? t.name : 
                        t.kind === "object" && t.name ? t.name : 
                        typeToString(t);
        if (!coveredTypes.has(typeName)) {
          uncovered.push(typeName);
        }
      }

      if (uncovered.length > 0) {
        this.warning(`Match may not be exhaustive. Missing cases: ${uncovered.join(", ")}`);
      }
    }

    // For optional types, check both value and null are covered
    if (valueType.kind === "optional") {
      const hasNullCase = arms.some(arm => 
        arm.pattern.kind === "LiteralPattern" && arm.pattern.value === null
      );
      const hasValueCase = arms.some(arm =>
        arm.pattern.kind === "TypePattern" ||
        arm.pattern.kind === "IdentifierPattern"
      );
      
      if (!hasNullCase || !hasValueCase) {
        this.warning(`Match on optional type may not be exhaustive`);
      }
    }

    // For bool type, check both true and false
    if (valueType.kind === "bool") {
      const hasTrue = arms.some(arm => 
        arm.pattern.kind === "LiteralPattern" && arm.pattern.value === true
      );
      const hasFalse = arms.some(arm => 
        arm.pattern.kind === "LiteralPattern" && arm.pattern.value === false
      );
      
      if (!hasTrue || !hasFalse) {
        this.warning(`Match on bool may not be exhaustive`);
      }
    }
  }

  private checkReturnStmt(stmt: AST.ReturnStmt): void {
    if (!this.currentFunction) {
      const err = TypeErrors.returnOutsideFunction();
      this.error(err.message, stmt.loc, err.hint);
      return;
    }

    if (stmt.value) {
      const returnType = this.inferExpr(stmt.value);
      if (!this.isAssignable(returnType, this.currentFunction.returnType)) {
        const err = TypeErrors.typeMismatch(typeToString(this.currentFunction.returnType), typeToString(returnType));
        this.error(err.message, stmt.loc, err.hint);
      }
      // Returning transfers ownership to caller - consume all spawns in return expr
      this.consumeSpawnsInExpr(stmt.value);
      
      // Check for escaping context-dependent closures from function-level with
      if (this.functionWithDepth > 0 && this.exprContainsEscapingLambda(stmt.value)) {
        this.error(
          `Cannot return closure that depends on context from 'with' block - it would outlive the context scope`,
          stmt.loc,
          `Context is cleaned up when 'with' block exits, but the returned closure needs it to execute`
        );
      }
    } else if (this.currentFunction.returnType.kind !== "void") {
      const err = TypeErrors.returnMissingValue(typeToString(this.currentFunction.returnType));
      this.error(err.message, stmt.loc, err.hint);
    }
  }

  private checkYieldStmt(stmt: AST.YieldStmt): void {
    if (!this.currentFunction || !this.currentFunction.isGenerator) {
      const err = TypeErrors.yieldOutsideGenerator();
      this.error(err.message, stmt.loc, err.hint);
      return;
    }

    this.inferExpr(stmt.value);
  }

  private checkTryStmt(stmt: AST.TryStmt): void {
    this.checkBlock(stmt.body);

    if (stmt.catch) {
      const catchEnv = this.env.child();
      catchEnv.define(stmt.catch.name, Types.ref("Error"));
      const savedEnv = this.env;
      this.env = catchEnv;
      this.checkBlock(stmt.catch.body);
      this.env = savedEnv;
    }
  }

  private checkWithStmt(stmt: AST.WithStmt): void {
    const bindings: ContextBinding[] = [];
    const isFunctionLevel = this.currentFunction !== null;
    
    // Track context variable names for escape analysis
    const savedWithContextVars = new Set(this.withContextVars);

    for (const ctx of stmt.contexts) {
      // Mark that we're inside a with context (allows Context instantiation)
      this.insideWithContext = true;
      const ctxType = this.inferExpr(ctx.expr);
      this.insideWithContext = false;
      
      if (ctx.name) {
        bindings.push({ name: ctx.name, type: ctxType });
        if (isFunctionLevel) {
          this.withContextVars.add(ctx.name);
        }
      }
    }

    const withEnv = this.env.withContext(bindings);
    const savedEnv = this.env;
    this.env = withEnv;
    
    // Track function-level with depth for escape analysis
    if (isFunctionLevel) {
      this.functionWithDepth++;
    }
    
    this.checkBlock(stmt.body);
    
    // Check for escaping closures in the with body's last expression (potential implicit return)
    if (isFunctionLevel) {
      const lastStmt = stmt.body.statements[stmt.body.statements.length - 1];
      if (lastStmt?.kind === "ExprStmt" && this.exprContainsEscapingLambda(lastStmt.expr)) {
        this.error(
          `Cannot return closure that depends on context from 'with' block - it would outlive the context scope`,
          lastStmt.loc,
          `Context is cleaned up when 'with' block exits, but the returned closure needs it to execute`
        );
      }
    }
    
    if (isFunctionLevel) {
      this.functionWithDepth--;
    }
    
    this.env = savedEnv;
    this.withContextVars = savedWithContextVars;
  }

  private checkFnDecl(decl: AST.FnDecl): void {
    const fnType = this.fnDeclToType(decl);
    const fnEnv = this.env.child();

    // Add parameters to scope
    for (const param of decl.params) {
      const paramType = param.type ? this.astTypeToType(param.type) : Types.any;
      fnEnv.define(param.name, paramType);
    }

    // Add context bindings to scope (from using clause)
    if (decl.using) {
      // Validate that all using types extend Context
      this.validateUsingClause(decl.using);
      
      for (const binding of decl.using.bindings) {
        const bindingType = this.astTypeToType(binding.type);
        if (binding.name) {
          fnEnv.define(binding.name, bindingType);
        }
      }
    }

    // Check body with spawn tracking
    const savedEnv = this.env;
    const savedFn = this.currentFunction;
    const savedSpawns = this.unawaitedSpawns;
    this.unawaitedSpawns = new Map();
    this.env = fnEnv;
    this.currentFunction = fnType;
    
    // Check function body statements directly (not via checkBlock which creates new scope)
    // This keeps the function's scope active for implicit return handling
    const bodyEnv = this.env.child();
    this.env = bodyEnv;
    for (const stmt of decl.body.statements) {
      this.checkStatement(stmt);
    }
    
    // Check for implicit return (last expression in body)
    // Mark any tracked spawns in the return expression as consumed (transferred to caller)
    const lastStmt = decl.body.statements[decl.body.statements.length - 1];
    if (lastStmt?.kind === "ExprStmt") {
      this.consumeSpawnsInExpr(lastStmt.expr);
      
      // Check for escaping context-dependent closures from function-level with (implicit return)
      if (this.functionWithDepth > 0 && this.exprContainsEscapingLambda(lastStmt.expr)) {
        this.error(
          `Cannot return closure that depends on context from 'with' block - it would outlive the context scope`,
          lastStmt.loc,
          `Context is cleaned up when 'with' block exits, but the returned closure needs it to execute`
        );
      }
      // Validate implicit return type matches declared return type
      // Only check for non-Promise return types to avoid complex async/await semantics
      if (decl.returnType && fnType.returnType.kind !== "promise" && fnType.returnType.kind !== "any") {
        let implicitReturnType = this.inferExpr(lastStmt.expr);
        const declaredReturnType = fnType.returnType;
        // Since all calls are implicitly awaited, unwrap Promise types for comparison
        if (implicitReturnType.kind === "promise") {
          implicitReturnType = (implicitReturnType as any).resolveType;
        }
        if (!this.isAssignable(implicitReturnType, declaredReturnType)) {
          const err = TypeErrors.typeMismatch(typeToString(declaredReturnType), typeToString(implicitReturnType));
          this.error(err.message, lastStmt.loc, err.hint);
        }
      }
    }
    
    // Error for any unawaited spawns at function exit
    for (const [name, loc] of this.unawaitedSpawns) {
      this.error(
        `spawn result '${name}' is never awaited (pass to race() or all() before function returns)`,
        loc
      );
    }
    
    this.unawaitedSpawns = savedSpawns;
    this.env = savedEnv;
    this.currentFunction = savedFn;

    this.types.set(decl, fnType);
  }

  private checkTestDecl(decl: AST.TestDecl): void {
    const testEnv = this.env.child();
    const savedEnv = this.env;
    this.env = testEnv;
    this.checkBlock(decl.body);
    this.env = savedEnv;
  }

  private checkBlock(block: AST.Block): void {
    const blockEnv = this.env.child();
    const savedEnv = this.env;
    this.env = blockEnv;

    for (const stmt of block.statements) {
      this.checkStatement(stmt);
    }

    this.env = savedEnv;
  }

  // ============================================
  // Expression Type Inference
  // ============================================

  private inferExpr(expr: AST.Expr): Type {
    let type: Type;

    switch (expr.kind) {
      case "Literal":
        type = this.inferLiteral(expr);
        break;
      case "Identifier":
        type = this.inferIdentifier(expr);
        break;
      case "BinaryExpr":
        type = this.inferBinaryExpr(expr);
        break;
      case "UnaryExpr":
        type = this.inferUnaryExpr(expr);
        break;
      case "CallExpr":
        type = this.inferCallExpr(expr);
        break;
      case "IndexExpr":
        type = this.inferIndexExpr(expr);
        break;
      case "MemberExpr":
        type = this.inferMemberExpr(expr);
        break;
      case "PipeExpr":
        type = this.inferPipeExpr(expr);
        break;
      case "LambdaExpr":
        type = this.inferLambdaExpr(expr);
        break;
      case "IfExpr":
        type = this.inferIfExpr(expr);
        break;
      case "MatchExpr":
        type = this.inferMatchExpr(expr);
        break;
      case "ListExpr":
        type = this.inferListExpr(expr);
        break;
      case "MapExpr":
        type = this.inferMapExpr(expr);
        break;
      case "SpawnExpr":
        type = this.inferSpawnExpr(expr);
        break;
      case "TypeAssertion":
        type = this.astTypeToType(expr.type);
        break;
      case "NullAssertion":
        type = nonNull(this.inferExpr(expr.expr));
        break;
      case "RangeExpr":
        type = Types.list(Types.number);
        break;
      default:
        type = Types.any;
    }

    this.types.set(expr, type);
    return type;
  }

  private inferLiteral(expr: AST.Literal): Type {
    if (typeof expr.value === "number") return Types.number;
    if (typeof expr.value === "string") return Types.string;
    if (typeof expr.value === "boolean") return Types.bool;
    if (expr.value === null) return Types.null;
    return Types.any;
  }

  private inferIdentifier(expr: AST.Identifier): Type {
    const symbol = this.env.lookup(expr.name);
    if (!symbol) {
      // Check if it's a type reference (for constructor calls)
      const typeRef = this.env.lookupType(expr.name);
      if (typeRef) {
        // Return a constructor type
        if (typeRef.kind === "object" && typeRef.name) {
          // Object types can be called as constructors
          // All properties become parameters, with optional/default ones marked as optional
          return Types.fn(
            typeRef.properties.map(p => Types.param(p.name, p.type, p.optional || p.defaultValue)),
            typeRef
          );
        }
        return typeRef;
      }
      const err = TypeErrors.unknownIdentifier(expr.name);
      this.error(err.message, expr.loc, err.hint);
      return Types.any;
    }
    return symbol.type;
  }

  private inferBinaryExpr(expr: AST.BinaryExpr): Type {
    const leftType = this.inferExpr(expr.left);
    const rightType = this.inferExpr(expr.right);

    switch (expr.op) {
      case "+":
        // Number + Number = Number, String + String = String
        if (leftType.kind === "string" || rightType.kind === "string") {
          return Types.string;
        }
        // Validate numeric addition
        if (leftType.kind !== "number" && leftType.kind !== "any") {
          const err = TypeErrors.operatorRequiresType("+", "number or string", typeToString(leftType));
          this.error(err.message, expr.left.loc, err.hint);
        }
        if (rightType.kind !== "number" && rightType.kind !== "any") {
          const err = TypeErrors.operatorRequiresType("+", "number or string", typeToString(rightType));
          this.error(err.message, expr.right.loc, err.hint);
        }
        return Types.number;
      case "-":
      case "*":
      case "/":
      case "%":
      case "^":
        // Validate operands are numbers
        if (leftType.kind !== "number" && leftType.kind !== "any") {
          const err = TypeErrors.operatorRequiresType(expr.op, "number", typeToString(leftType));
          this.error(err.message, expr.left.loc, err.hint);
        }
        if (rightType.kind !== "number" && rightType.kind !== "any") {
          const err = TypeErrors.operatorRequiresType(expr.op, "number", typeToString(rightType));
          this.error(err.message, expr.right.loc, err.hint);
        }
        return Types.number;
      case "<":
      case ">":
      case "<=":
      case ">=":
        // Comparison operators need compatible types
        // Unwrap optionals for comparison checking
        const leftBase = leftType.kind === "optional" ? leftType.inner : leftType;
        const rightBase = rightType.kind === "optional" ? rightType.inner : rightType;
        if (leftBase.kind !== "any" && rightBase.kind !== "any" &&
            leftBase.kind !== rightBase.kind &&
            !((leftBase.kind === "number" || leftBase.kind === "string") && 
              (rightBase.kind === "number" || rightBase.kind === "string"))) {
          const err = TypeErrors.cannotCompare(typeToString(leftType), typeToString(rightType));
          this.error(err.message, expr.loc, err.hint);
        }
        return Types.bool;
      case "==":
      case "!=":
      case "and":
      case "or":
        return Types.bool;
      case "is":
        return Types.bool;
      case "??":
        // a ?? b returns b's type if a is null
        if (isNullable(leftType)) {
          return Types.union(nonNull(leftType), rightType);
        }
        return leftType;
      default:
        return Types.any;
    }
  }

  private inferUnaryExpr(expr: AST.UnaryExpr): Type {
    const operandType = this.inferExpr(expr.operand);

    switch (expr.op) {
      case "-":
        if (operandType.kind !== "number" && operandType.kind !== "any") {
          const err = TypeErrors.operatorRequiresType("-", "number", typeToString(operandType));
          this.error(err.message, expr.operand.loc, err.hint);
        }
        return Types.number;
      case "not":
      case "!":
        return Types.bool;
      default:
        return operandType;
    }
  }

  private inferCallExpr(expr: AST.CallExpr): Type {
    // Handle generic constructor calls like Channel[T](...) 
    // The callee is an IndexExpr where object is the constructor name and index is the type arg
    if (expr.callee.kind === "IndexExpr" && expr.callee.object.kind === "Identifier") {
      const constructorName = expr.callee.object.name;
      
      // Handle Channel[T](buffer) -> Channel[T]
      if (constructorName === "Channel" && expr.callee.index.kind === "Identifier") {
        const typeArgName = expr.callee.index.name;
        const elementType = this.resolveTypeName(typeArgName);
        
        // Validate buffer argument if provided
        for (const arg of expr.args) {
          const argExpr = "kind" in arg ? arg : arg.value;
          const argType = this.inferExpr(argExpr);
          if (argType.kind !== "number" && argType.kind !== "any") {
            this.error(`Channel buffer size must be a number, got '${typeToString(argType)}'`, argExpr.loc);
          }
        }
        
        return Types.channel(elementType);
      }
    }
    
    const calleeType = this.inferExpr(expr.callee);

    // Consume spawns when:
    // 1. Called with race/all (they await promises)
    // 2. Passed to a function parameter of type Promise (function takes responsibility)
    if (expr.callee.kind === "Identifier" && 
        (expr.callee.name === "race" || expr.callee.name === "all")) {
      this.markSpawnsConsumed(expr.args);
    } else if (calleeType.kind === "function") {
      // Check each argument - if the parameter type involves Promise, consume the spawn
      const params = calleeType.params;
      for (let i = 0; i < expr.args.length && i < params.length; i++) {
        const param = params[i];
        if (param && this.typeInvolvesPromise(param.type)) {
          const arg = expr.args[i];
          const argExpr = arg && "kind" in arg ? arg : arg?.value;
          if (argExpr) this.consumeSpawnsInExpr(argExpr);
        }
      }
    }

    if (calleeType.kind === "function") {
      const args = expr.args;
      
      // Infer type parameters if this is a generic function
      const typeBindings = this.inferTypeParams(calleeType, args);
      
      // Substitute type params in parameter types
      const params = calleeType.params.map(p => ({
        ...p,
        type: this.substituteTypeParams(p.type, typeBindings)
      }));

      // Count required params (non-optional, non-rest)
      const requiredCount = params.filter(p => !p.optional && !p.rest).length;
      const hasRest = params.some(p => p.rest);
      const maxArgs = hasRest ? Infinity : params.length;

      // Check argument count
      if (args.length < requiredCount) {
        const err = TypeErrors.wrongArgumentCount(`at least ${requiredCount}`, args.length);
        this.error(err.message, expr.loc, err.hint);
      } else if (args.length > maxArgs) {
        const err = TypeErrors.wrongArgumentCount(`at most ${params.length}`, args.length);
        this.error(err.message, expr.loc, err.hint);
      }

      // Check each argument type
      for (let i = 0; i < args.length; i++) {
        const arg = args[i]!;
        let argType: Type;
        let argLoc: AST.SourceLocation;

        if ("name" in arg && "value" in arg) {
          // Named argument
          argType = this.inferExpr(arg.value);
          argLoc = arg.value.loc;
          // Find matching parameter by name
          const param = params.find(p => p.name === arg.name);
          if (!param) {
            const err = TypeErrors.unknownParameter(arg.name, params.map(p => p.name).filter(Boolean) as string[]);
            this.error(err.message, arg.value.loc, err.hint);
          } else if (!this.isAssignable(argType, param.type)) {
            const err = TypeErrors.typeMismatch(typeToString(param.type), typeToString(argType));
            this.error(`Argument '${arg.name}': ${err.message}`, arg.value.loc, err.hint);
          }
        } else {
          // Positional argument
          argType = this.inferExpr(arg as AST.Expr);
          argLoc = (arg as AST.Expr).loc;
          // Get parameter at this position (or rest param)
          const paramIndex = Math.min(i, params.length - 1);
          const param = params[paramIndex];
          if (param) {
            // For rest params, the annotation is the collected type
            // e.g., ...nums: list[number] means each arg is number
            const expectedType = param.rest && param.type.kind === "list" ? 
              param.type.elementType : param.type;
            if (!this.isAssignable(argType, expectedType)) {
              const err = TypeErrors.typeMismatch(typeToString(expectedType), typeToString(argType));
              this.error(`Argument ${i + 1}: ${err.message}`, argLoc, err.hint);
            }
          }
        }
      }

      // Check context requirements
      for (const binding of calleeType.context) {
        if (binding.name && !this.env.isDefined(binding.name)) {
          this.warning(`Function requires '${binding.name}' in context which may not be available`);
        }
      }

      // Substitute type params in return type
      const returnType = this.substituteTypeParams(calleeType.returnType, typeBindings);

      // Restriction: Context types can only be instantiated in 'with' clauses
      // (Constructor functions have object type as return type)
      if (returnType.kind === "object" && 
          this.extendsType(returnType, "Context") && 
          !this.insideWithContext) {
        this.error(`Context type '${returnType.name}' can only be instantiated in 'with' clauses`, expr.loc);
      }

      return returnType;
    }

    // Constructor call - check object type constructor (direct type reference)
    if (calleeType.kind === "object") {
      // Restriction: Context types can only be instantiated in 'with' clauses
      if (this.extendsType(calleeType, "Context") && !this.insideWithContext) {
        this.error(`Context type '${calleeType.name}' can only be instantiated in 'with' clauses`, expr.loc);
      }

      const props = calleeType.properties;
      const requiredProps = props.filter(p => !p.optional && !p.defaultValue);
      const args = expr.args;

      // Check argument count for constructor
      if (args.length < requiredProps.length) {
        const err = TypeErrors.wrongArgumentCount(`at least ${requiredProps.length}`, args.length);
        this.error(`Type '${calleeType.name}': ${err.message}`, expr.loc, err.hint);
      } else if (args.length > props.length) {
        const err = TypeErrors.wrongArgumentCount(`at most ${props.length}`, args.length);
        this.error(`Type '${calleeType.name}': ${err.message}`, expr.loc, err.hint);
      }

      // Check argument types against properties
      for (let i = 0; i < args.length; i++) {
        const arg = args[i]!;
        let argType: Type;

        if ("name" in arg && "value" in arg) {
          argType = this.inferExpr(arg.value);
          const prop = props.find(p => p.name === arg.name);
          if (!prop) {
            const err = TypeErrors.propertyNotExist(arg.name, calleeType.name!);
            this.error(err.message, arg.value.loc, err.hint);
          } else if (!this.isAssignable(argType, prop.type)) {
            const err = TypeErrors.typeMismatch(typeToString(prop.type), typeToString(argType));
            this.error(`Property '${arg.name}': ${err.message}`, arg.value.loc, err.hint);
          }
        } else {
          argType = this.inferExpr(arg as AST.Expr);
          const prop = props[i];
          if (prop && !this.isAssignable(argType, prop.type)) {
            const err = TypeErrors.typeMismatch(typeToString(prop.type), typeToString(argType));
            this.error(`Argument ${i + 1}: ${err.message}`, (arg as AST.Expr).loc, err.hint);
          }
        }
      }

      return calleeType;
    }

    // Infer arguments even for unknown callees
    for (const arg of expr.args) {
      if ("name" in arg && "value" in arg) {
        this.inferExpr(arg.value);
      } else {
        this.inferExpr(arg as AST.Expr);
      }
    }

    return Types.any;
  }

  private inferIndexExpr(expr: AST.IndexExpr): Type {
    const objectType = this.inferExpr(expr.object);

    if (expr.slice) {
      // Validate slice indices are numbers
      if (expr.slice.start) {
        const startType = this.inferExpr(expr.slice.start);
        if (startType.kind !== "number" && startType.kind !== "any") {
          const err = TypeErrors.indexTypeMismatch("number", typeToString(startType));
          this.error(`Slice start index: ${err.message}`, expr.slice.start.loc, err.hint);
        }
      }
      if (expr.slice.end) {
        const endType = this.inferExpr(expr.slice.end);
        if (endType.kind !== "number" && endType.kind !== "any") {
          const err = TypeErrors.indexTypeMismatch("number", typeToString(endType));
          this.error(`Slice end index: ${err.message}`, expr.slice.end.loc, err.hint);
        }
      }
      return objectType;
    }

    const indexType = this.inferExpr(expr.index);

    if (objectType.kind === "list") {
      if (indexType.kind !== "number" && indexType.kind !== "any") {
        const err = TypeErrors.indexTypeMismatch("number", typeToString(indexType));
        this.error(`List index: ${err.message}`, expr.index.loc, err.hint);
      }
      return objectType.elementType;
    }
    if (objectType.kind === "map") {
      if (!this.isAssignable(indexType, objectType.keyType)) {
        const err = TypeErrors.indexTypeMismatch(typeToString(objectType.keyType), typeToString(indexType));
        this.error(`Map key: ${err.message}`, expr.index.loc, err.hint);
      }
      return Types.optional(objectType.valueType);
    }
    if (objectType.kind === "string") {
      if (indexType.kind !== "number" && indexType.kind !== "any") {
        const err = TypeErrors.indexTypeMismatch("number", typeToString(indexType));
        this.error(`String index: ${err.message}`, expr.index.loc, err.hint);
      }
      return Types.string;
    }

    return Types.any;
  }

  private inferMemberExpr(expr: AST.MemberExpr): Type {
    const objectType = this.inferExpr(expr.object);
    const resolved = this.env.resolveType(objectType);

    if (resolved.kind === "object") {
      // Look for property
      const prop = resolved.properties.find(p => p.name === expr.property);
      if (prop) {
        return expr.optional ? Types.optional(prop.type) : prop.type;
      }
      // Look for method
      const method = resolved.methods.find(m => m.name === expr.property);
      if (method) {
        return method.type;
      }
      // Error for named types with unknown property
      if (resolved.name && !expr.optional) {
        const err = TypeErrors.propertyNotExist(expr.property, resolved.name);
        this.error(err.message, expr.loc, err.hint);
      }
    }

    // Built-in properties
    if (expr.property === "length") {
      if (objectType.kind === "string" || objectType.kind === "list") {
        return Types.number;
      }
    }

    // String methods
    if (objectType.kind === "string") {
      switch (expr.property) {
        case "upper":
        case "lower":
        case "trim":
        case "trim_start":
        case "trim_end":
          return Types.fn([], Types.string);
        case "split":
          return Types.fn([Types.param("sep", Types.string)], Types.list(Types.string));
        case "contains":
        case "starts_with":
        case "ends_with":
          return Types.fn([Types.param("s", Types.string)], Types.bool);
        case "replace":
          return Types.fn([Types.param("from", Types.string), Types.param("to", Types.string)], Types.string);
        case "slice":
          return Types.fn([Types.param("start", Types.number), Types.param("end", Types.number, true)], Types.string);
        case "char_at":
          return Types.fn([Types.param("index", Types.number)], Types.optional(Types.string));
        case "index_of":
          return Types.fn([Types.param("s", Types.string)], Types.optional(Types.number));
        case "repeat":
          return Types.fn([Types.param("n", Types.number)], Types.string);
        case "pad_start":
        case "pad_end":
          return Types.fn([Types.param("len", Types.number), Types.param("char", Types.string, true)], Types.string);
        case "chars":
          return Types.fn([], Types.list(Types.string));
      }
    }

    // List methods
    if (objectType.kind === "list") {
      switch (expr.property) {
        case "push":
          return Types.fn([Types.param("item", objectType.elementType)], objectType);
        case "insert":
          return Types.fn([Types.param("index", Types.number), Types.param("item", objectType.elementType)], Types.void);
        case "pop":
        case "shift":
          return Types.fn([], Types.optional(objectType.elementType));
        case "remove":
          return Types.fn([Types.param("index", Types.number)], objectType.elementType);
        case "clear":
          return Types.fn([], Types.void);
        case "index_of":
          return Types.fn([Types.param("item", objectType.elementType)], Types.optional(Types.number));
        case "contains":
          return Types.fn([Types.param("item", objectType.elementType)], Types.bool);
        case "join":
          return Types.fn([Types.param("sep", Types.string, true)], Types.string);
        case "reverse":
          return Types.fn([], objectType);
        case "sort":
          return Types.fn([Types.param("cmp", Types.fn([Types.param("a", objectType.elementType), Types.param("b", objectType.elementType)], Types.number), true)], objectType);
        case "slice":
          return Types.fn([Types.param("start", Types.number), Types.param("end", Types.number, true)], objectType);
        case "map":
          return Types.fn([Types.param("f", Types.fn([Types.param("x", objectType.elementType)], Types.any))], Types.list(Types.any));
        case "filter":
          return Types.fn([Types.param("f", Types.fn([Types.param("x", objectType.elementType)], Types.bool))], objectType);
        case "reduce":
          return Types.fn([Types.param("f", Types.fn([Types.param("acc", Types.any), Types.param("x", objectType.elementType)], Types.any)), Types.param("init", Types.any)], Types.any);
        case "find":
          return Types.fn([Types.param("f", Types.fn([Types.param("x", objectType.elementType)], Types.bool))], Types.optional(objectType.elementType));
        case "every":
        case "some":
          return Types.fn([Types.param("f", Types.fn([Types.param("x", objectType.elementType)], Types.bool))], Types.bool);
        case "flat":
          return Types.fn([], Types.list(Types.any));
        case "first":
        case "last":
          return Types.fn([], Types.optional(objectType.elementType));
        case "is_empty":
          return Types.fn([], Types.bool);
      }
    }

    // Map methods
    if (objectType.kind === "map") {
      switch (expr.property) {
        case "get":
          return Types.fn([Types.param("key", objectType.keyType)], Types.optional(objectType.valueType));
        case "set":
          return Types.fn([Types.param("key", objectType.keyType), Types.param("value", objectType.valueType)], Types.void);
        case "has":
          return Types.fn([Types.param("key", objectType.keyType)], Types.bool);
        case "delete":
          return Types.fn([Types.param("key", objectType.keyType)], Types.bool);
        case "keys":
          return Types.fn([], Types.list(objectType.keyType));
        case "values":
          return Types.fn([], Types.list(objectType.valueType));
        case "entries":
          return Types.fn([], Types.list(Types.tuple(objectType.keyType, objectType.valueType)));
        case "clear":
          return Types.fn([], Types.void);
        case "size":
          return Types.number;
      }
    }

    // Set methods
    if (objectType.kind === "set") {
      switch (expr.property) {
        case "add":
          return Types.fn([Types.param("item", objectType.elementType)], Types.void);
        case "has":
          return Types.fn([Types.param("item", objectType.elementType)], Types.bool);
        case "delete":
          return Types.fn([Types.param("item", objectType.elementType)], Types.bool);
        case "clear":
          return Types.fn([], Types.void);
        case "size":
          return Types.number;
        case "values":
          return Types.fn([], Types.list(objectType.elementType));
      }
    }

    // Channel methods
    if (objectType.kind === "channel") {
      switch (expr.property) {
        case "send":
          return Types.fn([Types.param("value", objectType.elementType)], Types.promise(Types.void));
        case "receive":
          return Types.fn([], Types.promise(Types.optional(objectType.elementType)));
        case "close":
          return Types.fn([], Types.void);
        case "isClosed":
          return Types.fn([], Types.bool);
        case "try_send":
          return Types.fn([Types.param("value", objectType.elementType)], Types.bool);
        case "try_receive":
          return Types.fn([], Types.optional(objectType.elementType));
      }
    }

    if (expr.optional) {
      return Types.optional(Types.any);
    }

    return Types.any;
  }

  private inferPipeExpr(expr: AST.PipeExpr): Type {
    const leftType = this.inferExpr(expr.left);
    const rightType = this.inferExpr(expr.right);

    // Pipe passes left as first argument to right
    if (rightType.kind === "function") {
      return rightType.returnType;
    }

    return Types.any;
  }

  private inferLambdaExpr(expr: AST.LambdaExpr): Type {
    const params = expr.params.map(p => ({
      name: p.name,
      type: p.type ? this.astTypeToType(p.type) : Types.any,
      optional: p.optional,
      rest: p.rest,
    }));

    const lambdaEnv = this.env.child();
    for (const param of params) {
      lambdaEnv.define(param.name, param.type);
    }

    const savedEnv = this.env;
    this.env = lambdaEnv;

    let returnType: Type;
    if (expr.body.kind === "Block") {
      this.checkBlock(expr.body as AST.Block);
      returnType = Types.void;  // TODO: Infer from return statements
    } else {
      returnType = this.inferExpr(expr.body as AST.Expr);
    }

    this.env = savedEnv;

    return Types.fn(params, returnType);
  }

  private inferIfExpr(expr: AST.IfExpr): Type {
    this.inferExpr(expr.condition);
    const thenType = this.inferExpr(expr.then);
    const elseType = this.inferExpr(expr.else);

    // Union of both branches
    if (this.isAssignable(thenType, elseType)) {
      return elseType;
    }
    if (this.isAssignable(elseType, thenType)) {
      return thenType;
    }
    return Types.union(thenType, elseType);
  }

  private inferMatchExpr(expr: AST.MatchExpr): Type {
    const valueType = this.inferExpr(expr.value);
    const armTypes: Type[] = [];

    for (const arm of expr.arms) {
      const armEnv = this.env.child();
      const savedEnv = this.env;
      this.env = armEnv;

      this.checkPattern(arm.pattern, valueType);
      if (arm.guard) {
        this.inferExpr(arm.guard);
      }

      let armType: Type;
      if (arm.body.kind === "Block") {
        this.checkBlock(arm.body as AST.Block);
        armType = Types.void;
      } else {
        armType = this.inferExpr(arm.body as AST.Expr);
      }
      armTypes.push(armType);

      this.env = savedEnv;
    }

    // Check exhaustiveness for match expressions
    this.checkMatchExhaustiveness(valueType, expr.arms, expr.loc);

    // Return union of all arm types
    if (armTypes.length === 0) return Types.never;
    if (armTypes.length === 1) return armTypes[0]!;
    return Types.union(...armTypes);
  }

  private inferListExpr(expr: AST.ListExpr): Type {
    if (expr.elements.length === 0) {
      return Types.list(Types.any);
    }

    const elementTypes: Type[] = [];
    for (const el of expr.elements) {
      if (el.kind === "SpreadElement") {
        const spreadType = this.inferExpr(el.expr);
        if (spreadType.kind === "list") {
          elementTypes.push(spreadType.elementType);
        }
        // Consume spawn variable if spread
        if (el.expr.kind === "Identifier") {
          this.unawaitedSpawns.delete(el.expr.name);
        }
      } else {
        elementTypes.push(this.inferExpr(el));
        // Consume spawn variables when placed into a list (list takes ownership)
        if (el.kind === "Identifier") {
          this.unawaitedSpawns.delete(el.name);
        }
      }
    }

    // Find common type
    const commonType = this.findCommonType(elementTypes);
    return Types.list(commonType);
  }

  private inferMapExpr(expr: AST.MapExpr): Type {
    if (expr.entries.length === 0) {
      return Types.map(Types.string, Types.any);
    }

    const keyTypes: Type[] = [];
    const valueTypes: Type[] = [];

    for (const entry of expr.entries) {
      if (!entry.spread) {
        // For identifier keys (like {a: 1}), treat them as string literals
        if (entry.key.kind === "Identifier") {
          keyTypes.push(Types.string);
        } else {
          keyTypes.push(this.inferExpr(entry.key));
        }
        valueTypes.push(this.inferExpr(entry.value));
      }
    }

    const keyType = this.findCommonType(keyTypes);
    const valueType = this.findCommonType(valueTypes);

    return Types.map(keyType, valueType);
  }

  private inferSpawnExpr(expr: AST.SpawnExpr): Type {
    // Check for spawn inside function-level with - this is dangerous
    if (this.functionWithDepth > 0) {
      this.error(
        `Cannot use 'spawn' inside function-level 'with' block - spawned task may outlive context scope`,
        expr.loc,
        `Move spawn outside the 'with' block or use top-level 'with' instead`
      );
    }
    
    const innerType = this.inferExpr(expr.expr);
    return Types.promise(innerType.kind === "function" ? (innerType as FunctionType).returnType : innerType);
  }

  // Mark spawn variables as consumed when passed to race/all
  private markSpawnsConsumed(args: (AST.Expr | { name: string; value: AST.Expr })[]): void {
    for (const arg of args) {
      const expr = "kind" in arg ? arg : arg.value;
      this.consumeSpawnsInExpr(expr);
    }
  }

  // Recursively consume all tracked spawns in an expression
  private consumeSpawnsInExpr(expr: AST.Expr): void {
    switch (expr.kind) {
      case "Identifier":
        this.unawaitedSpawns.delete(expr.name);
        break;
      case "ListExpr":
        for (const el of expr.elements) {
          if (el.kind !== "SpreadElement") {
            this.consumeSpawnsInExpr(el);
          } else {
            this.consumeSpawnsInExpr(el.expr);
          }
        }
        break;
      case "MapExpr":
        for (const entry of expr.entries) {
          this.consumeSpawnsInExpr(entry.value);
        }
        break;
      case "IfExpr":
        this.consumeSpawnsInExpr(expr.then);
        if (expr.else) this.consumeSpawnsInExpr(expr.else);
        break;
      case "IndexExpr":
        this.consumeSpawnsInExpr(expr.object);
        break;
      case "MemberExpr":
        this.consumeSpawnsInExpr(expr.object);
        break;
      case "CallExpr":
        // For race(values(x)), consume spawns if:
        // 1. Inner call returns Promise-related types
        // 2. Inner call is 'values' (extracts map values which may contain spawns)
        const callReturnType = this.inferExpr(expr);
        const isValuesCall = expr.callee.kind === "Identifier" && expr.callee.name === "values";
        if (this.typeInvolvesPromise(callReturnType) || isValuesCall) {
          for (const arg of expr.args) {
            const argExpr = "kind" in arg ? arg : arg.value;
            this.consumeSpawnsInExpr(argExpr);
          }
        }
        break;
    }
  }

  // Check if an expression contains spawn-derived values
  private exprContainsSpawn(expr: AST.Expr, exprType: Type): boolean {
    // Direct spawn
    if (expr.kind === "SpawnExpr") return true;
    
    // Tracked variable
    if (expr.kind === "Identifier" && this.unawaitedSpawns.has(expr.name)) return true;
    
    // Check if any call argument contains spawn (for object instantiation)
    if (expr.kind === "CallExpr") {
      for (const arg of expr.args) {
        const argExpr = "kind" in arg ? arg : arg.value;
        if (this.exprContainsSpawn(argExpr, this.inferExpr(argExpr))) return true;
      }
    }
    
    // List containing spawns
    if (expr.kind === "ListExpr") {
      for (const el of expr.elements) {
        if (el.kind === "SpreadElement") {
          if (this.exprContainsSpawn(el.expr, this.inferExpr(el.expr))) return true;
        } else if (this.exprContainsSpawn(el, this.inferExpr(el))) {
          return true;
        }
      }
    }
    
    // Map containing spawns
    if (expr.kind === "MapExpr") {
      for (const entry of expr.entries) {
        if (this.exprContainsSpawn(entry.value, this.inferExpr(entry.value))) return true;
      }
    }
    
    // Index/member access on tracked container
    if (expr.kind === "IndexExpr" && expr.object.kind === "Identifier") {
      if (this.unawaitedSpawns.has(expr.object.name)) return true;
    }
    if (expr.kind === "MemberExpr" && expr.object.kind === "Identifier") {
      if (this.unawaitedSpawns.has(expr.object.name)) return true;
    }
    
    // Conditional with spawns
    if (expr.kind === "IfExpr") {
      if (this.exprContainsSpawn(expr.then, this.inferExpr(expr.then))) return true;
      if (expr.else && this.exprContainsSpawn(expr.else, this.inferExpr(expr.else))) return true;
    }
    
    return false;
  }

  // Transfer tracking from source variables when reassigning
  private transferSpawnTracking(expr: AST.Expr): void {
    if (expr.kind === "Identifier") {
      this.unawaitedSpawns.delete(expr.name);
    } else if (expr.kind === "IfExpr") {
      if (expr.then.kind === "Identifier") this.unawaitedSpawns.delete(expr.then.name);
      if (expr.else?.kind === "Identifier") this.unawaitedSpawns.delete(expr.else.name);
    } else if (expr.kind === "ListExpr") {
      for (const el of expr.elements) {
        if (el.kind === "Identifier") this.unawaitedSpawns.delete(el.name);
        else if (el.kind === "SpreadElement" && el.expr.kind === "Identifier") {
          this.unawaitedSpawns.delete(el.expr.name);
        }
      }
    } else if (expr.kind === "MapExpr") {
      for (const entry of expr.entries) {
        if (entry.value.kind === "Identifier") this.unawaitedSpawns.delete(entry.value.name);
      }
    } else if (expr.kind === "CallExpr") {
      // Transfer from arguments (for object instantiation with spawn props)
      for (const arg of expr.args) {
        const argExpr = "kind" in arg ? arg : arg.value;
        this.transferSpawnTracking(argExpr);
      }
    }
  }

  // ============================================
  // Pattern Checking
  // ============================================

  private checkPattern(pattern: AST.Pattern, expectedType: Type): void {
    switch (pattern.kind) {
      case "IdentifierPattern":
        this.env.define(pattern.name, expectedType);
        break;
      case "LiteralPattern":
        // Check literal is compatible with expected type
        break;
      case "ObjectPattern":
        if (expectedType.kind === "object") {
          for (const prop of pattern.properties) {
            const propType = expectedType.properties.find(p => p.name === prop.key);
            if (propType) {
              this.checkPattern(prop.pattern, propType.type);
            }
          }
        }
        break;
      case "ArrayPattern":
        if (expectedType.kind === "list" || expectedType.kind === "tuple") {
          const elementType = expectedType.kind === "list"
            ? expectedType.elementType
            : Types.union(...expectedType.elements);
          for (const el of pattern.elements) {
            this.checkPattern(el, elementType);
          }
        }
        break;
      case "RestPattern":
        if (expectedType.kind === "list") {
          this.env.define(pattern.name, expectedType);
        }
        break;
      case "TypePattern":
        if (pattern.binding) {
          const narrowedType = this.astTypeToType(pattern.type);
          this.env.define(pattern.binding, narrowedType);
        }
        break;
      case "RangePattern":
      case "WildcardPattern":
        // No bindings
        break;
    }
  }

  private bindPattern(pattern: AST.Pattern, type: Type, mutable: boolean): void {
    switch (pattern.kind) {
      case "IdentifierPattern":
        try {
          this.env.define(pattern.name, type, mutable);
        } catch (e) {
          const err = TypeErrors.variableAlreadyDefined(pattern.name);
          this.error(err.message, pattern.loc, err.hint);
        }
        break;
      case "ObjectPattern":
        if (type.kind === "object") {
          for (const prop of pattern.properties) {
            const propType = type.properties.find(p => p.name === prop.key);
            this.bindPattern(prop.pattern, propType?.type ?? Types.any, mutable);
          }
        } else {
          for (const prop of pattern.properties) {
            this.bindPattern(prop.pattern, Types.any, mutable);
          }
        }
        break;
      case "ArrayPattern":
        const elementType = type.kind === "list" ? type.elementType : Types.any;
        for (const el of pattern.elements) {
          this.bindPattern(el, elementType, mutable);
        }
        break;
      case "RestPattern":
        this.env.define(pattern.name, type.kind === "list" ? type : Types.list(Types.any), mutable);
        break;
    }
  }

  // ============================================
  // Type Helpers
  // ============================================

  private astTypeToType(astType: AST.TypeExpr): Type {
    switch (astType.kind) {
      case "NamedType": {
        // Handle primitive types directly
        switch (astType.name) {
          case "number": return Types.number;
          case "string": return Types.string;
          case "bool": return Types.bool;
          case "null": return Types.null;
          case "bytes": return Types.bytes;
          case "any": return Types.any;
          case "never": return Types.never;
          case "void": return Types.void;
          // Handle collection types without parameters as having 'any' element types
          case "list": return Types.list(Types.any);
          case "map": return Types.map(Types.any, Types.any);
          case "set": return Types.set(Types.any);
          default: return Types.ref(astType.name);
        }
      }
      case "GenericType": {
        // Handle built-in generic types
        switch (astType.name) {
          case "list":
            return Types.list(this.astTypeToType(astType.args[0]!));
          case "map":
            return Types.map(this.astTypeToType(astType.args[0]!), this.astTypeToType(astType.args[1]!));
          case "set":
            return Types.set(this.astTypeToType(astType.args[0]!));
          case "Channel":
            return Types.channel(this.astTypeToType(astType.args[0]!));
          case "Promise":
            return Types.promise(this.astTypeToType(astType.args[0]!));
          case "Stream":
            return Types.stream(this.astTypeToType(astType.args[0]!));
          case "Result":
            return Types.result(this.astTypeToType(astType.args[0]!), this.astTypeToType(astType.args[1]!));
          default:
            return Types.generic(Types.ref(astType.name), astType.args.map(a => this.astTypeToType(a)));
        }
      }
      case "FunctionType":
        return Types.fn(
          astType.params.map((p, i) => Types.param(`arg${i}`, this.astTypeToType(p))),
          this.astTypeToType(astType.returnType)
        );
      case "UnionType":
        return Types.union(...astType.types.map(t => this.astTypeToType(t)));
      case "OptionalType":
        return Types.optional(this.astTypeToType(astType.inner));
      case "ListType":
        return Types.list(this.astTypeToType(astType.elementType));
      case "MapType":
        return Types.map(this.astTypeToType(astType.keyType), this.astTypeToType(astType.valueType));
      default:
        return Types.any;
    }
  }

  // Resolve a type name string to a Type (for generic type arguments parsed as identifiers)
  private resolveTypeName(name: string): Type {
    switch (name) {
      case "number": return Types.number;
      case "string": return Types.string;
      case "bool": return Types.bool;
      case "null": return Types.null;
      case "any": return Types.any;
      case "void": return Types.void;
      default:
        // Check if it's a declared type
        const resolved = this.env.lookup(name);
        if (resolved) return resolved;
        // Return as a type reference for user-defined types
        return Types.ref(name);
    }
  }

  private fnDeclToType(decl: AST.FnDecl): FunctionType {
    const params = decl.params.map(p => ({
      name: p.name,
      type: p.type ? this.astTypeToType(p.type) : Types.any,
      optional: p.optional,
      rest: p.rest,
    }));

    const returnType = decl.returnType ? this.astTypeToType(decl.returnType) : Types.any;

    const context: ContextBinding[] = decl.using?.bindings.map(c => ({
      name: c.name,
      type: this.astTypeToType(c.type),
    })) ?? [];

    return {
      kind: "function",
      params,
      returnType,
      isGenerator: decl.isGenerator,
      context,
    };
  }

  private methodToFunctionType(method: AST.MethodDecl): FunctionType {
    const params = method.params.map(p => ({
      name: p.name,
      type: p.type ? this.astTypeToType(p.type) : Types.any,
      optional: p.optional,
      rest: p.rest,
    }));

    const returnType = method.returnType ? this.astTypeToType(method.returnType) : Types.any;

    const context: ContextBinding[] = method.using?.bindings.map(c => ({
      name: c.name,
      type: this.astTypeToType(c.type),
    })) ?? [];

    return {
      kind: "function",
      params,
      returnType,
      isGenerator: false,
      context,
    };
  }

  // Check if a type involves Promise (is Promise, contains Promise, or has Promise properties)
  private typeInvolvesPromise(t: Type, visited: Set<string> = new Set()): boolean {
    if (t.kind === "promise") return true;
    if (t.kind === "list") return this.typeInvolvesPromise((t as any).elementType, visited);
    if (t.kind === "map") return this.typeInvolvesPromise((t as any).valueType, visited);
    if (t.kind === "optional") return this.typeInvolvesPromise((t as any).inner, visited);
    // Check object properties for nested Promises
    if (t.kind === "object") {
      const objType = t as any;
      // Prevent infinite recursion for recursive types
      if (objType.name && visited.has(objType.name)) return false;
      if (objType.name) visited.add(objType.name);
      for (const prop of objType.properties || []) {
        if (this.typeInvolvesPromise(prop.type, visited)) return true;
      }
    }
    // Check type references
    if (t.kind === "ref") {
      const resolved = this.env.resolveType(t);
      if (resolved && resolved !== t) {
        return this.typeInvolvesPromise(resolved, visited);
      }
    }
    return false;
  }

  private isAssignable(source: Type, target: Type): boolean {
    // Any is assignable to/from anything
    if (source.kind === "any" || target.kind === "any") return true;

    // Resolve type references
    const resolvedSource = source.kind === "ref" ? this.env.resolveType(source) : source;
    const resolvedTarget = target.kind === "ref" ? this.env.resolveType(target) : target;

    // Same primitive types
    if (resolvedSource.kind === resolvedTarget.kind) {
      switch (resolvedSource.kind) {
        case "number":
        case "string":
        case "bool":
        case "null":
        case "bytes":
        case "void":
        case "never":
          return true;
        case "ref":
          return (resolvedSource as any).name === (resolvedTarget as any).name;
        case "list":
          // list[T] is assignable to list[any]
          if ((resolvedTarget as any).elementType.kind === "any") return true;
          return this.isAssignable((resolvedSource as any).elementType, (resolvedTarget as any).elementType);
        case "map":
          // map[K, V] is assignable to map[any, any]
          if ((resolvedTarget as any).keyType.kind === "any" && (resolvedTarget as any).valueType.kind === "any") return true;
          return this.isAssignable((resolvedSource as any).keyType, (resolvedTarget as any).keyType) &&
                 this.isAssignable((resolvedSource as any).valueType, (resolvedTarget as any).valueType);
        case "channel":
          // Channel[T] is assignable to Channel[any]
          if ((resolvedTarget as any).elementType.kind === "any") return true;
          return this.isAssignable((resolvedSource as any).elementType, (resolvedTarget as any).elementType);
        case "promise":
          // Promise[T] is assignable to Promise[any]
          if ((resolvedTarget as any).resolveType.kind === "any") return true;
          return this.isAssignable((resolvedSource as any).resolveType, (resolvedTarget as any).resolveType);
        case "set":
          // Set[T] is assignable to Set[any]
          if ((resolvedTarget as any).elementType.kind === "any") return true;
          return this.isAssignable((resolvedSource as any).elementType, (resolvedTarget as any).elementType);
        case "stream":
          // Stream[T] is assignable to Stream[any]
          if ((resolvedTarget as any).elementType.kind === "any") return true;
          return this.isAssignable((resolvedSource as any).elementType, (resolvedTarget as any).elementType);
        case "object":
          // Same named type or structural compatibility
          if ((resolvedSource as any).name && (resolvedTarget as any).name) {
            return (resolvedSource as any).name === (resolvedTarget as any).name;
          }
          return true; // Structural compatibility TODO
        default:
          return true;
      }
    }

    // Null is assignable to optional
    if (resolvedSource.kind === "null" && resolvedTarget.kind === "optional") return true;

    // T is assignable to T?
    if (resolvedTarget.kind === "optional") {
      // T | null is assignable to T? (union with null is equivalent to optional)
      if (resolvedSource.kind === "union") {
        const unionTypes = (resolvedSource as any).types as Type[];
        const nonNullTypes = unionTypes.filter((t: Type) => t.kind !== "null");
        // If the union is T | null, check that T is assignable to the optional's inner type
        if (nonNullTypes.length === unionTypes.length - 1) {
          return nonNullTypes.every((t: Type) => this.isAssignable(t, (resolvedTarget as any).inner));
        }
      }
      return this.isAssignable(resolvedSource, (resolvedTarget as any).inner);
    }

    // T is assignable to T | U
    if (resolvedTarget.kind === "union") {
      return (resolvedTarget as any).types.some((t: Type) => this.isAssignable(resolvedSource, t));
    }

    // T | U is assignable to T (if all members are assignable)
    if (resolvedSource.kind === "union") {
      return (resolvedSource as any).types.every((t: Type) => this.isAssignable(t, resolvedTarget));
    }

    return false;
  }

  /**
   * Check if a type extends a base type (by name)
   * Used for checking that context types extend Context
   */
  private extendsType(type: Type, baseName: string): boolean {
    const resolved = type.kind === "ref" ? this.env.resolveType(type) : type;
    
    // Check if it's the base type itself
    if (resolved.kind === "object" && resolved.name === baseName) {
      return true;
    }
    
    // Check extends clause
    if (resolved.kind === "object" && resolved.extends) {
      for (const parent of resolved.extends) {
        if (this.extendsType(parent, baseName)) {
          return true;
        }
      }
    }
    
    return false;
  }

  /**
   * Validate that all types in a using clause extend Context
   */
  private validateUsingClause(using: AST.UsingClause): void {
    for (const binding of using.bindings) {
      const bindingType = this.astTypeToType(binding.type);
      if (!this.extendsType(bindingType, "Context")) {
        const typeName = binding.type.kind === "NamedType" ? binding.type.name : "unknown";
        this.error(
          `Type '${typeName}' used in 'using' clause must extend Context`,
          binding.loc,
          `Add 'extends Context' to the type definition`
        );
      }
    }
  }

  /**
   * Validate that a method override has the same signature as the base method
   */
  private validateMethodOverride(
    typeName: string,
    methodName: string,
    methodType: FunctionType,
    extendsTypes: AST.TypeExpr[],
    loc: AST.SourceLocation
  ): void {
    for (const extendExpr of extendsTypes) {
      const baseTypeName = extendExpr.kind === "NamedType" ? extendExpr.name : null;
      if (!baseTypeName) continue;
      
      const baseType = this.env.lookupType(baseTypeName);
      if (!baseType || baseType.kind !== "object") continue;
      
      const baseMethod = baseType.methods.find(m => m.name === methodName);
      if (!baseMethod) continue;
      
      // Check parameter count and types
      if (!this.paramsMatch(methodType.params, baseMethod.type.params)) {
        const err = TypeErrors.methodOverrideParamMismatch(methodName, typeName, baseTypeName);
        this.error(err.message, loc, err.hint);
        return;
      }
      
      // Check return type
      if (!this.typesEqual(methodType.returnType, baseMethod.type.returnType)) {
        const err = TypeErrors.methodOverrideReturnMismatch(
          methodName, typeName, baseTypeName,
          typeToString(baseMethod.type.returnType),
          typeToString(methodType.returnType)
        );
        this.error(err.message, loc, err.hint);
        return;
      }
      
      // Check using clause (context bindings)
      if (!this.contextMatch(methodType.context, baseMethod.type.context)) {
        const err = TypeErrors.methodOverrideUsingMismatch(methodName, typeName, baseTypeName);
        this.error(err.message, loc, err.hint);
        return;
      }
    }
  }

  /**
   * Check if two parameter lists match exactly
   */
  private paramsMatch(a: ParameterType[], b: ParameterType[]): boolean {
    if (a.length !== b.length) return false;
    for (let i = 0; i < a.length; i++) {
      const pa = a[i]!, pb = b[i]!;
      if (pa.optional !== pb.optional) return false;
      if (pa.rest !== pb.rest) return false;
      if (!this.typesEqual(pa.type, pb.type)) return false;
    }
    return true;
  }

  /**
   * Check if two context binding lists match exactly
   */
  private contextMatch(a: ContextBinding[], b: ContextBinding[]): boolean {
    if (a.length !== b.length) return false;
    for (let i = 0; i < a.length; i++) {
      const ca = a[i]!, cb = b[i]!;
      if (!this.typesEqual(ca.type, cb.type)) return false;
    }
    return true;
  }

  /**
   * Check if two types are structurally equal
   */
  private typesEqual(a: Type, b: Type): boolean {
    if (a.kind !== b.kind) return false;
    
    switch (a.kind) {
      case "number":
      case "string":
      case "bool":
      case "null":
      case "bytes":
      case "void":
      case "any":
      case "never":
        return true;
      case "ref":
        return (a as any).name === (b as any).name;
      case "list":
        return this.typesEqual((a as any).elementType, (b as any).elementType);
      case "map":
        return this.typesEqual((a as any).keyType, (b as any).keyType) &&
               this.typesEqual((a as any).valueType, (b as any).valueType);
      case "optional":
        return this.typesEqual((a as any).inner, (b as any).inner);
      case "function":
        const fa = a as FunctionType, fb = b as FunctionType;
        return this.paramsMatch(fa.params, fb.params) &&
               this.typesEqual(fa.returnType, fb.returnType) &&
               this.contextMatch(fa.context, fb.context);
      default:
        return typeToString(a) === typeToString(b);
    }
  }

  private getIterableElementType(type: Type): Type {
    if (type.kind === "list") return type.elementType;
    if (type.kind === "set") return type.elementType;
    if (type.kind === "string") return Types.string;
    if (type.kind === "map") return Types.tuple(type.keyType, type.valueType);
    if (type.kind === "stream") return type.elementType;
    if (type.kind === "channel") return type.elementType;
    return Types.any;
  }

  private findCommonType(types: Type[]): Type {
    if (types.length === 0) return Types.any;
    if (types.length === 1) return types[0]!;

    // Check if all types are the same
    const first = types[0]!;
    if (types.every(t => t.kind === first.kind)) {
      return first;
    }

    // Return union
    return Types.union(...types);
  }

  // ============================================
  // Context Escape Analysis
  // ============================================

  /**
   * Check if a function needs context (has using clause or calls functions that do)
   */
  private functionNeedsContext(fnName: string): boolean {
    // Check cache first
    if (this.needsContextCache.has(fnName)) {
      return this.needsContextCache.get(fnName)!;
    }
    
    // Prevent infinite recursion
    this.needsContextCache.set(fnName, false);
    
    // Check if function has using clause
    const symbol = this.env.lookup(fnName);
    if (symbol?.type.kind === "function" && (symbol.type as FunctionType).context.length > 0) {
      this.needsContextCache.set(fnName, true);
      return true;
    }
    
    // Check if function body calls any function that needs context
    const fnDecl = this.fnDecls.get(fnName);
    if (fnDecl?.body) {
      if (this.blockNeedsContext(fnDecl.body)) {
        this.needsContextCache.set(fnName, true);
        return true;
      }
    }
    
    return false;
  }

  private blockNeedsContext(block: AST.Block): boolean {
    for (const stmt of block.statements) {
      if (this.stmtNeedsContext(stmt)) return true;
    }
    return false;
  }

  private stmtNeedsContext(stmt: AST.Statement): boolean {
    switch (stmt.kind) {
      case "ExprStmt":
        return this.exprNeedsContext(stmt.expr);
      case "LetStmt":
      case "VarStmt":
        return this.exprNeedsContext(stmt.value);
      case "AssignStmt":
        return this.exprNeedsContext(stmt.value);
      case "IfStmt": {
        const thenNeedsCtx = stmt.then.kind === "Block" 
          ? this.blockNeedsContext(stmt.then) 
          : this.stmtNeedsContext(stmt.then);
        const elseNeedsCtx = stmt.else ? this.blockNeedsContext(stmt.else) : false;
        return this.exprNeedsContext(stmt.condition) || thenNeedsCtx || elseNeedsCtx;
      }
      case "ForStmt":
        return (stmt.iterable ? this.exprNeedsContext(stmt.iterable) : false) || 
          this.blockNeedsContext(stmt.body);
      case "ReturnStmt":
        return stmt.value ? this.exprNeedsContext(stmt.value) : false;
      case "WithStmt":
        return this.blockNeedsContext(stmt.body);
      default:
        return false;
    }
  }

  private exprNeedsContext(expr: AST.Expr): boolean {
    switch (expr.kind) {
      case "CallExpr":
        // Check if callee is a function that needs context
        if (expr.callee.kind === "Identifier") {
          if (this.functionNeedsContext(expr.callee.name)) return true;
        }
        // Check arguments
        for (const arg of expr.args) {
          const argExpr = "kind" in arg ? arg : arg.value;
          if (this.exprNeedsContext(argExpr)) return true;
        }
        return false;
      case "LambdaExpr":
        return this.lambdaNeedsContext(expr);
      case "BinaryExpr":
        return this.exprNeedsContext(expr.left) || this.exprNeedsContext(expr.right);
      case "UnaryExpr":
        return this.exprNeedsContext(expr.operand);
      case "IfExpr":
        return this.exprNeedsContext(expr.condition) ||
          this.exprNeedsContext(expr.then) ||
          this.exprNeedsContext(expr.else);
      case "ListExpr":
        return expr.elements.some(e => 
          e.kind === "SpreadElement" ? this.exprNeedsContext(e.expr) : this.exprNeedsContext(e)
        );
      case "MapExpr":
        return expr.entries.some(e => this.exprNeedsContext(e.value));
      case "MemberExpr":
        return this.exprNeedsContext(expr.object);
      case "IndexExpr":
        return this.exprNeedsContext(expr.object) || this.exprNeedsContext(expr.index);
      case "PipeExpr":
        return this.exprNeedsContext(expr.left) || this.exprNeedsContext(expr.right);
      default:
        return false;
    }
  }

  /**
   * Check if a lambda expression needs context
   */
  private lambdaNeedsContext(lambda: AST.LambdaExpr): boolean {
    if (lambda.body.kind === "Block") {
      return this.blockNeedsContext(lambda.body);
    } else {
      return this.exprNeedsContext(lambda.body);
    }
  }

  /**
   * Check if an expression contains a context-dependent lambda that would escape
   */
  private exprContainsEscapingLambda(expr: AST.Expr): boolean {
    switch (expr.kind) {
      case "LambdaExpr":
        return this.lambdaNeedsContext(expr);
      case "Identifier":
        // Check if this is a context variable
        return this.withContextVars.has(expr.name);
      case "ListExpr":
        return expr.elements.some(e =>
          e.kind === "SpreadElement" 
            ? this.exprContainsEscapingLambda(e.expr) 
            : this.exprContainsEscapingLambda(e)
        );
      case "MapExpr":
        return expr.entries.some(e => this.exprContainsEscapingLambda(e.value));
      case "IfExpr":
        return this.exprContainsEscapingLambda(expr.then) || 
          this.exprContainsEscapingLambda(expr.else);
      case "CallExpr":
        // Check if this is a type constructor with escaping lambdas
        for (const arg of expr.args) {
          const argExpr = "kind" in arg ? arg : arg.value;
          if (this.exprContainsEscapingLambda(argExpr)) return true;
        }
        return false;
      default:
        return false;
    }
  }

  /**
   * Check if a parameter escapes within a function body (is stored, returned, or passed to escaping fn)
   */
  private parameterEscapes(fnDecl: AST.FnDecl, paramName: string): boolean {
    if (!fnDecl.body) return true; // Extern functions: assume escapes
    return this.paramEscapesInBlock(fnDecl.body, paramName);
  }

  private paramEscapesInBlock(block: AST.Block, paramName: string): boolean {
    for (const stmt of block.statements) {
      if (this.paramEscapesInStmt(stmt, paramName)) return true;
    }
    return false;
  }

  private paramEscapesInStmt(stmt: AST.Statement, paramName: string): boolean {
    switch (stmt.kind) {
      case "ReturnStmt":
        // Returning the parameter means it escapes
        if (stmt.value && this.exprReferences(stmt.value, paramName)) return true;
        return false;
      case "LetStmt":
      case "VarStmt":
        // Assigning to a variable is OK as long as the variable doesn't escape
        // For simplicity, we allow this (the variable is local)
        return false;
      case "AssignStmt":
        // If assigning to something other than a local, it escapes
        // For now, assume member/index assignments escape
        if (stmt.target.kind !== "Identifier" && this.exprReferences(stmt.value, paramName)) {
          return true;
        }
        return false;
      case "ExprStmt":
        return this.paramEscapesInExpr(stmt.expr, paramName);
      case "IfStmt": {
        const thenEscapes = stmt.then.kind === "Block" 
          ? this.paramEscapesInBlock(stmt.then, paramName)
          : this.paramEscapesInStmt(stmt.then, paramName);
        const elseEscapes = stmt.else ? this.paramEscapesInBlock(stmt.else, paramName) : false;
        return thenEscapes || elseEscapes;
      }
      case "ForStmt":
        return this.paramEscapesInBlock(stmt.body, paramName);
      default:
        return false;
    }
  }

  private paramEscapesInExpr(expr: AST.Expr, paramName: string): boolean {
    switch (expr.kind) {
      case "CallExpr":
        // Check if parameter is passed to another function where it might escape
        for (let i = 0; i < expr.args.length; i++) {
          const arg = expr.args[i];
          const argExpr = arg && ("kind" in arg ? arg : arg.value);
          if (argExpr && this.exprReferences(argExpr, paramName)) {
            // Check if the callee function stores this parameter
            if (expr.callee.kind === "Identifier") {
              const calleeDecl = this.fnDecls.get(expr.callee.name);
              const calleeParam = calleeDecl?.params[i];
              if (calleeDecl && calleeParam) {
                const calleeParamName = calleeParam.name;
                if (this.parameterEscapes(calleeDecl, calleeParamName)) {
                  return true;
                }
              } else if (!calleeDecl) {
                // Extern function or unknown - assume escapes
                return true;
              }
            } else {
              // Complex callee - assume escapes
              return true;
            }
          }
        }
        // Check if callee itself references the param
        if (this.paramEscapesInExpr(expr.callee, paramName)) return true;
        return false;
      case "MemberExpr":
        // Method calls like list.push(param) - check if it's a storage method
        if (expr.property === "push" || expr.property === "unshift" || 
            expr.property === "set" || expr.property === "add") {
          // This is a storage operation - if param is in parent call args, it escapes
          return false; // The actual check happens at CallExpr level
        }
        return this.paramEscapesInExpr(expr.object, paramName);
      default:
        return false;
    }
  }

  private exprReferences(expr: AST.Expr, name: string): boolean {
    switch (expr.kind) {
      case "Identifier":
        return expr.name === name;
      case "CallExpr":
        if (this.exprReferences(expr.callee, name)) return true;
        for (const arg of expr.args) {
          const argExpr = "kind" in arg ? arg : arg.value;
          if (this.exprReferences(argExpr, name)) return true;
        }
        return false;
      case "LambdaExpr":
        // Lambda might capture the name
        if (expr.body.kind === "Block") {
          return this.blockReferences(expr.body as AST.Block, name);
        } else {
          return this.exprReferences(expr.body as AST.Expr, name);
        }
      case "BinaryExpr":
        return this.exprReferences(expr.left, name) || this.exprReferences(expr.right, name);
      case "UnaryExpr":
        return this.exprReferences(expr.operand, name);
      case "MemberExpr":
        return this.exprReferences(expr.object, name);
      case "IndexExpr":
        return this.exprReferences(expr.object, name) || this.exprReferences(expr.index, name);
      case "IfExpr":
        return this.exprReferences(expr.condition, name) ||
          this.exprReferences(expr.then, name) ||
          this.exprReferences(expr.else, name);
      case "ListExpr":
        return expr.elements.some(e =>
          e.kind === "SpreadElement" ? this.exprReferences(e.expr, name) : this.exprReferences(e, name)
        );
      case "MapExpr":
        return expr.entries.some(e => this.exprReferences(e.value, name));
      default:
        return false;
    }
  }

  private blockReferences(block: AST.Block, name: string): boolean {
    for (const stmt of block.statements) {
      if (this.stmtReferences(stmt, name)) return true;
    }
    return false;
  }

  private stmtReferences(stmt: AST.Statement, name: string): boolean {
    switch (stmt.kind) {
      case "ExprStmt":
        return this.exprReferences(stmt.expr, name);
      case "LetStmt":
      case "VarStmt":
        return this.exprReferences(stmt.value, name);
      case "AssignStmt":
        return this.exprReferences(stmt.value, name);
      case "ReturnStmt":
        return stmt.value ? this.exprReferences(stmt.value, name) : false;
      case "IfStmt": {
        const thenRefs = stmt.then.kind === "Block"
          ? this.blockReferences(stmt.then, name)
          : this.stmtReferences(stmt.then, name);
        const elseRefs = stmt.else ? this.blockReferences(stmt.else, name) : false;
        return this.exprReferences(stmt.condition, name) || thenRefs || elseRefs;
      }
      case "ForStmt":
        return (stmt.iterable ? this.exprReferences(stmt.iterable, name) : false) || 
          this.blockReferences(stmt.body, name);
      default:
        return false;
    }
  }

  // ============================================
  // Generic Type Inference
  // ============================================

  // Infer type parameters from actual arguments
  private inferTypeParams(fnType: FunctionType, args: (AST.Expr | AST.NamedArg)[]): Map<string, Type> {
    const bindings = new Map<string, Type>();
    if (!fnType.typeParams) return bindings;

    // Initialize all type params as unknown
    for (const tp of fnType.typeParams) {
      bindings.set(tp.name, Types.any);
    }

    // Infer from each argument
    for (let i = 0; i < args.length && i < fnType.params.length; i++) {
      const arg = args[i]!;
      const argExpr = "kind" in arg ? arg : arg.value;
      const argType = this.inferExpr(argExpr);
      const paramType = fnType.params[i]!.type;
      this.unifyTypes(paramType, argType, bindings);
    }

    return bindings;
  }

  // Unify parameter type with argument type to infer type variables
  private unifyTypes(paramType: Type, argType: Type, bindings: Map<string, Type>): void {
    // If param is a type variable, bind it
    if (paramType.kind === "typevar") {
      const existing = bindings.get(paramType.name);
      if (existing?.kind === "any") {
        bindings.set(paramType.name, argType);
      }
      return;
    }

    // If param is a type reference that matches a type param name, bind it
    if (paramType.kind === "ref" && bindings.has(paramType.name)) {
      const existing = bindings.get(paramType.name);
      if (existing?.kind === "any") {
        bindings.set(paramType.name, argType);
      }
      return;
    }

    // Recursively unify generic types
    if (paramType.kind === "list" && argType.kind === "list") {
      this.unifyTypes(paramType.elementType, argType.elementType, bindings);
    } else if (paramType.kind === "map" && argType.kind === "map") {
      this.unifyTypes(paramType.keyType, argType.keyType, bindings);
      this.unifyTypes(paramType.valueType, argType.valueType, bindings);
    } else if (paramType.kind === "set" && argType.kind === "set") {
      this.unifyTypes(paramType.elementType, argType.elementType, bindings);
    } else if (paramType.kind === "promise" && argType.kind === "promise") {
      this.unifyTypes(paramType.resolveType, argType.resolveType, bindings);
    } else if (paramType.kind === "channel" && argType.kind === "channel") {
      this.unifyTypes(paramType.elementType, argType.elementType, bindings);
    } else if (paramType.kind === "optional" && argType.kind === "optional") {
      this.unifyTypes(paramType.inner, argType.inner, bindings);
    } else if (paramType.kind === "function" && argType.kind === "function") {
      // Unify function parameter types and return type
      for (let i = 0; i < paramType.params.length && i < argType.params.length; i++) {
        this.unifyTypes(paramType.params[i]!.type, argType.params[i]!.type, bindings);
      }
      this.unifyTypes(paramType.returnType, argType.returnType, bindings);
    }
  }

  // Substitute type parameters in a type
  private substituteTypeParams(type: Type, bindings: Map<string, Type>): Type {
    if (bindings.size === 0) return type;

    switch (type.kind) {
      case "typevar": {
        const bound = bindings.get(type.name);
        return bound ?? type;
      }
      case "ref": {
        const bound = bindings.get(type.name);
        return bound ?? type;
      }
      case "list":
        return Types.list(this.substituteTypeParams(type.elementType, bindings));
      case "map":
        return Types.map(
          this.substituteTypeParams(type.keyType, bindings),
          this.substituteTypeParams(type.valueType, bindings)
        );
      case "set":
        return Types.set(this.substituteTypeParams(type.elementType, bindings));
      case "promise":
        return Types.promise(this.substituteTypeParams(type.resolveType, bindings));
      case "channel":
        return Types.channel(this.substituteTypeParams(type.elementType, bindings));
      case "optional":
        return Types.optional(this.substituteTypeParams(type.inner, bindings));
      case "function":
        return Types.fn(
          type.params.map(p => Types.param(
            p.name,
            this.substituteTypeParams(p.type, bindings),
            p.optional,
            p.rest
          )),
          this.substituteTypeParams(type.returnType, bindings)
        );
      default:
        return type;
    }
  }

  // ============================================
  // Error Reporting
  // ============================================

  private error(message: string, loc: AST.SourceLocation, hint?: string): void {
    this.errors.push(new TypeCheckError(message, loc, hint));
  }

  private warning(message: string): void {
    this.warnings.push(message);
  }
}
