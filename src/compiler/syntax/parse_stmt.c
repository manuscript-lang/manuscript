/* Owns statements and suites. */
#include "compiler/syntax/parse_internal.h"

/* A keyword of another language written as a statement: the words that name it, the advice, and whether
 * the advice quotes the word (`%S`) or carries a fix edit. */
typedef struct ForeignKeyword {
  const char *words[3]; /* NULL ends the list */
  const char *advice;
  const char *fix; /* replacement for the word, or NULL */
  bool quotes_word;
} ForeignKeyword;

static const char FAILURES_ADVICE[] =
    "'%S' is not a keyword; failures are values; return error(...) from a fn returning T!, propagate a "
    "Result with 'call()?', or handle it with 'if value := result:' and an else branch";

static const ForeignKeyword FOREIGN_KEYWORDS[] = {
    {{"assert"},
     "there is no 'assert': in a test block write 'expect_equal(actual, expected)?' or "
     "'expect_true(condition)?', imported from \"@std/test/test.ms\"",
     NULL,
     false},
    {{"pass"}, "'pass' is not a keyword; write 'void' for an empty block or match arm", "void", false},
    {{"const", "val", "final"},
     "'%S' is not a keyword; write 'name := ...' for a binding that is not reassigned, or 'var name = ...' "
     "when it changes",
     NULL,
     true},
    {{"throw", "raise", "catch"}, FAILURES_ADVICE, NULL, true},
    {{"elseif"}, "'elseif' is not a keyword; write 'else if <condition>:' for a further branch", NULL, false},
    {{"elif"}, "there is no 'elif': write 'else if <condition>:' for a further branch", NULL, false},
    {{"def"}, "there is no 'def': declare a function with 'fn name(a: Int) Int:'", NULL, false},
    {{"switch"},
     "'switch' is not a keyword; write 'match value:' with one arm per case of your own type, or 'if x == "
     "a:' with 'else if' for plain values",
     NULL,
     false},
    {{"except", "finally"}, FAILURES_ADVICE, NULL, true},
    {{"loop"}, "'loop' is not a keyword; write 'while true:' and leave it with 'break'", NULL, false},
    {{"foreach"}, "'foreach' is not a keyword; write 'for item in items:'", NULL, false},
    {{"class"},
     "'class' is not a keyword inside a fn; declare a type with 'type Name:' at module level",
     NULL,
     false},
    {{"del"},
     "'del' is not a keyword; remove from a collection with its methods, such as xs.remove(i) or "
     "m.remove(key)",
     NULL,
     false},
    {{"global", "nonlocal"},
     "'%S' is not a keyword; a fn sees module constants directly, and mutable state lives in a 'var' or a "
     "field passed explicitly",
     NULL,
     true},
    {{"yield"},
     "'yield' is not a keyword; there are no generators, so build a list and return it",
     NULL,
     false},
    {{"async", "await"},
     "'%S' is not a keyword; call the function directly, or start concurrent work with promise(fn: ...) "
     "from \"@std/concurrency/promise.ms\"",
     NULL,
     true},
    {{"go"},
     "'go' is not a keyword; start concurrent work with promise(fn: ...) from "
     "\"@std/concurrency/promise.ms\": result := promise(fn: work()), then result.wait()",
     NULL,
     false},
};

static bool names_keyword(const ForeignKeyword *entry, MsSpan name) {
  for (size_t index = 0; index < MS_COUNT_OF(entry->words) && entry->words[index] != NULL; index++) {
    if (ms_span_is_text(name, entry->words[index])) {
      return true;
    }
  }
  return false;
}

/* A name that is a keyword in another language, written as a statement: reports how to say it in
 * Manuscript and returns true. */
static bool report_foreign_keyword(Parser *p, MsToken t, MsSpan n) {
  for (size_t index = 0; index < MS_COUNT_OF(FOREIGN_KEYWORDS); index++) {
    const ForeignKeyword *entry = &FOREIGN_KEYWORDS[index];
    if (!names_keyword(entry, n)) {
      continue;
    }
    const MsSpan advice =
        entry->quotes_word ? parse_fmt(p, entry->advice, n) : ms_span_of_text(entry->advice);
    if (entry->fix != NULL) {
      parse_fail_fix(p, t, advice, ms_span_of_text(entry->fix));
    } else {
      parse_fail(p, t, advice);
    }
    return true;
  }
  return false;
}

