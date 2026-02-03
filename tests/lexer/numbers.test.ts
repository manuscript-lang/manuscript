import { describe, test, expect } from "bun:test";
import { lexerValueCases, tokenPairs, tokenTypes } from "../helpers";

describe("Lexer - Integer Literals", () => {
  lexerValueCases([
    ["0", "NUMBER", 0],
    ["1", "NUMBER", 1],
    ["42", "NUMBER", 42],
    ["123456789", "NUMBER", 123456789],
  ]);
});

describe("Lexer - Floating Point Literals", () => {
  lexerValueCases([
    ["3.14", "NUMBER", 3.14],
    ["0.5", "NUMBER", 0.5],
    ["123.456", "NUMBER", 123.456],
  ]);
});

describe("Lexer - Scientific Notation", () => {
  lexerValueCases([
    ["1e10", "NUMBER", 1e10],
    ["1E10", "NUMBER", 1e10],
    ["1.5e3", "NUMBER", 1500],
    ["2.5e-3", "NUMBER", 0.0025],
    ["1e+5", "NUMBER", 100000],
  ]);
});

describe("Lexer - Hex Literals", () => {
  lexerValueCases([
    ["0x0", "NUMBER", 0],
    ["0xFF", "NUMBER", 255],
    ["0x1F", "NUMBER", 31],
    ["0xDEADBEEF", "NUMBER", 0xDEADBEEF],
    ["0X10", "NUMBER", 16], // uppercase X
  ]);
});

describe("Lexer - Binary Literals", () => {
  lexerValueCases([
    ["0b0", "NUMBER", 0],
    ["0b1", "NUMBER", 1],
    ["0b1010", "NUMBER", 10],
    ["0b11111111", "NUMBER", 255],
    ["0B1100", "NUMBER", 12], // uppercase B
  ]);
});

describe("Lexer - Underscores in Numbers", () => {
  lexerValueCases([
    ["1_000", "NUMBER", 1000],
    ["1_000_000", "NUMBER", 1000000],
    ["3.14_15_92", "NUMBER", 3.141592],
    ["0xFF_FF", "NUMBER", 65535],
    ["0b1111_0000", "NUMBER", 240],
  ]);
});

describe("Lexer - Number edge cases", () => {
  test("number followed by dot (member access)", () => {
    // 42. followed by identifier should be NUMBER DOT IDENTIFIER
    expect(tokenTypes("42.foo")).toEqual(["NUMBER", "DOT", "IDENTIFIER"]);
    expect(tokenPairs("42.foo")[0]).toEqual(["NUMBER", 42]);
  });

  test("range operator", () => {
    expect(tokenTypes("1..10")).toEqual(["NUMBER", "DOTDOT", "NUMBER"]);
    expect(tokenPairs("1..10")).toEqual([
      ["NUMBER", 1],
      ["DOTDOT", ".."],
      ["NUMBER", 10],
    ]);
  });

  test("multiple numbers", () => {
    expect(tokenPairs("1 2 3")).toEqual([
      ["NUMBER", 1],
      ["NUMBER", 2],
      ["NUMBER", 3],
    ]);
  });

  test("negative number (minus is separate token)", () => {
    expect(tokenTypes("-5")).toEqual(["MINUS", "NUMBER"]);
  });
});
