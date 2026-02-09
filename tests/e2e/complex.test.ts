import { describe, test, expect } from "bun:test";
import { compile } from "../../src/compile";
import { executeWithOutput } from "../helpers/execution";

describe("E2E: Complex Programs", () => {
  test("iterative factorial", async () => {
    const { output } = await executeWithOutput(`
var result = 1
for i in 1..6
  result = result * i
print(result)`);
    expect(output).toContain("120");
  });

  test("iterative fibonacci", async () => {
    const { output } = await executeWithOutput(`
var a = 0
var b = 1
for _ in 0..10
  let temp = a + b
  a = b
  b = temp
print(a)`);
    expect(output).toContain("55");
  });

  test("list processing pipeline", async () => {
    const { output } = await executeWithOutput(`
import { filter, map, reduce } from "std/collections"
let nums = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
let evens = filter(nums, (x: number) => x % 2 == 0)
let doubled = map(evens, (x: number) => x * 2)
let sum = reduce(doubled, 0, (a: number, b: number) => a + b)
print(sum)`);
    expect(output).toContain("60");
  });

  test("string manipulation", async () => {
    const { output } = await executeWithOutput(`
import { map, filter } from "std/collections"
let words = ["hello", "world", "foo", "bar"]
let upper_words = map(words, (w: string) => upper(w))
let long_words = filter(upper_words, (w: string) => len(w) > 3)
print(long_words)`);
    expect(output[0]).toContain("HELLO");
    expect(output[0]).toContain("WORLD");
  });

  test("nested data structures", async () => {
    const { output } = await executeWithOutput(`
import { map, reduce } from "std/collections"
let users = [{name: "Alice", age: 30}, {name: "Bob", age: 25}]
let names = map(users, (u: map[string, string or number]) => u["name"] as string)
print(names)
let ages = map(users, (u: map[string, string or number]) => u["age"] as number)
let total_age = reduce(ages, 0, (a: number, b: number) => a + b)
print(total_age)`);
    expect(output[0]).toContain("Alice");
    expect(output[1]).toBe("55");
  });
});

describe("E2E: Error Detection", () => {
  test("lexer error: invalid character", () => {
    const result = compile("let x = @invalid");
    expect(result.success).toBe(false);
    expect(result.errors[0]!.phase).toBe("lexer");
  });

  test("parser error: unexpected token", () => {
    const result = compile("fn (");
    expect(result.success).toBe(false);
    expect(result.errors[0]!.phase).toBe("parser");
  });

  test("type error: type mismatch", () => {
    const result = compile(`let x: number = "string"`);
    expect(result.success).toBe(false);
    expect(result.errors.some(e => e.phase === "typecheck")).toBe(true);
  });
});

describe("E2E: Edge Cases", () => {
  test("empty program", () => {
    const result = compile("");
    expect(result.success).toBe(true);
  });

  test("comments only", () => {
    const result = compile(`
// This is a comment
// Another comment
`);
    expect(result.success).toBe(true);
  });

  test("deeply nested expressions", async () => {
    const { output } = await executeWithOutput(`
let result = ((1 + 2) * (3 + 4)) + ((5 - 6) * (7 - 8))
print(result)`);
    expect(output).toContain("22");
  });

  test("string escapes", async () => {
    const { output } = await executeWithOutput(`
print("line1\\nline2")
print("tab\\there")
print("quote\\"here\\"")`);
    expect(output[0]).toBe("line1\nline2");
    expect(output[1]).toBe("tab\there");
    expect(output[2]).toBe('quote"here"');
  });

  test("unicode in strings", async () => {
    const { output } = await executeWithOutput(`
print("Hello 世界")
print("emoji: 🎉")`);
    expect(output[0]).toBe("Hello 世界");
    expect(output[1]).toBe("emoji: 🎉");
  });
});
