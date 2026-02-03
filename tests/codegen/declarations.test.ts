import { describe, test, expect } from "bun:test";
import { compile, expectCompiled } from "../helpers";

describe("CodeGen - Import Declarations", () => {
  test("simple import", () => {
    expectCompiled('import { foo } from "./mod"', 'import { foo } from "./mod";');
  });

  test("import with alias", () => {
    expectCompiled('import { foo as bar } from "./mod"', "foo as bar");
  });
});

describe("CodeGen - Function Declarations", () => {
  test("simple function", () => {
    const js = compile(`fn greet(name: string)
  print(name)`);
    // Functions without capabilities are not async
    expect(js).toContain("function greet(name)");
  });

  test("function with return type", () => {
    const js = compile(`fn add(a: number, b: number): number
  return a + b`);
    // Functions without capabilities are not async
    expect(js).toContain("function add(a, b)");
    expect(js).toContain("return (a + b);");
  });

  test("function with default param", () => {
    const js = compile(`fn greet(name: string = "world")
  print(name)`);
    expect(js).toContain('name = "world"');
  });

  test("function with rest param", () => {
    const js = compile(`fn sum(...nums: number)
  print(nums)`);
    expect(js).toContain("...nums");
  });

  test("generator function", () => {
    // Generators are detected by yield statements (no fn* syntax)
    const js = compile(`fn count()
  yield 1
  yield 2`);
    expect(js).toContain("function* count()");
    expect(js).toContain("yield 1;");
  });

  test("function with context bindings", () => {
    const js = compile(`fn read(path: string) using (fs: Filesystem)
  fs.read(path)`);
    // Functions with context bindings take __ctx as parameter
    expect(js).toContain("__ctx");
    // Context bindings are destructured from __ctx
    expect(js).toContain("const { fs } = __ctx;");
  });
});

describe("CodeGen - Type Declarations", () => {
  test("type as class", () => {
    const js = compile(`type User
  name: string
  age: number`);
    expect(js).toContain("class User");
    expect(js).toContain("constructor(name, age)");
    expect(js).toContain("this.name = name;");
  });

  test("type with optional field", () => {
    const js = compile(`type User
  name: string
  email?: string`);
    expect(js).toContain("email = undefined");
  });

  test("type with default value", () => {
    const js = compile(`type Config
  timeout: number = 1000`);
    expect(js).toContain("timeout = 1000");
  });

  test("type with method", () => {
    const js = compile(`type Counter
  value: number = 0
  fn increment()
    value = value + 1`);
    expect(js).toContain("increment()");
  });

  test("type extends", () => {
    const js = compile(`type Admin extends User
  role: string`);
    expect(js).toContain("extends User");
  });
});

describe("CodeGen - Enum Declarations", () => {
  test("simple enum", () => {
    const js = compile(`enum Color
  Red
  Green
  Blue`);
    expect(js).toContain("const Color = Object.freeze({");
    expect(js).toContain('Red: "Red"');
  });
});

describe("CodeGen - Agent Declarations", () => {
  test("simple agent", () => {
    const js = compile(`agent Helper using (llm: LLM)
  tool greet(name: string)
    return "Hello, " + name
  
  run(prompt: string)
    greet("world")`);
    expect(js).toContain("class Helper extends __ms_runtime.Agent");
    expect(js).toContain("async greet(name)");
    expect(js).toContain("async run(prompt)");
  });
});

describe("CodeGen - Test Declarations", () => {
  test("simple test", () => {
    const js = compile(`test "should pass"
  assert true`);
    expect(js).toContain('__ms_runtime.test("should pass"');
    expect(js).toContain("async ()");
  });
});