/* An expression that is not a call, written as a statement where only calls may stand alone. */
static void report_standalone_expression(Parser *p, MsToken t, const MsExpr *e) {
  if (e->kind == MS_E_NAME && report_foreign_keyword(p, t, ms_names_span(p->names, e->u.sym))) {
    return;
  }
  if (parse_kind(p) == MS_T_Comma) {
    parse_fail(
        p, t,
        ms_span_of_text("a statement cannot start with a comma-separated list of names: write one binding "
                        "per line ('a := f()'), or destructure one value with '[a, b] := value'"));
    return;
  }
  parse_fail(p, t,
             ms_span_of_text(
                 "only a call, a call followed by '?', or match can be a standalone expression statement; "
                 "use 'name := ...' to keep the value, 'return' to return it, or call a function"));
}

/* `target = value`; an index target becomes the call that sets the element. */
MS_NODISCARD static bool assignment_statement(Parser *p, MsToken t, MsExpr *e, MsStmt *st) {
  MsExpr *left = NULL, *index = NULL;
  MsExpr *value = NULL;
  if (ms_expr_index(e, &left, &index)) {
    if (!parse_expression(p, 0, &value))
      return false;
    st->kind = MS_S_CALL;
    st->u.expr = parse_index_set(p, e->pos, left, index, value, false);
    return true;
  }
  if (!parse_assign_target(p, t, e, st))
    return false;
  if (!parse_expression(p, 0, &value))
    return false;
  st->kind = MS_S_ASSIGN;
  st->u.assign.value = value;
  return true;
}

MS_NODISCARD static bool expression_statement(Parser *p, MsToken t, bool allow_value, MsStmt *st) {
  MsExpr *e = NULL;
  if (!parse_expression(p, 0, &e))
    return false;
  if (parse_compound_assignment(p)) {
    if (!parse_compound(p, t, e, st))
      return false;
  } else if (parse_take(p, MS_T_Assign)) {
    if (!assignment_statement(p, t, e, st))
      return false;
  } else {
    bool try_call = e->kind == MS_E_UNARY && e->op == MS_U_TRY && e->u.bin.left->kind == MS_E_CALL;
    bool is_call = e->kind == MS_E_CALL || e->kind == MS_E_MATCH || e->kind == MS_E_VOID;
    if (!p->inline_return && !is_call && !try_call && !allow_value) {
      report_standalone_expression(p, t, e);
      return false;
    }
    st->kind = p->inline_return ? MS_S_RETURN : MS_S_CALL;
    st->u.expr = e;
  }
  return parse_end(p);
}

/* The statement parsers below each take the statement's first token and a statement `st` that
 * already holds its position. They set *out to the finished statement, or leave it NULL when the
 * tokens are not their statement, so the caller tries the next one. */

static bool ends_expression(MsTok k) {
  return k == MS_T_Newline || k == MS_T_Indent || k == MS_T_Dedent || k == MS_T_Eof || k == MS_T_Comma ||
         k == MS_T_RParen || k == MS_T_RBracket || k == MS_T_RBrace;
}

/* `void call()` runs the call and drops its result on purpose: the `_ := call()` binding. */
MS_NODISCARD static bool void_statement(Parser *p, MsToken t, MsStmt **out) {
  if (ends_expression((MsTok)parse_ahead(p, 1).kind)) {
    return true;
  }
  p->at++;
  MsExpr *value = NULL;
  if (!parse_expression(p, 0, &value))
    return false;
  if (!parse_end(p))
    return false;
  MsStmt *s = MS_ARENA_NEW(p->arena, MsStmt);
  s->id = parse_new_id(p);
  uint32_t pattern_id = parse_new_id(p);
  s->pos = t.pos;
  s->kind = MS_S_BIND;
  MsPattern *pt = MS_ARENA_NEW(p->arena, MsPattern);
  pt->id = pattern_id;
  pt->pos = t.pos;
  pt->kind = MS_P_NAME;
  pt->u.name = parse_intern(p, "_");
  s->u.bind.pattern = pt;
  s->u.bind.value = value;
  *out = s;
  return true;
}

