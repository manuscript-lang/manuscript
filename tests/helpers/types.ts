import { describe, test, expect } from "bun:test";
import { Parser } from "../../src/parser/parser";
import { TypeChecker, typeToString, Types } from "../../src/types";
import type { TypeCheckResult, Type } from "../../src/types";

/**
 * Type check source code and return result
 */
export const check = (src: string): TypeCheckResult => {
  const parser = new Parser(src);
  const program = parser.parse();
  const checker = new TypeChecker();
  return checker.check(program);
};

/**
 * Type check and expect no errors
 */
export const checkOk = (src: string): TypeCheckResult => {
  const result = check(src);
  if (result.errors.length > 0) {
    throw new Error(`Type check failed: ${result.errors.map(e => e.message).join(", ")}`);
  }
  return result;
};

/**
 * Type check and expect errors
 */
export const checkFails = (src: string, errorMatch?: string | RegExp): TypeCheckResult => {
  const result = check(src);
  expect(result.errors.length).toBeGreaterThan(0);
  if (errorMatch) {
    const hasMatch = result.errors.some(e => 
      typeof errorMatch === "string" 
        ? e.message.includes(errorMatch)
        : errorMatch.test(e.message)
    );
    expect(hasMatch).toBe(true);
  }
  return result;
};

/**
 * Get the inferred type of the last expression in a block
 */
export const inferType = (src: string): string => {
  const result = checkOk(src);
  // Find the last expression statement and return its type
  const lastStmt = result.program.body[result.program.body.length - 1];
  if (lastStmt?.kind === "ExprStmt") {
    const type = result.types.get(lastStmt.expr);
    if (type) return typeToString(type);
  }
  // For let/var, get the value type
  if (lastStmt?.kind === "LetStmt" || lastStmt?.kind === "VarStmt") {
    const value = lastStmt.kind === "LetStmt" ? lastStmt.value : lastStmt.value;
    const type = result.types.get(value);
    if (type) return typeToString(type);
  }
  return "unknown";
};

/**
 * Table-driven type inference tests
 */
export const typeCases = (cases: [string, string][]) => {
  cases.forEach(([input, expectedType]) => {
    test(`${input} : ${expectedType}`, () => {
      expect(inferType(input)).toBe(expectedType);
    });
  });
};

/**
 * Test that type check passes
 */
export const typeOkCases = (cases: string[]) => {
  cases.forEach((input) => {
    test(`ok: ${input.slice(0, 40)}...`, () => {
      checkOk(input);
    });
  });
};

/**
 * Test that type check fails
 */
export const typeFailCases = (cases: [string, string | RegExp][]) => {
  cases.forEach(([input, errorMatch]) => {
    test(`fail: ${input.slice(0, 40)}...`, () => {
      checkFails(input, errorMatch);
    });
  });
};
