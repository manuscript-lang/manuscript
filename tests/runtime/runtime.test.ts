import { describe, test, expect } from "bun:test";
import {
  len, keys, values, entries, contains, unique, flatten, sort, reverse,
  first, last, take, drop, zip, each, filter, reduce, find, any, all,
  group_by, sort_by, upper, lower, trim, split, join, replace,
  starts_with, ends_with, substring, matches, abs, min, max, floor,
  ceil, round, sqrt, pow, clamp, range, spawn, sleep, typeOf, clone,
  equals, hash, to_str, to_num, to_json, from_json, set, union,
  intersect, difference, is_subset, assert, error, ok, err, Channel,
  Agent,
} from "../../src/runtime/runtime";

describe("Runtime - Collection Functions", () => {
  test("len", () => {
    expect(len([1, 2, 3])).toBe(3);
    expect(len("hello")).toBe(5);
    expect(len({ a: 1, b: 2 })).toBe(2);
    expect(len(new Map([["a", 1]]))).toBe(1);
  });

  test("keys", () => {
    expect(keys({ a: 1, b: 2 })).toEqual(["a", "b"]);
    expect(keys(new Map([["a", 1], ["b", 2]]))).toEqual(["a", "b"]);
  });

  test("values", () => {
    expect(values({ a: 1, b: 2 })).toEqual([1, 2]);
  });

  test("entries", () => {
    expect(entries({ a: 1 })).toEqual([["a", 1]]);
  });

  test("contains", () => {
    expect(contains([1, 2, 3], 2)).toBe(true);
    expect(contains([1, 2, 3], 4)).toBe(false);
  });

  test("unique", () => {
    expect(unique([1, 2, 2, 3, 3, 3])).toEqual([1, 2, 3]);
  });

  test("flatten", () => {
    expect(flatten([[1, 2], [3, 4]])).toEqual([1, 2, 3, 4]);
  });

  test("sort", () => {
    expect(sort([3, 1, 2])).toEqual([1, 2, 3]);
  });

  test("reverse", () => {
    expect(reverse([1, 2, 3])).toEqual([3, 2, 1]);
  });

  test("first", () => {
    expect(first([1, 2, 3])).toBe(1);
    expect(first([])).toBe(undefined);
  });

  test("last", () => {
    expect(last([1, 2, 3])).toBe(3);
    expect(last([])).toBe(undefined);
  });

  test("take", () => {
    expect(take([1, 2, 3, 4], 2)).toEqual([1, 2]);
  });

  test("drop", () => {
    expect(drop([1, 2, 3, 4], 2)).toEqual([3, 4]);
  });

  test("zip", () => {
    expect(zip([1, 2], ["a", "b"])).toEqual([[1, "a"], [2, "b"]]);
  });
});

describe("Runtime - Higher Order Functions", () => {
  test("map", async () => {
    const { map } = require("../../src/runtime/collections");
    expect(await map([1, 2, 3], (x: number) => x * 2)).toEqual([2, 4, 6]);
  });

  test("each", async () => {
    expect(await each([1, 2, 3], (x) => x * 2)).toEqual([2, 4, 6]);
  });

  test("slice", () => {
    const { slice, concat } = require("../../src/runtime/collections");
    expect(slice([1, 2, 3, 4], 1, 3)).toEqual([2, 3]);
    expect(concat([1, 2], [3, 4])).toEqual([1, 2, 3, 4]);
  });

  test("filter", async () => {
    expect(await filter([1, 2, 3, 4], (x) => x % 2 === 0)).toEqual([2, 4]);
  });

  test("reduce", async () => {
    expect(await reduce([1, 2, 3], 0, (acc, x) => acc + x)).toBe(6);
  });

  test("find", async () => {
    expect(await find([1, 2, 3], (x) => x > 1)).toBe(2);
    expect(await find([1, 2, 3], (x) => x > 10)).toBe(undefined);
  });

  test("any", async () => {
    expect(await any([1, 2, 3], (x) => x > 2)).toBe(true);
    expect(await any([1, 2, 3], (x) => x > 10)).toBe(false);
  });

  test("all", async () => {
    expect(await all([1, 2, 3], (x) => x > 0)).toBe(true);
    expect(await all([1, 2, 3], (x) => x > 2)).toBe(false);
  });

  test("group_by", async () => {
    const result = await group_by([1, 2, 3, 4], (x) => x % 2);
    expect(result.get(0)).toEqual([2, 4]);
    expect(result.get(1)).toEqual([1, 3]);
  });

  test("sort_by", async () => {
    const items = [{ name: "b" }, { name: "a" }];
    expect(await sort_by(items, (x) => x.name)).toEqual([{ name: "a" }, { name: "b" }]);
  });
});