static bool starts_binding_target(MsTok k) {
  return k == MS_T_Name || k == MS_T_Underscore || k == MS_T_LBracket || k == MS_T_LBrace;
}

/* Reports the removed `let`, which is the current token, with the rewrite that replaces it;
 * `first` is where the diagnostic points. */
static void report_removed_let(Parser *p, MsToken first, MsSpan message) {
  MsToken name = parse_ahead(p, 1), eq = parse_ahead(p, 2);
  if (name.kind == MS_T_Name && eq.kind == MS_T_Assign) {
    MsSpan n = parse_text(p, name);
    parse_fail_fix_range(p, first, eq, message, parse_fmt(p, "%S :=", n));
    return;
  }
  parse_fail(p, first, message);
}

/* Syntax from other languages that was removed: `_ := v` and `let`. Returns true when it
 * reported one. */
static bool report_removed_binding(Parser *p, MsToken t) {
  if (t.kind == MS_T_Underscore && parse_ahead(p, 1).kind == MS_T_ColonAssign) {
    parse_fail_fix_range(p, t, parse_ahead(p, 1),
                         ms_span_of_text("'_ := value' was removed; write 'void value' to run an expression "
                                         "and drop its result on purpose"),
                         ms_span_of_text("void"));
    return true;
  }
  if (t.kind == MS_T_Name && parse_text_is(p, t, "let") &&
      starts_binding_target((MsTok)parse_ahead(p, 1).kind)) {
    report_removed_let(
        p, t,
        ms_span_of_text("'let' was removed; bind with 'x := value' (or 'x: Type := value'), destructure with "
                        "'[a, b] := value', and use 'var x = value' for a mutable binding"));
    return true;
  }
  return false;
}

MS_NODISCARD static bool var_statement(Parser *p, MsToken t, MsPos pos, MsStmt **out) {
  p->at++;
  if (parse_kind(p) == MS_T_LParen) {
    MsStmts entries = {0};
    if (!parse_binding_group(p, t, &entries))
      return false;
    p->nqueued = entries.len - 1;
    p->queued = entries.ptr + 1;
    *out = entries.ptr[0];
    return true;
  }
  MsStmt *s = NULL;
  if (!parse_binding(p, true, NULL, pos, &s))
    return false;
  if (!parse_end(p))
    return false;
  *out = s;
  return true;
}

/* `fn name(...) Result:` inside a body binds a lambda to the name. */
MS_NODISCARD static bool local_fn_statement(Parser *p, MsToken t, MsStmt *st, MsStmt **out) {
  if (!(parse_ahead(p, 1).kind == MS_T_Name &&
        (parse_ahead(p, 2).kind == MS_T_LParen || parse_ahead(p, 2).kind == MS_T_LBracket))) {
    return true;
  }
  p->at++;
  MsToken name = {0};
  if (!parse_need_token(p, MS_T_Name, &name))
    return false;
  if (parse_kind(p) == MS_T_LBracket) {
    parse_fail(p, parse_peek(p),
               ms_span_of_text(
                   "a local fn cannot take type parameters; declare a generic function at module level"));
    return false;
  }
  MsParams params = {0};
  if (!parse_parameters(p, true, false, &params))
    return false;
  MsTypeRef *result = NULL;
  if (!parse_result_type(p, &result))
    return false;
  MsStmts body = {0};
  if (!parse_statement_suite(p, true, false, &body))
    return false;
  uint32_t pid = parse_new_id(p);
  MsExpr *value = parse_mk(p, t.pos, MS_E_LAMBDA);
  value->u.lambda.params = params;
  value->u.lambda.result = result;
  value->u.lambda.body = body;
  MsPattern *pt = MS_ARENA_NEW(p->arena, MsPattern);
  pt->id = pid;
  pt->pos = name.pos;
  pt->kind = MS_P_NAME;
  pt->u.name = parse_sym(p, name);
  st->kind = MS_S_BIND;
  st->u.bind.pattern = pt;
  st->u.bind.value = value;
  *out = parse_finish_stmt(p, st);
  return true;
}

