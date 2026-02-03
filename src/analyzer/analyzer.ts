// Semantic Analyzer
// Performs validation beyond type checking: context binding inference, exhaustiveness, scope validation

import * as AST from "../parser/ast";
import { isBuiltin } from "../shared/stdlib";

// ============================================
// Semantic Errors
// ============================================

export class SemanticError extends Error {
  constructor(
    message: string,
    public loc: AST.SourceLocation
  ) {
    super(`${message} at line ${loc.line}, column ${loc.column}`);
    this.name = "SemanticError";
  }
}

// ============================================
// Analysis Result
// ============================================

export interface AnalysisResult {
  program: AST.Program;
  errors: SemanticError[];
  warnings: SemanticWarning[];
  contextBindings: ContextBindingInfo[];
  scopes: ScopeInfo[];
}

export interface SemanticWarning {
  message: string;
  loc: AST.SourceLocation;
}

export interface ContextBindingInfo {
  name: string;
  usedBy: string[];       // Function/agent names that require this binding
  providedBy: string[];   // Context declarations that provide this binding
}

export interface ScopeInfo {
  name: string;
  kind: "global" | "function" | "block" | "agent" | "context";
  parent?: string;
  symbols: string[];
}

// ============================================
// Context Tracker
// ============================================

interface ContextRequirement {
  name: string;
  loc: AST.SourceLocation;
}

class ContextTracker {
  private requirements: Map<string, ContextRequirement[]> = new Map(); // function/agent -> requirements
  private providers: Map<string, Set<string>> = new Map(); // context decl -> bindings
  private currentScope: string | null = null;
  
  enterScope(name: string): void {
    this.currentScope = name;
    if (!this.requirements.has(name)) {
      this.requirements.set(name, []);
    }
  }
  
  // Alias for backward compatibility
  enterFunction(name: string): void {
    this.enterScope(name);
  }
  
  exitScope(): void {
    this.currentScope = null;
  }
  
  exitFunction(): void {
    this.exitScope();
  }
  
  requireBinding(name: string, loc: AST.SourceLocation): void {
    if (this.currentScope) {
      this.requirements.get(this.currentScope)!.push({ name, loc });
    } else {
      // Track at global level
      if (!this.requirements.has("__global__")) {
        this.requirements.set("__global__", []);
      }
      this.requirements.get("__global__")!.push({ name, loc });
    }
  }
  
  registerProvider(contextName: string, bindings: string[]): void {
    this.providers.set(contextName, new Set(bindings));
  }
  
  getRequirements(): Map<string, ContextRequirement[]> {
    return this.requirements;
  }
  
  getProviders(): Map<string, Set<string>> {
    return this.providers;
  }
}

// ============================================
// Scope Tracker
// ============================================

interface Scope {
  name: string;
  kind: "global" | "function" | "block" | "agent" | "context";
  symbols: Set<string>;
  parent: Scope | null;
}

class ScopeTracker {
  private scopes: Scope[] = [];
  private current: Scope;
  
  constructor() {
    this.current = { name: "global", kind: "global", symbols: new Set(), parent: null };
    this.scopes.push(this.current);
  }
  
  enterScope(name: string, kind: Scope["kind"]): void {
    const scope: Scope = { name, kind, symbols: new Set(), parent: this.current };
    this.scopes.push(scope);
    this.current = scope;
  }
  
  exitScope(): void {
    if (this.current.parent) {
      this.current = this.current.parent;
    }
  }
  
  define(name: string): void {
    this.current.symbols.add(name);
  }
  
  isDefined(name: string): boolean {
    let scope: Scope | null = this.current;
    while (scope) {
      if (scope.symbols.has(name)) {
        return true;
      }
      scope = scope.parent;
    }
    return false;
  }
  
  isDefinedInCurrentScope(name: string): boolean {
    return this.current.symbols.has(name);
  }
  
  getCurrentScope(): Scope {
    return this.current;
  }
  
  getAllScopes(): Scope[] {
    return this.scopes;
  }
}

// ============================================
// Match Exhaustiveness Checker
// ============================================

interface PatternCoverage {
  covered: boolean;
  missing: string[];
}

