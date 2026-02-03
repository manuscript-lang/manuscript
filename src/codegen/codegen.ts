// Code Generator - Transpiles Manuscript AST to JavaScript
import * as AST from "../parser/ast";
import { STDLIB_FUNCTIONS, BUILTIN_CONSTRUCTORS } from "../shared/stdlib";

// ============================================
// Code Generator Options
// ============================================

export interface CodeGenOptions {
  indent: string;           // Indentation string (default: "  ")
  sourceMap: boolean;       // Generate source maps
  runtime: "bun" | "node";  // Target runtime
  module: "esm" | "cjs";    // Module format
  emitRuntimeImport: boolean; // Emit runtime import statement (default: true)
}

const defaultOptions: CodeGenOptions = {
  indent: "  ",
  sourceMap: false,
  runtime: "bun",
  module: "esm",
  emitRuntimeImport: true,
};

// ============================================
// Code Generator
// ============================================

export class CodeGenerator {
  private options: CodeGenOptions;
  private output: string[] = [];
  private indentLevel: number = 0;
  private tempVarCounter: number = 0;
  private declaredTypes: Set<string> = new Set();
  // Scope tracking for defer statements
  private scopeStack: { defers: AST.Statement[] }[] = [];
  // Track current class fields for method body generation
  private currentClassFields: Set<string> = new Set();
  // Track variable types: var name -> type name (for inferring context types)
  private variableTypes: Map<string, string> = new Map();
  // Track type hierarchy: type name -> parent type names (for interface matching)
  private typeHierarchy: Map<string, string[]> = new Map();

  constructor(options: Partial<CodeGenOptions> = {}) {
    this.options = { ...defaultOptions, ...options };
  }

  // Get all types that a given type can satisfy (itself + all ancestors)
  private getTypeChain(typeName: string): string[] {
    const chain: string[] = [typeName];
    const parents = this.typeHierarchy.get(typeName);
    if (parents) {
      for (const parent of parents) {
        chain.push(...this.getTypeChain(parent));
      }
    }
    return chain;
  }

  // Infer type name from an expression (for tracking variable types)
  private inferTypeName(expr: AST.Expr): string | undefined {
    // Type constructor call: TypeName(...)
    if (expr.kind === "CallExpr" && expr.callee.kind === "Identifier") {
      const name = expr.callee.name;
      if (this.declaredTypes.has(name)) {
        return name;
      }
    }
    // Identifier - look up tracked variable type
    if (expr.kind === "Identifier") {
      return this.variableTypes.get(expr.name);
    }
    return undefined;
  }

  // Scope management for defer
  private pushScope(): void {
    this.scopeStack.push({ defers: [] });
  }

  private popScope(): AST.Statement[] {
    return this.scopeStack.pop()?.defers || [];
  }

  private addDefer(stmt: AST.Statement): void {
    const scope = this.scopeStack[this.scopeStack.length - 1];
    if (scope) {
      scope.defers.push(stmt);
    }
  }

  /**
   * Generate JavaScript code from AST
   */
  generate(program: AST.Program): string {
    this.output = [];
    this.indentLevel = 0;
    this.tempVarCounter = 0;
    this.declaredTypes.clear();
    this.variableTypes.clear();
    this.typeHierarchy.clear();

    // First pass: collect declared type names and hierarchy
    for (const stmt of program.body) {
      if (stmt.kind === "TypeDecl") {
        this.declaredTypes.add(stmt.name);
        if (stmt.extends && stmt.extends.length > 0) {
          const parents = stmt.extends
            .filter(e => e.kind === "NamedType")
            .map(e => (e as { kind: "NamedType"; name: string }).name);
          if (parents.length > 0) {
            this.typeHierarchy.set(stmt.name, parents);
          }
        }
      } else if (stmt.kind === "EnumDecl") {
        this.declaredTypes.add(stmt.name);
      }
    }

    // Add runtime imports
    this.emitRuntimeImports();

    // Generate code for each statement
    for (const stmt of program.body) {
      this.genStatement(stmt);
    }

    return this.output.join("\n");
  }

  // ============================================
  // Runtime Imports
  // ============================================

  private emitRuntimeImports(): void {
    if (this.options.emitRuntimeImport) {
      this.emit('import { __ms_runtime } from "manuscript/runtime";');
      this.emit("");
    }
  }

  // ============================================
  // Statement Generation
  // ============================================

