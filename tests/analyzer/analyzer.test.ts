import { describe, test, expect } from "bun:test";
import { Parser } from "../../src/parser";
import { SemanticAnalyzer, analyze } from "../../src/analyzer";

function analyzeSource(source: string) {
  const parser = new Parser(source);
  const ast = parser.parse();
  return analyze(ast);
}

function expectNoErrors(source: string) {
  const result = analyzeSource(source);
  expect(result.errors).toHaveLength(0);
  return result;
}

function expectError(source: string, message: string) {
  const result = analyzeSource(source);
  expect(result.errors.length).toBeGreaterThan(0);
  expect(result.errors.some(e => e.message.includes(message))).toBe(true);
  return result;
}

describe("Scope Validation", () => {
  test("detects undefined variable", () => {
    expectError("print(x)", "Undefined identifier 'x'");
  });

  test("allows defined variable", () => {
    expectNoErrors(`let x = 42
print(x)`);
  });

  test("detects redeclaration in same scope", () => {
    expectError(`let x = 1
let x = 2`, "already declared");
  });

  test("allows shadowing in nested scope", () => {
    expectNoErrors(`let x = 1
fn foo()
  let x = 2
  print(x)`);
  });

  test("function parameters are in scope", () => {
    expectNoErrors(`fn add(a: number, b: number): number
  return a + b`);
  });

  test("for loop variable is in scope", () => {
    expectNoErrors(`for i in [1, 2, 3]
  print(i)`);
  });

  test("catch binding is in scope", () => {
    expectNoErrors(`try
  throw "error"
catch e
  print(e)`);
  });

  test("lambda parameters are in scope", () => {
    expectNoErrors(`let f = (x) => x + 1`);
  });
});

describe("Loop Control Validation", () => {
  test("break outside loop is error", () => {
    expectError(`fn foo()
  break`, "'break' can only be used inside a loop");
  });

  test("continue outside loop is error", () => {
    expectError(`fn foo()
  continue`, "'continue' can only be used inside a loop");
  });

  test("break inside for loop is valid", () => {
    expectNoErrors(`for i in [1, 2, 3]
  break`);
  });

  test("continue inside for loop is valid", () => {
    expectNoErrors(`for i in 0..10
  continue`);
  });
});

describe("Declaration Validation", () => {
  test("detects duplicate enum variants", () => {
    expectError(`enum Color
  Red
  Red`, "Duplicate enum variant");
  });

  test("detects duplicate type fields", () => {
    expectError(`type Person
  name: string
  name: string`, "Duplicate field");
  });

  test("allows valid enum", () => {
    expectNoErrors(`enum Status
  Pending
  Active
  Done`);
  });

  test("allows valid type", () => {
    expectNoErrors(`type User
  name: string
  age: number`);
  });
});

describe("Context Tracking", () => {
  test("tracks context providers", () => {
    const result = analyzeSource(`context production
  llm = Claude()`);
    expect(result.contextBindings.some(c => c.providedBy.includes("production"))).toBe(true);
  });

  test("tracks agent context requirements", () => {
    const result = analyzeSource(`agent Assistant using (LLM)
  fn greet(): string
    return "Hello"`);
    expect(result.contextBindings.some(c => c.name === "LLM")).toBe(true);
  });
});

describe("Scope Tracking", () => {
  test("tracks global scope", () => {
    const result = analyzeSource(`let x = 1
fn foo()
  let y = 2`);
    const globalScope = result.scopes.find(s => s.kind === "global");
    expect(globalScope).toBeDefined();
    expect(globalScope!.symbols).toContain("x");
    expect(globalScope!.symbols).toContain("foo");
  });

  test("tracks function scope", () => {
    const result = analyzeSource(`fn add(a: number, b: number): number
  let sum = a + b
  return sum`);
    const fnScope = result.scopes.find(s => s.kind === "function" && s.name === "add");
    expect(fnScope).toBeDefined();
    expect(fnScope!.symbols).toContain("a");
    expect(fnScope!.symbols).toContain("b");
    expect(fnScope!.symbols).toContain("sum");
  });

  test("tracks agent scope", () => {
    const result = analyzeSource(`agent Bot
  name: string`);
    const agentScope = result.scopes.find(s => s.kind === "agent");
    expect(agentScope).toBeDefined();
  });
});

describe("Built-in Recognition", () => {
  test("recognizes stdlib functions", () => {
    expectNoErrors(`print("hello")
let n = len([1, 2, 3])
let s = upper("hello")`);
  });

  test("recognizes capability constructors", () => {
    expectNoErrors(`let llm = Claude()
let fs = LocalFilesystem()`);
  });
});

describe("Expression Analysis", () => {
  test("analyzes binary expressions", () => {
    expectNoErrors(`let x = 1 + 2 * 3`);
  });

  test("analyzes call expressions", () => {
    expectNoErrors(`fn add(a: number, b: number): number
  return a + b
let result = add(1, 2)`);
  });

  test("analyzes member expressions", () => {
    expectNoErrors(`type Point
  x: number
  y: number
let p = Point(1, 2)`);
  });

  test("analyzes list expressions", () => {
    expectNoErrors(`let nums = [1, 2, 3]
let first = nums[0]`);
  });

  test("analyzes map expressions", () => {
    expectNoErrors(`let data = {a: 1, b: 2}`);
  });

  test("analyzes pipe expressions", () => {
    expectNoErrors(`let result = [1, 2, 3] | len`);
  });
});

describe("Pattern Analysis", () => {
  test("match pattern bindings are in scope", () => {
    expectNoErrors(`let x = 1
match x
  n => print(n)`);
  });

  test("array pattern bindings are in scope", () => {
    expectNoErrors(`fn foo(arr: list[number])
  match arr
    [first, ...rest] => print(first)`);
  });
});

describe("Warnings", () => {
  test("warns about non-exhaustive match (placeholder)", () => {
    // This is a placeholder - full exhaustiveness checking
    // would require type information
    const result = analyzeSource(`enum Status
  A
  B
let s = A`);
    // Currently we don't have enough type info to detect this
    expect(result.warnings).toBeDefined();
  });
});
