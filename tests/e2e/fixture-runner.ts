// Test Harness for running .ms fixture files
import { describe, test, expect } from "bun:test";
import { executeWithOutput, compiles, getErrors } from "../helpers/execution";
import * as path from "node:path";
import * as fs from "node:fs";

export interface TestResult {
  name: string;
  passed: boolean;
  output: string[];
  error?: string;
  expected?: string[];
  duration: number;
}

export interface FixtureConfig {
  /** Expected output lines (if not specified in file header) */
  expectedOutput?: string[];
  /** Whether to skip this test */
  skip?: boolean;
  /** Expected to throw/fail */
  shouldFail?: boolean;
  /** Custom timeout in ms */
  timeout?: number;
  /** Expected compile/type errors */
  expectedErrors?: string[];
}

/**
 * Parse test metadata from .ms file comments
 * Format:
 *   // @test: Test Name (in header)
 *   // @skip: reason (in header, optional)
 *   // @fail: expected error (in header, optional)
 *   // @error: expected type/compile error (for error tests)
 *   // @expect: expected output (can appear anywhere in file, collected in order)
 */
export function parseTestHeader(source: string): {
  name: string;
  expectedOutput: string[];
  skip?: string;
  shouldFail?: string;
  expectedErrors: string[];
} {
  const lines = source.split("\n");
  let name = "Unnamed Test";
  const expectedOutput: string[] = [];
  const expectedErrors: string[] = [];
  let skip: string | undefined;
  let shouldFail: string | undefined;

  // First pass: get test name, skip, fail from header
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed.startsWith("//")) break; // Stop at first non-comment line

    const match = trimmed.match(/^\/\/\s*@(\w+):\s*(.+)$/);
    if (match) {
      const [, directive, value] = match;
      switch (directive) {
        case "test":
          name = value;
          break;
        case "skip":
          skip = value;
          break;
        case "fail":
          shouldFail = value;
          break;
      }
    }
  }

  // Second pass: collect all @expect and @error from entire file (in order)
  for (const line of lines) {
    const expectMatch = line.trim().match(/^\/\/\s*@expect:\s*(.+)$/);
    if (expectMatch) {
      expectedOutput.push(expectMatch[1]);
    }
    const errorMatch = line.trim().match(/^\/\/\s*@error:\s*(.+)$/);
    if (errorMatch) {
      expectedErrors.push(errorMatch[1]);
    }
  }

  return { name, expectedOutput, skip, shouldFail, expectedErrors };
}

/**
 * Execute a .ms file and capture output (uses helpers/execution.ts)
 * Type checking is always enabled to test real-world behavior
 */
export async function executeFixture(
  source: string
): Promise<{ success: boolean; output: string[]; error?: string; errors?: string[] }> {
  // Check for compile errors (with type checking)
  if (!compiles(source, true)) {
    const errors = getErrors(source, true);
    return {
      success: false,
      output: [],
      errors,
      error: errors.join("\n"),
    };
  }

  try {
    const { output } = await executeWithOutput(source);
    return { success: true, output };
  } catch (e) {
    return {
      success: false,
      output: [],
      error: e instanceof Error ? e.message : String(e),
    };
  }
}

/**
 * Load all .ms files from a directory
 */
export function loadFixtures(dir: string): { path: string; source: string }[] {
  const fixtures: { path: string; source: string }[] = [];
  
  const files = fs.readdirSync(dir);
  for (const file of files) {
    if (file.endsWith(".ms")) {
      const filePath = path.join(dir, file);
      const source = fs.readFileSync(filePath, "utf-8");
      fixtures.push({ path: filePath, source });
    }
  }
  
  return fixtures.sort((a, b) => a.path.localeCompare(b.path));
}

/**
 * Run a single fixture and return the result
 */
export async function runFixture(
  source: string,
  config?: FixtureConfig
): Promise<TestResult> {
  const start = performance.now();
  const { name, expectedOutput, skip, shouldFail, typeCheck, expectedErrors } = parseTestHeader(source);
  
  if (skip || config?.skip) {
    return {
      name,
      passed: true,
      output: [],
      duration: performance.now() - start,
    };
  }

  const { success, output, error, errors } = await executeFixture(source);
  const duration = performance.now() - start;
  
  // Handle type error expectation tests
  const expectErrors = config?.expectedErrors || expectedErrors;
  if (expectErrors.length > 0) {
    // This test expects specific errors
    if (success) {
      return {
        name,
        passed: false,
        output,
        error: `Expected type errors but code compiled successfully. Expected: ${expectErrors.join(", ")}`,
        duration,
      };
    }
    
    // Check that all expected errors are present
    const actualErrors = errors || [error || ""];
    const allErrorsFound = expectErrors.every(expectedErr => 
      actualErrors.some(actualErr => actualErr.includes(expectedErr))
    );
    
    return {
      name,
      passed: allErrorsFound,
      output,
      expected: expectErrors,
      error: allErrorsFound ? undefined : `Error mismatch. Expected errors containing: ${expectErrors.join(", ")}\nActual: ${actualErrors.join("\n")}`,
      duration,
    };
  }
  
  // Check if test should fail
  if (shouldFail || config?.shouldFail) {
    return {
      name,
      passed: !success,
      output,
      error: success ? "Expected test to fail but it passed" : undefined,
      duration,
    };
  }

  // Check success
  if (!success) {
    return {
      name,
      passed: false,
      output,
      error,
      duration,
    };
  }

  // Check expected output if specified
  const expected = config?.expectedOutput || expectedOutput;
  if (expected.length > 0) {
    const passed = expected.every((exp, i) => {
      const actual = output[i];
      // Support regex patterns in expected output
      if (exp.startsWith("/") && exp.endsWith("/")) {
        const pattern = new RegExp(exp.slice(1, -1));
        return actual !== undefined && pattern.test(actual);
      }
      return actual === exp;
    });

    return {
      name,
      passed,
      output,
      expected,
      error: passed ? undefined : "Output mismatch",
      duration,
    };
  }

  return {
    name,
    passed: true,
    output,
    duration,
  };
}

/**
 * Create bun tests from all fixtures in a directory
 */
export function runFixtureTests(fixtureDir: string, suiteName: string) {
  const fixtures = loadFixtures(fixtureDir);
  
  describe(suiteName, () => {
    for (const { path: filePath, source } of fixtures) {
      const { name, skip } = parseTestHeader(source);
      const testName = `${name} (${path.basename(filePath)})`;
      
      if (skip) {
        test.skip(testName, () => {});
        continue;
      }

      test(testName, async () => {
        const result = await runFixture(source);
        if (!result.passed) {
          if (result.error) {
            throw new Error(
              `Test failed: ${result.error}\nOutput: ${result.output.join("\n")}`
            );
          }
          throw new Error(
            `Output mismatch:\nExpected: ${result.expected?.join("\n")}\nActual: ${result.output.join("\n")}`
          );
        }
      });
    }
  });
}
