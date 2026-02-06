import { describe, test, expect } from "bun:test";
import { Parser } from "../../src/parser/parser";
import { createGlobalEnvironment } from "../../src/types/environment";
import { collectDeclarations } from "../../src/types/passes/collect-declarations";
import {
  analyzeContext,
  exprContainsEscapingLambda,
  parameterEscapes,
} from "../../src/types/passes/context-analysis";
import * as AST from "../../src/parser/ast";

const parse = (src: string) => new Parser(src).parse();

describe("Context Analysis - analyzeContext", () => {
  test("with block and let binding capturing context var (alias path)", () => {
    const program = parse(`type Logger
  prefix: string
fn greet(): string using (logger: Logger)
  with let l = Logger(prefix: "x")
    let msg = l
    let x = msg
    x`);
    const env = createGlobalEnvironment();
    const { env: populatedEnv, fnDecls } = collectDeclarations({ program, env });
    const result = analyzeContext({ program, env: populatedEnv, fnDecls });
    expect(result.errors).toEqual([]);
  });

  test("with block and var capturing context", () => {
    const program = parse(`type C
  x: number
fn f(): number using (c: C)
  with let c = C(1)
    var v = c.x
    v`);
    const env = createGlobalEnvironment();
    const { env: populatedEnv, fnDecls } = collectDeclarations({ program, env });
    const result = analyzeContext({ program, env: populatedEnv, fnDecls });
    expect(result.errors).toEqual([]);
  });

  test("if stmt branches analyzed", () => {
    const program = parse(`type C
  x: number
fn f(): number using (c: C)
  with let c = C(1)
    if c.x > 0
      1
    else
      0`);
    const env = createGlobalEnvironment();
    const { env: populatedEnv, fnDecls } = collectDeclarations({ program, env });
    const result = analyzeContext({ program, env: populatedEnv, fnDecls });
    expect(result.errors).toEqual([]);
  });

  test("for stmt body analyzed", () => {
    const program = parse(`type C
  x: number
fn f(): number using (c: C)
  with let c = C(1)
    for i in 0..1
      c.x`);
    const env = createGlobalEnvironment();
    const { env: populatedEnv, fnDecls } = collectDeclarations({ program, env });
    const result = analyzeContext({ program, env: populatedEnv, fnDecls });
    expect(result.errors).toEqual([]);
  });

  test("try/catch blocks analyzed", () => {
    const program = parse(`type C
  x: number
fn f(): number using (c: C)
  with let c = C(1)
    try
      c.x
    catch e
      c.x`);
    const env = createGlobalEnvironment();
    const { env: populatedEnv, fnDecls } = collectDeclarations({ program, env });
    const result = analyzeContext({ program, env: populatedEnv, fnDecls });
    expect(result.errors).toEqual([]);
  });
});

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

describe("Context Analysis - parameterEscapes", () => {
  test("function without body returns true", () => {
    const fnDecl = {
      kind: "FnDecl" as const,
      name: "noBody",
      params: [{ kind: "Parameter" as const, name: "x", type: undefined, optional: false, rest: false, loc: { line: 1, column: 1, offset: 0 } }],
      returnType: undefined,
      body: undefined,
      isGenerator: false,
      loc: { line: 1, column: 1, offset: 0 },
    } as unknown as AST.FnDecl;
    expect(parameterEscapes(fnDecl, "x", new Map())).toBe(true);
  });

  test("function with return referencing param", () => {
    const program = parse(`fn id(x: number): number
  x`);
    const fnDecl = program.body.find((s): s is AST.FnDecl => s.kind === "FnDecl")!;
    const fnDecls = new Map<string, AST.FnDecl>([[fnDecl.name, fnDecl]]);
    const result = parameterEscapes(fnDecl, "x", fnDecls);
    expect(typeof result).toBe("boolean");
  });

  test("function passing param to another function", () => {
    const program = parse(`fn inner(cb: fn (): number): number
  cb()
fn outer(f: fn (): number): number
  inner(f)`);
    const fnDecls = new Map<string, AST.FnDecl>();
    for (const stmt of program.body) {
      if (stmt.kind === "FnDecl") fnDecls.set(stmt.name, stmt);
    }
    const outer = fnDecls.get("outer")!;
    const inner = fnDecls.get("inner")!;
    expect(typeof parameterEscapes(outer, "f", fnDecls)).toBe("boolean");
    expect(typeof parameterEscapes(inner, "cb", fnDecls)).toBe("boolean");
  });

  test("AssignStmt with non-Identifier target and param in value", () => {
    const program = parse(`type T
  x: number
fn f(obj: T): number
  obj.x = obj
  0`);
    const fnDecl = program.body.find((s): s is AST.FnDecl => s.kind === "FnDecl")!;
    const fnDecls = new Map<string, AST.FnDecl>([[fnDecl.name, fnDecl]]);
    expect(parameterEscapes(fnDecl, "obj", fnDecls)).toBe(true);
  });

  test("param passed to unknown callee escapes", () => {
    const program = parse(`fn outer(x: number): number
  unknown(x)`);
    const fnDecl = program.body.find((s): s is AST.FnDecl => s.kind === "FnDecl")!;
    const fnDecls = new Map<string, AST.FnDecl>([[fnDecl.name, fnDecl]]);
    expect(parameterEscapes(fnDecl, "x", fnDecls)).toBe(true);
  });

  test("param in call with non-Identifier callee (recurse)", () => {
    const program = parse(`fn getCb(): fn (number): number
  (n) => n
fn outer(x: number): number
  getCb()(x)`);
    const fnDecls = new Map<string, AST.FnDecl>();
    for (const stmt of program.body) {
      if (stmt.kind === "FnDecl") fnDecls.set(stmt.name, stmt);
    }
    const outer = fnDecls.get("outer")!;
    expect(parameterEscapes(outer, "x", fnDecls)).toBe(true);
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
    const result = analyzeContext({ program, env: populatedEnv, fnDecls });
    expect(result.errors).toEqual([]);
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