function checkExhaustiveness(
  matchExpr: AST.MatchExpr,
  enumValues?: string[]
): PatternCoverage {
  const arms = matchExpr.arms;
  let hasWildcard = false;
  const coveredPatterns = new Set<string>();
  
  for (const arm of arms) {
    if (arm.pattern.kind === "WildcardPattern") {
      hasWildcard = true;
    } else if (arm.pattern.kind === "IdentifierPattern") {
      // Check if it's a binding (lowercase) or enum variant (PascalCase)
      const name = arm.pattern.name;
      const firstChar = name[0];
      if (firstChar && firstChar === firstChar.toUpperCase()) {
        coveredPatterns.add(name);
      } else {
        // Variable binding acts as wildcard
        hasWildcard = true;
      }
    } else if (arm.pattern.kind === "LiteralPattern") {
      coveredPatterns.add(String(arm.pattern.value));
    }
  }
  
  if (hasWildcard) {
    return { covered: true, missing: [] };
  }
  
  // If we have enum values, check coverage
  if (enumValues) {
    const missing = enumValues.filter(v => !coveredPatterns.has(v));
    return { covered: missing.length === 0, missing };
  }
  
  // Without type info, we can't determine exhaustiveness
  return { covered: true, missing: [] };
}

// ============================================
// Semantic Analyzer
// ============================================

export class SemanticAnalyzer {
  private errors: SemanticError[] = [];
  private warnings: SemanticWarning[] = [];
  private contextTracker: ContextTracker = new ContextTracker();
  private scopes: ScopeTracker = new ScopeTracker();
  private inLoop: boolean = false;
  private inAgent: boolean = false;
  private declaredEnums: Map<string, string[]> = new Map(); // enum name -> variants
  
  /**
   * Analyze a program for semantic issues
   */
  analyze(program: AST.Program): AnalysisResult {
    // First pass: collect declarations
    this.collectDeclarations(program);
    
    // Second pass: analyze statements
    for (const stmt of program.body) {
      this.analyzeStatement(stmt);
    }
    
    // Build context binding info
    const contextBindingInfo = this.buildContextBindingInfo();
    
    // Build scope info
    const scopeInfo = this.buildScopeInfo();
    
    return {
      program,
      errors: this.errors,
      warnings: this.warnings,
      contextBindings: contextBindingInfo,
      scopes: scopeInfo,
    };
  }
  
  // ============================================
  // Declaration Collection
  // ============================================
  
  private collectDeclarations(program: AST.Program): void {
    for (const stmt of program.body) {
      switch (stmt.kind) {
        case "FnDecl":
          this.scopes.define(stmt.name);
          break;
        case "TypeDecl":
          this.scopes.define(stmt.name);
          break;
        case "EnumDecl":
          this.scopes.define(stmt.name);
          this.declaredEnums.set(stmt.name, stmt.variants.map(v => v.name));
          break;
        case "AgentDecl":
          this.scopes.define(stmt.name);
          break;
        case "ContextDecl":
          this.scopes.define(stmt.name);
          break;
        case "LetStmt":
          // LetStmt has pattern which could be identifier or destructuring
          if ((stmt as AST.LetStmt).pattern.kind === "IdentifierPattern") {
            const name = ((stmt as AST.LetStmt).pattern as AST.IdentifierPattern).name;
            if (this.scopes.isDefinedInCurrentScope(name)) {
              this.error(`Variable '${name}' is already declared in this scope`, stmt.loc);
            } else {
              this.scopes.define(name);
            }
          }
          break;
        case "VarStmt":
          const varName = (stmt as AST.VarStmt).name;
          if (this.scopes.isDefinedInCurrentScope(varName)) {
            this.error(`Variable '${varName}' is already declared in this scope`, stmt.loc);
          } else {
            this.scopes.define(varName);
          }
          break;
      }
    }
  }
  
  // ============================================
  // Statement Analysis
  // ============================================
  