  private genStatement(stmt: AST.Statement): void {
    switch (stmt.kind) {
      case "ImportDecl":
        this.genImport(stmt);
        break;
      case "FnDecl":
        this.genFnDecl(stmt);
        break;
      case "ExternFnDecl":
        // Extern functions are implemented in the runtime, no code generated
        break;
      case "TypeDecl":
        this.genTypeDecl(stmt);
        break;
      case "EnumDecl":
        this.genEnumDecl(stmt);
        break;
      case "KeywordDecl":
        // Keywords are compile-time only, no runtime code
        break;
      case "ContextDecl":
        this.genContextDecl(stmt);
        break;
      case "AgentDecl":
        this.genAgentDecl(stmt);
        break;
      case "TestDecl":
        this.genTestDecl(stmt);
        break;
      case "LetStmt":
        this.genLetStmt(stmt);
        break;
      case "VarStmt":
        this.genVarStmt(stmt);
        break;
      case "AssignStmt":
        this.genAssignStmt(stmt);
        break;
      case "IfStmt":
        this.genIfStmt(stmt);
        break;
      case "ForStmt":
        this.genForStmt(stmt);
        break;
      case "MatchStmt":
        this.genMatchStmt(stmt);
        break;
      case "ReturnStmt":
        this.genReturnStmt(stmt);
        break;
      case "YieldStmt":
        this.genYieldStmt(stmt);
        break;
      case "BreakStmt":
        this.emit("break;");
        break;
      case "ContinueStmt":
        this.emit("continue;");
        break;
      case "DeferStmt":
        this.genDeferStmt(stmt);
        break;
      case "TryStmt":
        this.genTryStmt(stmt);
        break;
      case "ThrowStmt":
        this.genThrowStmt(stmt);
        break;
      case "WithStmt":
        this.genWithStmt(stmt);
        break;
      case "ExprStmt":
        // Wrap map expressions in parentheses to avoid JS ambiguity with blocks
        if (stmt.expr.kind === "MapExpr") {
          this.emit(`(${this.genExpr(stmt.expr)});`);
        } else {
          this.emit(`${this.genExpr(stmt.expr)};`);
        }
        break;
    }
  }

  // ============================================
  // Declaration Generation
  // ============================================

  private genImport(decl: AST.ImportDecl): void {
    const items = decl.names.map(item => {
      if (item.alias) {
        return `${item.name} as ${item.alias}`;
      }
      return item.name;
    });

    if (this.options.module === "esm") {
      this.emit(`import { ${items.join(", ")} } from "${decl.source}";`);
    } else {
      this.emit(`const { ${items.join(", ")} } = require("${decl.source}");`);
    }
  }

  private genFnDecl(decl: AST.FnDecl): void {
    const params = this.genParams(decl.params);
    // Generators can't be async, all other functions are async for implicit await
    const prefix = decl.isGenerator ? "function*" : "async function";

    this.emit(`${prefix} ${decl.name}(${params}) {`);
    this.indentLevel++;
    
    // Pull context bindings from runtime stack (non-viral using)
    if (decl.using && decl.using.bindings.length > 0) {
      for (const binding of decl.using.bindings) {
        const name = binding.name || `_binding${this.tempVarCounter++}`;
        const typeName = binding.type.kind === "NamedType" ? binding.type.name : "unknown";
        this.emit(`const ${name} = __ms_runtime.__getContext("${typeName}");`);
      }
    }
    
    this.genBlock(decl.body, true);
    this.indentLevel--;
    this.emit("}");
    this.emit("");
  }

  private genParams(params: AST.Parameter[]): string {
    return params.map(p => {
      let param = p.name;
      if (p.rest) param = `...${param}`;
      if (p.defaultValue) {
        param += ` = ${this.genExpr(p.defaultValue)}`;
      }
      return param;
    }).join(", ");
  }

