/* Owns expressions: operators, pipes, ranges, and match and if expressions. */
#include "compiler/syntax/parse_internal.h"

static const char TRY_REMOVED[] =
    "'try' was replaced by a postfix '?': write f(x)? instead of try f(x), and x | step? instead of x | try "
    "step";

/* ---- expressions ---- */

MsExpr *parse_mk_unary(Parser *p, MsPos pos, MsUnaryOp op, MsExpr *operand) {
  MsExpr *e = parse_mk(p, pos, MS_E_UNARY);
  e->op = (uint8_t)op;
  e->u.bin.left = operand;
  return e;
}

/* Rejects prefix `try`. When the operand is one call or access chain, the fix rewrites
 * `try f(x)` to `f(x)?`. */
static void fail_try(Parser *p, MsToken t) {
  p->at++;
  MsToken start = parse_peek(p);
  Checkpoint checkpoint = parse_checkpoint_take(p);
  MsExpr *operand = NULL;
  if (!parse_expression(p, PREFIX_OPERAND, &operand)) {
    parse_checkpoint_restore(p, &checkpoint);
    operand = NULL;
  }
  MsDiag *d = parse_diag(p, t.pos, ms_span_of_text(TRY_REMOVED));
  d->has_end = true;
  d->end = t.end;
  MsToken last = parse_previous(p);
  bool chain = false;
  if (operand != NULL) {
    switch (operand->kind) {
    case MS_E_NAME:
    case MS_E_MEMBER:
    case MS_E_CALL:
    case MS_E_INDEX:
    case MS_E_APPLY:
      chain = true;
      break;
    default:
      break;
    }
  }
  if (chain && last.end.line > 0 && start.lo < last.hi) {
    MsSpan replacement = parse_fmt(p, "%S?", (int)(last.hi - start.lo), p->source.ptr + start.lo);
    d->has_end = true;
    d->end = last.end;
    d->has_fix = true;
    d->fix_pos = t.pos;
    d->fix_end = last.end;
    d->replacement = replacement;
  }
}

/* `start..end` as the call `range(start, end)`; `..` names the standard `range`. */
static MsExpr *range_call(Parser *p, MsExpr *start, MsExpr *stop) {
  MsPos pos = start->pos;
  MsExpr *callee = parse_mk_name(p, pos, parse_intern(p, ".."));
  MsArg *args = MS_ARENA_NEW_ARRAY(p->arena, MsArg, 2);
  args[0] = (MsArg){start->pos, false, 0, start};
  args[1] = (MsArg){stop->pos, false, 0, stop};
  return parse_mk_call(p, pos, callee, args, 2);
}

/* Parses one `| step` after `lhs` and desugars it to the ordinary expression the step names. */
MS_NODISCARD static bool parse_pipe(Parser *p, MsExpr *lhs, MsExpr **out) {
  p->at++;
  if (parse_kind(p) == MS_T_Pipe) {
    MsToken t = parse_peek(p);
    MsToken first = parse_previous(p);
    parse_fail_word_operator(
        p, first, t,
        ms_span_of_text(
            "'||' is not an operator; write 'or' for logical or, and '|' only to start a pipe step"),
        "or");
    return false;
  }
  if (parse_kind(p) == MS_T_Try) {
    parse_fail(p, parse_peek(p), ms_span_of_text(TRY_REMOVED));
    return false;
  }
  MsExpr *step;
  if (parse_kind(p) == MS_T_Dot) {
    if (!parse_postfix(p, lhs, &step))
      return false;
  } else {
    MsToken name = parse_peek(p);
    if (name.kind != MS_T_Name) {
      const char *hint = "";
      if (name.kind == MS_T_Newline) {
        hint = "; to continue a flow on the next line, end this line before '|' and start the next line with "
               "'|'";
      }
      MsSpan dn = parse_describe(p, name);
      parse_fail(p, name,
                 parse_fmt(p,
                           "a pipe step is a function name, a call without its first argument, or a "
                           "'.method' step; write x | f, x | f(a: 1), or x | .method(a: 1), found %S%s",
                           dn, hint));
      return false;
    }
    p->at++;
    MsExpr *callee = parse_mk_name(p, name.pos, parse_sym(p, name));
    size_t links = 0;
    /* A '.' on a later line continues the flow and applies to the step's result. */
    while (parse_kind(p) == MS_T_Dot && parse_peek(p).pos.line == p->tokens[p->at - 1].pos.line) {
      if (!parse_link(p, &links))
        return false;
      p->at++;
      MsToken member = {0};
      if (!parse_need_token(p, MS_T_Name, &member))
        return false;
      callee = parse_mk_member(p, member.pos, callee, parse_sym(p, member));
    }
    if (parse_kind(p) == MS_T_LBracket) {
      MsSpan n = parse_text(p, name);
      parse_fail(p, parse_peek(p),
                 parse_fmt(p,
                           "a pipe step cannot take type arguments; bind the instance to a name first, e.g. "
                           "step := %S[Int], then write x | step",
                           n));
      return false;
    }
    Args rest = {NULL, 0};
    if (parse_take(p, MS_T_LParen)) {
      if (!parse_call_arguments(p, &rest))
        return false;
    }
    MsArg *args = MS_ARENA_NEW_ARRAY(p->arena, MsArg, rest.len + 1);
    args[0] = (MsArg){lhs->pos, false, 0, lhs};
    if (rest.len != 0) {
      __builtin_memcpy(args + 1, rest.ptr, rest.len * sizeof(MsArg));
    }
    step = parse_mk_call(p, name.pos, callee, args, rest.len + 1);
  }
  if (parse_kind(p) == MS_T_Question) {
    MsToken question = parse_peek(p);
    p->at++;
    step = parse_mk_unary(p, question.pos, MS_U_TRY, step);
  }
  *out = step;
  return true;
}

