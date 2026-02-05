import { describe, test, expect } from "bun:test";
import { compile, check } from "../../src/cli/compiler";
import { executeWithOutput } from "../helpers/execution";

describe("E2E: Types and Enums", () => {
  test("type declaration and instantiation", async () => {
    const { output } = await executeWithOutput(`
type Point
  x: number
  y: number

let p = Point(3, 4)
print(p.x, p.y)`);
    expect(output).toContain("3 4");
  });

  test("enum declaration compiles", () => {
    const result = compile(`
enum Color
  Red = 1
  Green = 2
  Blue = 3

let c = Color.Red
`, { typeCheck: false, emitRuntimeImport: false });
    expect(result.success).toBe(true);
    expect(result.code).toContain("Color");
    expect(result.code).toContain("Red");
  });
});

describe("E2E: Type System", () => {
  test("type inference on variables", () => {
    const result = check(`
let n = 42
let s = "hello"
let b = true
let nums = [1, 2, 3]
`);
    expect(result.success).toBe(true);
  });

  test("function return type inference", () => {
    const result = check(`
fn double(x: number): number
  return x * 2

let result = double(21)
`);
    expect(result.success).toBe(true);
  });

  test("optional types", () => {
    const result = check(`
fn maybeGet(flag: bool): string?
  if flag
    return "value"
  return null

let x = maybeGet(true)
`);
    expect(result.success).toBe(true);
  });

  test("type declarations", () => {
    const result = check(`
type Point
  x: number
  y: number

let p = Point(1, 2)
`);
    expect(result.success).toBe(true);
  });
});

describe("E2E: Agents and Capabilities", () => {
  test("agent declaration compiles", () => {
    const result = compile(`
agent Assistant using (LLM)
  fn greet(): string
    return "Hello"
`, { typeCheck: false });
    
    expect(result.success).toBe(true);
    expect(result.code).toContain("function Assistant");
  });

  test("capabilities declaration compiles", () => {
    const result = compile(`
capabilities production
  llm = Claude()
`, { typeCheck: false });
    
    expect(result.success).toBe(true);
  });
});