  private genTypeDecl(decl: AST.TypeDecl): void {
    // Generate as a class
    if (!decl.body) {
      // Type alias - no runtime code needed (TypeScript-like)
      this.emit(`// type ${decl.name} = ...`);
      return;
    }

    let extendsClause = "";
    if (decl.extends && decl.extends.length > 0 && decl.extends[0]) {
      const parentType = decl.extends[0];
      let parentName = parentType.kind === "NamedType" ? parentType.name : "Object";
      // Context is from the runtime
      if (parentName === "Context") {
        parentName = "__ms_runtime.Context";
      }
      extendsClause = ` extends ${parentName}`;
    }

    this.emit(`class ${decl.name}${extendsClause} {`);
    this.indentLevel++;

    // Collect fields and methods
    const fields: AST.FieldDecl[] = [];
    const methods: AST.MethodDecl[] = [];

    for (const member of decl.body.members) {
      if (member.kind === "FieldDecl") {
        fields.push(member);
      } else if (member.kind === "MethodDecl") {
        methods.push(member);
      }
    }

    // Generate constructor
    const requiredFields = fields.filter(f => !f.optional && !f.defaultValue);
    const optionalFields = fields.filter(f => f.optional || f.defaultValue);

    const hasExtends = decl.extends && decl.extends.length > 0;
    
    if (fields.length > 0 || hasExtends) {
      const constructorParams = requiredFields.map(f => f.name).join(", ");
      const optionalParams = optionalFields.map(f => {
        if (f.defaultValue) {
          return `${f.name} = ${this.genExpr(f.defaultValue)}`;
        }
        return `${f.name} = undefined`;
      }).join(", ");

      const allParams = [constructorParams, optionalParams].filter(p => p).join(", ");
      
      this.emit(`constructor(${allParams}) {`);
      this.indentLevel++;
      // Call super() if extending another class
      if (hasExtends) {
        this.emit("super();");
      }
      for (const field of fields) {
        this.emit(`this.${field.name} = ${field.name};`);
      }
      this.indentLevel--;
      this.emit("}");
      this.emit("");
    }

    // Generate methods - track field names for this. prefix
    this.currentClassFields = new Set(fields.map(f => f.name));
    
    for (const method of methods) {
      // Generators can't be async, all other methods are async for implicit await
      const prefix = method.isGenerator ? "*" : "async ";
      const params = this.genParams(method.params);
      
      this.emit(`${prefix}${method.name}(${params}) {`);
      this.indentLevel++;
      if (method.body) {
        this.genBlock(method.body, true);
      }
      this.indentLevel--;
      this.emit("}");
      this.emit("");
    }
    
    // Clear class context after generating methods
    this.currentClassFields.clear();

    this.indentLevel--;
    this.emit("}");
    this.emit("");
  }

  private genEnumDecl(decl: AST.EnumDecl): void {
    this.emit(`const ${decl.name} = Object.freeze({`);
    this.indentLevel++;
    
    for (let i = 0; i < decl.variants.length; i++) {
      const variant = decl.variants[i];
      if (!variant) continue;
      const comma = i < decl.variants.length - 1 ? "," : "";
      
      if (variant.value) {
        this.emit(`${variant.name}: ${this.genExpr(variant.value)}${comma}`);
      } else {
        this.emit(`${variant.name}: "${variant.name}"${comma}`);
      }
    }
    
    this.indentLevel--;
    this.emit("});");
    this.emit("");
  }

  private genContextDecl(decl: AST.ContextDecl): void {
    // Generate context object with bindings
    this.emit(`const ${decl.name} = {`);
    this.indentLevel++;
    
    // Generate bindings
    if (decl.bindings) {
      for (const binding of decl.bindings) {
        const value = this.genExpr(binding.value);
        this.emit(`${binding.name}: ${value},`);
      }
    }
    
    // Generate methods (especially exit for cleanup)
    if (decl.methods) {
      for (const method of decl.methods) {
        const params = this.genParams(method.params);
        this.emit(`async ${method.name}(${params}) {`);
        this.indentLevel++;
        if (method.body) {
          this.genBlock(method.body);
        }
        this.indentLevel--;
        this.emit("},");
      }
    }
    
    this.indentLevel--;
    this.emit("};");
    this.emit("");
  }

  private genAgentDecl(decl: AST.AgentDecl): void {
    this.emit(`class ${decl.name} extends __ms_runtime.Agent {`);
    this.indentLevel++;

    // Constructor with context bindings
    const bindings = decl.context?.map(c => c.name || "_binding") || [];
    this.emit(`constructor(${bindings.join(", ")}) {`);
    this.indentLevel++;
    this.emit("super();");
    for (const binding of bindings) {
      this.emit(`this.${binding} = ${binding};`);
    }
    this.indentLevel--;
    this.emit("}");
    this.emit("");

    // Generate tools
    if (decl.tools) {
      for (const tool of decl.tools) {
        const params = this.genParams(tool.params);
        this.emit(`async ${tool.name}(${params}) {`);
        this.indentLevel++;
        this.genBlock(tool.body);
        this.indentLevel--;
        this.emit("}");
        this.emit("");
      }
    }

    // Generate run method
    if (decl.run) {
      const params = this.genParams(decl.run.params);
      this.emit(`async run(${params}) {`);
      this.indentLevel++;
      this.genBlock(decl.run.body);
      this.indentLevel--;
      this.emit("}");
    }

    this.indentLevel--;
    this.emit("}");
    this.emit("");
  }

  private genTestDecl(decl: AST.TestDecl): void {
    this.emit(`__ms_runtime.test(${JSON.stringify(decl.description)}, async () => {`);
    this.indentLevel++;
    this.genBlock(decl.body);
    this.indentLevel--;
    this.emit("});");
    this.emit("");
  }

  // ============================================
  // Statement Generation
  // ============================================

  private genLetStmt(stmt: AST.LetStmt): void {
    const pattern = this.genPattern(stmt.pattern);
    const value = this.genExpr(stmt.value);
    this.emit(`const ${pattern} = ${value};`);
    
    // Track variable type for type-based context matching
    if (stmt.pattern.kind === "IdentifierPattern") {
      const typeName = this.inferTypeName(stmt.value);
      if (typeName) {
        this.variableTypes.set(stmt.pattern.name, typeName);
      }
    }
  }