  private analyzeStatement(stmt: AST.Statement): void {
    switch (stmt.kind) {
      case "FnDecl":
        this.analyzeFnDecl(stmt);
        break;
      case "LetStmt":
        this.analyzeLetStmt(stmt as AST.LetStmt);
        break;
      case "VarStmt":
        this.analyzeVarStmt(stmt as AST.VarStmt);
        break;
      case "AssignStmt":
        this.analyzeAssignStmt(stmt);
        break;
      case "IfStmt":
        this.analyzeIfStmt(stmt);
        break;
      case "ForStmt":
        this.analyzeForStmt(stmt);
        break;
      case "MatchStmt":
        this.analyzeMatchStmt(stmt);
        break;
      case "ReturnStmt":
        this.analyzeReturnStmt(stmt);
        break;
      case "BreakStmt":
      case "ContinueStmt":
        this.analyzeLoopControl(stmt);
        break;
      case "TryStmt":
        this.analyzeTryStmt(stmt);
        break;
      case "WithStmt":
        this.analyzeWithStmt(stmt);
        break;
      case "AgentDecl":
        this.analyzeAgentDecl(stmt);
        break;
      case "ContextDecl":
        this.analyzeContextDecl(stmt);
        break;
      case "EnumDecl":
        this.analyzeEnumDecl(stmt);
        break;
      case "TypeDecl":
        this.analyzeTypeDecl(stmt);
        break;
      case "TestDecl":
        this.analyzeTestDecl(stmt);
        break;
      case "ExprStmt":
        this.analyzeExpr(stmt.expr);
        break;
    }
  }
  
  private analyzeFnDecl(decl: AST.FnDecl): void {
    this.contextTracker.enterFunction(decl.name);
    this.scopes.enterScope(decl.name, "function");
    
    // Define parameters
    for (const param of decl.params) {
      this.scopes.define(param.name);
    }
    
    // Analyze body - body is a Block with statements
    if (decl.body && decl.body.statements) {
      for (const stmt of decl.body.statements) {
        this.analyzeStatement(stmt);
      }
    }
    
    this.scopes.exitScope();
    this.contextTracker.exitFunction();
  }
  
  private analyzeLetStmt(stmt: AST.LetStmt): void {
    // Analyze the value expression first
    this.analyzeExpr(stmt.value);
    
    // Then bind the pattern (don't check redeclaration, first pass already did it)
    this.analyzeBindingPattern(stmt.pattern, false);
  }
  
  private analyzeVarStmt(stmt: AST.VarStmt): void {
    // Redeclaration check is done in first pass
    if (stmt.value) {
      this.analyzeExpr(stmt.value);
    }
  }
  
  private analyzeBindingPattern(pattern: AST.Pattern, checkRedeclaration: boolean = true): void {
    switch (pattern.kind) {
      case "IdentifierPattern":
        if (checkRedeclaration && this.scopes.isDefinedInCurrentScope(pattern.name)) {
          this.error(`Variable '${pattern.name}' is already declared in this scope`, pattern.loc);
        }
        // Don't re-define if already defined in first pass
        if (!this.scopes.isDefinedInCurrentScope(pattern.name)) {
          this.scopes.define(pattern.name);
        }
        break;
      case "ArrayPattern":
        for (const elem of pattern.elements) {
          if (elem) this.analyzeBindingPattern(elem, checkRedeclaration);
        }
        break;
      case "ObjectPattern":
        for (const prop of pattern.properties) {
          if (prop.pattern) {
            this.analyzeBindingPattern(prop.pattern, checkRedeclaration);
          } else if (!this.scopes.isDefinedInCurrentScope(prop.key)) {
            this.scopes.define(prop.key);
          }
        }
        break;
    }
  }
  
  private analyzeAssignStmt(stmt: AST.AssignStmt): void {
    this.analyzeExpr(stmt.target);
    this.analyzeExpr(stmt.value);
    
    // Check if target is assignable
    if (stmt.target.kind === "Identifier") {
      if (!this.scopes.isDefined(stmt.target.name)) {
        this.error(`Cannot assign to undefined variable '${stmt.target.name}'`, stmt.loc);
      }
    }
  }
  
  private analyzeIfStmt(stmt: AST.IfStmt): void {
    this.analyzeExpr(stmt.condition);
    
    this.scopes.enterScope("if-then", "block");
    if (stmt.then && Array.isArray(stmt.then)) {
      for (const s of stmt.then) {
        this.analyzeStatement(s);
      }
    } else if (stmt.then && "statements" in stmt.then) {
      for (const s of (stmt.then as AST.Block).statements) {
        this.analyzeStatement(s);
      }
    }
    this.scopes.exitScope();
    
    if (stmt.else) {
      this.scopes.enterScope("if-else", "block");
      if (Array.isArray(stmt.else)) {
        for (const s of stmt.else) {
          this.analyzeStatement(s);
        }
      } else if ("statements" in stmt.else) {
        for (const s of (stmt.else as AST.Block).statements) {
          this.analyzeStatement(s);
        }
      }
      this.scopes.exitScope();
    }
  }
  
