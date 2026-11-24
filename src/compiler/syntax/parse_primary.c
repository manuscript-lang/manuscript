/* Owns primary expressions: brackets, postfix, calls, literals, lambdas and groups. */
#include "compiler/syntax/parse_internal.h"

MS_LIST_DEFINE(StmtList, stmt_list, MsStmt *)

/* ---- brackets ---- */

/* Reinterprets a type as the value expression that spells it. */
static MsExpr *type_value(Parser *p, const MsTypeRef *t) {
  if (t->kind != MS_TYPE_NAMED) {
    return NULL;
  }
  MsSpan full = ms_names_span(p->names, t->name);
  size_t i = 0;
  while (i < full.len && full.ptr[i] != '.') {
    i++;
  }
  MsExpr *e = parse_mk_name(p, t->pos, ms_names_intern(p->names, ms_span_of(full.ptr, i)));
  /* token = tokens.partition_point(|k| k.pos.offset < t.pos.offset) */
  size_t lo = 0, hi = p->ntokens;
  while (lo < hi) {
    size_t mid = (lo + hi) / 2;
    if (p->tokens[mid].pos.offset < t->pos.offset) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  size_t token = lo;
  size_t index = 0;
  while (i < full.len) {
    i++; /* the dot */
    size_t j = i;
    while (j < full.len && full.ptr[j] != '.') {
      j++;
    }
    MsPos pos = p->tokens[token + 2 * (index + 1)].pos;
    e = parse_mk_member(p, pos, e, ms_names_intern(p->names, ms_span_of(full.ptr + i, j - i)));
    i = j;
    index++;
  }
  if (t->args.len != 0) {
    MsTypeRefs types = parse_copy_types(p, t->args);
    MsExpr *value = t->args.len == 1 ? type_value(p, t->args.ptr[0]) : NULL;
    MsExpr *a = parse_mk(p, t->pos, MS_E_APPLY);
    a->u.apply.left = e;
    a->u.apply.types = types;
    a->u.apply.value = value;
    e = a;
  }
  return e;
}

/* Brackets may contain types or a value. A single name or application keeps both interpretations
 * until name resolution identifies the receiver. */
MS_NODISCARD bool parse_bracket(Parser *p, MsExpr *left, MsExpr **out) {
  size_t start = p->at;
  MsTypeRefs types = {NULL, 0};
  bool have_types = false;
  /* A type starts with a name, `fn` or `(`; anything else is a value. */
  if (parse_starts_type(parse_kind(p)) && parse_type_bracket(p, start - 1)) {
    Checkpoint checkpoint = parse_checkpoint_take(p);
    p->speculative++;
    have_types = parse_type_args(p, &types);
    p->speculative--;
    if (!have_types) {
      parse_checkpoint_restore(p, &checkpoint);
      p->at = start;
      types = (MsTypeRefs){NULL, 0};
    }
  }
  if (have_types) {
    MsPos pos = left->pos;
    MsExpr *value = NULL;
    if (types.len == 1) {
      value = type_value(p, types.ptr[0]);
    }
    if (value != NULL) {
      types = parse_copy_types(p, types);
    }
    MsExpr *a = parse_mk(p, pos, MS_E_APPLY);
    a->u.apply.left = left;
    a->u.apply.types = types;
    a->u.apply.value = value;
    *out = a;
    return true;
  }
  MsExpr *index = NULL;
  if (!parse_expression(p, 0, &index))
    return false;
  if (parse_kind(p) == MS_T_Colon) {
    parse_fail(p, parse_peek(p),
               ms_span_of_text("there is no slice syntax; call slice(start: 0, end: 2) on a List or String"));
    return false;
  }
  if (!parse_need(p, MS_T_RBracket))
    return false;
  MsPos pos = left->pos;
  MsExpr *ix = parse_mk(p, pos, MS_E_INDEX);
  ix->u.bin.left = left;
  ix->u.bin.right = index;
  *out = ix;
  return true;
}

/* ---- primary, postfix, calls ---- */

MS_NODISCARD bool parse_postfix(Parser *p, MsExpr *e, MsExpr **out) {
  size_t links = 0;
  for (;;) {
    MsExpr *l, *ix;
    if (parse_take(p, MS_T_Dot)) {
      if (!parse_link(p, &links))
        return false;
      if (parse_kind(p) == MS_T_Number) {
        parse_fail(p, parse_peek(p),
                   ms_span_of_text("a number has at most one decimal point and member access needs a name; "
                                   "write the number once, e.g. 1.2"));
        return false;
      }
      MsToken name = {0};
      if (!parse_need_token(p, MS_T_Name, &name))
        return false;
      e = parse_mk_member(p, name.pos, e, parse_sym(p, name));
    } else if (parse_take(p, MS_T_LBracket)) {
      if (!parse_link(p, &links))
        return false;
      if (!parse_bracket(p, e, &e))
        return false;
    } else if (parse_take(p, MS_T_LParen)) {
      if (!parse_link(p, &links))
        return false;
      MsPos pos = e->pos;
      Args args = {0};
      if (!parse_call_arguments(p, &args))
        return false;
      e = parse_mk_call(p, pos, e, args.ptr, args.len);
    } else if (parse_kind(p) == MS_T_Question && ms_expr_index(e, &l, &ix) &&
               parse_ahead(p, 1).kind != MS_T_Dot) {
      p->at++;
      MsPos pos = e->pos;
      MsExpr *pr = parse_mk(p, pos, MS_E_PROBE);
      pr->u.bin.left = e;
      e = pr;
    } else if (parse_kind(p) == MS_T_Question) {
      /* `call()?` is `try call()`; one per value keeps a line readable. */
      p->at++;
      if (parse_kind(p) == MS_T_Question) {
        parse_fail(
            p, parse_peek(p),
            ms_span_of_text(
                "'?\?' is not an operator and '?' cannot repeat: unwrap an Optional with 'if x := v:' or "
                "give it a default with 'v.get_or(default)', or bind a Result to a name before the next '?'"));
        return false;
      }
      MsPos pos = e->pos;
      e = parse_mk_unary(p, pos, MS_U_TRY, e);
    } else {
      break;
    }
  }
  *out = e;
  return true;
}

/* Rejects an argument written with `=` (a label or an arrow closure) or with `var`. */
MS_NODISCARD static bool argument_is_plain(Parser *p) {
  if (parse_kind(p) == MS_T_Name && parse_ahead(p, 1).kind == MS_T_Assign) {
    MsToken eq = parse_ahead(p, 1);
    MsSpan n = parse_text(p, parse_peek(p));
    MsToken gt = parse_ahead(p, 2);
    if (gt.kind == MS_T_Gt && gt.pos.offset == eq.end.offset) {
      /* `x => x * 2`: a closure written with an arrow. */
      MsToken nm = parse_peek(p);
      MsSpan message = parse_fmt(p,
                                 "there is no '=>' closure; write fn %S: body, with the parameter after fn "
                                 "and a colon before the body",
                                 n);
      parse_fail_fix_range(p, nm, gt, message, parse_fmt(p, "fn %S:", n));
      return false;
    }
    parse_fail(p, eq, parse_fmt(p, "argument labels use a colon; write %S: value", n));
    return false;
  }
  if (parse_kind(p) == MS_T_Var) {
    MsToken t = parse_peek(p);
    t.end = parse_ahead(p, 1).pos;
    parse_fail_fix_range(p, t, t,
                         ms_span_of_text("a call does not write `var`: the callee's parameter declares "
                                         "that it changes the argument; write the argument plainly"),
                         ms_span_of_text(""));
    return false;
  }
  return true;
}

/* Rejects `x -> ...` after the argument `value`. */
MS_NODISCARD static bool argument_is_not_arrow(Parser *p, const MsExpr *value) {
  if (value->kind == MS_E_NAME && parse_kind(p) == MS_T_Arrow) {
    MsSpan n = ms_names_span(p->names, value->u.sym);
    parse_fail(p, parse_peek(p),
               parse_fmt(p,
                         "arrow closures are not supported; write 'fn %S: %S + 1', or 'fn(%S: Int) Int: %S "
                         "+ 1' with explicit types",
                         n, n, n, n));
    return false;
  }
  return true;
}

/* Parses the arguments after an opening parenthesis, through `)`. */
MS_NODISCARD bool parse_call_arguments(Parser *p, Args *out) {
  Args result = {NULL, 0};
  if (parse_take(p, MS_T_RParen)) {
    *out = result;
    return true;
  }
  size_t m = parse_mark(p);
  for (;;) {
    MsPos pos = parse_peek(p).pos;
    bool has_name = false;
    MsName name = 0;
    if (parse_kind(p) == MS_T_Name && parse_ahead(p, 1).kind == MS_T_Colon) {
      name = parse_sym(p, parse_peek(p));
      has_name = true;
      p->at += 2;
    }
    if (!argument_is_plain(p))
      return false;
    MsExpr *value = NULL;
    if (!parse_expression(p, 0, &value))
      return false;
    if (!argument_is_not_arrow(p, value))
      return false;
    MsArg a = {pos, has_name, name, value};
    parse_push(p, &a, sizeof a);
    if (!parse_take(p, MS_T_Comma)) {
      break;
    }
    if (parse_kind(p) == MS_T_RParen) {
      break;
    }
  }
  if (!parse_need(p, MS_T_RParen))
    return false;
  result.ptr = parse_finish(p, m, &result.len, sizeof(MsArg), _Alignof(MsArg));
  *out = result;
  return true;
}

MS_NODISCARD static bool list_literal(Parser *p, MsToken t, MsExpr **out) {
  MsExprs items = {NULL, 0};
  if (!parse_take(p, MS_T_RBracket)) {
    size_t m = parse_mark(p);
    for (;;) {
      if (!parse_push_expression(p, 0))
        return false;
      if (!parse_take(p, MS_T_Comma) || parse_kind(p) == MS_T_RBracket) {
        break;
      }
    }
    if (!parse_need(p, MS_T_RBracket))
      return false;
    items.ptr = parse_finish(p, m, &items.len, sizeof(void *), _Alignof(void *));
  }
  MsExpr *e = parse_mk(p, t.pos, MS_E_LIST);
  e->u.list = items;
  *out = e;
  return true;
}

MS_NODISCARD static bool match_expression(Parser *p, MsToken t, MsExpr **out) {
  MsExpr *scrutinee = NULL;
  if (!parse_expression(p, 0, &scrutinee))
    return false;
  MsExpr *arms_holder = MS_ARENA_NEW(p->arena, MsExpr);
  if (!parse_match_arms(p, t, arms_holder))
    return false;
  MsExpr *e = parse_mk(p, t.pos, MS_E_MATCH);
  e->u.match.scrutinee = scrutinee;
  e->u.match.arms = arms_holder->u.match.arms;
  *out = e;
  return true;
}

/* One `key: value` entry of a map literal, pushed on the scratch stack. */
MS_NODISCARD static bool map_entry(Parser *p) {
  MsExpr *key = NULL;
  if (!parse_expression(p, 0, &key))
    return false;
  if (parse_kind(p) == MS_T_Comma || parse_kind(p) == MS_T_RBrace) {
    parse_fail(
        p, parse_peek(p),
        ms_span_of_text("a brace literal is a Map and needs 'key: value' entries; there is no set literal, "
                        "so write Set[T]() and call add(value), or [a, b].to_set() from a List"));
    return false;
  }
  if (!parse_need(p, MS_T_Colon))
    return false;
  MsExpr *value = NULL;
  if (!parse_expression(p, 0, &value))
    return false;
  MsMapEntry entry = {key, value};
  parse_push(p, &entry, sizeof entry);
  return true;
}

MS_NODISCARD static bool map_literal(Parser *p, MsToken t, MsExpr **out) {
  uint32_t n = 0;
  MsMapEntry *entries = NULL;
  if (!parse_take(p, MS_T_RBrace)) {
    size_t m = parse_mark(p);
    for (;;) {
      if (!map_entry(p))
        return false;
      if (!parse_take(p, MS_T_Comma) || parse_kind(p) == MS_T_RBrace) {
        break;
      }
    }
    if (!parse_need(p, MS_T_RBrace))
      return false;
    entries = parse_finish(p, m, &n, sizeof(MsMapEntry), _Alignof(MsMapEntry));
  }
  MsExpr *e = parse_mk(p, t.pos, MS_E_MAP);
  e->u.map.ptr = entries;
  e->u.map.len = n;
  *out = e;
  return true;
}

/* The parameters of `fn a, b: ...`, which have no parentheses or types. A bracket or brace pattern
 * binds from a hidden parameter, and `destructured` collects the statements that unpack it. */
MS_NODISCARD static bool bare_lambda_parameters(Parser *p, MsParams *params, StmtList *destructured) {
  size_t m = parse_mark(p);
  uint32_t count = 0;
  while (parse_kind(p) == MS_T_Name || parse_kind(p) == MS_T_LBracket || parse_kind(p) == MS_T_LBrace ||
         (parse_kind(p) == MS_T_Var && parse_ahead(p, 1).kind == MS_T_Name)) {
    if (parse_kind(p) == MS_T_LBracket || parse_kind(p) == MS_T_LBrace) {
      MsPattern *pat = NULL;
      if (!parse_pattern(p, &pat))
        return false;
      MsName hidden = parse_numbered_name(p, "for item ", count);
      parse_push_ptr(p, parse_mk_param(p, pat->pos, hidden, NULL, NULL, false, false));
      count++;
      stmt_list_push(destructured, parse_destructure(p, pat, hidden));
    } else {
      /* `fn var exchange, next: ...`: a parameter the function changes in place;
       * `fn move item: ...` takes ownership of it. */
      bool moving = parse_take_move(p, (const MsTok[]){MS_T_Name}, 1);
      bool is_mutable = parse_take(p, MS_T_Var);
      MsToken name = parse_next(p);
      parse_push_ptr(p, parse_mk_param(p, name.pos, parse_sym(p, name), NULL, NULL, is_mutable, moving));
      count++;
    }
    if (!parse_take(p, MS_T_Comma)) {
      break;
    }
  }
  (*params).ptr = parse_finish(p, m, &(*params).len, sizeof(void *), _Alignof(void *));
  return true;
}

/* The parameters in parentheses of `fn (a: Int) Int: ...`, and its optional result type. */
MS_NODISCARD static bool lambda_signature(Parser *p, MsParams *params, MsTypeRef **result, bool *moves) {
  if (!parse_parameters(p, true, true, params))
    return false;
  if (parse_kind(p) == MS_T_Arrow) {
    parse_fail_fix(p, parse_peek(p),
                   ms_span_of_text("result types follow the parameter list without an arrow; remove '->', "
                                   "e.g. fn (x Int) Int: x + 1"),
                   ms_span_of_text(""));
    return false;
  }
  if (parse_kind(p) != MS_T_Colon) {
    return parse_move_type(p, result, moves);
  }
  return true;
}

MS_NODISCARD static bool lambda_expression(Parser *p, MsToken t, MsExpr **out) {
  MsTypeRef *result = NULL;
  bool result_moves = false;
  MsParams params = {0};
  StmtList destructured = {0};
  bool ok = parse_kind(p) == MS_T_LParen ? lambda_signature(p, &params, &result, &result_moves)
                                         : bare_lambda_parameters(p, &params, &destructured);
  MsStmts body = {0};
  ok = ok && parse_statement_suite(p, true, false, &body);
  size_t ndestructured = destructured.len;
  if (ok && ndestructured != 0) {
    MsStmt **with_unpacking = MS_ARENA_NEW_ARRAY(p->arena, MsStmt *, body.len + ndestructured);
    __builtin_memcpy(with_unpacking, destructured.ptr, ndestructured * sizeof(MsStmt *));
    __builtin_memcpy(with_unpacking + ndestructured, body.ptr, body.len * sizeof(MsStmt *));
    body.ptr = with_unpacking;
    body.len += (uint32_t)ndestructured;
  }
  stmt_list_free(&destructured);
  if (!ok) {
    return false;
  }
  MsExpr *e = parse_mk(p, t.pos, MS_E_LAMBDA);
  e->u.lambda.params = params;
  e->u.lambda.result = result;
  e->u.lambda.result_moves = result_moves;
  e->u.lambda.body = body;
  *out = e;
  return true;
}

/* What to say about a token that cannot start an expression; `before` is the token ahead of it. */
static const char *expression_hint(MsToken t, MsTok before) {
  if (t.kind == MS_T_Else) {
    return "'else' continues an 'if' block: put it on its own line at the same indentation as that 'if', "
           "directly after the if body";
  }
  if (t.kind == MS_T_Gt && before == MS_T_Lt) {
    return "'<>' is not an operator; write '!=' for inequality";
  }
  if (t.kind == MS_T_Star && before == MS_T_Star) {
    return "there is no '**' power operator; multiply explicitly or call a function from @std/math/math.ms";
  }
  if ((t.kind == MS_T_Comma || t.kind == MS_T_RParen) && before == MS_T_Colon) {
    return "a label before ':' needs a value, e.g. count: 1";
  }
  if (t.kind == MS_T_Comma) {
    return "remove the extra comma or add the missing value before it";
  }
  return "write a value, name, call, or literal here";
}

static void report_expected_expression(Parser *p, MsToken t) {
  MsTok before = p->at > 1 ? (MsTok)p->tokens[p->at - 2].kind : MS_T_Eof;
  MsSpan word = parse_text(p, t);
  MsSpan dt = parse_describe(p, t);
  /* Words that read as names (`type`, `test`) are the ones written as variables. */
  bool reserved = t.kind == MS_T_Test || t.kind == MS_T_Type || t.kind == MS_T_Fixture;
  if (reserved) {
    parse_fail(p, t,
               parse_fmt(p,
                         "expected an expression, found %S; '%S' is a reserved word and cannot be used as a "
                         "name: pick another name for the variable, field or parameter",
                         dt, word));
    return;
  }
  parse_fail(p, t, parse_fmt(p, "expected an expression, found %S; %s", dt, expression_hint(t, before)));
}

/* `( expression )`. */
MS_NODISCARD static bool grouped_expression(Parser *p, MsToken t, MsExpr **out) {
  if (parse_kind(p) == MS_T_RParen) {
    parse_fail(p, t, ms_span_of_text("'()' is not a value; the Void value is written 'void'"));
    return false;
  }
  if (!parse_expression(p, 0, out))
    return false;
  if (parse_kind(p) == MS_T_Comma) {
    parse_fail(p, parse_peek(p),
               ms_span_of_text("Manuscript has no tuples; declare a type with 'type Pair:' and named fields, "
                               "or use a List when the items share one type"));
    return false;
  }
  return parse_need(p, MS_T_RParen);
}

/* The expressions that are one token or a simple literal; *out stays NULL for any other token. */
MS_NODISCARD static bool simple_primary(Parser *p, MsToken t, MsExpr **out) {
  switch (t.kind) {
  case MS_T_Name:
  case MS_T_SelfKw:
  case MS_T_Fixture:
    *out = parse_mk_name(p, t.pos, parse_sym(p, t));
    return true;
  case MS_T_Number:
    *out = parse_mk(p, t.pos, MS_E_NUMBER);
    (*out)->u.sym = parse_sym(p, t);
    return true;
  case MS_T_True:
  case MS_T_False:
    *out = parse_mk(p, t.pos, MS_E_BOOL);
    (*out)->u.flag = t.kind == MS_T_True;
    return true;
  case MS_T_Void:
    *out = parse_mk(p, t.pos, MS_E_VOID);
    return true;
  case MS_T_String: {
    TextParts parts = {0};
    if (!parse_text_parts_of(p, t, &parts))
      return false;
    MsExpr *e = parse_mk(p, t.pos, MS_E_TEXT);
    e->u.text.ptr = parts.ptr;
    e->u.text.len = parts.len;
    *out = e;
    return true;
  }
  default:
    return true;
  }
}

MS_NODISCARD static bool primary_operand(Parser *p, MsToken t, MsExpr **out) {
  switch (t.kind) {
  case MS_T_LParen:
    return grouped_expression(p, t, out);
  case MS_T_LBracket:
    return list_literal(p, t, out);
  case MS_T_Match:
    return match_expression(p, t, out);
  case MS_T_LBrace:
    return map_literal(p, t, out);
  case MS_T_Fn:
    return lambda_expression(p, t, out);
  case MS_T_If:
    return parse_if_expression(p, t, out);
  default:
    report_expected_expression(p, t);
    return false;
  }
}

MS_NODISCARD bool parse_primary(Parser *p, MsExpr **out) {
  MsToken t = parse_peek(p);
  p->at++;
  MsExpr *e = NULL;
  if (!simple_primary(p, t, &e))
    return false;
  if (e == NULL && !primary_operand(p, t, &e))
    return false;
  return parse_postfix(p, e, out);
}
