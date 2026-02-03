import { describe, test, expect } from "bun:test";
import { lexerCases, tokenTypes, tokenPairs, expectLexerError } from "../helpers";

describe("Lexer - Keywords", () => {
  lexerCases({
    "fn": ["FN"],
    "type": ["TYPE"],
    "let": ["LET"],
    "var": ["VAR"],
    "if": ["IF"],
    "else": ["ELSE"],
    "for": ["FOR"],
    "match": ["MATCH"],
    "return": ["RETURN"],
    "using": ["USING"],
    "with": ["WITH"],
    "import": ["IMPORT"],
    "from": ["FROM"],
    "test": ["TEST"],
    "keyword": ["KEYWORD"],
    "yield": ["YIELD"],
    "defer": ["DEFER"],
    "try": ["TRY"],
    "catch": ["CATCH"],
    "throw": ["THROW"],
    "break": ["BREAK"],
    "continue": ["CONTINUE"],
    "spawn": ["SPAWN"],
    "sealed": ["SEALED"],
    "extends": ["EXTENDS"],
    "and": ["AND"],
    "or": ["OR"],
    "not": ["NOT"],
    "is": ["IS"],
    "as": ["AS"],
    "then": ["THEN"],
    "in": ["IN"],
    "true": ["TRUE"],
    "false": ["FALSE"],
    "null": ["NULL"],
    "where": ["WHERE"],
  });

  test("keywords with values", () => {
    expect(tokenPairs("true false null")).toEqual([
      ["TRUE", true],
      ["FALSE", false],
      ["NULL", null],
    ]);
  });
});

describe("Lexer - Identifiers", () => {
  lexerCases({
    "foo": ["IDENTIFIER"],
    "bar123": ["IDENTIFIER"],
    "_private": ["IDENTIFIER"],
    "camelCase": ["IDENTIFIER"],
    "PascalCase": ["IDENTIFIER"],
    "snake_case": ["IDENTIFIER"],
  });

  test("identifier values", () => {
    expect(tokenPairs("foo bar _x")).toEqual([
      ["IDENTIFIER", "foo"],
      ["IDENTIFIER", "bar"],
      ["IDENTIFIER", "_x"],
    ]);
  });

  // agent, capabilities, prompt are all identifiers
  // They are defined via keyword declarations (syntax.md), not core keywords
  test("agent, capabilities, prompt are identifiers (keyword-defined)", () => {
    expect(tokenTypes("agent capabilities prompt enum")).toEqual([
      "IDENTIFIER", "IDENTIFIER", "IDENTIFIER", "IDENTIFIER"
    ]);
  });
});

describe("Lexer - Operators", () => {
  lexerCases({
    "+": ["PLUS"],
    "-": ["MINUS"],
    "*": ["STAR"],
    "/": ["SLASH"],
    "%": ["PERCENT"],
    "^": ["CARET"],
    "==": ["EQ"],
    "!=": ["NEQ"],
    "<": ["LT"],
    ">": ["GT"],
    "<=": ["LTE"],
    ">=": ["GTE"],
    "=": ["ASSIGN"],
    "+=": ["PLUS_ASSIGN"],
    "-=": ["MINUS_ASSIGN"],
    "*=": ["STAR_ASSIGN"],
    "/=": ["SLASH_ASSIGN"],
    "%=": ["PERCENT_ASSIGN"],
    "??": ["NULLISH"],
    "?.": ["OPTIONAL"],
    "!": ["BANG"],
    "|": ["PIPE"],
    "..": ["DOTDOT"],
    "...": ["SPREAD"],
    "=>": ["ARROW"],
    ":": ["COLON"],
    "?": ["QUESTION"],
  });

  test("compound operator sequences", () => {
    expect(tokenTypes("a += b")).toEqual(["IDENTIFIER", "PLUS_ASSIGN", "IDENTIFIER"]);
    expect(tokenTypes("x ?? y")).toEqual(["IDENTIFIER", "NULLISH", "IDENTIFIER"]);
    expect(tokenTypes("a?.b")).toEqual(["IDENTIFIER", "OPTIONAL", "IDENTIFIER"]);
  });
});