  private analyzeForStmt(stmt: AST.ForStmt): void {
    this.scopes.enterScope("for", "block");
    
    // ForStmt uses pattern, not variable
    if (stmt.pattern && stmt.pattern.kind === "IdentifierPattern") {
      this.scopes.define(stmt.pattern.name);
    }
    
    if (stmt.iterable) {
      this.analyzeExpr(stmt.iterable);
    }
    
    const wasInLoop = this.inLoop;
    this.inLoop = true;
    
    // body is a Block
    this.analyzeBlock(stmt.body);
    
    this.inLoop = wasInLoop;
    this.scopes.exitScope();
  }
  
  private analyzeMatchStmt(stmt: AST.MatchStmt): void {
    // MatchStmt uses value, not subject
    this.analyzeExpr(stmt.value);
    
    for (const arm of stmt.arms) {
      this.scopes.enterScope("match-arm", "block");
      this.analyzePattern(arm.pattern);
      
      if (arm.guard) {
        this.analyzeExpr(arm.guard);
      }
      
      // body can be Expr or Block
      if (arm.body && "kind" in arm.body) {
        if (arm.body.kind === "Block") {
          this.analyzeBlock(arm.body as AST.Block);
        } else {
          this.analyzeExpr(arm.body as AST.Expr);
        }
      }
      this.scopes.exitScope();
    }
    
    // Check exhaustiveness for enum matches
    // We would need type info here to properly check
  }
  
  private analyzeReturnStmt(stmt: AST.ReturnStmt): void {
    if (stmt.value) {
      this.analyzeExpr(stmt.value);
    }
  }
  
  private analyzeLoopControl(stmt: AST.BreakStmt | AST.ContinueStmt): void {
    if (!this.inLoop) {
      const keyword = stmt.kind === "BreakStmt" ? "break" : "continue";
      this.error(`'${keyword}' can only be used inside a loop`, stmt.loc);
    }
  }
  
  private analyzeTryStmt(stmt: AST.TryStmt): void {
    // TryStmt has body: Block, not try
    this.scopes.enterScope("try", "block");
    if (stmt.body) {
      this.analyzeBlock(stmt.body);
    }
    this.scopes.exitScope();
    
    if (stmt.catch) {
      this.scopes.enterScope("catch", "block");
      // catch has name and body
      if (stmt.catch.name) {
        this.scopes.define(stmt.catch.name);
      }
      if (stmt.catch.body) {
        this.analyzeBlock(stmt.catch.body);
      }
      this.scopes.exitScope();
    }
  }
  
  private analyzeWithStmt(stmt: AST.WithStmt): void {
    this.scopes.enterScope("with", "block");
    
    if (stmt.contexts) {
      for (const ctx of stmt.contexts) {
        this.analyzeExpr(ctx.expr);
        if (ctx.alias) {
          this.scopes.define(ctx.alias);
        }
      }
    }
    
    // body is a Block
    if (stmt.body) {
      this.analyzeBlock(stmt.body);
    }
    
    this.scopes.exitScope();
  }
  
  private analyzeAgentDecl(decl: AST.AgentDecl): void {
    this.scopes.enterScope(decl.name, "agent");
    this.contextTracker.enterScope(decl.name); // Track context bindings for this agent
    this.inAgent = true;
    
    // Track required context bindings
    if (decl.context) {
      for (const binding of decl.context) {
        // ContextBinding has type property with TypeExpr
        const bindingType = binding.type;
        const name = bindingType && "name" in bindingType ? bindingType.name : undefined;
        if (name) {
          this.contextTracker.requireBinding(name, decl.loc);
        }
      }
    }
    
    // Analyze fields
    if (decl.fields) {
      for (const field of decl.fields) {
        this.scopes.define(field.name);
      }
    }
    
    // Analyze tools
    if (decl.tools) {
      for (const tool of decl.tools) {
        this.analyzeFnDecl(tool);
      }
    }
    
    // Analyze run method
    if (decl.run) {
      this.analyzeFnDecl(decl.run);
    }
    
    this.inAgent = false;
    this.contextTracker.exitScope();
    this.scopes.exitScope();
  }
  
