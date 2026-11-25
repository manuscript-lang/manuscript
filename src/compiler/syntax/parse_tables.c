/* Owns the parser tables: operator classes, type-bracket scan and foreign declaration words. */
#include "compiler/syntax/parse_internal.h"

/* ---- tables ---- */

static bool type_token(MsTok k) {
  switch (k) {
  case MS_T_Name:
  case MS_T_Dot:
  case MS_T_LBracket:
  case MS_T_RBracket:
  case MS_T_Comma:
  case MS_T_Question:
  case MS_T_Bang:
  case MS_T_Fn:
  case MS_T_Var:
  case MS_T_LParen:
  case MS_T_RParen:
    return true;
  default:
    return false;
  }
}

typedef struct OpenBracket {
  size_t at;
  bool ok;
} OpenBracket;

MS_LIST_DEFINE(OpenList, open_list, OpenBracket)

static void close_bracket(OpenList *open, uint64_t *bits) {
  OpenBracket closed;
  if (!open_list_pop(open, &closed)) {
    return;
  }
  if (closed.ok) {
    bits[closed.at / 64] |= (uint64_t)1 << (closed.at % 64);
  }
  if (open->len != 0) {
    open_list_last(open)->ok &= closed.ok;
  }
}

/* One bit per token: set on a `[` whose bracketed tokens could all be type arguments. */
uint64_t *parse_compute_type_brackets(MsArena *arena, const MsToken *tokens, size_t count) {
  size_t words = (count + 63) / 64;
  uint64_t *bits = MS_ARENA_NEW_ARRAY(arena, uint64_t, words ? words : 1);
  OpenList open = {0};
  for (size_t at = 0; at < count; at++) {
    MsTok kind = (MsTok)tokens[at].kind;
    if (kind == MS_T_LBracket) {
      open_list_push(&open, (OpenBracket){at, true});
    } else if (kind == MS_T_RBracket) {
      close_bracket(&open, bits);
    } else if (!type_token(kind) && open.len != 0) {
      open_list_last(&open)->ok = false;
    }
  }
  open_list_free(&open);
  return bits;
}

bool parse_type_bracket(const Parser *p, size_t at) {
  return (p->type_brackets[at / 64] >> (at % 64)) & 1;
}

bool parse_binary_op(MsTok k, MsBinaryOp *op) {
  switch (k) {
  case MS_T_Or:
    *op = MS_B_OR;
    return true;
  case MS_T_And:
    *op = MS_B_AND;
    return true;
  case MS_T_EqEq:
    *op = MS_B_EQ;
    return true;
  case MS_T_NotEq:
    *op = MS_B_NE;
    return true;
  case MS_T_Lt:
    *op = MS_B_LT;
    return true;
  case MS_T_Gt:
    *op = MS_B_GT;
    return true;
  case MS_T_Le:
    *op = MS_B_LE;
    return true;
  case MS_T_Ge:
    *op = MS_B_GE;
    return true;
  case MS_T_Plus:
    *op = MS_B_ADD;
    return true;
  case MS_T_Minus:
    *op = MS_B_SUB;
    return true;
  case MS_T_Star:
    *op = MS_B_MUL;
    return true;
  case MS_T_Slash:
    *op = MS_B_DIV;
    return true;
  case MS_T_Percent:
    *op = MS_B_REM;
    return true;
  default:
    return false;
  }
}

bool parse_arith_op(MsTok k, MsBinaryOp *op) {
  switch (k) {
  case MS_T_Plus:
  case MS_T_Minus:
  case MS_T_Star:
  case MS_T_Slash:
  case MS_T_Percent:
    return parse_binary_op(k, op);
  default:
    return false;
  }
}

bool parse_starts_type(MsTok k) {
  return k == MS_T_Name || k == MS_T_Fn || k == MS_T_LParen;
}

const char *ms_unary_str(MsUnaryOp op) {
  switch (op) {
  case MS_U_NOT:
    return "not";
  case MS_U_NEG:
    return "-";
  case MS_U_PLUS:
    return "+";
  default:
    return "try";
  }
}