describe("Lexer - Delimiters", () => {
  lexerCases({
    "(": ["LPAREN"],
    ")": ["RPAREN"],
    "[": ["LBRACKET"],
    "]": ["RBRACKET"],
    "{": ["LBRACE"],
    "}": ["RBRACE"],
    ",": ["COMMA"],
    ".": ["DOT"],
  });

  test("delimiter sequences", () => {
    expect(tokenTypes("(a, b)")).toEqual([
      "LPAREN", "IDENTIFIER", "COMMA", "IDENTIFIER", "RPAREN"
    ]);
    expect(tokenTypes("[1, 2, 3]")).toEqual([
      "LBRACKET", "NUMBER", "COMMA", "NUMBER", "COMMA", "NUMBER", "RBRACKET"
    ]);
    expect(tokenTypes("{a: 1}")).toEqual([
      "LBRACE", "IDENTIFIER", "COLON", "NUMBER", "RBRACE"
    ]);
  });
});

describe("Lexer - Comments", () => {
  test("single line comments are ignored", () => {
    expect(tokenTypes("a // comment\nb")).toEqual([
      "IDENTIFIER", "NEWLINE", "IDENTIFIER"
    ]);
  });

  test("comment at end of input", () => {
    expect(tokenTypes("a // comment")).toEqual(["IDENTIFIER"]);
  });

  test("multiple comments", () => {
    // First line is comment-only, so we get NEWLINE at line 2 start
    expect(tokenTypes("// first\na // second\n// third\nb")).toEqual([
      "NEWLINE", "IDENTIFIER", "NEWLINE", "IDENTIFIER"
    ]);
  });
});

describe("Lexer - Mixed expressions", () => {
  test("function call", () => {
    expect(tokenTypes("foo(1, 2)")).toEqual([
      "IDENTIFIER", "LPAREN", "NUMBER", "COMMA", "NUMBER", "RPAREN"
    ]);
  });

  test("member access", () => {
    expect(tokenTypes("a.b.c")).toEqual([
      "IDENTIFIER", "DOT", "IDENTIFIER", "DOT", "IDENTIFIER"
    ]);
  });

  test("arithmetic", () => {
    expect(tokenTypes("1 + 2 * 3")).toEqual([
      "NUMBER", "PLUS", "NUMBER", "STAR", "NUMBER"
    ]);
  });

  test("comparison", () => {
    expect(tokenTypes("a == b and c != d")).toEqual([
      "IDENTIFIER", "EQ", "IDENTIFIER", "AND", "IDENTIFIER", "NEQ", "IDENTIFIER"
    ]);
  });

  test("type annotation", () => {
    expect(tokenTypes("x: number")).toEqual([
      "IDENTIFIER", "COLON", "IDENTIFIER"
    ]);
  });

  test("lambda", () => {
    expect(tokenTypes("(x) => x * 2")).toEqual([
      "LPAREN", "IDENTIFIER", "RPAREN", "ARROW", "IDENTIFIER", "STAR", "NUMBER"
    ]);
  });

  test("generic type", () => {
    expect(tokenTypes("list[T]")).toEqual([
      "IDENTIFIER", "LBRACKET", "IDENTIFIER", "RBRACKET"
    ]);
  });

  test("spread operator", () => {
    expect(tokenTypes("[...items]")).toEqual([
      "LBRACKET", "SPREAD", "IDENTIFIER", "RBRACKET"
    ]);
  });

  test("range", () => {
    expect(tokenTypes("0..10")).toEqual([
      "NUMBER", "DOTDOT", "NUMBER"
    ]);
  });

  test("pipe operator", () => {
    expect(tokenTypes("data | map | filter")).toEqual([
      "IDENTIFIER", "PIPE", "IDENTIFIER", "PIPE", "IDENTIFIER"
    ]);
  });
});

describe("Lexer - Error handling", () => {
  test("unexpected character", () => {
    expectLexerError("@", /Unexpected character/);
  });

  test("unexpected character with context", () => {
    expectLexerError("let x = @", /Unexpected character/);
  });
});
