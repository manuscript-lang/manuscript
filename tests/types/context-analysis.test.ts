import { describe, test, expect } from "bun:test";
import { Parser } from "../../src/parser/parser";
import { createGlobalEnvironment } from "../../src/types/environment";
import { collectDeclarations } from "../../src/types/passes/collect-declarations";
import {
  exprContainsEscapingLambda,
} from "../../src/types/passes/context-utils";
import * as AST from "../../src/parser/ast";

const parse = (src: string) => new Parser(src).parse();

describe("Context Analysis - exprContainsEscapingLambda", () => {
  test("LambdaExpr with body that is identifier in ctxVars", () => {
    const cache = new Map<string, boolean>();
    const env = createGlobalEnvironment();
    const fnDecls = new Map<string, AST.FnDecl>();
    const lambda: AST.LambdaExpr = {
      kind: "LambdaExpr",
      params: [],
      body: { kind: "Identifier", name: "ctxVar", loc: { line: 1, column: 1, offset: 0 } },
      loc: { line: 1, column: 1, offset: 0 },
    };
    const ctxVars = new Set<string>(["ctxVar"]);
    const result = exprContainsEscapingLambda(lambda, ctxVars, env, fnDecls, cache);
    expect(typeof result).toBe("boolean");
  });

  test("Identifier in ctxVars", () => {
    const cache = new Map<string, boolean>();
    const env = createGlobalEnvironment();
    const fnDecls = new Map<string, AST.FnDecl>();
    const expr: AST.Expr = {
      kind: "Identifier",
      name: "ctxVar",
      loc: { line: 1, column: 1, offset: 0 },
    };
    const ctxVars = new Set<string>(["ctxVar"]);
    expect(exprContainsEscapingLambda(expr, ctxVars, env, fnDecls, cache)).toBe(true);
    expect(exprContainsEscapingLambda(expr, new Set(), env, fnDecls, cache)).toBe(false);
  });

  test("ListExpr and MapExpr elements", () => {
    const cache = new Map<string, boolean>();
    const env = createGlobalEnvironment();
    const fnDecls = new Map<string, AST.FnDecl>();
    const listExpr: AST.Expr = {
      kind: "ListExpr",
      elements: [
        { kind: "Identifier", name: "x", loc: { line: 1, column: 1, offset: 0 } },
      ],
      loc: { line: 1, column: 1, offset: 0 },
    };
    expect(exprContainsEscapingLambda(listExpr, new Set(["x"]), env, fnDecls, cache)).toBe(true);
    const entryLoc = { line: 1, column: 1, offset: 0 };
    const mapExpr: AST.Expr = {
      kind: "MapExpr",
      entries: [
        {
          kind: "MapEntry",
          key: { kind: "Literal", value: "k", loc: entryLoc },
          value: { kind: "Identifier", name: "y", loc: entryLoc },
          loc: entryLoc,
        },
      ],
      loc: entryLoc,
    };
    expect(exprContainsEscapingLambda(mapExpr, new Set(["y"]), env, fnDecls, cache)).toBe(true);
  });

  test("IfExpr then/else and CallExpr args", () => {
    const cache = new Map<string, boolean>();
    const env = createGlobalEnvironment();
    const fnDecls = new Map<string, AST.FnDecl>();
    const ifExpr: AST.Expr = {
      kind: "IfExpr",
      condition: { kind: "Literal", value: true, loc: { line: 1, column: 1, offset: 0 } },
      then: { kind: "Identifier", name: "a", loc: { line: 1, column: 1, offset: 0 } },
      else: { kind: "Identifier", name: "b", loc: { line: 1, column: 1, offset: 0 } },
      loc: { line: 1, column: 1, offset: 0 },
    };
    expect(exprContainsEscapingLambda(ifExpr, new Set(["a"]), env, fnDecls, cache)).toBe(true);
    expect(exprContainsEscapingLambda(ifExpr, new Set(["b"]), env, fnDecls, cache)).toBe(true);
    const callExpr: AST.Expr = {
      kind: "CallExpr",
      callee: { kind: "Identifier", name: "f", loc: { line: 1, column: 1, offset: 0 } },
      args: [{ kind: "Identifier", name: "arg", loc: { line: 1, column: 1, offset: 0 } }],
      loc: { line: 1, column: 1, offset: 0 },
    };
    expect(exprContainsEscapingLambda(callExpr, new Set(["arg"]), env, fnDecls, cache)).toBe(true);
  });
});

describe("Context Analysis - fnNeedsContext and exprNeedsContext", () => {
  test("lambda calling using function triggers fnNeedsContext", () => {
    const program = parse(`type Logger
  prefix: string
fn greet(): string using (logger: Logger)
  "hi"
fn escape(): fn (): string
  with let l = Logger(prefix: "x")
    return () => greet()`);
    const env = createGlobalEnvironment();
    const { env: populatedEnv, fnDecls } = collectDeclarations({ program, env });
    const cache = new Map<string, boolean>();
    const escapeFn = program.body.find((s): s is AST.FnDecl => s.kind === "FnDecl" && s.name === "escape")!;
    const withStmt = escapeFn.body!.statements.find((s): s is AST.WithStmt => s.kind === "WithStmt")!;
    const returnStmt = withStmt.body.statements.find((s): s is AST.ReturnStmt => s.kind === "ReturnStmt")!;
    const lambda = returnStmt.value! as AST.LambdaExpr;
    const ctxVars = new Set(withStmt.contexts.map(c => c.name).filter(Boolean)) as Set<string>;
    const contains = exprContainsEscapingLambda(lambda, ctxVars, populatedEnv, fnDecls, cache);
    expect(contains).toBe(true);
  });
});