MS_NODISCARD static bool return_statement(Parser *p, MsStmt *st, MsStmt **out) {
  p->at++;
  MsExpr *value = NULL;
  MsTok k = parse_kind(p);
  bool closes_inline =
      p->inline_statement && (k == MS_T_Comma || k == MS_T_RParen || k == MS_T_RBracket || k == MS_T_RBrace);
  if (k != MS_T_Newline && !closes_inline) {
    if (!parse_expression(p, 0, &value))
      return false;
  }
  if (!parse_end(p))
    return false;
  st->kind = MS_S_RETURN;
  st->u.expr = value;
  *out = parse_finish_stmt(p, st);
  return true;
}

/* The binding of `if value := optional:` or `if var value = optional:`; none when absent. */
MS_NODISCARD static bool if_binding(Parser *p, MsToken t, MsPattern **bind, bool *is_mutable) {
  if (parse_kind(p) == MS_T_Name && parse_text_is(p, parse_peek(p), "let") &&
      starts_binding_target((MsTok)parse_ahead(p, 1).kind)) {
    report_removed_let(p, parse_peek(p),
                       ms_span_of_text("'if let' was removed; write 'if value := optional:' (or 'if var "
                                       "value = optional:' for a mutable binding)"));
    return false;
  }
  bool names_binding = (parse_kind(p) == MS_T_Name || parse_kind(p) == MS_T_Underscore) &&
                       parse_ahead(p, 1).kind == MS_T_ColonAssign;
  if (parse_kind(p) != MS_T_Var && !names_binding) {
    return true;
  }
  *is_mutable = parse_kind(p) == MS_T_Var;
  if (*is_mutable) {
    p->at++;
  }
  MsPattern *pat = NULL;
  if (!parse_pattern(p, &pat))
    return false;
  if (pat->kind != MS_P_NAME) {
    parse_fail(p, t,
               ms_span_of_text("an if binding takes one name; write 'if value := optional:' and destructure "
                               "the value inside the branch"));
    return false;
  }
  if (parse_kind(p) == MS_T_LParen) {
    parse_fail(p, t,
               ms_span_of_text(
                   "an if binding unwraps an Optional or Result into one name; it does not match alternative "
                   "cases. Write 'match value:' with a 'Case(x):' arm, or 'if value := optional:'"));
    return false;
  }
  *bind = pat;
  return parse_need(p, *is_mutable ? MS_T_Assign : MS_T_ColonAssign);
}

MS_NODISCARD static bool if_statement(Parser *p, MsToken t, MsStmt *st, MsStmt **out) {
  p->at++;
  MsPattern *bind = NULL;
  bool is_mutable = false;
  if (!if_binding(p, t, &bind, &is_mutable))
    return false;
  MsExpr *cond = NULL;
  if (!parse_expression(p, 0, &cond))
    return false;
  MsStmts body = {0};
  if (!parse_suite(p, &body))
    return false;
  parse_newlines(p);
  MsStmts else_body = {NULL, 0};
  if (parse_take(p, MS_T_Else)) {
    if (parse_kind(p) == MS_T_If) {
      else_body.ptr = MS_ARENA_NEW_ARRAY(p->arena, MsStmt *, 1);
      if (!parse_statement(p, false, &else_body.ptr[0]))
        return false;
      else_body.len = 1;
    } else if (!parse_suite(p, &else_body)) {
      return false;
    }
  }
  st->kind = MS_S_IF;
  st->u.branch.binding = bind;
  st->u.branch.is_mutable = is_mutable;
  st->u.branch.cond = cond;
  st->u.branch.body = body;
  st->u.branch.else_body = else_body;
  *out = parse_finish_stmt(p, st);
  return true;
}

MS_NODISCARD static bool while_statement(Parser *p, MsStmt *st, MsStmt **out) {
  p->at++;
  MsExpr *cond = NULL;
  if (!parse_expression(p, 0, &cond))
    return false;
  if (parse_kind(p) == MS_T_ColonAssign) {
    parse_fail(p, parse_peek(p),
               ms_span_of_text(
                   "while takes a condition, not a binding; to loop while a value is present write 'while "
                   "true:', bind it inside with 'if name := value:', and leave with 'else: break'"));
    return false;
  }
  MsStmts body = {0};
  if (!parse_suite(p, &body))
    return false;
  st->kind = MS_S_WHILE;
  st->u.loop.cond = cond;
  st->u.loop.body = body;
  *out = parse_finish_stmt(p, st);
  return true;
}

