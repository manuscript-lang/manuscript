import { describe, test, expect } from "bun:test";
import { compile, expectCompiled, compileCases } from "../helpers";

describe("CodeGen - Literals", () => {
  compileCases([
    ["42", "42"],
    ["3.14", "3.14"],
    ['"hello"', '"hello"'],
    ["true", "true"],
    ["false", "false"],
    ["null", "null"],
  ]);
});

describe("CodeGen - Identifiers", () => {
  test("identifier", () => {
    expectCompiled("x", /\bx\b/);
  });
});

describe("CodeGen - Binary Expressions", () => {
  compileCases([
    ["1 + 2", "(1 + 2)"],
    ["1 - 2", "(1 - 2)"],
    ["1 * 2", "(1 * 2)"],
    ["1 / 2", "(1 / 2)"],
    ["2 ^ 3", "Math.pow(2, 3)"],
    ["a and b", "(a && b)"],
    ["a or b", "(a || b)"],
    ["a ?? b", "(a ?? b)"],
  ]);

  test("is operator", () => {
    const js = compile(`type Foo
  x: number
let f = Foo(1)
let check = f is Foo`);
    expect(js).toContain("instanceof Foo");
  });
});

describe("CodeGen - Unary Expressions", () => {
  compileCases([
    ["-5", "-5"],
    ["not true", "!true"],
  ]);
});

describe("CodeGen - Lists", () => {
  compileCases([
    ["[]", "[]"],
    ["[1, 2, 3]", "[1, 2, 3]"],
    ['["a", "b"]', '["a", "b"]'],
  ]);

  test("spread in list", () => {
    expectCompiled("[...items]", "...items");
  });
});

describe("CodeGen - Maps", () => {
  compileCases([
    ["{}", "{}"],
    ["{a: 1}", "{ a: 1 }"],
    ["{a: 1, b: 2}", "a: 1"],
  ]);
});

describe("CodeGen - Member Access", () => {
  compileCases([
    ["obj.prop", "obj.prop"],
    ["obj?.prop", "obj?.prop"],
  ]);
});

describe("CodeGen - Index Access", () => {
  compileCases([
    ["arr[0]", "arr[0]"],
    ["arr[1:3]", "arr.slice(1, 3)"],
  ]);
});

describe("CodeGen - Call Expressions", () => {
  compileCases([
    ["f()", "f()"],
    ["f(1, 2)", "f(1, 2)"],
    ["obj.method()", "obj.method()"],
  ]);

  test("type constructor is factory function", () => {
    const js = compile(`type Point
  x: number
  y: number
let p = Point(1, 2)`);
    expect(js).toContain("Point(1, 2)");
    expect(js).not.toContain("new Point");
  });

  test("named arguments (generic callee → object)", () => {
    expectCompiled("f(x: 1, y: 2)", "{ x: 1, y: 2 }");
  });

  test("named arguments to user fn → positional in param order", () => {
    const js = compile(`
fn add(a: number, b: number): number
  a + b
let x = add(b: 2, a: 1)
`);
    expect(js).toContain("add(1, 2)");
    expect(js).not.toContain("add({");
  });

  test("builtin Channel constructor", () => {
    expectCompiled("Channel[number]()", "new __ms_runtime.Channel()");
  });

  test("extern type constructor with named args (MockLLM)", () => {
    const js = compile(`test "mock"
  let llm = MockLLM(responses: [{match: ".*", reply: "Done"}])`);
    expect(js).toContain("new __ms_runtime.MockLLM(");
    expect(js).toContain("responses:");
    expect(js).toContain('reply: "Done"');
  });
});

describe("CodeGen - Pipe Expressions", () => {
  test("pipe to function", () => {
    // Pipe operator is | (single pipe)
    expectCompiled("x | f", "f(x)");
  });

  test("pipe to call", () => {
    expectCompiled("x | f(1)", "f(x, 1)");
  });
});

describe("CodeGen - Lambda Expressions", () => {
  compileCases([
    ["(x) => x", "(x) => x"],
    ["(x, y) => x + y", "(x, y) => (x + y)"],
  ]);
});

describe("CodeGen - If Expressions", () => {
  test("ternary", () => {
    expectCompiled("if true then 1 else 2", "(true ? 1 : 2)");
  });
});

describe("CodeGen - Range Expressions", () => {
  test("range", () => {
    expectCompiled("0..10", "__ms_runtime.range(0, 10, false)");
  });
});

describe("CodeGen - Spawn Expressions", () => {
  test("spawn", () => {
    expectCompiled("spawn f()", "__ms_runtime.spawn");
  });
});

describe("CodeGen - Match Expressions", () => {
  test("match expression with identifier pattern", () => {
    const js = compile(`let result = match x
  n => n + 1`);
    expect(js).toContain("const n =");
    expect(js).toContain("return");
  });
});

describe("CodeGen - Template Literals", () => {
  test("simple template", () => {
    expectCompiled('let s = "hello {name}"', '"hello " + __ms_runtime.to_str(name)');
  });

  test("template with multiple parts", () => {
    expectCompiled('let s = "{a} + {b} = {c}"', '__ms_runtime.to_str(b)');
  });
});

describe("CodeGen - Maps Advanced", () => {
  test("spread in map", () => {
    expectCompiled("let m = {...base, a: 1}", "...base");
  });
});

describe("CodeGen - Index Advanced", () => {
  test("slice with no start", () => {
    expectCompiled("arr[:3]", "arr.slice(0, 3)");
  });

  test("slice with no end", () => {
    expectCompiled("arr[1:]", "arr.slice(1,");
  });
});

describe("CodeGen - Pipe Advanced", () => {
  test("pipe to stdlib function", () => {
    expectCompiled("items | len", "__ms_runtime.len(items)");
  });
});
