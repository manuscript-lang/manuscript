/* Owns the token kind table: display texts, keyword lookup and contextual keywords. */
#include "compiler/syntax/token.h"

static const char *const TOKEN_TEXT[] = {
#define X(name, text) text,
    MS_TOKENS(X)
#undef X
};

const char *ms_tok_str(MsTok kind) {
  return TOKEN_TEXT[kind];
}

typedef struct Keyword {
  const char *word;
  uint8_t kind;
} Keyword;

static const Keyword KEYWORDS[] = {
    {"and", MS_T_And},
    {"break", MS_T_Break},
    {"continue", MS_T_Continue},
    {"else", MS_T_Else},
    {"enum", MS_T_Enum},
    {"export", MS_T_Export},
    {"extern", MS_T_Extern},
    {"false", MS_T_False},
    {"fixture", MS_T_Fixture},
    {"fn", MS_T_Fn},
    {"for", MS_T_For},
    {"if", MS_T_If},
    {"impl", MS_T_Impl},
    {"import", MS_T_Import},
    {"in", MS_T_In},
    {"interface", MS_T_Interface},
    {"match", MS_T_Match},
    {"not", MS_T_Not},
    {"or", MS_T_Or},
    {"return", MS_T_Return},
    {"self", MS_T_SelfKw},
    {"test", MS_T_Test},
    {"true", MS_T_True},
    {"try", MS_T_Try},
    {"type", MS_T_Type},
    {"var", MS_T_Var},
    {"void", MS_T_Void},
    {"while", MS_T_While},
    {"_", MS_T_Underscore},
};

MsTok ms_tok_from_word(MsSpan word) {
  if (word.len > 9 || word.len == 0) {
    return MS_T_Name;
  }
  for (size_t index = 0; index < MS_COUNT_OF(KEYWORDS); index++) {
    if (ms_span_is_text(word, KEYWORDS[index].word)) {
      return (MsTok)KEYWORDS[index].kind;
    }
  }
  return MS_T_Name;
}

bool ms_tok_is_contextual(MsTok kind) {
  switch (kind) {
  case MS_T_Break:
  case MS_T_Continue:
  case MS_T_Enum:
  case MS_T_Export:
  case MS_T_Extern:
  case MS_T_Fixture:
  case MS_T_For:
  case MS_T_If:
  case MS_T_Impl:
  case MS_T_Import:
  case MS_T_In:
  case MS_T_Interface:
  case MS_T_Match:
  case MS_T_Return:
  case MS_T_Test:
  case MS_T_Type:
  case MS_T_While:
    return true;
  default:
    return false;
  }
}
