/* syntax/token.h: token kinds and tokens. The names match the Rust lexer's `Tok`. */
#ifndef MS_SYNTAX_TOKEN_H
#define MS_SYNTAX_TOKEN_H

#include "compiler/syntax/pos.h"

#define MS_TOKENS(X)                                                                                         \
  X(Comment, "#comment")                                                                                     \
  X(Newline, "NEWLINE")                                                                                      \
  X(Indent, "INDENT")                                                                                        \
  X(Dedent, "DEDENT")                                                                                        \
  X(Eof, "EOF")                                                                                              \
  X(Name, "NAME") X(Number, "NUMBER") X(String, "STRING") X(And, "and") X(Break, "break")                    \
      X(Continue, "continue") X(Else, "else") X(Enum, "enum") X(Export, "export") X(Extern, "extern")        \
          X(False, "false") X(Fixture, "fixture") X(Fn, "fn") X(For, "for") X(If, "if") X(Impl, "impl")      \
              X(Import, "import") X(In, "in") X(Interface, "interface") X(Match, "match") X(Not, "not")      \
                  X(Or, "or") X(Return, "return") X(SelfKw, "self") X(Test, "test") X(True, "true")          \
                      X(Try, "try") X(Type, "type") X(Void, "void") X(Var, "var") X(While, "while")          \
                          X(Underscore, "_") X(LParen, "(") X(RParen, ")") X(LBracket, "[") X(RBracket, "]") \
                              X(LBrace, "{") X(RBrace, "}") X(Colon, ":") X(Comma, ",") X(Dot, ".")          \
                                  X(Plus, "+") X(Minus, "-") X(Star, "*") X(Slash, "/") X(Percent, "%")      \
                                      X(Lt, "<") X(Gt, ">") X(Assign, "=") X(Amp, "&") X(Pipe, "|")          \
                                          X(Ellipsis, "...") X(DotDot, "..") X(Question, "?") X(Bang, "!")   \
                                              X(ColonAssign, ":=") X(Arrow, "->") X(EqEq, "==")              \
                                                  X(NotEq, "!=") X(Le, "<=") X(Ge, ">=") X(At, "@")

typedef enum MsTok {
#define X(name, text) MS_T_##name,
  MS_TOKENS(X)
#undef X
      MS_T_COUNT
} MsTok;

/* The display text of a kind (a static string). */
const char *ms_tok_str(MsTok kind);

/* Maps an identifier-shaped word to its keyword kind, or MS_T_Name. */
MsTok ms_tok_from_word(MsSpan word);

/* A keyword that is an ordinary name where a member or field name is expected. */
bool ms_tok_is_contextual(MsTok kind);

/* One token. The text is source[lo..hi] of the CRLF-normalised source; layout tokens have an empty range. */
typedef struct MsToken {
  MsPos pos; /* start, in original-source coordinates */
  MsPos end; /* exclusive end */
  uint32_t lo, hi;
  uint8_t kind; /* MsTok */
} MsToken;

#endif