  private genVarStmt(stmt: AST.VarStmt): void {
    const value = this.genExpr(stmt.value);
    this.emit(`let ${stmt.name} = ${value};`);
    
    // Track variable type for type-based context matching
    const typeName = this.inferTypeName(stmt.value);
    if (typeName) {
      this.variableTypes.set(stmt.name, typeName);
    }
  }

  private genAssignStmt(stmt: AST.AssignStmt): void {
    const target = this.genExpr(stmt.target);
    const value = this.genExpr(stmt.value);
    this.emit(`${target} ${stmt.op} ${value};`);
  }

  private genIfStmt(stmt: AST.IfStmt): void {
    const cond = this.genExpr(stmt.condition);
    this.emit(`if (${cond}) {`);
    this.indentLevel++;
    
    if (stmt.then.kind === "Block") {
      this.genBlock(stmt.then);
    } else {
      this.genStatement(stmt.then);
    }
    
    this.indentLevel--;

    for (const elif of stmt.elseIfs) {
      const elifCond = this.genExpr(elif.condition);
      this.emit(`} else if (${elifCond}) {`);
      this.indentLevel++;
      this.genBlock(elif.body);
      this.indentLevel--;
    }

    if (stmt.else) {
      this.emit("} else {");
      this.indentLevel++;
      this.genBlock(stmt.else);
      this.indentLevel--;
    }

    this.emit("}");
  }

  /**
   * Generate an if statement where each branch returns its value
   */
  private genIfStmtWithReturn(stmt: AST.IfStmt): void {
    const cond = this.genExpr(stmt.condition);
    this.emit(`if (${cond}) {`);
    this.indentLevel++;
    
    if (stmt.then.kind === "Block") {
      this.genBlock(stmt.then, true);
    } else {
      // Single statement - wrap as return
      if (stmt.then.kind === "ExprStmt") {
        const expr = stmt.then.expr.kind === "MapExpr" 
          ? `(${this.genExpr(stmt.then.expr)})` 
          : this.genExpr(stmt.then.expr);
        this.emit(`return ${expr};`);
      } else {
        this.genStatement(stmt.then);
      }
    }
    
    this.indentLevel--;

    for (const elif of stmt.elseIfs) {
      const elifCond = this.genExpr(elif.condition);
      this.emit(`} else if (${elifCond}) {`);
      this.indentLevel++;
      this.genBlock(elif.body, true);
      this.indentLevel--;
    }

    if (stmt.else) {
      this.emit("} else {");
      this.indentLevel++;
      this.genBlock(stmt.else, true);
      this.indentLevel--;
    }

    this.emit("}");
  }

  private genForStmt(stmt: AST.ForStmt): void {
    if (!stmt.pattern || !stmt.iterable) {
      // Infinite loop
      this.emit("while (true) {");
      this.indentLevel++;
      this.genBlock(stmt.body);
      this.indentLevel--;
      this.emit("}");
      return;
    }

    const pattern = this.genPattern(stmt.pattern);
    const iterable = this.genExpr(stmt.iterable);

    // Check if it's a range expression
    if (stmt.iterable.kind === "RangeExpr") {
      const range = stmt.iterable as AST.RangeExpr;
      const start = this.genExpr(range.start);
      const end = this.genExpr(range.end);
      const inclusive = range.inclusive ? "<=" : "<";
      this.emit(`for (let ${pattern} = ${start}; ${pattern} ${inclusive} ${end}; ${pattern}++) {`);
    } else {
      // Use for-await-of to support both sync and async iterables (like Channel)
      this.emit(`for await (const ${pattern} of ${iterable}) {`);
    }
    
    this.indentLevel++;
    this.genBlock(stmt.body);
    this.indentLevel--;
    this.emit("}");
  }

  private genMatchStmt(stmt: AST.MatchStmt): void {
    const value = this.genExpr(stmt.value);
    const tempVar = `_match${this.tempVarCounter++}`;
    
    this.emit(`const ${tempVar} = ${value};`);
    
    let first = true;
    for (const arm of stmt.arms) {
      const condition = this.genMatchCondition(tempVar, arm.pattern, arm.guard);
      
      if (first) {
        this.emit(`if (${condition}) {`);
        first = false;
      } else {
        this.emit(`} else if (${condition}) {`);
      }
      
      this.indentLevel++;
      
      // Bind pattern variables
      this.genPatternBindings(tempVar, arm.pattern);
      
      if (arm.body.kind === "Block") {
        this.genBlock(arm.body as AST.Block);
      } else {
        const expr = this.genExpr(arm.body as AST.Expr);
        this.emit(`${expr};`);
      }
      
      this.indentLevel--;
    }
    
    this.emit("}");
  }

