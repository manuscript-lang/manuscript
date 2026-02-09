import { describe, test, expect } from "bun:test";
import { __ms_runtime } from "../../src/runtime/runtime";

// Helper to call async runtime functions
const rt = __ms_runtime;

describe("Runtime - Extern Functions", () => {
  test("len", () => {
    expect(rt.len([1, 2, 3])).toBe(3);
    expect(rt.len("hello")).toBe(5);
    expect(rt.len({ a: 1, b: 2 })).toBe(2);
    expect(rt.len(new Map([["a", 1]]))).toBe(1);
  });

  test("keys/values/entries", () => {
    expect(rt.keys({ a: 1, b: 2 })).toEqual(["a", "b"]);
    expect(rt.values({ a: 1, b: 2 })).toEqual([1, 2]);
    expect(rt.entries({ a: 1 })).toEqual([["a", 1]]);
  });

  test("sort", () => {
    expect(rt.sort([3, 1, 2])).toEqual([1, 2, 3]);
  });

  test("string functions", () => {
    expect(rt.upper("hello")).toBe("HELLO");
    expect(rt.lower("HELLO")).toBe("hello");
    expect(rt.trim("  hello  ")).toBe("hello");
    expect(rt.split("a,b,c", ",")).toEqual(["a", "b", "c"]);
    expect(rt.join(["a", "b", "c"], ",")).toBe("a,b,c");
    expect(rt.replace("hello world", "world", "there")).toBe("hello there");
    expect(rt.starts_with("hello", "hel")).toBe(true);
    expect(rt.ends_with("hello", "lo")).toBe(true);
    expect(rt.substring("hello", 1, 3)).toBe("el");
    expect(rt.matches("hello", "^hel")).toBe(true);
  });

  test("math functions", () => {
    expect(rt.sqrt(4)).toBe(2);
    expect(rt.pow(2, 3)).toBe(8);
    expect(rt.floor(3.7)).toBe(3);
    expect(rt.ceil(3.2)).toBe(4);
    expect(rt.round(3.5)).toBe(4);
  });

  test("conversion functions", () => {
    expect(rt.to_str(42)).toBe("42");
    expect(rt.to_num("42")).toBe(42);
    expect(rt.to_json({ a: 1 })).toBe('{"a":1}');
    expect(rt.from_json('{"a":1}')).toEqual({ a: 1 });
  });

  test("type operations", () => {
    expect(rt.typeof(null)).toBe("null");
    expect(rt.typeof([1, 2])).toBe("list");
    expect(rt.typeof({ a: 1 })).toBe("object");
    expect(rt.clone([1, 2, 3])).toEqual([1, 2, 3]);
    expect(typeof rt.hash("test")).toBe("number");
  });

  test("error functions", () => {
    const e = rt.error("test error");
    expect(e.message).toBe("test error");
    expect(() => rt.panic("panic!")).toThrow("panic!");
  });
});

describe("Runtime - Compiled Stdlib Functions", () => {
  test("math helpers", async () => {
    expect(await rt.abs(-5)).toBe(5);
    expect(await rt.min(3, 5)).toBe(3);
    expect(await rt.max(3, 5)).toBe(5);
    expect(await rt.clamp(10, 0, 5)).toBe(5);
  });

  test("collection functions", async () => {
    expect(await rt.first([1, 2, 3])).toBe(1);
    expect(await rt.last([1, 2, 3])).toBe(3);
    expect(await rt.take([1, 2, 3, 4], 2)).toEqual([1, 2]);
    expect(await rt.drop([1, 2, 3, 4], 2)).toEqual([3, 4]);
    expect(await rt.reverse([1, 2, 3])).toEqual([3, 2, 1]);
    expect(await rt.contains([1, 2, 3], 2)).toBe(true);
    expect(await rt.unique([1, 2, 2, 3])).toEqual([1, 2, 3]);
    expect(await rt.flatten([[1, 2], [3, 4]])).toEqual([1, 2, 3, 4]);
    expect(await rt.zip([1, 2], ["a", "b"])).toEqual([[1, "a"], [2, "b"]]);
    expect(await rt.concat([1, 2], [3, 4])).toEqual([1, 2, 3, 4]);
    expect(await rt.slice([1, 2, 3, 4], 1, 3)).toEqual([2, 3]);
    expect(await rt.range(0, 3)).toEqual([0, 1, 2]);
  });

  test("higher-order functions", async () => {
    expect(await rt.map([1, 2, 3], (x: number) => x * 2)).toEqual([2, 4, 6]);
    expect(await rt.filter([1, 2, 3, 4], (x: number) => x % 2 === 0)).toEqual([2, 4]);
    expect(await rt.reduce([1, 2, 3], 0, (a: number, x: number) => a + x)).toBe(6);
    expect(await rt.find([1, 2, 3], (x: number) => x > 1)).toBe(2);
    expect(await rt.any([1, 2, 3], (x: number) => x > 2)).toBe(true);
    expect(await rt.all([1, 2, 3], (x: number) => x > 0)).toBe(true);
  });

  test("set functions", async () => {
    const s = await rt.set([1, 2, 2, 3]);
    expect(rt.len(s)).toBe(3);
  });

  test("result helpers", async () => {
    type OkResult = { __typename: string; ok: boolean; value?: number };
    type ErrResult = { __typename: string; ok: boolean; error?: string };
    const success = (await rt.ok(42)) as OkResult;
    expect(success.__typename).toBe("Result");
    expect(success.ok).toBe(true);
    expect(success.value).toBe(42);
    const failure = (await rt.err("failed")) as ErrResult;
    expect(failure.__typename).toBe("Result");
    expect(failure.ok).toBe(false);
    expect(failure.error).toBe("failed");
  });

  test("equality", async () => {
    expect(await rt.equals({ a: 1 }, { a: 1 })).toBe(true);
    expect(await rt.equals([1, 2], [1, 2])).toBe(true);
    expect(await rt.equals([1, 2], [1, 3])).toBe(false);
  });
});
