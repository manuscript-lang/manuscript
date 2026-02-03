import { describe, test, expect } from "bun:test";
import { executeWithOutput } from "../helpers/execution";

describe("E2E: Variables and Literals", () => {
  test("number literals", async () => {
    const { output } = await executeWithOutput(`
let x = 42
let y = 3.14
let z = 1_000_000
print(x, y, z)`);
    expect(output).toContain("42 3.14 1000000");
  });

  test("string literals", async () => {
    const { output } = await executeWithOutput(`
let s = "hello world"
print(s)`);
    expect(output).toContain("hello world");
  });

  test("boolean and null", async () => {
    const { output } = await executeWithOutput(`
let t = true
let f = false
let n = null
print(t, f, n)`);
    expect(output).toContain("true false null");
  });

  test("list literals", async () => {
    const { output } = await executeWithOutput(`
let nums = [1, 2, 3]
print(len(nums))`);
    expect(output).toContain("3");
  });

  test("map literals", async () => {
    const { output } = await executeWithOutput(`
let obj = {name: "Alice", age: 30}
print(obj.name, obj.age)`);
    expect(output).toContain("Alice 30");
  });

  test("mutable variables", async () => {
    const { output } = await executeWithOutput(`
var x = 1
x = 2
print(x)`);
    expect(output).toContain("2");
  });
});

describe("E2E: Operators", () => {
  test("arithmetic operators", async () => {
    const { output } = await executeWithOutput(`
print(2 + 3)
print(10 - 4)
print(3 * 4)
print(15 / 3)
print(17 % 5)
print(2 ^ 3)`);
    expect(output).toEqual(["5", "6", "12", "5", "2", "8"]);
  });

  test("comparison operators", async () => {
    const { output } = await executeWithOutput(`
print(1 == 1)
print(1 != 2)
print(1 < 2)
print(2 > 1)
print(1 <= 1)
print(2 >= 2)`);
    expect(output).toEqual(["true", "true", "true", "true", "true", "true"]);
  });

  test("logical operators", async () => {
    const { output } = await executeWithOutput(`
print(true and true)
print(true and false)
print(true or false)
print(not true)`);
    expect(output).toEqual(["true", "false", "true", "false"]);
  });

  test("null coalescing", async () => {
    const { output } = await executeWithOutput(`
let x = null
print(x ?? "default")`);
    expect(output).toContain("default");
  });
});

describe("E2E: Destructuring", () => {
  test("object destructuring", async () => {
    const { output } = await executeWithOutput(`
let user = {name: "Alice", age: 30}
let {name, age} = user
print(name, age)`);
    expect(output).toContain("Alice 30");
  });

  test("array destructuring", async () => {
    const { output } = await executeWithOutput(`
let nums = [1, 2, 3]
let [a, b, c] = nums
print(a, b, c)`);
    expect(output).toContain("1 2 3");
  });
});
