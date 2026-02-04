// Code Generator Types
import type * as AST from "../parser/ast";

// Code generation options
export interface CodeGenOptions {
  indent: string;
  sourceMap: boolean;
  runtime: "bun" | "node";
  module: "esm" | "cjs";
  emitRuntimeImport: boolean;
}

export const defaultOptions: CodeGenOptions = {
  indent: "  ",
  sourceMap: false,
  runtime: "bun",
  module: "cjs",
  emitRuntimeImport: true,
};

// Generation context - passed explicitly to all generators
export type GenOpts = {
  implicitReturn: boolean;
  classFields: Set<string> | null;
  isGenerator: boolean;
  declaredTypes: Set<string>;
  variableTypes: Map<string, string>;
  selfVar?: string;  // Variable name for 'this' in factory functions (e.g., "self")
};

// Output context - manages emission state
export type Ctx = {
  out: string[];
  indent: number;
  options: CodeGenOptions;
  scopeStack: { defers: AST.Statement[] }[];
  tempCounter: number;
  typeFields: Map<string, Set<string>>; // type name -> field names (for embedding)
  keywordDecls: Map<string, AST.KeywordDecl>; // keyword name -> declaration
};

// Create fresh context
export function createCtx(options: Partial<CodeGenOptions> = {}): Ctx {
  return {
    out: [],
    indent: 0,
    typeFields: new Map(),
    keywordDecls: new Map(),
    options: { ...defaultOptions, ...options },
    scopeStack: [],
    tempCounter: 0,
  };
}

// Create default generation options
export function createOpts(overrides: Partial<GenOpts> = {}): GenOpts {
  return {
    implicitReturn: false,
    classFields: null,
    isGenerator: false,
    declaredTypes: new Set(),
    variableTypes: new Map(),
    ...overrides,
  };
}

// Emit a line with current indentation
export function emit(ctx: Ctx, line: string): void {
  ctx.out.push(ctx.options.indent.repeat(ctx.indent) + line);
}

// Indent management
export function pushIndent(ctx: Ctx): void {
  ctx.indent++;
}

export function popIndent(ctx: Ctx): void {
  ctx.indent--;
}

// Generate unique temp variable name
export function tempVar(ctx: Ctx, prefix = "_t"): string {
  return `${prefix}${ctx.tempCounter++}`;
}

// Scope management for defer statements
export function pushScope(ctx: Ctx): void {
  ctx.scopeStack.push({ defers: [] });
}

export function popScope(ctx: Ctx): AST.Statement[] {
  return ctx.scopeStack.pop()?.defers || [];
}

export function addDefer(ctx: Ctx, stmt: AST.Statement): void {
  const scope = ctx.scopeStack[ctx.scopeStack.length - 1];
  if (scope) {
    scope.defers.push(stmt);
  }
}

// Get output as string
export function getOutput(ctx: Ctx): string {
  return ctx.out.join("\n");
}

// Reset context for new generation
export function resetCtx(ctx: Ctx): void {
  ctx.out = [];
  ctx.indent = 0;
  ctx.scopeStack = [];
  ctx.tempCounter = 0;
  ctx.typeFields = new Map();
  ctx.keywordDecls = new Map();
}

// Exhaustiveness helper for switch statements
export function exhaustive(_x: never): never {
  throw new Error(`Unhandled node kind`);
}
