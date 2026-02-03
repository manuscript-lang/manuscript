import { describe, test, expect } from "bun:test";
import { tokenPairs, tokenTypes, expectLexerError, tokenize } from "../helpers";

describe("Lexer - Basic Strings", () => {
  test("simple string", () => {
    expect(tokenPairs('"hello"')).toEqual([["STRING", "hello"]]);
  });

  test("empty string", () => {
    expect(tokenPairs('""')).toEqual([["STRING", ""]]);
  });

  test("string with spaces", () => {
    expect(tokenPairs('"hello world"')).toEqual([["STRING", "hello world"]]);
  });

  test("string with numbers", () => {
    expect(tokenPairs('"test123"')).toEqual([["STRING", "test123"]]);
  });
});

describe("Lexer - Escape Sequences", () => {
  test("newline escape", () => {
    expect(tokenPairs('"hello\\nworld"')).toEqual([["STRING", "hello\nworld"]]);
  });

  test("tab escape", () => {
    expect(tokenPairs('"hello\\tworld"')).toEqual([["STRING", "hello\tworld"]]);
  });

  test("carriage return escape", () => {
    expect(tokenPairs('"hello\\rworld"')).toEqual([["STRING", "hello\rworld"]]);
  });

  test("backslash escape", () => {
    expect(tokenPairs('"path\\\\file"')).toEqual([["STRING", "path\\file"]]);
  });

  test("quote escape", () => {
    expect(tokenPairs('"say \\"hi\\""')).toEqual([["STRING", 'say "hi"']]);
  });

  test("brace escapes", () => {
    expect(tokenPairs('"\\{not interpolation\\}"')).toEqual([["STRING", "{not interpolation}"]]);
  });

  test("unicode escape (4 digit)", () => {
    expect(tokenPairs('"\\u0041"')).toEqual([["STRING", "A"]]);
  });

  test("unicode escape (braced)", () => {
    expect(tokenPairs('"\\u{1F600}"')).toEqual([["STRING", "😀"]]);
  });

  test("invalid escape sequence", () => {
    expectLexerError('"\\q"', /Invalid escape sequence/);
  });
});

describe("Lexer - String Interpolation", () => {
  test("simple interpolation marker", () => {
    // Lexer keeps { in string, parser handles interpolation
    const tokens = tokenize('"hello {name}"');
    expect(tokens[0]?.value).toBe("hello {name}");
  });

  test("multiple interpolations", () => {
    const tokens = tokenize('"{a} and {b}"');
    expect(tokens[0]?.value).toBe("{a} and {b}");
  });
});

describe("Lexer - Multiline Strings", () => {
  test("basic multiline", () => {
    const src = '"""hello\nworld"""';
    expect(tokenPairs(src)).toEqual([["STRING", "hello\nworld"]]);
  });

  test("multiline with indentation", () => {
    const src = '"""line1\n  line2\n    line3"""';
    expect(tokenPairs(src)).toEqual([["STRING", "line1\n  line2\n    line3"]]);
  });

  test("empty multiline", () => {
    expect(tokenPairs('""""""')).toEqual([["STRING", ""]]);
  });

  test("multiline with escapes", () => {
    expect(tokenPairs('"""hello\\nworld"""')).toEqual([["STRING", "hello\nworld"]]);
  });

  test("unterminated multiline", () => {
    expectLexerError('"""unterminated', /Unterminated multiline string/);
  });
});

describe("Lexer - Raw Strings", () => {
  test("basic raw string", () => {
    expect(tokenPairs('r"C:\\path\\file"')).toEqual([["STRING", "C:\\path\\file"]]);
  });

  test("raw string preserves backslashes", () => {
    expect(tokenPairs('r"\\n\\t"')).toEqual([["STRING", "\\n\\t"]]);
  });

  test("raw multiline string", () => {
    const src = 'r"""line1\nline2"""';
    expect(tokenPairs(src)).toEqual([["STRING", "line1\nline2"]]);
  });

  test("unterminated raw string", () => {
    expectLexerError('r"unterminated', /Unterminated raw string/);
  });
});

describe("Lexer - Byte Strings", () => {
  test("basic byte string", () => {
    expect(tokenPairs('b"binary"')).toEqual([["STRING", "binary"]]);
  });

  test("byte string with escape", () => {
    expect(tokenPairs('b"hello\\x00world"')); // Just verify it doesn't crash
  });
});

describe("Lexer - String Errors", () => {
  test("unterminated string", () => {
    expectLexerError('"unterminated', /Unterminated string/);
  });

  test("newline in single-line string", () => {
    expectLexerError('"hello\nworld"', /Unterminated string/);
  });
});

describe("Lexer - String edge cases", () => {
  test("adjacent strings", () => {
    expect(tokenTypes('"a" "b"')).toEqual(["STRING", "STRING"]);
  });

  test("string in expression", () => {
    expect(tokenTypes('let x = "hello"')).toEqual([
      "LET", "IDENTIFIER", "ASSIGN", "STRING"
    ]);
  });

  test("string raw value is preserved", () => {
    const tokens = tokenize('"hello"');
    expect(tokens[0]?.raw).toBe('"hello"');
  });
});