  private genMatchCondition(tempVar: string, pattern: AST.Pattern, guard?: AST.Expr): string {
    let condition = this.genPatternCondition(tempVar, pattern);
    
    if (guard) {
      // For identifier patterns with guards, we need to bind the variable before evaluating the guard
      if (pattern.kind === "IdentifierPattern") {
        // Use a function to create a scope where the binding exists for the guard
        condition = `${condition} && (((${pattern.name}) => (${this.genExpr(guard)}))(${tempVar}))`;
      } else {
        condition = `${condition} && (${this.genExpr(guard)})`;
      }
    }
    
    return condition;
  }

  private genPatternCondition(tempVar: string, pattern: AST.Pattern): string {
    switch (pattern.kind) {
      case "WildcardPattern":
        return "true";
      case "IdentifierPattern":
        return "true"; // Always matches, binds value
      case "LiteralPattern":
        return `${tempVar} === ${JSON.stringify(pattern.value)}`;
      case "TypePattern":
        const typeName = pattern.type.kind === "NamedType" ? pattern.type.name : "Object";
        return `${tempVar} instanceof ${typeName}`;
      case "RangePattern":
        // RangePattern has numeric start/end
        return `${tempVar} >= ${pattern.start} && ${tempVar} <= ${pattern.end}`;
      case "ArrayPattern":
        return `Array.isArray(${tempVar})`;
      case "ObjectPattern":
        return `typeof ${tempVar} === "object" && ${tempVar} !== null`;
      default:
        return "true";
    }
  }

  private genPatternBindings(tempVar: string, pattern: AST.Pattern): void {
    switch (pattern.kind) {
      case "IdentifierPattern":
        this.emit(`const ${pattern.name} = ${tempVar};`);
        break;
      case "TypePattern":
        if (pattern.binding) {
          this.emit(`const ${pattern.binding} = ${tempVar};`);
        }
        break;
      case "ArrayPattern":
        for (let i = 0; i < pattern.elements.length; i++) {
          const el = pattern.elements[i];
          if (!el) continue;
          if (el.kind === "IdentifierPattern") {
            this.emit(`const ${el.name} = ${tempVar}[${i}];`);
          } else if (el.kind === "RestPattern") {
            this.emit(`const ${el.name} = ${tempVar}.slice(${i});`);
          }
        }
        break;
      case "ObjectPattern":
        for (const prop of pattern.properties) {
          if (prop.pattern.kind === "IdentifierPattern") {
            this.emit(`const ${prop.pattern.name} = ${tempVar}.${prop.key};`);
          }
        }
        break;
    }
  }

  private genReturnStmt(stmt: AST.ReturnStmt): void {
    if (stmt.value) {
      this.emit(`return ${this.genExpr(stmt.value)};`);
    } else {
      this.emit("return;");
    }
  }

  private genYieldStmt(stmt: AST.YieldStmt): void {
    this.emit(`yield ${this.genExpr(stmt.value)};`);
  }

  private genDeferStmt(stmt: AST.DeferStmt): void {
    // Collect defer statement for execution at scope exit
    this.addDefer(stmt.body);
  }

  private genTryStmt(stmt: AST.TryStmt): void {
    this.emit("try {");
    this.indentLevel++;
    this.genBlock(stmt.body);
    this.indentLevel--;
    
    if (stmt.catch) {
      this.emit(`} catch (${stmt.catch.name}) {`);
      this.indentLevel++;
      this.genBlock(stmt.catch.body);
      this.indentLevel--;
    }
    
    this.emit("}");
  }

  private genThrowStmt(stmt: AST.ThrowStmt): void {
    const value = this.genExpr(stmt.value);
    this.emit(`throw ${value};`);
  }

