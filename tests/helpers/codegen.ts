import { describe, test, expect } from "bun:test";
import { Parser } from "../../src/parser/parser";
import { CodeGenerator } from "../../src/codegen/codegen";
import type { CodeGenOptions } from "../../src/codegen/codegen";

/**
 * Compile Manuscript source to JavaScript
 */
export const compile = (src: string, options?: Partial<CodeGenOptions>): string => {
  const parser = new Parser(src);
  const program = parser.parse();
  const codegen = new CodeGenerator(options);
  return codegen.generate(program);
};

/**
 * Check that compiled code contains expected string
 */
export const expectCompiled = (src: string, expected: string | RegExp): void => {
  const js = compile(src);
  if (typeof expected === "string") {
    expect(js).toContain(expected);
  } else {
    expect(js).toMatch(expected);
  }
};

/**
 * Table-driven compilation tests
 */
export const compileCases = (cases: [string, string | RegExp][]) => {
  cases.forEach(([input, expected]) => {
    test(`${input.slice(0, 40)}...`, () => {
      expectCompiled(input, expected);
    });
  });
};

/**
 * Strip runtime import and whitespace for comparison
 */
export const stripRuntime = (js: string): string => {
  return js
    .replace(/import \{ __ms_runtime \} from "manuscript\/runtime";/, "")
    .trim();
};
