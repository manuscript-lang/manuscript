import { describe, test, expect } from "bun:test";
import { executeWithOutput } from "../helpers/execution";

describe("E2E: Standard Library", () => {
  test("string functions", async () => {
    const { output } = await executeWithOutput(`
print(len("hello"))
print(upper("hello"))
print(lower("HELLO"))
print(trim("  hi  "))
print(split("a,b,c", ","))`);
    expect(output[0]).toBe("5");
    expect(output[1]).toBe("HELLO");
    expect(output[2]).toBe("hello");
    expect(output[3]).toBe("hi");
  });

  test("list functions", async () => {
    const { output } = await executeWithOutput(`
import { first, last, reverse } from "std/collections"
let nums = [1, 2, 3]
print(len(nums))
print(first(nums))
print(last(nums))
print(reverse(nums))`);
    expect(output[0]).toBe("3");
    expect(output[1]).toBe("1");
    expect(output[2]).toBe("3");
  });

  test("map/filter/reduce", async () => {
    const { output } = await executeWithOutput(`
import { map, filter, reduce } from "std/collections"
let nums = [1, 2, 3, 4, 5]
let doubled = map(nums, (x: number) => x * 2)
let evens = filter(nums, (x: number) => x % 2 == 0)
let sum = reduce(nums, 0, (acc: number, x: number) => acc + x)
print(doubled)
print(evens)
print(sum)`);
    expect(output[2]).toBe("15");
  });

  test("type conversions", async () => {
    const { output } = await executeWithOutput(`
print(to_str(42))
print(to_num("3.14"))
print(to_json({a: 1}))`);
    expect(output[0]).toBe("42");
    expect(output[1]).toBe("3.14");
    expect(output[2]).toBe('{"a":1}');
  });
});

describe("E2E: Pipe Operator", () => {
  test("basic pipe", async () => {
    const { output } = await executeWithOutput(`
let result = [1, 2, 3] | len
print(result)`);
    expect(output).toContain("3");
  });

  test("pipe chain", async () => {
    const { output } = await executeWithOutput(`
let result = "  HELLO  " | trim | lower
print(result)`);
    expect(output).toContain("hello");
  });
});