/* The variable of `for`: a name, or a hidden name when the element is destructured by `*pat`. */
MS_NODISCARD static bool for_variable(Parser *p, MsName *name, MsPattern **pat) {
  if (parse_kind(p) == MS_T_LBracket || parse_kind(p) == MS_T_LBrace) {
    *name = parse_intern(p, PARSE_HIDDEN_ITEM);
    return parse_pattern(p, pat);
  }
  MsToken name_token = {0};
  if (!parse_need_token(p, MS_T_Name, &name_token))
    return false;
  *name = parse_sym(p, name_token);
  return true;
}

MS_NODISCARD static bool for_statement(Parser *p, MsStmt *st, MsStmt **out) {
  p->at++;
  if (parse_kind(p) == MS_T_LParen) {
    parse_fail(p, parse_peek(p),
               ms_span_of_text("for does not take parentheses or a counter clause; write 'for item in "
                               "items:' to visit a List, or 'for i in 0..n:' to count"));
    return false;
  }
  MsName name = 0;
  MsPattern *pat = NULL;
  if (!for_variable(p, &name, &pat))
    return false;
  if (parse_kind(p) == MS_T_Name && parse_text_is(p, parse_peek(p), "of")) {
    parse_fail(p, parse_peek(p), ms_span_of_text("for uses 'in', not 'of'; write 'for item in items:'"));
    return false;
  }
  if (parse_kind(p) == MS_T_Comma) {
    parse_fail(p, parse_peek(p),
               ms_span_of_text(
                   "for binds one name or one pattern; to read positions, loop over the entries, e.g. 'for "
                   "entry in items.entries():' and use entry.index and entry.value (a Map's entries() give "
                   "entry.key and entry.value), or destructure each element with 'for [a, b] in pairs:'"));
    return false;
  }
  if (!parse_need(p, MS_T_In))
    return false;
  MsExpr *iter = NULL;
  if (!parse_expression(p, 0, &iter))
    return false;
  MsStmts body = {0};
  if (!parse_suite(p, &body))
    return false;
  if (pat != NULL) {
    MsStmt **with_binding = MS_ARENA_NEW_ARRAY(p->arena, MsStmt *, body.len + 1);
    with_binding[0] = parse_destructure(p, pat, name);
    __builtin_memcpy(with_binding + 1, body.ptr, body.len * sizeof(MsStmt *));
    body.ptr = with_binding;
    body.len++;
  }
  st->kind = MS_S_FOR;
  st->u.each.name = name;
  st->u.each.iter = iter;
  st->u.each.body = body;
  *out = parse_finish_stmt(p, st);
  return true;
}

/* The statements that start with a keyword; *out stays NULL for any other. */
MS_NODISCARD static bool keyword_statement(Parser *p, MsToken t, MsStmt *st, MsStmt **out) {
  switch (t.kind) {
  case MS_T_Void:
    return void_statement(p, t, out);
  case MS_T_Var:
    return var_statement(p, t, st->pos, out);
  case MS_T_Fn:
    return local_fn_statement(p, t, st, out);
  case MS_T_Return:
    return return_statement(p, st, out);
  case MS_T_Break:
  case MS_T_Continue:
    p->at++;
    if (!parse_end(p))
      return false;
    st->kind = t.kind == MS_T_Break ? MS_S_BREAK : MS_S_CONTINUE;
    *out = parse_finish_stmt(p, st);
    return true;
  case MS_T_If:
    return if_statement(p, t, st, out);
  case MS_T_While:
    return while_statement(p, st, out);
  case MS_T_For:
    return for_statement(p, st, out);
  default:
    return true;
  }
}

MS_NODISCARD bool parse_statement(Parser *p, bool allow_value, MsStmt **out) {
  MsToken t = parse_peek(p);
  MsStmt st = {0};
  st.pos = t.pos;
  *out = NULL;
  if (report_removed_binding(p, t)) {
    return false;
  }
  if (starts_binding_target((MsTok)t.kind) && parse_binding_ahead(p)) {
    MsStmt *s = NULL;
    if (!parse_binding(p, false, NULL, t.pos, &s))
      return false;
    if (!parse_end(p))
      return false;
    *out = s;
    return true;
  }
  if (!keyword_statement(p, t, &st, out))
    return false;
  if (*out != NULL)
    return true;
  if (!expression_statement(p, t, allow_value, &st))
    return false;
  *out = parse_finish_stmt(p, &st);
  return true;
}