describe("Runtime - String Functions", () => {
  test("upper", () => {
    expect(upper("hello")).toBe("HELLO");
  });

  test("lower", () => {
    expect(lower("HELLO")).toBe("hello");
  });

  test("trim", () => {
    expect(trim("  hello  ")).toBe("hello");
  });

  test("split", () => {
    expect(split("a,b,c", ",")).toEqual(["a", "b", "c"]);
  });

  test("join", () => {
    expect(join(["a", "b", "c"], ",")).toBe("a,b,c");
  });

  test("replace", () => {
    expect(replace("hello world", "world", "universe")).toBe("hello universe");
  });

  test("starts_with", () => {
    expect(starts_with("hello", "he")).toBe(true);
    expect(starts_with("hello", "lo")).toBe(false);
  });

  test("ends_with", () => {
    expect(ends_with("hello", "lo")).toBe(true);
    expect(ends_with("hello", "he")).toBe(false);
  });

  test("substring", () => {
    expect(substring("hello", 1, 3)).toBe("el");
  });

  test("matches", () => {
    expect(matches("hello", "^h")).toBe(true);
    expect(matches("hello", "^x")).toBe(false);
  });
});

describe("Runtime - Number Functions", () => {
  test("abs", () => {
    expect(abs(-5)).toBe(5);
  });

  test("min/max", () => {
    expect(min(1, 2)).toBe(1);
    expect(max(1, 2)).toBe(2);
  });

  test("floor/ceil/round", () => {
    expect(floor(3.7)).toBe(3);
    expect(ceil(3.2)).toBe(4);
    expect(round(3.5)).toBe(4);
  });

  test("clamp", () => {
    expect(clamp(5, 0, 10)).toBe(5);
    expect(clamp(-5, 0, 10)).toBe(0);
    expect(clamp(15, 0, 10)).toBe(10);
  });

  test("sqrt/pow", () => {
    expect(sqrt(4)).toBe(2);
    expect(pow(2, 3)).toBe(8);
  });

  test("random returns 0-1", () => {
    const { random } = require("../../src/runtime/numbers");
    const val = random();
    expect(val).toBeGreaterThanOrEqual(0);
    expect(val).toBeLessThan(1);
  });

  test("random_int returns integer in range", () => {
    const { random_int } = require("../../src/runtime/numbers");
    const val = random_int(1, 10);
    expect(val).toBeGreaterThanOrEqual(1);
    expect(val).toBeLessThanOrEqual(10);
    expect(Number.isInteger(val)).toBe(true);
  });
});

describe("Runtime - Utility Functions", () => {
  test("range", () => {
    expect(range(0, 5)).toEqual([0, 1, 2, 3, 4]);
    expect(range(0, 5, true)).toEqual([0, 1, 2, 3, 4, 5]);
  });

  test("typeOf", () => {
    expect(typeOf(null)).toBe("null");
    expect(typeOf([])).toBe("list");
    expect(typeOf(new Map())).toBe("map");
    expect(typeOf(new Set())).toBe("set");
    expect(typeOf(42)).toBe("number");
    expect(typeOf("hi")).toBe("string");
  });

  test("clone", () => {
    const arr = [1, 2, 3];
    const cloned = clone(arr);
    expect(cloned).toEqual(arr);
    expect(cloned).not.toBe(arr);
  });

  test("equals", () => {
    expect(equals([1, 2], [1, 2])).toBe(true);
    expect(equals([1, 2], [1, 3])).toBe(false);
    expect(equals({ a: 1 }, { a: 1 })).toBe(true);
  });

  test("hash", () => {
    expect(typeof hash("hello")).toBe("number");
  });
});