  private analyzeContextDecl(decl: AST.ContextDecl): void {
    this.scopes.enterScope(decl.name, "context");
    
    const bindings: string[] = [];
    
    if (decl.bindings) {
      for (const binding of decl.bindings) {
        this.scopes.define(binding.name);
        bindings.push(binding.name);
        this.analyzeExpr(binding.value);
      }
    }
    
    if (decl.methods) {
      for (const method of decl.methods) {
        this.analyzeMethodDecl(method);
      }
    }
    
    this.contextTracker.registerProvider(decl.name, bindings);
    
    this.scopes.exitScope();
  }
  
  private analyzeMethodDecl(method: AST.MethodDecl): void {
    this.scopes.enterScope(method.name, "function");
    
    for (const param of method.params) {
      this.scopes.define(param.name);
    }
    
    if (method.body) {
      this.analyzeBlock(method.body);
    }
    
    this.scopes.exitScope();
  }
  
  private analyzeEnumDecl(decl: AST.EnumDecl): void {
    const seenVariants = new Set<string>();
    
    for (const variant of decl.variants) {
      if (seenVariants.has(variant.name)) {
        this.error(`Duplicate enum variant '${variant.name}'`, decl.loc);
      }
      seenVariants.add(variant.name);
    }
  }
  
  private analyzeTypeDecl(decl: AST.TypeDecl): void {
    // Check for duplicate field names
    const seenFields = new Set<string>();
    
    // TypeDecl has body: TypeBody with members
    if (decl.body && decl.body.members) {
      for (const member of decl.body.members) {
        if (member.kind === "FieldDecl") {
          if (seenFields.has(member.name)) {
            this.error(`Duplicate field '${member.name}' in type '${decl.name}'`, decl.loc);
          }
          seenFields.add(member.name);
        }
      }
    }
  }
  
  private analyzeTestDecl(decl: AST.TestDecl): void {
    this.scopes.enterScope(`test:${decl.description}`, "function");
    
    // TestDecl has body: Block
    if (decl.body) {
      this.analyzeBlock(decl.body);
    }
    
    this.scopes.exitScope();
  }
  
  private analyzeBlock(block: AST.Block): void {
    if (!block || !block.statements) return;
    
    this.scopes.enterScope("block", "block");
    
    for (const stmt of block.statements) {
      this.analyzeStatement(stmt);
    }
    
    this.scopes.exitScope();
  }
  
  // ============================================
  // Expression Analysis
  // ============================================
  
  private analyzeExpr(expr: AST.Expr): void {
    switch (expr.kind) {
      case "Identifier":
        if (!this.scopes.isDefined(expr.name)) {
          // Check if it's a built-in
          if (!this.isBuiltIn(expr.name)) {
            this.error(`Undefined identifier '${expr.name}'`, expr.loc);
          }
        }
        break;
        
      case "BinaryExpr":
        this.analyzeExpr(expr.left);
        this.analyzeExpr(expr.right);
        break;
        
      case "UnaryExpr":
        this.analyzeExpr(expr.operand);
        break;
        
      case "CallExpr":
        this.analyzeExpr(expr.callee);
        for (const arg of expr.args) {
          if ("name" in arg && "value" in arg && !("kind" in arg)) {
            // Named argument
            this.analyzeExpr(arg.value);
          } else {
            this.analyzeExpr(arg as AST.Expr);
          }
        }
        break;
        
      case "MemberExpr":
        this.analyzeExpr(expr.object);
        break;
        
      case "IndexExpr":
        this.analyzeExpr(expr.object);
        this.analyzeExpr(expr.index);
        if (expr.slice) {
          if (expr.slice.start) this.analyzeExpr(expr.slice.start);
          if (expr.slice.end) this.analyzeExpr(expr.slice.end);
        }
        break;
        
      case "LambdaExpr":
        this.scopes.enterScope("lambda", "function");
        for (const param of expr.params) {
          this.scopes.define(param.name);
        }
        if (expr.body.kind === "Block") {
          this.analyzeBlock(expr.body);
        } else {
          this.analyzeExpr(expr.body);
        }
        this.scopes.exitScope();
        break;
        
      case "IfExpr":
        this.analyzeExpr(expr.condition);
        this.analyzeExpr(expr.then);
        this.analyzeExpr(expr.else);
        break;
        
      case "MatchExpr":
        this.analyzeExpr(expr.value);
        for (const arm of expr.arms) {
          this.scopes.enterScope("match-arm", "block");
          this.analyzePattern(arm.pattern);
          if (arm.guard) this.analyzeExpr(arm.guard);
          if (arm.body.kind === "Block") {
            this.analyzeBlock(arm.body);
          } else {
            this.analyzeExpr(arm.body);
          }
          this.scopes.exitScope();
        }
        
        // Check exhaustiveness
        const coverage = checkExhaustiveness(expr);
        if (!coverage.covered) {
          this.warning(
            `Non-exhaustive match: missing patterns ${coverage.missing.join(", ")}`,
            expr.loc
          );
        }
        break;
        
      case "ListExpr":
        for (const elem of expr.elements) {
          if (elem.kind === "SpreadElement") {
            this.analyzeExpr(elem.expr);
          } else {
            this.analyzeExpr(elem);
          }
        }
        break;
        
      case "MapExpr":
        for (const entry of expr.entries) {
          // Map keys that are plain Identifiers are just key names, not variable references
          // Only analyze if the key is a more complex expression (computed key)
          if (entry.key.kind !== "Identifier") {
            this.analyzeExpr(entry.key);
          }
          this.analyzeExpr(entry.value);
        }
        break;
        
      case "PipeExpr":
        this.analyzeExpr(expr.left);
        this.analyzeExpr(expr.right);
        break;
        
      case "SpawnExpr":
        this.analyzeExpr(expr.expr);
        break;
        
      case "RangeExpr":
        this.analyzeExpr(expr.start);
        this.analyzeExpr(expr.end);
        break;
        
      case "TemplateLiteral":
        for (const part of expr.parts) {
          if (typeof part !== "string") {
            // part is TemplateExpr which has expr: Expr
            this.analyzeExpr(part.expr);
          }
        }
        break;
        
      case "NullAssertion":
      case "TypeAssertion":
        this.analyzeExpr(expr.expr);
        break;
    }
  }
  
