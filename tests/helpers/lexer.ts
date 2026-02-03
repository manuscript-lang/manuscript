import { describe, test, expect } from "bun:test";
import { Lexer } from "../../src/lexer";
import type { Token, TokenType } from "../../src/lexer";

/**
 * Quick tokenize - returns just token types (excluding EOF)
 */
export const tokenTypes = (src: string): TokenType[] =>
  new Lexer(src).tokenize().filter(t => t.type !== "EOF").map(t => t.type);

/**
 * Quick tokenize - returns type:value pairs (excluding EOF)
 */
export const tokenPairs = (src: string): [TokenType, any][] =>
  new Lexer(src).tokenize().filter(t => t.type !== "EOF").map(t => [t.type, t.value]);

/**
 * Get all tokens including EOF
 */
export const tokenize = (src: string): Token[] =>
  new Lexer(src).tokenize();

/**
 * Assert specific token sequence
 */
export const expectTokens = (src: string, expected: Partial<Token>[]) => {
  const tokens = new Lexer(src).tokenize();
  expected.forEach((exp, i) => {
    expect(tokens[i]).toMatchObject(exp);
  });
};

/**
 * Table-driven lexer tests - generates test cases from a map of input -> expected types
 */
export const lexerCases = (cases: Record<string, TokenType[]>) => {
  Object.entries(cases).forEach(([input, expected]) => {
    test(`"${input}" → ${expected.join(", ")}`, () => {
      expect(tokenTypes(input)).toEqual(expected);
    });
  });
};

/**
 * Table-driven value tests - verifies both type and value
 */
export const lexerValueCases = (cases: [string, TokenType, any][]) => {
  cases.forEach(([input, expectedType, expectedValue]) => {
    test(`"${input}" → ${expectedType}(${JSON.stringify(expectedValue)})`, () => {
      const tokens = tokenize(input);
      expect(tokens[0]?.type).toBe(expectedType);
      expect(tokens[0]?.value).toBe(expectedValue);
    });
  });
};

/**
 * Test that lexer throws on invalid input
 */
export const expectLexerError = (src: string, messageMatch?: string | RegExp) => {
  expect(() => new Lexer(src).tokenize()).toThrow(messageMatch);
};
