import { describe, test, expect } from "bun:test";
import { Channel, spawn, sleep, all_settled, race, timeout, delay } from "../../src/runtime/concurrency";

describe("Runtime - Channel", () => {
  test("buffered channel stores values", async () => {
    const ch = new Channel<number>(2);
    await ch.send(1);
    await ch.send(2);
    expect(await ch.receive()).toBe(1);
    expect(await ch.receive()).toBe(2);
  });

  test("unbuffered channel blocks sender until receiver", async () => {
    const ch = new Channel<number>(0);
    let received = 0;
    
    // Start receiving in parallel
    const recvPromise = ch.receive().then(v => { received = v!; });
    // Allow receiver to register
    await sleep(1);
    await ch.send(42);
    await recvPromise;
    
    expect(received).toBe(42);
  });

  test("send on closed channel throws", async () => {
    const ch = new Channel<number>();
    ch.close();
    await expect(ch.send(1)).rejects.toThrow("Cannot send on closed channel");
  });

  test("receive on closed empty channel returns undefined", async () => {
    const ch = new Channel<number>();
    ch.close();
    expect(await ch.receive()).toBeUndefined();
  });

  test("isClosed() returns correct state", () => {
    const ch = new Channel<number>();
    expect(ch.isClosed()).toBe(false);
    ch.close();
    expect(ch.isClosed()).toBe(true);
  });

  test("close() resolves waiting receivers", async () => {
    const ch = new Channel<number>();
    
    // Start a receiver that will wait
    const recvPromise = ch.receive();
    await sleep(1);
    ch.close();
    
    expect(await recvPromise).toBeUndefined();
  });

  test("async iterator yields values until closed", async () => {
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