describe("Runtime - Conversion Functions", () => {
  test("to_str", () => {
    expect(to_str(42)).toBe("42");
    expect(to_str(null)).toBe("null");
  });

  test("to_num", () => {
    expect(to_num("42")).toBe(42);
  });

  test("to_json/from_json", () => {
    expect(to_json({ a: 1 })).toBe('{"a":1}');
    expect(from_json('{"a":1}')).toEqual({ a: 1 });
  });
});

describe("Runtime - Set Functions", () => {
  test("set", () => {
    expect(set([1, 2, 2, 3])).toEqual(new Set([1, 2, 3]));
  });

  test("union", () => {
    const a = new Set([1, 2]);
    const b = new Set([2, 3]);
    expect(union(a, b)).toEqual(new Set([1, 2, 3]));
  });

  test("intersect", () => {
    const a = new Set([1, 2, 3]);
    const b = new Set([2, 3, 4]);
    expect(intersect(a, b)).toEqual(new Set([2, 3]));
  });

  test("difference", () => {
    const a = new Set([1, 2, 3]);
    const b = new Set([2, 3, 4]);
    expect(difference(a, b)).toEqual(new Set([1]));
  });

  test("is_subset", () => {
    expect(is_subset(new Set([1, 2]), new Set([1, 2, 3]))).toBe(true);
    expect(is_subset(new Set([1, 4]), new Set([1, 2, 3]))).toBe(false);
  });
});

describe("Runtime - Error Handling", () => {
  test("assert passes", () => {
    expect(() => assert(true)).not.toThrow();
  });

  test("assert fails", () => {
    expect(() => assert(false, "oops")).toThrow("oops");
  });

  test("error", () => {
    const e = error("test error");
    expect(e.message).toBe("test error");
  });

  test("ok", () => {
    expect(ok(42)).toEqual({ ok: true, value: 42 });
  });

  test("err", () => {
    expect(err("error")).toEqual({ ok: false, error: "error" });
  });
});

describe("Runtime - Channel", () => {
  test("unbuffered send/receive", async () => {
    const ch = new Channel<number>();
    
    // Start receiver
    const receiver = ch.receive();
    
    // Send value
    await ch.send(42);
    
    // Receive should get value
    expect(await receiver).toBe(42);
  });

  test("buffered channel", async () => {
    const ch = new Channel<number>(2);
    
    await ch.send(1);
    await ch.send(2);
    
    expect(await ch.receive()).toBe(1);
    expect(await ch.receive()).toBe(2);
  });

  test("close channel", async () => {
    const ch = new Channel<number>(1);
    await ch.send(1);
    ch.close();
    
    expect(await ch.receive()).toBe(1);
    expect(await ch.receive()).toBe(undefined);
    expect(ch.isClosed()).toBe(true);
  });

  test("async iterator", async () => {
    const ch = new Channel<number>(3);
    await ch.send(1);
    await ch.send(2);
    await ch.send(3);
    ch.close();
    
    const values: number[] = [];
    for await (const v of ch) {
      values.push(v);
    }
    
    expect(values).toEqual([1, 2, 3]);
  });
});

// Context is now passed as a function parameter (__ctx)
// No global context stack tests needed

describe("Runtime - Spawn", () => {
  test("spawn executes async", async () => {
    const result = await spawn(async () => 42);
    expect(result).toBe(42);
  });
});

describe("Runtime - Sleep", () => {
  test("sleep delays execution", async () => {
    const start = Date.now();
    await sleep(50);
    const elapsed = Date.now() - start;
    expect(elapsed).toBeGreaterThanOrEqual(40);
  });
});
