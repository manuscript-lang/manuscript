import { describe, test, expect } from "bun:test";
import { expr, exprCases, binary, lit, id, call, member, index, unary, list, lambda, pipe, range, ifExpr } from "../helpers";

describe("Parser - Literals", () => {
  exprCases([
    ["42", lit(42)],
    ["3.14", lit(3.14)],
    ['"hello"', lit("hello")],
    ["true", lit(true)],
    ["false", lit(false)],
    ["null", lit(null)],
  ]);
});

describe("Parser - Identifiers", () => {
  exprCases([
    ["foo", id("foo")],
    ["bar123", id("bar123")],
    ["_private", id("_private")],
  ]);
});

describe("Parser - Binary Operators", () => {
  describe("Arithmetic", () => {
    exprCases([
      ["1 + 2", binary("+", lit(1), lit(2))],
      ["1 - 2", binary("-", lit(1), lit(2))],
      ["1 * 2", binary("*", lit(1), lit(2))],
      ["1 / 2", binary("/", lit(1), lit(2))],
      ["1 % 2", binary("%", lit(1), lit(2))],
      ["2 ^ 3", binary("^", lit(2), lit(3))],
    ]);
  });

  describe("Comparison", () => {
    exprCases([
      ["a == b", binary("==", id("a"), id("b"))],
      ["a != b", binary("!=", id("a"), id("b"))],
      ["a < b", binary("<", id("a"), id("b"))],
      ["a > b", binary(">", id("a"), id("b"))],
      ["a <= b", binary("<=", id("a"), id("b"))],
      ["a >= b", binary(">=", id("a"), id("b"))],
    ]);
  });

  describe("Logical", () => {
    exprCases([
      ["a and b", binary("and", id("a"), id("b"))],
      ["a or b", binary("or", id("a"), id("b"))],
    ]);
  });

  describe("Nullish", () => {
    exprCases([
      ["a ?? b", binary("??", id("a"), id("b"))],
    ]);
  });
});

describe("Parser - Operator Precedence", () => {
  test("* before +", () => {
    expect(expr("1 + 2 * 3")).toMatchObject(
      binary("+", lit(1), binary("*", lit(2), lit(3)))
    );
  });

  test("/ before -", () => {
    expect(expr("1 - 4 / 2")).toMatchObject(
      binary("-", lit(1), binary("/", lit(4), lit(2)))
    );
  });

  test("^ is right associative", () => {
    expect(expr("2 ^ 3 ^ 4")).toMatchObject(
      binary("^", lit(2), binary("^", lit(3), lit(4)))
    );
  });

  test("and before or", () => {
    expect(expr("a or b and c")).toMatchObject(
      binary("or", id("a"), binary("and", id("b"), id("c")))
    );
  });

  test("comparison before and", () => {
    expect(expr("a == b and c")).toMatchObject(
      binary("and", binary("==", id("a"), id("b")), id("c"))
    );
  });

  test("parentheses override precedence", () => {
    expect(expr("(1 + 2) * 3")).toMatchObject(
      binary("*", binary("+", lit(1), lit(2)), lit(3))
    );
  });

  test("complex precedence chain", () => {
    // a + b * c == d and e or f
    // Should parse as: ((a + (b * c)) == d) and e) or f
    const result = expr("a + b * c == d and e or f");
    expect(result).toMatchObject({
      kind: "BinaryExpr",
      op: "or",
    });
  });
});

describe("Parser - Unary Operators", () => {
  exprCases([
    ["-5", unary("-", lit(5))],
    ["not true", unary("not", lit(true))],
    ["-a", unary("-", id("a"))],
  ]);

  test("unary binds tighter than binary", () => {
    expect(expr("-a + b")).toMatchObject(
      binary("+", unary("-", id("a")), id("b"))
    );
  });

  test("double negative", () => {
    expect(expr("--5")).toMatchObject(
      unary("-", unary("-", lit(5)))
    );
  });
});