/* The first operand: a prefix `not`, `+` or `-` with its operand, or a primary expression. */
MS_NODISCARD static bool leading_operand(Parser *p, int min, MsExpr **out) {
  MsToken t = parse_peek(p);
  if (t.kind == MS_T_Not && min > PREFIX_OPERAND) {
    parse_fail(
        p, t,
        ms_span_of_text(
            "not requires grouping at this operator position; wrap it in parentheses, e.g. a == (not b)"));
    return false;
  }
  if (t.kind == MS_T_Try) {
    fail_try(p, t);
    return false;
  }
  if (t.kind != MS_T_Not && t.kind != MS_T_Plus && t.kind != MS_T_Minus) {
    return parse_primary(p, out);
  }
  p->at++;
  MsUnaryOp op = MS_U_NOT;
  int binding_power = PREFIX_OPERAND;
  if (t.kind != MS_T_Not) {
    op = t.kind == MS_T_Plus ? MS_U_PLUS : MS_U_NEG;
    binding_power = 8;
  }
  MsExpr *operand = NULL;
  if (!parse_expression(p, binding_power, &operand))
    return false;
  *out = parse_mk_unary(p, t.pos, op, operand);
  return true;
}

/* `e | step`, then a member access or call chain on the result. */
MS_NODISCARD static bool pipe_operator(Parser *p, MsExpr **e, size_t *links) {
  if (!parse_link(p, links))
    return false;
  if (!parse_pipe(p, *e, e))
    return false;
  if (parse_kind(p) == MS_T_Dot) {
    if (!parse_postfix(p, *e, e))
      return false;
  }
  MsBinaryOp ignored;
  if (parse_binary_op(parse_kind(p), &ignored)) {
    parse_fail(p, parse_peek(p),
               ms_span_of_text("a pipe has the lowest precedence; parenthesize it to use its result in an "
                               "operator, e.g. (x | f) == y"));
    return false;
  }
  return true;
}

/* `e..right`, which is the call range(e, right). */
MS_NODISCARD static bool range_operator(Parser *p, MsExpr **e) {
  p->at++;
  MsExpr *right = NULL;
  if (!parse_expression(p, RANGE_LEVEL + 1, &right))
    return false;
  if (parse_kind(p) == MS_T_DotDot) {
    parse_fail(p, parse_peek(p),
               ms_span_of_text("a range cannot chain; write one 'start..end', or use range_by for a step "
                               "from \"@std/collections/collections.ms\""));
    return false;
  }
  *e = range_call(p, *e, right);
  return true;
}

/* Rejects `x++` and `x--` written as statements, which parse as two operators. */
static bool is_increment(const Parser *p, MsToken op, const MsExpr *e) {
  return (op.kind == MS_T_Plus || op.kind == MS_T_Minus) && e->kind == MS_E_NAME &&
         parse_ahead(p, 1).kind == op.kind && parse_ahead(p, 2).kind == MS_T_Newline;
}

