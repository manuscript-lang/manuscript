import { describe, test, expect } from "bun:test";
import { stmt, program, expectParseError } from "../helpers";

describe("Parser - Let Statements", () => {
  test("simple let", () => {
    const result = stmt("let x = 42");
    expect(result).toMatchObject({
      kind: "LetStmt",
      pattern: { kind: "IdentifierPattern", name: "x" },
      value: { kind: "Literal", value: 42 },
    });
  });

  test("let with type", () => {
    const result = stmt("let x: number = 42");
    expect(result).toMatchObject({
      kind: "LetStmt",
      pattern: { kind: "IdentifierPattern", name: "x" },
      type: { kind: "NamedType", name: "number" },
      value: { kind: "Literal", value: 42 },
    });
  });

  test("destructuring let", () => {
    const result = stmt("let {a, b} = obj");
    expect(result).toMatchObject({
      kind: "LetStmt",
      pattern: {
        kind: "ObjectPattern",
        properties: [
          { key: "a", pattern: { kind: "IdentifierPattern", name: "a" } },
          { key: "b", pattern: { kind: "IdentifierPattern", name: "b" } },
        ],
      },
    });
  });

  test("array destructuring", () => {
    const result = stmt("let [first, second] = items");
    expect(result).toMatchObject({
      kind: "LetStmt",
      pattern: {
        kind: "ArrayPattern",
        elements: [
          { kind: "IdentifierPattern", name: "first" },
          { kind: "IdentifierPattern", name: "second" },
        ],
      },
    });
  });

  test("rest pattern", () => {
    const result = stmt("let [first, ...rest] = items");
    expect(result).toMatchObject({
      kind: "LetStmt",
      pattern: {
        kind: "ArrayPattern",
        elements: [
          { kind: "IdentifierPattern", name: "first" },
          { kind: "RestPattern", name: "rest" },
        ],
      },
    });
  });
});

describe("Parser - Var Statements", () => {
  test("simple var", () => {
    const result = stmt("var x = 0");
    expect(result).toMatchObject({
      kind: "VarStmt",
      name: "x",
      value: { kind: "Literal", value: 0 },
    });
  });

  test("var with type", () => {
    const result = stmt("var count: number = 0");
    expect(result).toMatchObject({
      kind: "VarStmt",
      name: "count",
      type: { kind: "NamedType", name: "number" },
    });
  });
});

describe("Parser - Assignment Statements", () => {
  test("simple assignment", () => {
    const result = stmt("x = 1");
    expect(result).toMatchObject({
      kind: "AssignStmt",
      target: { kind: "Identifier", name: "x" },
      op: "=",
      value: { kind: "Literal", value: 1 },
    });
  });

  test("compound assignments", () => {
    expect(stmt("x += 1")).toMatchObject({ kind: "AssignStmt", op: "+=" });
    expect(stmt("x -= 1")).toMatchObject({ kind: "AssignStmt", op: "-=" });
    expect(stmt("x *= 2")).toMatchObject({ kind: "AssignStmt", op: "*=" });
    expect(stmt("x /= 2")).toMatchObject({ kind: "AssignStmt", op: "/=" });
    expect(stmt("x %= 3")).toMatchObject({ kind: "AssignStmt", op: "%=" });
  });

  test("member assignment", () => {
    const result = stmt("obj.field = value");
    expect(result).toMatchObject({
      kind: "AssignStmt",
      target: { kind: "MemberExpr", property: "field" },
    });
  });

  test("index assignment", () => {
    const result = stmt("arr[0] = value");
    expect(result).toMatchObject({
      kind: "AssignStmt",
      target: { kind: "IndexExpr" },
    });
  });
});

describe("Parser - If Statements", () => {
  test("if with block", () => {
    const src = `if x > 0
  print(x)`;
    const result = stmt(src);
    expect(result).toMatchObject({
      kind: "IfStmt",
      condition: { kind: "BinaryExpr", op: ">" },
      then: {
        kind: "Block",
        statements: [{ kind: "ExprStmt" }],
      },
    });
  });

  test("inline if-then", () => {
    const result = stmt("if x then return 0");
    expect(result).toMatchObject({
      kind: "IfStmt",
      condition: { kind: "Identifier", name: "x" },
      then: { kind: "ReturnStmt" },
    });
  });

  test("if-else", () => {
    const src = `if cond
  a
else
  b`;
    const result = stmt(src);
    expect(result).toMatchObject({
      kind: "IfStmt",
      then: { kind: "Block" },
      else: { kind: "Block" },
    });
  });

  test("if-else-if chain", () => {
    const src = `if a
  x
else if b
  y
else
  z`;
    const result = stmt(src);
    expect(result).toMatchObject({
      kind: "IfStmt",
      elseIfs: [{ condition: { kind: "Identifier", name: "b" } }],
      else: { kind: "Block" },
    });
  });

  test("guard form: if let", () => {
    const result = stmt('if let user = get_user(id) else return "Not found"');
    expect(result).toMatchObject({
      kind: "IfStmt",
      pattern: { kind: "IdentifierPattern", name: "user" },
      elseReturn: { kind: "Literal", value: "Not found" },
    });
  });
});

