import { describe, test, expect } from "bun:test";
import { executeWithOutput } from "../helpers/execution";

describe("E2E: Functions", () => {
  test("basic function definition and call", async () => {
    const { output } = await executeWithOutput(`
fn greet(name: string): string
  return "Hello, " + name

let result = greet("World")
print(result)`);
    expect(output).toContain("Hello, World");
  });

  test("function with multiple parameters", async () => {
    const { output } = await executeWithOutput(`
fn add(a: number, b: number): number
  return a + b

let result = add(2, 3)
print(result)`);
    expect(output).toContain("5");
  });

  test("function with default parameters", async () => {
    const { output } = await executeWithOutput(`
fn greet(name: string = "World"): string
  return "Hello, " + name

print(greet())
print(greet("Alice"))`);
    expect(output).toEqual(["Hello, World", "Hello, Alice"]);
  });

  test("lambda expressions", async () => {
    const { output } = await executeWithOutput(`
let double = (x: number) => x * 2
print(double(5))`);
    expect(output).toContain("10");
  });

  test("higher-order functions", async () => {
    const { output } = await executeWithOutput(`
fn apply(f: fn(number): number, x: number): number
  return f(x)

let inc = (n: number) => n + 1
print(apply(inc, 5))`);
    expect(output).toContain("6");
  });

  test("closure captures variables", async () => {
    const { output } = await executeWithOutput(`
var total = 0
fn addToTotal(n: number)
  total = total + n
addToTotal(1)
addToTotal(2)
addToTotal(3)
print(total)`);
    expect(output).toContain("6");
  });
});