  private genWithStmt(stmt: AST.WithStmt, implicitReturn: boolean = false): void {
    // With statement creates scoped context bindings with cleanup
    this.emit("{");
    this.indentLevel++;
    this.pushScope(); // Start tracking defers for this scope
    
    // Push runtime context scope
    this.emit("__ms_runtime.__pushContext();");
    
    // Create context variable(s) and register in runtime context stack
    const ctxNames: string[] = [];
    for (const ctx of stmt.contexts) {
      const expr = this.genExpr(ctx.expr);
      
      // Syntax: with let name = expr OR with expr
      let name: string;
      if (ctx.name) {
        // with let name = expr
        name = ctx.name;
        this.emit(`const ${name} = ${expr};`);
      } else {
        // with expr (anonymous) - generate temp var
        name = `__ctx${this.tempVarCounter++}`;
        this.emit(`const ${name} = ${expr};`);
      }
      ctxNames.push(name);
      
      // Register in runtime context stack by type AND all parent types (interface matching)
      const typeName = this.inferTypeName(ctx.expr);
      if (typeName) {
        // Get full type chain (concrete type + all interfaces it implements)
        const typeChain = this.getTypeChain(typeName);
        for (const t of typeChain) {
          this.emit(`__ms_runtime.__setContext("${t}", ${name});`);
        }
      }
    }
    
    // Wrap body in try/finally for cleanup
    this.emit("try {");
    this.indentLevel++;
    this.genBlock(stmt.body, implicitReturn);
    this.indentLevel--;
    this.emit("} finally {");
    this.indentLevel++;
    
    // Execute defers in reverse order (LIFO)
    const defers = this.popScope();
    for (const defer of defers.reverse()) {
      this.genStatement(defer);
    }
    
    // Call exit() on contexts
    for (const name of ctxNames) {
      this.emit(`if (${name}?.exit) ${name}.exit();`);
    }
    
    // Pop runtime context scope
    this.emit("__ms_runtime.__popContext();");
    
    this.indentLevel--;
    this.emit("}");
    this.indentLevel--;
    this.emit("}");
  }

  private genBlock(block: AST.Block, implicitReturn: boolean = false): void {
    const stmts = block.statements;
    for (let i = 0; i < stmts.length; i++) {
      const stmt = stmts[i];
      const isLast = i === stmts.length - 1;
      
      // If this is the last statement and we want implicit return
      if (isLast && implicitReturn && stmt) {
        // Expression statements should be returned
        if (stmt.kind === "ExprStmt") {
          // Wrap map expressions in parentheses to avoid JS ambiguity with blocks
          const expr = stmt.expr.kind === "MapExpr" 
            ? `(${this.genExpr(stmt.expr)})` 
            : this.genExpr(stmt.expr);
          this.emit(`return ${expr};`);
          continue;
        }
        // Match statements should be converted to return the match expression
        if (stmt.kind === "MatchStmt") {
          this.genMatchStmtWithReturn(stmt);
          continue;
        }
        // If statements should have implicit return in each branch
        if (stmt.kind === "IfStmt") {
          this.genIfStmtWithReturn(stmt);
          continue;
        }
        // With statements should propagate implicit return to their body
        if (stmt.kind === "WithStmt") {
          this.genWithStmt(stmt, true);
          continue;
        }
      }
      
      if (stmt) this.genStatement(stmt);
    }
  }
  
  /**
   * Generate a match statement that returns the matched value
   */
  private genMatchStmtWithReturn(stmt: AST.MatchStmt): void {
    const value = this.genExpr(stmt.value);
    const tempVar = `_match${this.tempVarCounter++}`;
    
    this.emit(`const ${tempVar} = ${value};`);
    
    let first = true;
    for (const arm of stmt.arms) {
      const condition = this.genMatchCondition(tempVar, arm.pattern, arm.guard);
      
      if (first) {
        this.emit(`if (${condition}) {`);
        first = false;
      } else {
        this.emit(`} else if (${condition}) {`);
      }
      
      this.indentLevel++;
      
      // Bind pattern variables
      this.genPatternBindings(tempVar, arm.pattern);
      
      if (arm.body.kind === "Block") {
        // Generate block with implicit return for the last statement
        this.genBlock(arm.body as AST.Block, true);
      } else {
        const expr = this.genExpr(arm.body as AST.Expr);
        this.emit(`return ${expr};`);
      }
      
      this.indentLevel--;
    }
    
    this.emit("}");
  }

  // ============================================
  // Expression Generation
  // ============================================

  private genExpr(expr: AST.Expr): string {
    switch (expr.kind) {
      case "Literal":
        return this.genLiteral(expr);
      case "Identifier":
        // Use this. prefix for class fields when inside a method
        if (this.currentClassFields.has(expr.name)) {
          return `this.${expr.name}`;
        }
        return expr.name;
      case "BinaryExpr":
        return this.genBinaryExpr(expr);
      case "UnaryExpr":
        return this.genUnaryExpr(expr);
      case "CallExpr":
        return this.genCallExpr(expr);
      case "IndexExpr":
        return this.genIndexExpr(expr);
      case "MemberExpr":
        return this.genMemberExpr(expr);
      case "PipeExpr":
        return this.genPipeExpr(expr);
      case "LambdaExpr":
        return this.genLambdaExpr(expr);
      case "IfExpr":
        return this.genIfExpr(expr);
      case "MatchExpr":
        return this.genMatchExpr(expr);
      case "ListExpr":
        return this.genListExpr(expr);
      case "MapExpr":
        return this.genMapExpr(expr);
      case "TemplateLiteral":
        return this.genTemplateLiteral(expr);
      case "SpawnExpr":
        return this.genSpawnExpr(expr);
      case "TypeAssertion":
        return this.genExpr(expr.expr); // Type assertions are compile-time only
      case "NullAssertion":
        return this.genExpr(expr.expr); // Runtime check could be added
      case "RangeExpr":
        return this.genRangeExpr(expr);
      default:
        return "undefined";
    }
  }