describe("Parser - Call Expressions", () => {
  test("simple call", () => {
    expect(expr("foo()")).toMatchObject(call(id("foo")));
  });

  test("call with args", () => {
    expect(expr("foo(1, 2)")).toMatchObject(call(id("foo"), lit(1), lit(2)));
  });

  test("nested calls", () => {
    expect(expr("foo(bar())")).toMatchObject(
      call(id("foo"), call(id("bar")))
    );
  });

  test("call with named args", () => {
    const result = expr("foo(a: 1, b: 2)");
    expect(result).toMatchObject({
      kind: "CallExpr",
      callee: { kind: "Identifier", name: "foo" },
    });
    expect((result as any).args[0]).toMatchObject({ name: "a", value: { kind: "Literal", value: 1 } });
  });

  test("chained calls", () => {
    expect(expr("a()()")).toMatchObject(
      call(call(id("a")))
    );
  });
});

describe("Parser - Member Access", () => {
  test("simple member", () => {
    expect(expr("a.b")).toMatchObject(member(id("a"), "b"));
  });

  test("chained member", () => {
    expect(expr("a.b.c")).toMatchObject(
      member(member(id("a"), "b"), "c")
    );
  });

  test("optional chaining", () => {
    expect(expr("a?.b")).toMatchObject(member(id("a"), "b", true));
  });

  test("member with call", () => {
    expect(expr("a.b()")).toMatchObject(
      call(member(id("a"), "b"))
    );
  });
});

describe("Parser - Index Access", () => {
  test("simple index", () => {
    expect(expr("a[0]")).toMatchObject(index(id("a"), lit(0)));
  });

  test("string key", () => {
    expect(expr('a["key"]')).toMatchObject(index(id("a"), lit("key")));
  });

  test("chained index", () => {
    expect(expr("a[0][1]")).toMatchObject(
      index(index(id("a"), lit(0)), lit(1))
    );
  });

  test("slice notation", () => {
    const result = expr("a[1:3]");
    expect(result).toMatchObject({
      kind: "IndexExpr",
      slice: { start: { value: 1 }, end: { value: 3 } },
    });
  });

  test("slice with step", () => {
    const result = expr("a[::2]");
    expect(result).toMatchObject({
      kind: "IndexExpr",
      slice: { step: { value: 2 } },
    });
  });
});

describe("Parser - List Expressions", () => {
  test("empty list", () => {
    expect(expr("[]")).toMatchObject({ kind: "ListExpr", elements: [] });
  });

  test("list with elements", () => {
    expect(expr("[1, 2, 3]")).toMatchObject(list(lit(1), lit(2), lit(3)));
  });

  test("nested lists", () => {
    expect(expr("[[1], [2]]")).toMatchObject(
      list(list(lit(1)), list(lit(2)))
    );
  });

  test("list with spread", () => {
    const result = expr("[...items]");
    expect(result).toMatchObject({
      kind: "ListExpr",
      elements: [{ kind: "SpreadElement", expr: { kind: "Identifier", name: "items" } }],
    });
  });
});

describe("Parser - Map Expressions", () => {
  test("empty map", () => {
    expect(expr("{}")).toMatchObject({ kind: "MapExpr", entries: [] });
  });

  test("map with entries", () => {
    const result = expr("{a: 1, b: 2}");
    expect(result).toMatchObject({
      kind: "MapExpr",
      entries: [
        { key: { kind: "Identifier", name: "a" }, value: { kind: "Literal", value: 1 } },
        { key: { kind: "Identifier", name: "b" }, value: { kind: "Literal", value: 2 } },
      ],
    });
  });

  test("map with string keys", () => {
    const result = expr('{"key": value}');
    expect(result).toMatchObject({
      kind: "MapExpr",
      entries: [
        { key: { kind: "Literal", value: "key" }, value: { kind: "Identifier", name: "value" } },
      ],
    });
  });

  test("map with keyword as key (e.g. match)", () => {
    const result = expr('{match: ".*", reply: "Done"}');
    expect(result).toMatchObject({
      kind: "MapExpr",
      entries: [
        { key: { kind: "Identifier", name: "match" }, value: { kind: "Literal", value: ".*" } },
        { key: { kind: "Identifier", name: "reply" }, value: { kind: "Literal", value: "Done" } },
      ],
    });
  });
});

