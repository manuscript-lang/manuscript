import { describe, test, expect } from "bun:test";
import { spawn, sleep, all_settled, race, timeout, delay } from "../../src/runtime/concurrency";

describe("Runtime - Concurrency Functions", () => {
  test("spawn() executes async function", async () => {
    const result = await spawn(async () => 42);
    expect(result).toBe(42);
  });

  test("sleep() delays execution", async () => {
    const start = Date.now();
    await sleep(10);
    expect(Date.now() - start).toBeGreaterThanOrEqual(9);
  });

  test("delay() is alias for sleep()", async () => {
    const start = Date.now();
    await delay(10);
    expect(Date.now() - start).toBeGreaterThanOrEqual(9);
  });

  test("all_settled() waits for all promises", async () => {
    const results = await all_settled([
      Promise.resolve(1),
      Promise.resolve(2),
      Promise.resolve(3),
    ]);
    expect(results).toEqual([1, 2, 3]);
  });

  test("race() returns first resolved", async () => {
    const result = await race([
      sleep(50).then(() => "slow"),
      Promise.resolve("fast"),
    ]);
    expect(result).toBe("fast");
  });

  test("timeout() rejects on timeout", async () => {
    const slowPromise = sleep(100).then(() => "done");
    await expect(timeout(10, slowPromise)).rejects.toThrow("Timeout");
  });

  test("timeout() resolves if promise completes in time", async () => {
    const fastPromise = Promise.resolve("done");
    const result = await timeout(100, fastPromise);
    expect(result).toBe("done");
  });
});
