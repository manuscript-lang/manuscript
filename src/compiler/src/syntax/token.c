#include <string.h>

#include "ms/token.h"

static const char *const tok_text[] = {
#define X(name, text) text,
    MS_TOKENS(X)
#undef X
};

const char *ms_tok_str(MsTok k) {
    return tok_text[k];
}

typedef struct {
    const char *word;
    uint8_t kind;
} Keyword;

/* Sorted by word. */
static const Keyword keywords[] = {
    {"and", MS_T_And},         {"break", MS_T_Break},   {"continue", MS_T_Continue},
    {"else", MS_T_Else},       {"enum", MS_T_Enum},     {"export", MS_T_Export},
    {"extern", MS_T_Extern},   {"false", MS_T_False},   {"fixture", MS_T_Fixture},
    {"fn", MS_T_Fn},           {"for", MS_T_For},       {"if", MS_T_If},
    {"impl", MS_T_Impl},       {"import", MS_T_Import}, {"in", MS_T_In},
    {"interface", MS_T_Interface}, {"match", MS_T_Match}, {"not", MS_T_Not},
    {"or", MS_T_Or},           {"return", MS_T_Return}, {"self", MS_T_SelfKw},
    {"test", MS_T_Test},       {"true", MS_T_True},     {"try", MS_T_Try},
    {"type", MS_T_Type},       {"var", MS_T_Var},       {"void", MS_T_Void},
    {"while", MS_T_While},     {"_", MS_T_Underscore},
};

MsTok ms_tok_from_word(const char *w, size_t n) {
    if (n > 9 || n == 0) {
        return MS_T_Name;
    }
    for (size_t i = 0; i < sizeof keywords / sizeof keywords[0]; i++) {
        const char *k = keywords[i].word;
        if (k[0] == w[0] && strlen(k) == n && memcmp(k, w, n) == 0) {
            return (MsTok)keywords[i].kind;
        }
    }
    return MS_T_Name;
}

bool ms_tok_is_contextual(MsTok k) {
    switch (k) {
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