describe("Parser - Lambda Expressions", () => {
  test("single param no parens", () => {
    expect(expr("(x) => x")).toMatchObject(lambda(["x"], id("x")));
  });

  test("multiple params", () => {
    expect(expr("(a, b) => a + b")).toMatchObject(
      lambda(["a", "b"], binary("+", id("a"), id("b")))
    );
  });

  test("no params", () => {
    expect(expr("() => 42")).toMatchObject(lambda([], lit(42)));
  });

  test("lambda with typed params", () => {
    const result = expr("(x: number) => x");
    expect(result).toMatchObject({
      kind: "LambdaExpr",
      params: [{ kind: "Parameter", name: "x", type: { kind: "NamedType", name: "number" } }],
    });
  });
});

describe("Parser - Pipe Expressions", () => {
  test("simple pipe", () => {
    expect(expr("a | b")).toMatchObject(pipe(id("a"), id("b")));
  });

  test("chained pipes", () => {
    expect(expr("a | b | c")).toMatchObject(
      pipe(pipe(id("a"), id("b")), id("c"))
    );
  });

  test("pipe to call", () => {
    expect(expr("data | map(f)")).toMatchObject(
      pipe(id("data"), call(id("map"), id("f")))
    );
  });
});

describe("Parser - Range Expressions", () => {
  test("simple range", () => {
    expect(expr("0..10")).toMatchObject(range(lit(0), lit(10)));
  });

  test("range with expressions", () => {
    expect(expr("start..end")).toMatchObject(range(id("start"), id("end")));
  });
});

describe("Parser - Conditional Expressions", () => {
  test("if-then-else expression", () => {
    expect(expr("if a then b else c")).toMatchObject(
      ifExpr(id("a"), id("b"), id("c"))
    );
  });

  test("nested conditionals", () => {
    expect(expr("if a then if b then c else d else e")).toMatchObject({
      kind: "IfExpr",
      condition: { kind: "Identifier", name: "a" },
      then: {
        kind: "IfExpr",
        condition: { kind: "Identifier", name: "b" },
      },
    });
  });
});

describe("Parser - Type Operators", () => {
  test("is type check", () => {
    const result = expr("x is number");
    expect(result).toMatchObject({
      kind: "IsExpr",
      expr: { kind: "Identifier", name: "x" },
      type: { kind: "NamedType", name: "number" },
    });
  });

  test("is with generic type", () => {
    const result = expr("x is list[number]");
    expect(result).toMatchObject({
      kind: "IsExpr",
      expr: { kind: "Identifier", name: "x" },
      type: { kind: "GenericType", name: "list", args: [{ kind: "NamedType", name: "number" }] },
    });
  });

  test("is with optional type", () => {
    const result = expr("x is Node?");
    expect(result).toMatchObject({
      kind: "IsExpr",
      expr: { kind: "Identifier", name: "x" },
      type: { kind: "OptionalType", inner: { kind: "NamedType", name: "Node" } },
    });
  });

  test("as type assertion", () => {
    const result = expr("x as string");
    expect(result).toMatchObject({
      kind: "TypeAssertion",
      expr: { kind: "Identifier", name: "x" },
      type: { kind: "NamedType", name: "string" },
    });
  });

  test("null assertion", () => {
    const result = expr("x!");
    expect(result).toMatchObject({
      kind: "NullAssertion",
      expr: { kind: "Identifier", name: "x" },
    });
  });
});

describe("Parser - Spawn Expressions", () => {
  test("spawn call", () => {
    const result = expr("spawn foo()");
    expect(result).toMatchObject({
      kind: "SpawnExpr",
      expr: { kind: "CallExpr", callee: { kind: "Identifier", name: "foo" } },
    });
  });

  test("spawn identifier", () => {
    const result = expr("spawn task");
    expect(result).toMatchObject({
      kind: "SpawnExpr",
      expr: { kind: "Identifier", name: "task" },
    });
  });
});
