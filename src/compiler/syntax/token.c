/* Owns the token kind table: display texts, keyword lookup and contextual keywords. */
#include "compiler/syntax/token.h"
#include <string.h>

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
  uint8_t len;
  uint8_t kind;
} Keyword;

#define KW(text, kind) {text, sizeof(text) - 1, kind}

static const Keyword KEYWORDS[] = {
    KW("and", MS_T_And),
    KW("break", MS_T_Break),
    KW("continue", MS_T_Continue),
    KW("else", MS_T_Else),
    KW("enum", MS_T_Enum),
    KW("export", MS_T_Export),
    KW("extern", MS_T_Extern),
    KW("false", MS_T_False),
    KW("fixture", MS_T_Fixture),
    KW("fn", MS_T_Fn),
    KW("for", MS_T_For),
    KW("if", MS_T_If),
    KW("impl", MS_T_Impl),
    KW("import", MS_T_Import),
    KW("in", MS_T_In),
    KW("interface", MS_T_Interface),
    KW("match", MS_T_Match),
    KW("not", MS_T_Not),
    KW("or", MS_T_Or),
    KW("return", MS_T_Return),
    KW("self", MS_T_SelfKw),
    KW("test", MS_T_Test),
    KW("true", MS_T_True),
    KW("try", MS_T_Try),
    KW("type", MS_T_Type),
    KW("var", MS_T_Var),
    KW("void", MS_T_Void),
    KW("while", MS_T_While),
    KW("_", MS_T_Underscore),
};

/* KEYWORDS is sorted by text up to `_`, which comes last: a binary search on the first byte finds the few
 * keywords that start like the word. */
MsTok ms_tok_from_word(MsSpan word) {
  if (word.len > 9 || word.len == 0) {
    return MS_T_Name;
  }
  if (word.len == 1 && word.ptr[0] == '_') {
    return MS_T_Underscore;
  }
  const uint8_t first = word.ptr[0];
  size_t low = 0;
  size_t high = MS_COUNT_OF(KEYWORDS) - 1; /* without `_` */
  while (low < high) {
    const size_t mid = low + (high - low) / 2;
    if ((uint8_t)KEYWORDS[mid].word[0] < first) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  for (; low < MS_COUNT_OF(KEYWORDS) - 1 && (uint8_t)KEYWORDS[low].word[0] == first; low++) {
    const Keyword *keyword = &KEYWORDS[low];
    if (keyword->len == word.len && memcmp(keyword->word, word.ptr, word.len) == 0) {
      return (MsTok)keyword->kind;
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