MS_NODISCARD static bool expression_inner(Parser *p, int min, MsExpr **out) {
  MsExpr *e = NULL;
  if (!leading_operand(p, min, &e))
    return false;
  bool compared = false;
  size_t links = 0;
  for (;;) {
    MsToken op = parse_peek(p);
    if (parse_compound_assignment(p)) {
      break;
    }
    if (op.kind == MS_T_Amp) {
      parse_and_and(p, op);
      return false;
    }
    if (op.kind == MS_T_Pipe || op.kind == MS_T_DotDot) {
      if (min > (op.kind == MS_T_Pipe ? 0 : RANGE_LEVEL)) {
        break;
      }
      bool ok = op.kind == MS_T_Pipe ? pipe_operator(p, &e, &links) : range_operator(p, &e);
      if (!ok)
        return false;
      continue;
    }
    MsBinaryOp bop;
    if (!parse_binary_op((MsTok)op.kind, &bop)) {
      break;
    }
    int level = ms_binary_precedence(bop);
    if (level < min) {
      break;
    }
    if (is_increment(p, op, e)) {
      const char *o = ms_tok_str((MsTok)op.kind);
      MsSpan n = ms_names_span(p->names, e->u.sym);
      parse_fail(p, op, parse_fmt(p, "Manuscript has no '%s%s' operator; write '%S %s= 1'", o, o, n, o));
      return false;
    }
    if (level == 4 && compared) {
      parse_fail(
          p, op,
          ms_span_of_text(
              "comparison operators cannot chain; combine two comparisons with 'and', e.g. a < b and b < c"));
      return false;
    }
    p->at++;
    if (!parse_link(p, &links))
      return false;
    MsExpr *right = NULL;
    if (!parse_expression(p, level + 1, &right))
      return false;
    MsExpr *b = parse_mk(p, op.pos, MS_E_BINARY);
    b->op = (uint8_t)bop;
    b->u.bin.left = e;
    b->u.bin.right = right;
    e = b;
    compared = compared || level == 4;
  }
  *out = e;
  return true;
}

MS_NODISCARD bool parse_expression(Parser *p, int min, MsExpr **out) {
  if (!parse_enter(p))
    return false;
  MsExpr *r = NULL;
  if (!expression_inner(p, min, &r))
    return false;
  p->depth--;
  *out = r;
  return true;
}

MS_NODISCARD static bool case_path(Parser *p, MsExpr **out) {
  MsToken t = {0};
  if (!parse_need_token(p, MS_T_Name, &t))
    return false;
  MsExpr *e = parse_mk_name(p, t.pos, parse_sym(p, t));
  if (parse_take(p, MS_T_LBracket)) {
    MsTypeRefs types = {0};
    if (!parse_type_args(p, &types))
      return false;
    MsExpr *a = parse_mk(p, t.pos, MS_E_APPLY);
    a->u.apply.left = e;
    a->u.apply.types = types;
    e = a;
  }
  size_t links = 0;
  while (parse_take(p, MS_T_Dot)) {
    if (!parse_link(p, &links))
      return false;
    MsToken name = {0};
    if (!parse_need_token(p, MS_T_Name, &name))
      return false;
    e = parse_mk_member(p, name.pos, e, parse_sym(p, name));
  }
  *out = e;
  return true;
}

/* ---- match ---- */