const char *ms_binary_str(MsBinaryOp op) {
  static const char *const s[] = {"or", "and", "==", "!=", "<", ">", "<=", ">=", "+", "-", "*", "/", "%"};
  return s[op];
}

int ms_binary_precedence(MsBinaryOp op) {
  switch (op) {
  case MS_B_OR:
    return 1;
  case MS_B_AND:
    return 2;
  case MS_B_EQ:
  case MS_B_NE:
  case MS_B_LT:
  case MS_B_GT:
  case MS_B_LE:
  case MS_B_GE:
    return 4;
  case MS_B_ADD:
  case MS_B_SUB:
    return 6;
  default:
    return 7;
  }
}

/* Declaration words from other languages: the message and the Manuscript spelling to replace the
 * word with, when there is one. */
bool parse_foreign_declaration(Parser *p, MsToken t, MsSpan *message, const char **replacement) {
  if (t.kind == MS_T_Var) {
    *message = ms_span_of_text("module level holds only constants (NAME := value); keep mutable state in a "
                               "'var' inside a fn, or in a field of a type");
    *replacement = NULL;
    return true;
  }
  if (t.kind != MS_T_Name) {
    return false;
  }
  MsSpan w = parse_text(p, t);
  const char *advice;
  const char *rep = NULL;
  if (ms_span_is_text(w, "function") || ms_span_is_text(w, "def") || ms_span_is_text(w, "func") ||
      ms_span_is_text(w, "fun") || ms_span_is_text(w, "sub")) {
    rep = "fn";
    advice = "declare a function as 'fn name(a Int) Int { ... }' with the result type after the parameters";
  } else if (ms_span_is_text(w, "class") || ms_span_is_text(w, "struct") || ms_span_is_text(w, "record") ||
             ms_span_is_text(w, "data")) {
    rep = "type";
    advice = "declare a type with 'type Name { ... }' and 'field Type' lines, then add methods as 'fn "
             "Name.method(...)' after it";
  } else if (ms_span_is_text(w, "union") || ms_span_is_text(w, "variant") || ms_span_is_text(w, "sealed")) {
    rep = "enum";
    advice = "declare an enum with 'enum Name { ... }' and one 'Variant' or 'Variant(field Type)' line each";
  } else if (ms_span_is_text(w, "trait") || ms_span_is_text(w, "protocol") ||
             ms_span_is_text(w, "abstract")) {
    rep = "interface";
    advice = "declare a contract with 'interface Name { ... }' and method signatures, then give a type methods that "
             "match it, 'fn Type.operation(...)'";
  } else if (ms_span_is_text(w, "const") || ms_span_is_text(w, "val") || ms_span_is_text(w, "final") ||
             ms_span_is_text(w, "let")) {
    advice = "write 'NAME := value' (or 'NAME: Type := value') for a module constant";
  } else if (ms_span_is_text(w, "pub") || ms_span_is_text(w, "public")) {
    rep = "export";
    advice = "write 'export' before the declaration to make it visible to other modules";
  } else if (ms_span_is_text(w, "use") || ms_span_is_text(w, "require") || ms_span_is_text(w, "include") ||
             ms_span_is_text(w, "using") || ms_span_is_text(w, "from")) {
    rep = "import";
    advice = "imports read: import name from \"path.ms\"";
  } else if (ms_span_is_text(w, "static") || ms_span_is_text(w, "private") ||
             ms_span_is_text(w, "internal") || ms_span_is_text(w, "async") || ms_span_is_text(w, "extern") ||
             ms_span_is_text(w, "package") || ms_span_is_text(w, "namespace") ||
             ms_span_is_text(w, "module")) {
    advice = "there is no such modifier; top level holds only import, fn, type, enum, interface, and test, "
             "constants (NAME := value), optionally prefixed by export";
  } else {
    return false;
  }
  *message = parse_fmt(p, "'%S' is not a Manuscript declaration keyword; %s", w, advice);
  *replacement = rep;
  return true;
}
