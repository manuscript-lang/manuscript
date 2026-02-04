import { describe, test, expect } from "bun:test";
import {
  formatErrorMessage,
  LexerErrors,
  ParserErrors,
  TypeErrors,
  withHint,
} from "../../src/shared/errors";

describe("Shared Errors", () => {
  test("formatErrorMessage includes message, location, and optional hint", () => {
    const msg = formatErrorMessage("Bad token", { line: 2, column: 5 });
    expect(msg).toContain("Bad token");
    expect(msg).toContain("line 2");
    expect(msg).toContain("column 5");
    expect(formatErrorMessage("Error", { line: 1, column: 0 }, "Fix it")).toContain("Hint: Fix it");
  });

  test("withHint appends hint to base message", () => {
    expect(withHint("Error", "try again")).toBe("Error. Hint: try again");
  });

  test("LexerErrors return message and hint", () => {
    expect(LexerErrors.unterminatedString().message).toBe("Unterminated string literal");
    expect(LexerErrors.invalidEscapeSequence("z").message).toContain("\\z");
    expect(LexerErrors.inconsistentIndentation(2, 3).hint).toContain("spacing");
  });

  test("ParserErrors return message and hint", () => {
    expect(ParserErrors.unexpectedToken(";").message).toContain(";");
    expect(ParserErrors.expectedToken(")", "}").hint).toContain(")");
    expect(ParserErrors.expectedTypeOrFn("let").message).toContain("type");
  });

  test("TypeErrors return message and hint for common cases", () => {
    expect(TypeErrors.unknownIdentifier("foo").message).toContain("foo");
    expect(TypeErrors.typeMismatch("number", "string").message).toContain("number");
    expect(TypeErrors.matchNotExhaustive(["A"]).message).toContain("A");
    expect(TypeErrors.unknownParameter("z", ["a", "b"]).hint).toContain("a");
    expect(TypeErrors.unknownParameter("z", []).hint).toContain("signature");
  });
});