/* `if c: a else: b` (also `else if`) as a match over the Bool `c`. */
MS_NODISCARD bool parse_if_expression(Parser *p, MsToken t, MsExpr **out) {
  MsExpr *cond = NULL;
  if (!parse_expression(p, 0, &cond))
    return false;
  if (!parse_need(p, MS_T_Colon))
    return false;
  if (parse_kind(p) == MS_T_Newline) {
    parse_fail(p, parse_peek(p),
               ms_span_of_text("an if expression writes its branches on one line, 'if c: a else: b'; to run "
                               "statements, use an if statement that assigns a 'var' or returns"));
    return false;
  }
  MsExpr *then = NULL;
  if (!parse_expression(p, 0, &then))
    return false;
  if (parse_kind(p) != MS_T_Else) {
    parse_fail(p, parse_peek(p),
               ms_span_of_text("an if expression needs an else branch; write 'if c: a else: b', or use an if "
                               "statement when no value is needed"));
    return false;
  }
  MsToken else_token = parse_peek(p);
  p->at++;
  MsExpr *els = NULL;
  if (parse_kind(p) == MS_T_If) {
    MsToken nested = parse_peek(p);
    p->at++;
    if (!parse_if_expression(p, nested, &els))
      return false;
  } else {
    if (!parse_need(p, MS_T_Colon))
      return false;
    if (!parse_expression(p, 0, &els))
      return false;
  }
  MsArm **arms = MS_ARENA_NEW_ARRAY(p->arena, MsArm *, 2);
  for (int k = 0; k < 2; k++) {
    MsPos pos = k == 0 ? t.pos : else_token.pos;
    MsExpr *path = parse_mk(p, pos, MS_E_BOOL);
    path->u.flag = k == 0;
    MsArm *a = MS_ARENA_NEW(p->arena, MsArm);
    a->id = parse_new_id(p);
    a->pos = pos;
    a->path = path;
    a->value = k == 0 ? then : els;
    a->from_if = true;
    arms[k] = a;
  }
  MsExpr *m = parse_mk(p, t.pos, MS_E_MATCH);
  m->u.match.scrutinee = cond;
  m->u.match.arms.ptr = arms;
  m->u.match.arms.len = 2;
  *out = m;
  return true;
}

/* An arm's final expression supplies its value; a statement-only arm yields Void. */
MS_NODISCARD static bool value_arm_inner(Parser *p, MsArm *a) {
  p->inline_return = false;
  if (!parse_need(p, MS_T_Colon))
    return false;
  bool indented = parse_take(p, MS_T_Newline);
  if (indented) {
    if (!parse_need(p, MS_T_Indent))
      return false;
  }
  p->inline_statement = !indented;
  size_t m = parse_mark(p);
  for (;;) {
    if (!parse_statements(p, true))
      return false;
    if (!indented) {
      break;
    }
    parse_newlines(p);
    if (parse_kind(p) == MS_T_Dedent || parse_kind(p) == MS_T_Eof) {
      break;
    }
  }
  a->body.ptr = parse_finish(p, m, &a->body.len, sizeof(void *), _Alignof(void *));
  if (a->body.len != 0 && a->body.ptr[a->body.len - 1]->kind == MS_S_CALL) {
    a->value = a->body.ptr[a->body.len - 1]->u.expr;
    a->body.len--;
  }
  for (uint32_t k = 0; k < a->body.len; k++) {
    MsStmt *s = a->body.ptr[k];
    if (s->kind == MS_S_CALL) {
      MsExpr *e = s->u.expr;
      bool is_try = e->kind == MS_E_UNARY && e->op == MS_U_TRY;
      if (e->kind != MS_E_CALL && e->kind != MS_E_MATCH && !is_try) {
        parse_diag(p, s->pos, ms_span_of_text("an arm value must be its final expression"));
        return false;
      }
    }
  }
  if (indented) {
    if (!parse_need(p, MS_T_Dedent))
      return false;
  } else {
    p->inline_statement = false;
    if (!parse_end(p))
      return false;
  }
  return true;
}

MS_NODISCARD static bool value_arm(Parser *p, MsArm *a) {
  bool outer = p->inline_statement, outer_return = p->inline_return;
  if (!value_arm_inner(p, a))
    return false;
  p->inline_statement = outer;
  p->inline_return = outer_return;
  return true;
}

static bool is_lower_start(MsSpan s) {
  return s.len > 0 && ((s.ptr[0] >= 'a' && s.ptr[0] <= 'z') || s.ptr[0] == '_');
}

/* The names in `(a, b)` after a variant path, pushed as arm bindings. The `(` is consumed. */
MS_NODISCARD static bool payload_bindings(Parser *p) {
  for (;;) {
    MsToken tok = parse_peek(p);
    if (!parse_take(p, MS_T_Underscore)) {
      if (!parse_need(p, MS_T_Name))
        return false;
    }
    MsArmBinding b = {parse_sym(p, tok), tok.pos};
    parse_push(p, &b, sizeof b);
    if (parse_kind(p) == MS_T_LParen) {
      parse_fail(p, parse_peek(p),
                 ms_span_of_text("patterns cannot be nested; bind the outer payload, then handle it in a "
                                 "separate match or helper function"));
      return false;
    }
    if (!parse_take(p, MS_T_Comma) || parse_kind(p) == MS_T_RParen) {
      break;
    }
  }
  return parse_need(p, MS_T_RParen);
}