  private analyzePattern(pattern: AST.Pattern): void {
    switch (pattern.kind) {
      case "IdentifierPattern":
        // If lowercase, it's a binding
        const firstChar = pattern.name[0];
        if (firstChar && firstChar === firstChar.toLowerCase()) {
          this.scopes.define(pattern.name);
        }
        break;
        
      case "ArrayPattern":
        for (const elem of pattern.elements) {
          if (elem) this.analyzePattern(elem);
        }
        break;
        
      case "ObjectPattern":
        for (const prop of pattern.properties) {
          if (prop.pattern) {
            this.analyzePattern(prop.pattern);
          } else {
            this.scopes.define(prop.key);
          }
        }
        break;
        
      case "RestPattern":
        this.scopes.define(pattern.name);
        break;
    }
  }
  
  // ============================================
  // Helpers
  // ============================================
  
  private isBuiltIn(name: string): boolean {
    return isBuiltin(name);
  }
  
  private error(message: string, loc: AST.SourceLocation): void {
    this.errors.push(new SemanticError(message, loc));
  }
  
  private warning(message: string, loc: AST.SourceLocation): void {
    this.warnings.push({ message, loc });
  }
  
  private buildContextBindingInfo(): ContextBindingInfo[] {
    const requirements = this.contextTracker.getRequirements();
    const providers = this.contextTracker.getProviders();
    
    // Collect all binding names
    const allBindings = new Set<string>();
    for (const reqs of requirements.values()) {
      for (const req of reqs) {
        allBindings.add(req.name);
      }
    }
    for (const bindings of providers.values()) {
      for (const binding of bindings) {
        allBindings.add(binding);
      }
    }
    
    // Build info for each binding
    const info: ContextBindingInfo[] = [];
    for (const binding of allBindings) {
      const usedBy: string[] = [];
      for (const [fn, reqs] of requirements) {
        if (reqs.some(r => r.name === binding)) {
          usedBy.push(fn);
        }
      }
      
      const providedBy: string[] = [];
      for (const [ctx, bindings] of providers) {
        if (bindings.has(binding)) {
          providedBy.push(ctx);
        }
      }
      
      info.push({ name: binding, usedBy, providedBy });
    }
    
    return info;
  }
  
  private buildScopeInfo(): ScopeInfo[] {
    return this.scopes.getAllScopes().map(scope => ({
      name: scope.name,
      kind: scope.kind,
      parent: scope.parent?.name,
      symbols: [...scope.symbols],
    }));
  }
}

/**
 * Convenience function to analyze a program
 */
export function analyze(program: AST.Program): AnalysisResult {
  const analyzer = new SemanticAnalyzer();
  return analyzer.analyze(program);
}
