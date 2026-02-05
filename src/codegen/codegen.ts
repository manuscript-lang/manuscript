// Code Generator - Transpiles Manuscript AST to JavaScript
import type * as AST from "../parser/ast";
import {
  type Ctx,
  type GenOpts,
  type CodeGenOptions,
  createCtx,
  createOpts,
  emit,
  getOutput,
  resetCtx,
} from "./types";

// Import generators
import { genExpr, setGen as setExprGen } from "./expressions";
import { setGen as setStmtGen, genLet, genVar, genAssign, genIf, genFor, genMatch, genReturn, genYield, genDefer, genTry, genThrow, genWith, genExprStmt, genBlock } from "./statements";
import { genImport, genFn, genType, genEnum, genContext, genAgent, genTest, genKeywordTypeUse } from "./declarations";

// Main dispatch function - handles all AST nodes
export function gen(ctx: Ctx, node: AST.Statement | AST.Expr, opts: GenOpts): string {
  switch (node.kind) {
    // Expressions - return string
    case "Literal":
    case "Identifier":
    case "BinaryExpr":
    case "UnaryExpr":
    case "CallExpr":
    case "IndexExpr":
    case "MemberExpr":
    case "PipeExpr":
    case "LambdaExpr":
    case "IfExpr":
    case "MatchExpr":
    case "ListExpr":
    case "MapExpr":
    case "TemplateLiteral":
    case "SpawnExpr":
    case "TypeAssertion":
    case "NullAssertion":
    case "RangeExpr":
      return genExpr(ctx, node, opts);

    // Declarations - emit and return ""
    case "ImportDecl":
      genImport(ctx, node, opts);
      return "";
    case "FnDecl":
      genFn(ctx, node, opts);
      return "";
    case "ExternFnDecl":
      // Extern functions are runtime-provided
      return "";
    case "TypeDecl":
      genType(ctx, node, opts);
      return "";
    case "EnumDecl":
      genEnum(ctx, node, opts);
      return "";
    case "KeywordDecl":
      // Keywords are compile-time only, no codegen
      return "";
    case "KeywordTypeUse":
      genKeywordTypeUse(ctx, node, opts);
      return "";
    case "ContextDecl":
      genContext(ctx, node, opts);
      return "";
    case "AgentDecl":
      genAgent(ctx, node, opts);
      return "";
    case "TestDecl":
      genTest(ctx, node, opts);
      return "";

    // Statements - emit and return ""
    case "LetStmt":
      genLet(ctx, node, opts);
      return "";
    case "VarStmt":
      genVar(ctx, node, opts);
      return "";
    case "AssignStmt":
      genAssign(ctx, node, opts);
      return "";
    case "IfStmt":
      genIf(ctx, node, opts);
      return "";
    case "ForStmt":
      genFor(ctx, node, opts);
      return "";
    case "MatchStmt":
      genMatch(ctx, node, opts);
      return "";
    case "ReturnStmt":
      genReturn(ctx, node, opts);
      return "";
    case "YieldStmt":
      genYield(ctx, node, opts);
      return "";
    case "BreakStmt":
      emit(ctx, "break;");
      return "";
    case "ContinueStmt":
      emit(ctx, "continue;");
      return "";
    case "DeferStmt":
      genDefer(ctx, node);
      return "";
    case "TryStmt":
      genTry(ctx, node, opts);
      return "";
    case "ThrowStmt":
      genThrow(ctx, node, opts);
      return "";
    case "WithStmt":
      genWith(ctx, node, opts);
      return "";
    case "ExprStmt":
      genExprStmt(ctx, node, opts);
      return "";

    default:
      return "";
  }
}

// Wire up circular references
setExprGen(gen);
setStmtGen(gen);

// Collect type information and keyword declarations from program
function collectTypeInfo(program: AST.Program, opts: GenOpts, ctx: Ctx): void {
  for (const stmt of program.body) {
    if (stmt.kind === "TypeDecl") {
      opts.declaredTypes.add(stmt.name);
      if (stmt.body?.members) {
        const paramNames = stmt.body.members
          .filter((m): m is AST.FieldDecl => m.kind === "FieldDecl" && !(m.embedded && m.name === "Context"))
          .map((m) => m.name);
        if (paramNames.length > 0) opts.callableParamOrder.set(stmt.name, paramNames);
      }
    } else if (stmt.kind === "EnumDecl") {
      opts.declaredTypes.add(stmt.name);
    } else if (stmt.kind === "FnDecl") {
      opts.callableParamOrder.set(stmt.name, stmt.params.map((p) => p.name));
    } else if (stmt.kind === "KeywordDecl") {
      ctx.keywordDecls.set(stmt.name, stmt);
    }
  }
}

// Emit runtime imports
function emitRuntimeImports(ctx: Ctx): void {
  if (ctx.options.emitRuntimeImport) {
    emit(ctx, 'import { __ms_runtime } from "manuscript/runtime";');
    emit(ctx, "");
  }
}

// CodeGenerator class for backward compatibility
export class CodeGenerator {
  private ctx: Ctx;

  constructor(options: Partial<CodeGenOptions> = {}) {
    this.ctx = createCtx(options);
  }

  generate(program: AST.Program): string {
    resetCtx(this.ctx);
    const opts = createOpts();

    collectTypeInfo(program, opts, this.ctx);
    emitRuntimeImports(this.ctx);

    for (const stmt of program.body) {
      gen(this.ctx, stmt, opts);
    }

    return getOutput(this.ctx);
  }
}

// Re-export types for external use
export type { CodeGenOptions } from "./types";