  private genLiteral(expr: AST.Literal): string {
    if (expr.value === null) return "null";
    if (typeof expr.value === "string") return JSON.stringify(expr.value);
    if (typeof expr.value === "boolean") return expr.value ? "true" : "false";
    return String(expr.value);
  }

  private genBinaryExpr(expr: AST.BinaryExpr): string {
    const left = this.genExpr(expr.left);
    const right = this.genExpr(expr.right);

    // Map Manuscript operators to JavaScript
    switch (expr.op) {
      case "and":
        return `(${left} && ${right})`;
      case "or":
        return `(${left} || ${right})`;
      case "^":
        return `Math.pow(${left}, ${right})`;
      case "is":
        return `(${left} instanceof ${right})`;
      case "??":
        return `(${left} ?? ${right})`;
      default:
        return `(${left} ${expr.op} ${right})`;
    }
  }

  private genUnaryExpr(expr: AST.UnaryExpr): string {
    const operand = this.genExpr(expr.operand);

    switch (expr.op) {
      case "not":
        return `!${operand}`;
      default:
        return `${expr.op}${operand}`;
    }
  }

  private genCallExpr(expr: AST.CallExpr): string {
    let callee = this.genExpr(expr.callee);
    
    // Prefix stdlib functions with __ms_runtime
    if (expr.callee.kind === "Identifier" && STDLIB_FUNCTIONS.has(expr.callee.name)) {
      callee = `__ms_runtime.${expr.callee.name}`;
    }
    
    // Handle generic builtin constructors like Channel[T](...)
    // The IndexExpr is Channel[T] where Channel is the constructor and T is type param
    if (expr.callee.kind === "IndexExpr" && expr.callee.object.kind === "Identifier") {
      const baseName = expr.callee.object.name;
      if (BUILTIN_CONSTRUCTORS.has(baseName)) {
        const args = this.genCallArgs(expr.args);
        return `new __ms_runtime.${baseName}(${args})`;
      }
    }
    
    const args = this.genCallArgs(expr.args);
    
    // Use 'new' for type constructors (no await)
    if (expr.callee.kind === "Identifier" && this.declaredTypes.has(expr.callee.name)) {
      return `new ${callee}(${args})`;
    }
    
    // Implicit await for all function calls
    return `(await ${callee}(${args}))`;
  }

  private genCallArgs(args: (AST.Expr | { name: string; value: AST.Expr })[]): string {
    // Check if we have named args
    const hasNamed = args.some(a => "name" in a && "value" in a);
    
    if (hasNamed) {
      // Convert to object for named args
      const parts: string[] = [];
      for (const arg of args) {
        if ("name" in arg && "value" in arg) {
          parts.push(`${arg.name}: ${this.genExpr(arg.value)}`);
        } else {
          parts.push(this.genExpr(arg as AST.Expr));
        }
      }
      return `{ ${parts.join(", ")} }`;
    }
    
    return args.map(a => this.genExpr(a as AST.Expr)).join(", ");
  }

  private genIndexExpr(expr: AST.IndexExpr): string {
    const obj = this.genExpr(expr.object);
    
    if (expr.slice) {
      const start = expr.slice.start ? this.genExpr(expr.slice.start) : "0";
      const end = expr.slice.end ? this.genExpr(expr.slice.end) : "";
      return `${obj}.slice(${start}, ${end})`;
    }
    
    const index = this.genExpr(expr.index);
    return `${obj}[${index}]`;
  }

  private genMemberExpr(expr: AST.MemberExpr): string {
    const obj = this.genExpr(expr.object);
    
    if (expr.optional) {
      return `${obj}?.${expr.property}`;
    }
    
    return `${obj}.${expr.property}`;
  }

  private genPipeExpr(expr: AST.PipeExpr): string {
    const left = this.genExpr(expr.left);
    const right = expr.right;
    
    // Pipe with implicit await
    if (right.kind === "CallExpr") {
      let callee = this.genExpr(right.callee);
      if (right.callee.kind === "Identifier" && STDLIB_FUNCTIONS.has(right.callee.name)) {
        callee = `__ms_runtime.${right.callee.name}`;
      }
      const args = [left, ...right.args.map(a => this.genExpr(a as AST.Expr))];
      return `(await ${callee}(${args.join(", ")}))`;
    } else if (right.kind === "Identifier") {
      const fnName = STDLIB_FUNCTIONS.has(right.name) ? `__ms_runtime.${right.name}` : right.name;
      return `(await ${fnName}(${left}))`;
    }
    
    return `(await (${this.genExpr(right)})(${left}))`;
  }

