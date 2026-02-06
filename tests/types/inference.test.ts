import { describe, test, expect } from "bun:test";
import { typeCases, inferType, checkOk, checkFails } from "../helpers";

describe("Type Inference - Literals", () => {
  typeCases([
    ["42", "number"],
    ["3.14", "number"],
    ['"hello"', "string"],
    ["true", "bool"],
    ["false", "bool"],
    ["null", "null"],
  ]);
});

describe("Type Inference - Variables", () => {
  test("let infers type from value", () => {
    expect(inferType("let x = 42")).toBe("number");
  });

  test("let with type annotation", () => {
    const result = checkOk("let x: number = 42");
    expect(result.errors).toHaveLength(0);
  });

  test("var infers type from value", () => {
    expect(inferType("var x = 42")).toBe("number");
  });
});

describe("Type Inference - Binary Operations", () => {
  typeCases([
    ["1 + 2", "number"],
    ["1 - 2", "number"],
    ["1 * 2", "number"],
    ["1 / 2", "number"],
    ["1 % 2", "number"],
    ["2 ^ 3", "number"],
    ['"a" + "b"', "string"],
    ["1 == 2", "bool"],
    ["1 != 2", "bool"],
    ["1 < 2", "bool"],
    ["1 > 2", "bool"],
    ["1 <= 2", "bool"],
    ["1 >= 2", "bool"],
    ["true and false", "bool"],
    ["true or false", "bool"],
  ]);
});

describe("Type Inference - Unary Operations", () => {
  typeCases([
    ["-5", "number"],
    ["not true", "bool"],
  ]);
});

describe("Type Inference - Lists", () => {
  typeCases([
    ["[]", "list[unknown]"],
    ["[1, 2, 3]", "list[number]"],
    ['["a", "b"]', "list[string]"],
    ["[[1], [2]]", "list[list[number]]"],
  ]);
});

describe("Type Inference - Maps", () => {
  typeCases([
    ["{}", "map[string, unknown]"],
    ["{a: 1, b: 2}", "map[string, number]"],
    ['{"x": 1, "y": 2}', "map[string, number]"],
  ]);
});

describe("Type Inference - Functions", () => {
  test("function declaration", () => {
    const src = `fn add(a: number, b: number): number
  a + b`;
    const result = checkOk(src);
    expect(result.errors).toHaveLength(0);
  });

  test("function call", () => {
    const src = `fn double(x: number): number
  x * 2
double(5)`;
    expect(inferType(src)).toBe("number");
  });
});

describe("Type Inference - Lambdas", () => {
  test("simple lambda", () => {
    expect(inferType("(x) => x")).toMatch(/fn/);
  });

  test("typed lambda", () => {
    expect(inferType("(x: number) => x * 2")).toMatch(/fn/);
  });
});

describe("Type Inference - Conditionals", () => {
  test("if expression", () => {
    expect(inferType("if true then 1 else 2")).toBe("number");
  });

  test("if expression with different types", () => {
    // Returns union type
    const result = inferType('if true then 1 else "a"');
    expect(result).toMatch(/number|string/);
  });
});

describe("Type Inference - Expected type propagation", () => {
  test("return value gets expected type from function return", () => {
    checkOk("fn f(): number\n  return 42");
  });

  test("generic identity call infers from argument and return", () => {
    const src = `fn identity[T](x: T): T
  x
identity(42)`;
    expect(inferType(src)).toBe("number");
  });

  test("match with number arms type-checks", () => {
    checkOk(`match 1
  1 => 42
  _ => 0`);
  });
});

describe("Type Inference - Patterns", () => {
  test("let with object pattern", () => {
    checkOk("let { a } = { a: 1 }\na");
    expect(inferType("let { a } = { a: 1 }\na")).toBe("number");
  });

  test("let with array pattern", () => {
    checkOk("let [x, y] = [1, 2]\nx + y");
    expect(inferType("let [x, y] = [1, 2]\nx + y")).toBe("number");
  });

  test("let with type annotation and pattern", () => {
    checkOk("let [a, b]: list[number] = [1, 2]\na");
  });
});

describe("Type Inference - Built-in Functions", () => {
  typeCases([
    ['len("hello")', "number"],
    ['upper("hello")', "string"],
    ['lower("HELLO")', "string"],
    ["abs(-5)", "number"],
    ["min(1, 2)", "number"],
    ["max(1, 2)", "number"],
    ["floor(3.7)", "number"],
    ["ceil(3.2)", "number"],
    ["round(3.5)", "number"],
  ]);
});

describe("Type Inference - Member Access", () => {
  test("list length", () => {
    expect(inferType("[1, 2, 3].length")).toBe("number");
  });

  test("string length", () => {
    expect(inferType('"hello".length')).toBe("number");
  });
});

describe("Type Inference - Index Access", () => {
  test("list index", () => {
    expect(inferType("[1, 2, 3][0]")).toBe("number");
  });

  test("string index", () => {
    expect(inferType('"hello"[0]')).toBe("string");
  });
});

describe("Type Inference - Range", () => {
  test("number range", () => {
    expect(inferType("0..10")).toBe("list[number]");
  });
});

describe("Type Inference - Null Handling", () => {
  test("null coalescing", () => {
    // a ?? b returns non-null type
    const src = `let x: number? = null
x ?? 0`;
    // This is a bit complex to test directly, just verify it type checks
    checkOk(src);
  });
});

describe("Type Inference - Spawn", () => {
  test("spawn returns promise", () => {
    // Spawn assigned and consumed via race
    const result = inferType("let x = spawn print(1)\nrace([x])");
    expect(result).toMatch(/Promise|promise/);
  });
});
