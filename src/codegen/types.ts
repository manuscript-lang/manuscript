// Code Generator Types
import type * as AST from "../parser/ast";
import type { Type, FunctionType, ObjectType } from "../types/types";

// Code generation options
export interface CodeGenOptions {
  indent: string;
  sourceMap: boolean;
  runtime: "bun" | "node";
  module: "esm" | "cjs";
  emitRuntimeImport: boolean;
  /** When set, emit this path instead of "manuscript/runtime" (for built output that resolves runtime internally) */
  runtimeImportPath?: string;
  /** For project compile: specifier -> emit path (e.g. "agents/coder" -> "./agents/coder.js") */
  importEmitPaths?: Map<string, string>;
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
  selfVar?: string;  // Variable name for 'this' in factory functions (e.g., "self")
};

// ============================================
// Type Helpers - use node.resolvedType
// ============================================

export function isMapType(node: AST.ASTNode): boolean {
  return node.resolvedType?.kind === "map";
}

export function getTypeName(node: AST.ASTNode): string | undefined {
  const t = node.resolvedType;
  if (t?.kind === "object") return (t as ObjectType).name;
  if (t?.kind === "ref") return t.name;
  return undefined;
}

export function isTypeConstructor(node: AST.ASTNode): boolean {
  const t = node.resolvedType;
  if (!t) return false;
  if (t.kind === "object" && !!(t as ObjectType).name) return true;
  if (t.kind === "function") {
    const fnType = t as FunctionType;
    const retType = fnType.returnType;
    if (retType.kind === "object" && !!(retType as ObjectType).name) return true;
    if (retType.kind === "generic") return true;
  }
  return false;
}

export function getParamOrder(node: AST.ASTNode): string[] | undefined {
  const t = node.resolvedType;
  if (t?.kind === "function") {
    return (t as FunctionType).params.map(p => p.name);
  }
  if (t?.kind === "object") {
    return (t as ObjectType).properties.map(p => p.name);
  }
  return undefined;
}

// Output context - manages emission state
export type Ctx = {
  out: string[];
  indent: number;
  options: CodeGenOptions;
  scopeStack: { defers: AST.Statement[] }[];
  tempCounter: number;
  typeFields: Map<string, Set<string>>; // type name -> field names (for embedding)
};

// Create fresh context
export function createCtx(options: Partial<CodeGenOptions> = {}): Ctx {
  return {
    out: [],
    indent: 0,
    typeFields: new Map(),
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
}

// Exhaustiveness helper for switch statements
export function exhaustive(_x: never): never {
  throw new Error(`Unhandled node kind`);
}
