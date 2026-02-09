import { describe, test, expect } from "bun:test";
import { compile, check, parse, formatErrors } from "../../src/compile";

describe("Compiler Pipeline", () => {
  describe("compile", () => {
    test("compiles simple expression and returns AST", () => {
      const result = compile("let x = 42");
      expect(result.success).toBe(true);
      expect(result.code).toContain("const x = 42");
      expect(result.ast?.body.length).toBe(1);
    });

    test("compiles function declaration", () => {
      const result = compile(`
fn add(a: number, b: number): number
  return a + b
`);
      expect(result.success).toBe(true);
      expect(result.code).toContain("function add(a, b)");
    });

    test("reports lexer errors", () => {
      const result = compile("let x = @invalid");
      expect(result.success).toBe(false);
      expect(result.errors.length).toBeGreaterThan(0);
      expect(result.errors[0]!.phase).toBe("lexer");
    });

    test("reports parser errors", () => {
      const result = compile("let = 42");
      expect(result.success).toBe(false);
      expect(result.errors.length).toBeGreaterThan(0);
      expect(result.errors[0]!.phase).toBe("parser");
    });

    test("reports type errors", () => {
      const result = compile('let x: number = "hello"');
      expect(result.success).toBe(false);
      expect(result.errors.length).toBeGreaterThan(0);
      expect(result.errors[0]!.phase).toBe("typecheck");
    });

    test("skips type checking when disabled", () => {
      const result = compile('let x: number = "hello"', { typeCheck: false });
      expect(result.success).toBe(true);
    });

    test("includes filename in errors", () => {
      const result = compile("let = 42", { filename: "test.ms" });
      expect(result.errors[0]!.file).toBe("test.ms");
    });

  });

  describe("check", () => {
    test("type checks valid code", () => {
      const result = check("let x: number = 42");
      expect(result.success).toBe(true);
      expect(result.errors.length).toBe(0);
    });

    test("detects type errors and still returns AST", () => {
      const result = check('let x: number = "string"');
      expect(result.success).toBe(false);
      expect(result.errors.length).toBeGreaterThan(0);
      expect(result.ast).toBeDefined();
    });

    test("reports parse errors with hint and location", () => {
      const result = check("let = 42");
      expect(result.success).toBe(false);
      expect(result.errors[0]!.phase).toBe("parser");
      expect(result.errors[0]!.message).toBeDefined();
      expect(result.errors[0]!.hint).toBeDefined();
    });

    test("reports lexer errors when check fails on invalid token", () => {
      const result = check("let x = @bad");
      expect(result.success).toBe(false);
      expect(result.errors[0]!.phase).toBe("lexer");
    });
  });

  describe("parse", () => {
    test("parses without type checking", () => {
      // This would fail type check but should parse fine
      const result = parse('let x: number = "string"');
      expect(result.success).toBe(true);
      expect(result.ast).toBeDefined();
    });

    test("reports parse errors", () => {
      const result = parse("let = invalid");
      expect(result.success).toBe(false);
    });
  });

  describe("formatErrors", () => {
    test("formats error without source", () => {
      const formatted = formatErrors([{
        message: "Test error",
        phase: "parser",
      }]);
      expect(formatted).toContain("[parser] Test error");
    });

    test("formats error with location", () => {
      const formatted = formatErrors([{
        message: "Test error",
        line: 5,
        column: 10,
        phase: "lexer",
      }]);
      expect(formatted).toContain("line 5");
      expect(formatted).toContain("column 10");
    });

    test("formats error with source context", () => {
      const source = "let x = 42\nlet y = @invalid";
      const formatted = formatErrors([{
        message: "Invalid token",
        line: 2,
        column: 9,
        phase: "lexer",
      }], source);
      expect(formatted).toContain("let y = @invalid");
    });

    test("includes filename in output", () => {
      const formatted = formatErrors([{
        message: "Error",
        file: "test.ms",
        phase: "typecheck",
      }]);
      expect(formatted).toContain("test.ms");
    });
  });
});

describe("Complex Programs", () => {
  test("compiles type declaration", () => {
    const result = compile(`
type Person
  name: string
  age: number
`);
    expect(result.success).toBe(true);
    expect(result.code).toContain("function Person");
  });

  test("compiles test declaration", () => {
    const result = compile(`
test "addition works"
  let x = 1 + 1
  assert x == 2
`);
    expect(result.success).toBe(true);
    expect(result.code).toContain("__ms_runtime.test");
  });
});
