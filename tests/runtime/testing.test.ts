import { describe, test, expect, beforeEach } from "bun:test";
import { test as msTest, getTestCount, clearTests, runTests, runTestsWithResults } from "../../src/runtime/testing";

describe("Runtime - Test Runner", () => {
  beforeEach(() => {
    clearTests();
  });

  test("test() registers a test case", () => {
    expect(getTestCount()).toBe(0);
    msTest("sample test", async () => {});
    expect(getTestCount()).toBe(1);
  });

  test("clearTests() removes all registered tests", () => {
    msTest("test 1", async () => {});
    msTest("test 2", async () => {});
    expect(getTestCount()).toBe(2);
    clearTests();
    expect(getTestCount()).toBe(0);
  });

  test("runTests() executes passing tests", async () => {
    msTest("passing test", async () => {
      // No throw = pass
    });
    
    const result = await runTests();
    expect(result.passed).toBe(1);
    expect(result.failed).toBe(0);
  });

  test("runTests() handles failing tests", async () => {
    msTest("failing test", async () => {
      throw new Error("test error");
    });
    
    const result = await runTests();
    expect(result.passed).toBe(0);
    expect(result.failed).toBe(1);
  });

  test("runTestsWithResults() returns detailed results", async () => {
    msTest("pass", async () => {});
    msTest("fail", async () => { throw new Error("oops"); });
    
    const results = await runTestsWithResults();
    expect(results).toHaveLength(2);
    expect(results[0]).toEqual({ name: "pass", passed: true });
    expect(results[1]!.name).toBe("fail");
    expect(results[1]!.passed).toBe(false);
    expect(results[1]!.error).toBe("oops");
  });
});
