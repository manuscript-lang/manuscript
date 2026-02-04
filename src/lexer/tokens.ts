// Token types for the Manuscript language

export type TokenType =
  // Literals
  | "NUMBER"
  | "STRING"
  | "IDENTIFIER"
  // Keywords (core language)
  | "FN"
  | "TYPE"
  | "LET"
  | "VAR"
  | "IF"
  | "ELSE"
  | "FOR"
  | "MATCH"
  | "RETURN"
  | "USING"
  | "WITH"
  | "CONTEXT"
  | "IMPORT"
  | "FROM"
  | "TEST"
  | "KEYWORD"
  | "YIELD"
  | "DEFER"
  | "TRY"
  | "CATCH"
  | "THROW"
  | "BREAK"
  | "CONTINUE"
  | "SPAWN"
  | "SEALED"
  | "EXTERN"
  // NOTE: enum, agent, capabilities are NOT keywords - they are defined via
  // `keyword` declarations and resolved at semantic level per syntax.md
  | "AND"
  | "OR"
  | "NOT"
  | "IS"
  | "AS"
  | "THEN"
  | "IN"
  | "TRUE"
  | "FALSE"
  | "NULL"
  | "WHERE"
  // Operators
  | "PLUS"          // +
  | "MINUS"         // -
  | "STAR"          // *
  | "SLASH"         // /
  | "PERCENT"       // %
  | "CARET"         // ^
  | "EQ"            // ==
  | "NEQ"           // !=
  | "LT"            // <
  | "GT"            // >
  | "LTE"           // <=
  | "GTE"           // >=
  | "ASSIGN"        // =
  | "PLUS_ASSIGN"   // +=
  | "MINUS_ASSIGN"  // -=
  | "STAR_ASSIGN"   // *=
  | "SLASH_ASSIGN"  // /=
  | "PERCENT_ASSIGN" // %=
  | "NULLISH"       // ??
  | "OPTIONAL"      // ?.
  | "BANG"          // !
  | "PIPE"          // |
  | "DOTDOT"        // ..
  | "SPREAD"        // ...
  | "ARROW"         // =>
  | "COLON"         // :
  | "QUESTION"      // ?
  // Delimiters
  | "LPAREN"        // (
  | "RPAREN"        // )
  | "LBRACKET"      // [
  | "RBRACKET"      // ]
  | "LBRACE"        // {
  | "RBRACE"        // }
  | "COMMA"         // ,
  | "DOT"           // .
  // Indentation
  | "INDENT"
  | "DEDENT"
  | "NEWLINE"
  // End of file
  | "EOF";

export interface SourceLocation {
  line: number;
  column: number;
  offset: number;
}

export interface Token {
  type: TokenType;
  value: string | number | boolean | null;
  raw: string;       // Original source text
  loc: SourceLocation;
  leadingComment?: string;  // Comment(s) immediately preceding this token
}

// Core keywords built into the lexer
export const KEYWORDS: Record<string, TokenType> = {
  fn: "FN",
  type: "TYPE",
  let: "LET",
  var: "VAR",
  if: "IF",
  else: "ELSE",
  for: "FOR",
  match: "MATCH",
  return: "RETURN",
  using: "USING",
  with: "WITH",
  context: "CONTEXT",
  import: "IMPORT",
  from: "FROM",
  test: "TEST",
  keyword: "KEYWORD",
  yield: "YIELD",
  defer: "DEFER",
  try: "TRY",
  catch: "CATCH",
  throw: "THROW",
  break: "BREAK",
  continue: "CONTINUE",
  spawn: "SPAWN",
  sealed: "SEALED",
  extern: "EXTERN",
  // NOTE: enum, agent, capabilities are defined via keyword declarations
  and: "AND",
  or: "OR",
  not: "NOT",
  is: "IS",
  as: "AS",
  then: "THEN",
  in: "IN",
  true: "TRUE",
  false: "FALSE",
  null: "NULL",
  where: "WHERE",
};
