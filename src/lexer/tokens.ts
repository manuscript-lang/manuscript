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
  | "INTERFACE"
  | "IMPORT"
  | "FROM"
  | "TEST"
  | "YIELD"
  | "DEFER"
  | "TRY"
  | "CATCH"
  | "THROW"
  | "BREAK"
  | "CONTINUE"
  | "SPAWN"
  | "EXTERN"
  // enum, agent, capabilities are identifiers; use plain type for enum/agent patterns
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
// Using Map avoids prototype pollution (e.g., "constructor", "__proto__" won't match)
export const KEYWORDS = new Map<string, TokenType>([
  ["fn", "FN"],
  ["type", "TYPE"],
  ["let", "LET"],
  ["var", "VAR"],
  ["if", "IF"],
  ["else", "ELSE"],
  ["for", "FOR"],
  ["match", "MATCH"],
  ["return", "RETURN"],
  ["using", "USING"],
  ["with", "WITH"],
  ["interface", "INTERFACE"],
  ["import", "IMPORT"],
  ["from", "FROM"],
  ["test", "TEST"],
  ["yield", "YIELD"],
  ["defer", "DEFER"],
  ["try", "TRY"],
  ["catch", "CATCH"],
  ["throw", "THROW"],
  ["break", "BREAK"],
  ["continue", "CONTINUE"],
  ["spawn", "SPAWN"],
  ["extern", "EXTERN"],
  ["and", "AND"],
  ["or", "OR"],
  ["not", "NOT"],
  ["is", "IS"],
  ["as", "AS"],
  ["then", "THEN"],
  ["in", "IN"],
  ["true", "TRUE"],
  ["false", "FALSE"],
  ["null", "NULL"],
  ["where", "WHERE"],
]);