/* A variant path, optionally with payload names. A lone lowercase name binds an Optional payload;
 * the checker tells that from a lowercase variant using the scrutinee's type. */
MS_NODISCARD static bool variant_pattern(Parser *p, MsToken start, MsExpr **path, bool *bare) {
  MsExpr *written = NULL;
  if (!case_path(p, &written))
    return false;
  if (written->kind == MS_E_NAME && ms_span_is_text(ms_names_span(p->names, written->u.sym), "some") &&
      parse_kind(p) == MS_T_LParen && p->speculative == 0) {
    parse_fail(p, parse_peek(p),
               ms_span_of_text(
                   "there is no some pattern; write the payload name alone, e.g. 'value:' beside 'none:'"));
    return false;
  }
  if (written->kind == MS_E_NAME && parse_kind(p) != MS_T_LParen) {
    MsSpan n = ms_names_span(p->names, written->u.sym);
    if (!ms_span_is_text(n, "none") && is_lower_start(n)) {
      MsArmBinding single = {written->u.sym, start.pos};
      parse_push(p, &single, sizeof single);
      *bare = true;
    }
  }
  *path = written;
  if (parse_take(p, MS_T_LParen)) {
    return payload_bindings(p);
  }
  return true;
}

static bool starts_literal_pattern(const Parser *p) {
  MsTok k = parse_kind(p);
  return k == MS_T_Number || k == MS_T_True || k == MS_T_False || k == MS_T_String ||
         (k == MS_T_Minus && parse_ahead(p, 1).kind == MS_T_Number);
}

/* One `pattern: body` arm. */
MS_NODISCARD static bool match_arm(Parser *p, MsArm **out) {
  MsToken start = parse_peek(p);
  size_t bindings_start = parse_mark(p);
  bool bare = false;
  MsExpr *path = NULL;
  if (starts_literal_pattern(p)) {
    if (!parse_expression(p, 0, &path))
      return false;
  } else if (parse_take(p, MS_T_Underscore)) {
    path = parse_mk_name(p, start.pos, parse_intern(p, "_"));
  } else if (!variant_pattern(p, start, &path, &bare)) {
    return false;
  }
  MsArm *a = MS_ARENA_NEW(p->arena, MsArm);
  a->bindings.ptr =
      parse_finish(p, bindings_start, &a->bindings.len, sizeof(MsArmBinding), _Alignof(MsArmBinding));
  a->id = parse_new_id(p);
  a->pos = start.pos;
  a->path = path;
  a->bare = bare;
  if (!value_arm(p, a))
    return false;
  *out = a;
  return true;
}

MS_NODISCARD bool parse_match_arms(Parser *p, MsToken header, MsExpr *m) {
  if (!parse_need(p, MS_T_Colon))
    return false;
  if (!parse_need(p, MS_T_Newline))
    return false;
  if (!parse_need(p, MS_T_Indent))
    return false;
  size_t arms_start = parse_mark(p);
  uint32_t narms = 0;
  for (;;) {
    parse_newlines(p);
    if (parse_kind(p) == MS_T_Dedent) {
      if (narms == 0) {
        parse_fail(p, header,
                   ms_span_of_text(
                       "match requires at least one arm; add a case pattern or '_' arm under the header"));
        return false;
      }
      break;
    }
    MsToken prefix;
    if (parse_legacy_case_prefix(p, &prefix)) {
      parse_fail_fix(p, prefix,
                     ms_span_of_text("match arms use bare variant names, e.g. Paid(receipt): or Missing:; "
                                     "remove the legacy 'case' prefix"),
                     ms_span_of_text(""));
      return false;
    }
    MsArm *arm = NULL;
    if (!match_arm(p, &arm))
      return false;
    parse_push_ptr(p, arm);
    narms++;
  }
  if (!parse_need(p, MS_T_Dedent))
    return false;
  uint32_t n = 0;
  MsArm **arms = parse_finish(p, arms_start, &n, sizeof(void *), _Alignof(void *));
  m->u.match.arms.ptr = arms;
  m->u.match.arms.len = n;
  return true;
}
