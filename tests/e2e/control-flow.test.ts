import { describe, test, expect } from "bun:test";
import { executeWithOutput } from "../helpers/execution";

describe("E2E: Control Flow", () => {
  test("if statement", async () => {
    const { output } = await executeWithOutput(`
let x = 10
if x > 5
  print("big")
else
  print("small")`);
    expect(output).toContain("big");
  });

  test("if-else chain", async () => {
    const { output } = await executeWithOutput(`
let score = 85
if score >= 90
  print("A")
else if score >= 80
  print("B")
else if score >= 70
  print("C")
else
  print("F")`);
    expect(output).toContain("B");
  });

  test("inline if statement", async () => {
    const { output } = await executeWithOutput(`
let x = 3
if x > 5 then print("big")
if x < 5 then print("small")`);
    expect(output).toContain("small");
    expect(output).not.toContain("big");
  });

  test("if expression", async () => {
    const { output } = await executeWithOutput(`
let x = 10
let result = if x > 5 then "big" else "small"
print(result)`);
    expect(output).toContain("big");
  });

  test("for loop with range", async () => {
    const { output } = await executeWithOutput(`
var sum = 0
for i in 1..5
  sum = sum + i
print(sum)`);
    expect(output).toContain("10");
  });

  test("for loop with list", async () => {
    const { output } = await executeWithOutput(`
let items = ["a", "b", "c"]
for item in items
  print(item)`);
    expect(output).toEqual(["a", "b", "c"]);
  });

  test("for loop with break", async () => {
    const { output } = await executeWithOutput(`
for i in 0..10
  if i == 3 then break
  print(i)`);
    expect(output).toEqual(["0", "1", "2"]);
  });

  test("for loop with continue", async () => {
    const { output } = await executeWithOutput(`
for i in 0..5
  if i == 2 then continue
  print(i)`);
    expect(output).toEqual(["0", "1", "3", "4"]);
  });
});

describe("E2E: Match Expressions", () => {
  test("basic match", async () => {
    const { output } = await executeWithOutput(`
let x = 2
match x
  1 => print("one")
  2 => print("two")
  _ => print("other")`);
    expect(output).toContain("two");
  });

  test("match with literal patterns", async () => {
    const { output } = await executeWithOutput(`
let status = "ok"
match status
  "ok" => print("success")
  "error" => print("failure")
  _ => print("unknown")`);
    expect(output).toContain("success");
  });

  test("match wildcard", async () => {
    const { output } = await executeWithOutput(`
let x = 42
match x
  1 => print("one")
  _ => print("other")`);
    expect(output).toContain("other");
  });
});

describe("E2E: Error Handling", () => {
  test("try-catch", async () => {
    const { output } = await executeWithOutput(`
try
  throw "oops"
catch e
  print("caught:", e)`);
    expect(output[0]).toContain("caught:");
  });

  test("try-catch with expression", async () => {
    const { output } = await executeWithOutput(`
fn risky()
  throw "error"

try
  risky()
catch e
  print("handled")`);
    expect(output).toContain("handled");
  });
});