describe("Parser - For Statements", () => {
  test("for-in loop", () => {
    const src = `for item in items
  print(item)`;
    const result = stmt(src);
    expect(result).toMatchObject({
      kind: "ForStmt",
      pattern: { kind: "IdentifierPattern", name: "item" },
      iterable: { kind: "Identifier", name: "items" },
    });
  });

  test("for with destructuring", () => {
    const src = `for {key, value} in entries(map)
  print(key)`;
    const result = stmt(src);
    expect(result).toMatchObject({
      kind: "ForStmt",
      pattern: { kind: "ObjectPattern" },
    });
  });

  test("for with range", () => {
    const src = `for i in 0..10
  print(i)`;
    const result = stmt(src);
    expect(result).toMatchObject({
      kind: "ForStmt",
      iterable: { kind: "RangeExpr" },
    });
  });

  test("infinite loop", () => {
    const src = `for
  if done then break`;
    const result = stmt(src);
    expect(result.kind).toBe("ForStmt");
    // Infinite loop has no pattern and no iterable
    const forStmt = result as any;
    expect(forStmt.pattern).toBeUndefined();
    expect(forStmt.iterable).toBeUndefined();
    expect(forStmt.body.kind).toBe("Block");
  });
});

describe("Parser - Match Statements", () => {
  test("simple match", () => {
    const src = `match value
  1 => "one"
  2 => "two"
  _ => "other"`;
    const result = stmt(src);
    expect(result).toMatchObject({
      kind: "MatchStmt",
      arms: [
        { pattern: { kind: "LiteralPattern", value: 1 } },
        { pattern: { kind: "LiteralPattern", value: 2 } },
        { pattern: { kind: "WildcardPattern" } },
      ],
    });
  });

  test("match with guard", () => {
    const src = `match n
  x if x > 0 => "positive"
  _ => "other"`;
    const result = stmt(src);
    expect(result.kind).toBe("MatchStmt");
    const matchStmt = result as any;
    expect(matchStmt.arms[0].pattern).toMatchObject({ kind: "IdentifierPattern", name: "x" });
    expect(matchStmt.arms[0].guard).toMatchObject({ kind: "BinaryExpr", op: ">" });
  });

  test("match with type pattern", () => {
    const src = `match msg
  Text as t => t.content
  Image as i => i.url`;
    const result = stmt(src);
    expect(result).toMatchObject({
      kind: "MatchStmt",
      arms: [
        { pattern: { kind: "TypePattern", binding: "t" } },
        { pattern: { kind: "TypePattern", binding: "i" } },
      ],
    });
  });

  test("match with range pattern", () => {
    const src = `match status
  200..299 => "success"
  _ => "error"`;
    const result = stmt(src);
    expect(result.kind).toBe("MatchStmt");
    const matchStmt = result as any;
    expect(matchStmt.arms[0].pattern).toMatchObject({ 
      kind: "RangePattern", 
      start: 200, 
      end: 299 
    });
  });
});

describe("Parser - Control Flow", () => {
  test("return with value", () => {
    const result = stmt("return x + 1");
    expect(result).toMatchObject({
      kind: "ReturnStmt",
      value: { kind: "BinaryExpr" },
    });
  });

  test("return without value", () => {
    const result = stmt("return");
    expect(result).toMatchObject({
      kind: "ReturnStmt",
      value: undefined,
    });
  });

  test("yield", () => {
    const result = stmt("yield item");
    expect(result).toMatchObject({
      kind: "YieldStmt",
      value: { kind: "Identifier", name: "item" },
    });
  });

  test("break", () => {
    expect(stmt("break")).toMatchObject({ kind: "BreakStmt" });
  });

  test("continue", () => {
    expect(stmt("continue")).toMatchObject({ kind: "ContinueStmt" });
  });
});

describe("Parser - Defer Statements", () => {
  test("simple defer", () => {
    const result = stmt("defer file.close()");
    expect(result).toMatchObject({
      kind: "DeferStmt",
      body: { kind: "ExprStmt" },
    });
  });
});

describe("Parser - Try-Catch", () => {
  test("try-catch", () => {
    const src = `try
  risky()
catch e
  handle(e)`;
    const result = stmt(src);
    expect(result).toMatchObject({
      kind: "TryStmt",
      body: { kind: "Block" },
      catch: { name: "e", body: { kind: "Block" } },
    });
  });

  test("try without catch", () => {
    const src = `try
  maybe_fail()`;
    const result = stmt(src);
    expect(result).toMatchObject({
      kind: "TryStmt",
      catch: undefined,
    });
  });
});

describe("Parser - Throw", () => {
  test("throw string", () => {
    // throw("error") parses as throw followed by grouped expression
    const result = stmt('throw("error")');
    expect(result).toMatchObject({
      kind: "ThrowStmt",
      value: { kind: "Literal", value: "error" },
    });
  });

  test("throw expression", () => {
    const result = stmt('throw "error message"');
    expect(result).toMatchObject({
      kind: "ThrowStmt",
      value: { kind: "Literal", value: "error message" },
    });
  });

  test("throw Error call", () => {
    const result = stmt('throw Error(message: "failed")');
    expect(result).toMatchObject({
      kind: "ThrowStmt",
      value: { kind: "CallExpr", callee: { kind: "Identifier", name: "Error" } },
    });
  });
});

describe("Parser - With Statements", () => {
  test("simple with", () => {
    const src = `with production()
  run()`;
    const result = stmt(src);
    expect(result).toMatchObject({
      kind: "WithStmt",
      contexts: [{ expr: { kind: "CallExpr" } }],
    });
  });

  test("with alias", () => {
    const src = `with Trace("op") as t
  t.event("start")`;
    const result = stmt(src);
    expect(result).toMatchObject({
      kind: "WithStmt",
      contexts: [{ 
        expr: { kind: "CallExpr", callee: { kind: "Identifier", name: "Trace" } },
        alias: "t" 
      }],
    });
  });

  test("multiple contexts", () => {
    const src = `with production(), Trace("op")
  run()`;
    const result = stmt(src);
    expect(result).toMatchObject({
      kind: "WithStmt",
      contexts: [{}, {}],
    });
  });
});
