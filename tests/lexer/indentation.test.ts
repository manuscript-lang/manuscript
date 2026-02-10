import { describe, test, expect } from "bun:test";
import { tokenTypes, tokenize, expectLexerError } from "../helpers";

describe("Lexer - Basic Indentation", () => {
  test("no indentation", () => {
    expect(tokenTypes("a\nb")).toEqual([
      "IDENTIFIER", "NEWLINE", "IDENTIFIER"
    ]);
  });

  test("single indent", () => {
    const src = `if x
  y`;
    expect(tokenTypes(src)).toEqual([
      "IF", "IDENTIFIER", "NEWLINE",
      "INDENT", "IDENTIFIER", "DEDENT"
    ]);
  });

  test("indent and dedent", () => {
    const src = `if x
  y
z`;
    expect(tokenTypes(src)).toEqual([
      "IF", "IDENTIFIER", "NEWLINE",
      "INDENT", "IDENTIFIER", "NEWLINE",
      "DEDENT", "IDENTIFIER"
    ]);
  });

  test("multiple indents", () => {
    const src = `a
  b
    c`;
    expect(tokenTypes(src)).toEqual([
      "IDENTIFIER", "NEWLINE",
      "INDENT", "IDENTIFIER", "NEWLINE",
      "INDENT", "IDENTIFIER", "DEDENT", "DEDENT"
    ]);
  });

  test("multiple dedents", () => {
    const src = `a
  b
    c
d`;
    expect(tokenTypes(src)).toEqual([
      "IDENTIFIER", "NEWLINE",
      "INDENT", "IDENTIFIER", "NEWLINE",
      "INDENT", "IDENTIFIER", "NEWLINE",
      "DEDENT", "DEDENT", "IDENTIFIER"
    ]);
  });
});

describe("Lexer - Function blocks", () => {
  test("simple function", () => {
    const src = `fn add(a, b)
  a + b`;
    expect(tokenTypes(src)).toEqual([
      "FN", "IDENTIFIER", "LPAREN", "IDENTIFIER", "COMMA", "IDENTIFIER", "RPAREN", "NEWLINE",
      "INDENT", "IDENTIFIER", "PLUS", "IDENTIFIER", "DEDENT"
    ]);
  });

  test("function with multiple statements", () => {
    const src = `fn foo()
  let x = 1
  let y = 2
  x + y`;
    expect(tokenTypes(src)).toEqual([
      "FN", "IDENTIFIER", "LPAREN", "RPAREN", "NEWLINE",
      "INDENT",
      "LET", "IDENTIFIER", "ASSIGN", "NUMBER", "NEWLINE",
      "LET", "IDENTIFIER", "ASSIGN", "NUMBER", "NEWLINE",
      "IDENTIFIER", "PLUS", "IDENTIFIER",
      "DEDENT"
    ]);
  });
});

describe("Lexer - Nested blocks", () => {
  test("if inside function", () => {
    const src = `fn check(x)
  if x > 0
    return true
  false`;
    expect(tokenTypes(src)).toEqual([
      "FN", "IDENTIFIER", "LPAREN", "IDENTIFIER", "RPAREN", "NEWLINE",
      "INDENT",
      "IF", "IDENTIFIER", "GT", "NUMBER", "NEWLINE",
      "INDENT", "RETURN", "TRUE", "NEWLINE",
      "DEDENT", "FALSE",
      "DEDENT"
    ]);
  });

  test("if-else", () => {
    const src = `if cond
  a
else
  b`;
    expect(tokenTypes(src)).toEqual([
      "IF", "IDENTIFIER", "NEWLINE",
      "INDENT", "IDENTIFIER", "NEWLINE",
      "DEDENT", "ELSE", "NEWLINE",
      "INDENT", "IDENTIFIER", "DEDENT"
    ]);
  });
});

describe("Lexer - Empty lines and comments", () => {
  test("empty lines are skipped", () => {
    const src = `a

b`;
    expect(tokenTypes(src)).toEqual([
      "IDENTIFIER", "NEWLINE", "IDENTIFIER"
    ]);
  });

  test("comment-only lines don't affect indentation", () => {
    const src = `fn foo()
  // comment
  x`;
    expect(tokenTypes(src)).toEqual([
      "FN", "IDENTIFIER", "LPAREN", "RPAREN", "NEWLINE",
      "INDENT", "IDENTIFIER", "DEDENT"
    ]);
  });

  test("indented empty lines", () => {
    const src = `if x
  a
  
  b`;
    expect(tokenTypes(src)).toEqual([
      "IF", "IDENTIFIER", "NEWLINE",
      "INDENT", "IDENTIFIER", "NEWLINE", "IDENTIFIER", "DEDENT"
    ]);
  });
});

describe("Lexer - Tab handling", () => {
  test("tabs converted to spaces", () => {
    const src = "if x\n\ty"; // tab = 2 spaces
    expect(tokenTypes(src)).toEqual([
      "IF", "IDENTIFIER", "NEWLINE",
      "INDENT", "IDENTIFIER", "DEDENT"
    ]);
  });
});

describe("Lexer - INDENT/DEDENT balance", () => {
  test("always balanced at EOF", () => {
    const examples = [
      "a\n  b\n    c\n      d",
      "fn x()\n  if y\n    z",
      "a\n  b\nc\n  d",
    ];

    for (const src of examples) {
      const types = tokenTypes(src);
      const indents = types.filter(t => t === "INDENT").length;
      const dedents = types.filter(t => t === "DEDENT").length;
      expect(indents).toBe(dedents);
    }
  });
});

describe("Lexer - Inconsistent indentation", () => {
  test("allows dedent to intermediate level (e.g. continuation then body)", () => {
    const src = `if x
    y
  z`;
    expect(tokenTypes(src)).toEqual([
      "IF", "IDENTIFIER", "NEWLINE",
      "INDENT", "IDENTIFIER", "NEWLINE",
      "DEDENT", "INDENT", "IDENTIFIER", "DEDENT"
    ]);
  });
});

describe("Lexer - Real-world examples", () => {
  test("type definition", () => {
    const src = `type User
  id: number
  name: string`;
    expect(tokenTypes(src)).toEqual([
      "TYPE", "IDENTIFIER", "NEWLINE",
      "INDENT",
      "IDENTIFIER", "COLON", "IDENTIFIER", "NEWLINE",
      "IDENTIFIER", "COLON", "IDENTIFIER",
      "DEDENT"
    ]);
  });

  test("match expression", () => {
    const src = `match value
  1 => "one"
  2 => "two"
  _ => "other"`;
    expect(tokenTypes(src)).toEqual([
      "MATCH", "IDENTIFIER", "NEWLINE",
      "INDENT",
      "NUMBER", "ARROW", "STRING", "NEWLINE",
      "NUMBER", "ARROW", "STRING", "NEWLINE",
      "IDENTIFIER", "ARROW", "STRING",
      "DEDENT"
    ]);
  });

  test("for loop", () => {
    const src = `for item in items
  print(item)`;
    expect(tokenTypes(src)).toEqual([
      "FOR", "IDENTIFIER", "IN", "IDENTIFIER", "NEWLINE",
      "INDENT", "IDENTIFIER", "LPAREN", "IDENTIFIER", "RPAREN", "DEDENT"
    ]);
  });
});