/* Parses `: body`. `expression` marks a lambda body (an inline body is its value); `fn_body`
 * marks a function or method body (inline returns, may be empty). */
MS_NODISCARD static bool statement_suite_inner(Parser *p, bool is_expression, bool fn_body, bool outer,
                                               bool outer_lambda, MsStmts *out) {
  if (!parse_need(p, MS_T_Colon))
    return false;
  MsStmts none = {NULL, 0};
  if (parse_kind(p) == MS_T_Ellipsis && fn_body) {
    p->at++;
    p->ellipsis_body = true;
    if (!parse_end(p))
      return false;
    *out = none;
    return true;
  }
  if (parse_kind(p) != MS_T_Newline) {
    if (parse_kind(p) == MS_T_If && (is_expression || fn_body)) {
      /* `fn x: if c: a else: b`: the body is the conditional expression. */
      size_t start = p->at;
      MsPos at_pos = parse_peek(p).pos;
      Checkpoint checkpoint = parse_checkpoint_take(p);
      MsExpr *value = NULL;
      bool ok = parse_expression(p, 0, &value) && (is_expression || parse_end(p));
      if (!ok) {
        parse_checkpoint_restore(p, &checkpoint);
      }
      if (ok) {
        MsStmt *s = MS_ARENA_NEW(p->arena, MsStmt);
        s->id = parse_new_id(p);
        s->pos = at_pos;
        s->kind = MS_S_RETURN;
        s->u.expr = value;
        MsStmts result = {MS_ARENA_NEW_ARRAY(p->arena, MsStmt *, 1), 1};
        result.ptr[0] = s;
        *out = result;
        return true;
      }
      /* Not a conditional expression: report it as the statement it was written as. */
      p->at = start;
    }
    if (parse_kind(p) == MS_T_If || parse_kind(p) == MS_T_While || parse_kind(p) == MS_T_For) {
      MsToken t = parse_peek(p);
      parse_fail(
          p, t,
          parse_fmt(
              p, "inline bodies require one simple statement; put '%s' on its own line in an indented block",
              ms_tok_str((MsTok)t.kind)));
      return false;
    }
    p->inline_statement = true;
    p->inline_return = is_expression || fn_body;
    MsStmts body = {MS_ARENA_NEW_ARRAY(p->arena, MsStmt *, 1), 1};
    if (!parse_statement(p, false, &body.ptr[0]))
      return false;
    p->inline_statement = outer;
    if (!is_expression) {
      if (!parse_end(p))
        return false;
    }
    *out = body;
    return true;
  }
  p->inline_statement = false;
  p->inline_return = false;
  p->block_lambda = outer_lambda || is_expression;
  if (!parse_need(p, MS_T_Newline))
    return false;
  if (!parse_need(p, MS_T_Indent))
    return false;
  size_t m = parse_mark(p);
  for (;;) {
    parse_newlines(p);
    if (parse_kind(p) == MS_T_Dedent || parse_kind(p) == MS_T_Eof) {
      break;
    }
    if (!parse_statements(p, false))
      return false;
  }
  if (!parse_need(p, MS_T_Dedent))
    return false;
  MsStmts body;
  body.ptr = parse_finish(p, m, &body.len, sizeof(void *), _Alignof(void *));
  if (body.len == 0) {
    parse_fail(p, parse_previous(p),
               ms_span_of_text("suite cannot be empty; add at least one statement, or write '...' after the "
                               "colon for a runtime-bound declaration"));
    return false;
  }
  *out = body;
  return true;
}

MS_NODISCARD bool parse_statement_suite(Parser *p, bool is_expression, bool fn_body, MsStmts *out) {
  if (!parse_enter(p))
    return false;
  bool outer = p->inline_statement, outer_return = p->inline_return, outer_lambda = p->block_lambda;
  MsStmts r = {0};
  if (!statement_suite_inner(p, is_expression, fn_body, outer, outer_lambda, &r))
    return false;
  p->inline_statement = outer;
  p->inline_return = outer_return;
  p->block_lambda = outer_lambda;
  p->depth--;
  *out = r;
  return true;
}
