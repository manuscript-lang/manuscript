// Type Checker - Validates types and infers missing annotations
import * as AST from "../parser/ast";
import type { Type, FunctionType, ObjectType, ContextBinding } from "./types";
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

  constructor() {
    this.env = createGlobalEnvironment();
  }

  /**
   * Type check a program
   */
  check(program: AST.Program): TypeCheckResult {
    // First pass: collect type declarations
    this.collectDeclarations(program);

    // Second pass: check all statements
    for (const stmt of program.body) {
      this.checkStatement(stmt);
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
        this.inferExpr(stmt.expr);
        break;
      case "FnDecl":
        this.checkFnDecl(stmt);
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

    for (const ctx of stmt.contexts) {
      const ctxType = this.inferExpr(ctx.expr);
      if (ctx.alias) {
        bindings.push({ name: ctx.alias, type: ctxType });
      }
    }

    const withEnv = this.env.withContext(bindings);
    const savedEnv = this.env;
    this.env = withEnv;
    this.checkBlock(stmt.body);
    this.env = savedEnv;
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
      for (const binding of decl.using.bindings) {
        const bindingType = this.astTypeToType(binding.type);
        if (binding.name) {
          fnEnv.define(binding.name, bindingType);
        }
      }
    }

    // Check body
    const savedEnv = this.env;
    const savedFn = this.currentFunction;
    this.env = fnEnv;
    this.currentFunction = fnType;
    this.checkBlock(decl.body);
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
    const calleeType = this.inferExpr(expr.callee);

    if (calleeType.kind === "function") {
      const params = calleeType.params;
      const args = expr.args;

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
            const expectedType = param.rest ? 
              (param.type.kind === "list" ? param.type.elementType : param.type) : 
              param.type;
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
      return calleeType.returnType;
    }

    // Constructor call - check object type constructor
    if (calleeType.kind === "object") {
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
      } else {
        elementTypes.push(this.inferExpr(el));
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
    const innerType = this.inferExpr(expr.expr);
    return Types.promise(innerType.kind === "function" ? (innerType as FunctionType).returnType : innerType);
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
  // Error Reporting
  // ============================================

  private error(message: string, loc: AST.SourceLocation, hint?: string): void {
    this.errors.push(new TypeCheckError(message, loc, hint));
  }

  private warning(message: string): void {
    this.warnings.push(message);
  }
}