  private genLambdaExpr(expr: AST.LambdaExpr): string {
    const params = expr.params.map(p => {
      let param = p.name;
      if (p.rest) param = `...${param}`;
      if (p.defaultValue) param += ` = ${this.genExpr(p.defaultValue)}`;
      return param;
    }).join(", ");

    if (expr.body.kind === "Block") {
      const bodyLines: string[] = [];
      this.indentLevel++;
      for (const stmt of expr.body.statements) {
        const prevOutput = this.output;
        this.output = [];
        this.genStatement(stmt);
        bodyLines.push(...this.output);
        this.output = prevOutput;
      }
      this.indentLevel--;
      return `async (${params}) => {\n${bodyLines.join("\n")}\n${this.getIndent()}}`;
    }
    
    // All lambdas are async to support implicit await in body
    return `async (${params}) => ${this.genExpr(expr.body as AST.Expr)}`;
  }

  private genIfExpr(expr: AST.IfExpr): string {
    const cond = this.genExpr(expr.condition);
    const then = this.genExpr(expr.then);
    const elseExpr = this.genExpr(expr.else);
    return `(${cond} ? ${then} : ${elseExpr})`;
  }

  private genMatchExpr(expr: AST.MatchExpr): string {
    // Convert to IIFE with switch-like logic
    const value = this.genExpr(expr.value);
    const tempVar = `_m${this.tempVarCounter++}`;
    
    let code = `((_${tempVar}) => {\n`;
    
    for (const arm of expr.arms) {
      const condition = this.genPatternCondition(`_${tempVar}`, arm.pattern);
      code += `  if (${condition}) {\n`;
      
      // Bind pattern variables
      if (arm.pattern.kind === "IdentifierPattern") {
        code += `    const ${arm.pattern.name} = _${tempVar};\n`;
      }
      
      if (arm.body.kind === "Block") {
        // Complex body - would need proper handling
        code += `    // block body\n`;
      } else {
        code += `    return ${this.genExpr(arm.body as AST.Expr)};\n`;
      }
      
      code += `  }\n`;
    }
    
    code += `})(${value})`;
    return code;
  }

  private genListExpr(expr: AST.ListExpr): string {
    const elements = expr.elements.map(el => {
      if (el.kind === "SpreadElement") {
        return `...${this.genExpr(el.expr)}`;
      }
      return this.genExpr(el);
    });
    return `[${elements.join(", ")}]`;
  }

  private genMapExpr(expr: AST.MapExpr): string {
    if (expr.entries.length === 0) return "{}";
    
    const entries = expr.entries.map(entry => {
      if (entry.spread) {
        return `...${this.genExpr(entry.key)}`;
      }
      
      const key = entry.key.kind === "Identifier" 
        ? entry.key.name 
        : `[${this.genExpr(entry.key)}]`;
      const value = this.genExpr(entry.value);
      return `${key}: ${value}`;
    });
    
    return `{ ${entries.join(", ")} }`;
  }

  private genTemplateLiteral(expr: AST.TemplateLiteral): string {
    // Convert template literal to string concatenation
    const parts = expr.parts.map(p => {
      if (typeof p === "string") return JSON.stringify(p);
      // p is TemplateExpr
      return this.genExpr(p.expr);
    });
    return parts.length === 1 ? parts[0]! : `(${parts.join(" + ")})`;
  }

  private genSpawnExpr(expr: AST.SpawnExpr): string {
    const inner = this.genExpr(expr.expr);
    return `__ms_runtime.spawn(async () => ${inner})`;
  }

  private genRangeExpr(expr: AST.RangeExpr): string {
    const start = this.genExpr(expr.start);
    const end = this.genExpr(expr.end);
    return `__ms_runtime.range(${start}, ${end}, ${expr.inclusive})`;
  }

  // ============================================
  // Pattern Generation
  // ============================================

  private genPattern(pattern: AST.Pattern): string {
    switch (pattern.kind) {
      case "IdentifierPattern":
        return pattern.name;
      case "ArrayPattern":
        const elements = pattern.elements.map(el => this.genPattern(el));
        return `[${elements.join(", ")}]`;
      case "ObjectPattern":
        const props = pattern.properties.map(p => {
          if (p.pattern.kind === "IdentifierPattern" && p.pattern.name === p.key) {
            return p.key;
          }
          return `${p.key}: ${this.genPattern(p.pattern)}`;
        });
        return `{ ${props.join(", ")} }`;
      case "RestPattern":
        return `...${pattern.name}`;
      default:
        return "_";
    }
  }

  // ============================================
  // Helpers
  // ============================================

  private emit(line: string): void {
    this.output.push(this.getIndent() + line);
  }

  private getIndent(): string {
    return this.options.indent.repeat(this.indentLevel);
  }
}
