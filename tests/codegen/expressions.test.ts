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
