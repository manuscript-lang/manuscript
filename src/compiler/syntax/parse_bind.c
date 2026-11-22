/* Owns patterns, bindings and assignment targets, including index stores and compound assignment. */
#include "compiler/syntax/parse_internal.h"

/* ---- patterns ---- */

static MsPattern *new_pattern(Parser *p, MsPos pos, MsPatternKind k) {
  MsPattern *pt = MS_ARENA_NEW(p->arena, MsPattern);
  pt->id = parse_new_id(p);
  pt->pos = pos;
  pt->kind = (uint8_t)k;
  return pt;
}

/* `[a, b]`: the list pattern after its opening bracket was seen at `t`. */
MS_NODISCARD static bool pattern_list(Parser *p, MsToken t, MsPattern **out) {
  MsPatterns elements = {NULL, 0};
  if (!parse_take(p, MS_T_RBracket)) {
    size_t m = parse_mark(p);
    for (;;) {
      if (!parse_push_pattern(p))
        return false;
      if (!parse_take(p, MS_T_Comma)) {
        break;
      }
      if (parse_kind(p) == MS_T_RBracket) {
        break;
      }
    }
    if (!parse_need(p, MS_T_RBracket))
      return false;
    elements.ptr = parse_finish(p, m, &elements.len, sizeof(void *), _Alignof(void *));
  }
  MsPattern *pt = new_pattern(p, t.pos, MS_P_LIST);
  pt->u.list = elements;
  *out = pt;
  return true;
}

/* `{x, y: pattern}`: the type pattern after its opening brace was seen at `t`. */
MS_NODISCARD static bool pattern_fields(Parser *p, MsToken t, MsPattern **out) {
  size_t m = parse_mark(p);
  for (;;) {
    MsToken name = {0};
    if (!parse_need_token(p, MS_T_Name, &name))
      return false;
    MsPattern *child;
    if (parse_take(p, MS_T_Colon)) {
      if (!parse_pattern(p, &child))
        return false;
    } else {
      child = new_pattern(p, name.pos, MS_P_NAME);
      child->u.name = parse_sym(p, name);
    }
    MsPatternField f = {name.pos, parse_sym(p, name), child};
    parse_push(p, &f, sizeof f);
    if (!parse_take(p, MS_T_Comma)) {
      break;
    }
    if (parse_kind(p) == MS_T_RBrace) {
      break;
    }
  }
  if (!parse_need(p, MS_T_RBrace))
    return false;
  MsPattern *pt = NULL;
  uint32_t n;
  MsPatternField *fields = parse_finish(p, m, &n, sizeof(MsPatternField), _Alignof(MsPatternField));
  pt = new_pattern(p, t.pos, MS_P_TYPE);
  pt->u.fields.ptr = fields;
  pt->u.fields.len = n;
  *out = pt;
  return true;
}

MS_NODISCARD static bool pattern_inner(Parser *p, MsPattern **out) {
  MsToken t = parse_peek(p);
  if (t.kind == MS_T_Void) {
    parse_fail(p, t,
               ms_span_of_text("void is a reserved value keyword, not a binding name; choose another name "
                               "such as code_unit, and use void for the Void value"));
    return false;
  }
  if (parse_take(p, MS_T_Name)) {
    MsPattern *pt = new_pattern(p, t.pos, MS_P_NAME);
    pt->u.name = parse_sym(p, t);
    *out = pt;
    return true;
  }
  /* `_` binds a value nothing reads, such as a `Result` ignored on purpose. */
  if (parse_take(p, MS_T_Underscore)) {
    MsPattern *pt = new_pattern(p, t.pos, MS_P_NAME);
    pt->u.name = parse_intern(p, "_");
    *out = pt;
    return true;
  }
  if (parse_take(p, MS_T_LBracket)) {
    return pattern_list(p, t, out);
  }
  if (parse_take(p, MS_T_LBrace)) {
    return pattern_fields(p, t, out);
  }
  MsSpan dt = parse_describe(p, t);
  parse_fail(
      p, t,
      parse_fmt(
          p,
          "expected a binding name, list pattern, or type pattern, found %S; write a name, [a, b], or {x, y}",
          dt));
  return false;
}

MS_NODISCARD bool parse_pattern(Parser *p, MsPattern **out) {
  if (!parse_enter(p))
    return false;
  MsPattern *r = NULL;
  if (!pattern_inner(p, &r))
    return false;
  p->depth--;
  *out = r;
  return true;
}

/* ---- statements ---- */

MsStmt *parse_finish_stmt(Parser *p, const MsStmt *st) {
  MsStmt *s = MS_ARENA_NEW(p->arena, MsStmt);
  *s = *st;
  s->id = parse_new_id(p);
  return s;
}

/* `pattern := hidden`: the first statement of a `for` body or lambda whose parameter is a pattern. */
MsStmt *parse_destructure(Parser *p, MsPattern *pat, MsName hidden) {
  MsPos pos = pat->pos;
  MsExpr *value = parse_mk_name(p, pos, hidden);
  MsStmt *s = MS_ARENA_NEW(p->arena, MsStmt);
  s->id = parse_new_id(p);
  s->pos = pos;
  s->kind = MS_S_BIND;
  s->u.bind.pattern = pat;
  s->u.bind.value = value;
  return s;
}

bool parse_binding_ahead(const Parser *p) {
  switch (parse_kind(p)) {
  case MS_T_Name:
  case MS_T_Underscore:
    return parse_ahead(p, 1).kind == MS_T_ColonAssign || parse_ahead(p, 1).kind == MS_T_Colon;
  case MS_T_LBracket:
  case MS_T_LBrace: {
    size_t depth = 0;
    for (size_t i = p->at; i < p->ntokens; i++) {
      switch (p->tokens[i].kind) {
      case MS_T_LParen:
      case MS_T_LBracket:
      case MS_T_LBrace:
        depth++;
        break;
      case MS_T_RParen:
      case MS_T_RBracket:
      case MS_T_RBrace:
        depth--;
        if (depth == 0) {
          return i + 1 < p->ntokens && p->tokens[i + 1].kind == MS_T_ColonAssign;
        }
        break;
      case MS_T_Newline:
      case MS_T_Eof:
        return false;
      default:
        break;
      }
    }
    return false;
  }
  default:
    return false;
  }
}

/* A binding: `var pattern [: Type] = value` after `var`, or an immutable `name := value`,
 * `name: Type := value`, or `pattern := value`. */
MS_NODISCARD bool parse_binding(Parser *p, bool is_mutable, const MsPos *group, MsPos pos, MsStmt **out) {
  MsPattern *pat = NULL;
  if (!parse_pattern(p, &pat))
    return false;
  MsTypeRef *ty = NULL;
  bool named = pat->kind == MS_P_NAME;
  if (is_mutable) {
    if (named && parse_take(p, MS_T_Colon)) {
      if (!parse_typ(p, &ty))
        return false;
    }
    if (parse_kind(p) == MS_T_ColonAssign) {
      parse_fail_fix(
          p, parse_peek(p),
          ms_span_of_text("'var' binds with '=': write 'var x = value'; ':=' declares an immutable binding"),
          ms_span_of_text("="));
      return false;
    }
    if (!parse_need(p, MS_T_Assign))
      return false;
  } else {
    if (named && parse_take(p, MS_T_Colon)) {
      if (!parse_typ(p, &ty))
        return false;
    }
    if (!parse_need_immutable_bind(p))
      return false;
  }
  MsExpr *value = NULL;
  if (!parse_expression(p, 0, &value))
    return false;
  MsStmt st = {0};
  st.pos = pos;
  st.kind = MS_S_BIND;
  st.u.bind.is_mutable = is_mutable;
  st.u.bind.pattern = pat;
  st.u.bind.ty = ty;
  st.u.bind.value = value;
  if (group != NULL) {
    st.u.bind.has_group = true;
    st.u.bind.group = *group;
  }
  *out = parse_finish_stmt(p, &st);
  return true;
}

/* The column of the line `keyword` starts, which the group's `)` aligns with. */
static uint32_t group_indent(const Parser *p, MsToken keyword) {
  uint32_t indent = keyword.pos.column;
  long i = (long)p->at - 2;
  while (i >= 0 && p->tokens[i].pos.line == keyword.pos.line && p->tokens[i].kind != MS_T_Newline) {
    indent = p->tokens[i].pos.column;
    i--;
  }
  return indent;
}

/* The `(` and the line end after it. */
MS_NODISCARD static bool group_open(Parser *p, const char *kw) {
  if (p->inline_statement) {
    parse_fail(p, parse_peek(p),
               parse_fmt(p,
                         "a binding group needs its own lines; put '%s (' on a line of its own with one "
                         "binding per indented line, or write single '%s name = value' bindings",
                         kw, kw));
    return false;
  }
  if (!parse_need(p, MS_T_LParen))
    return false;
  if (parse_kind(p) != MS_T_Newline) {
    parse_fail(
        p, parse_peek(p),
        parse_fmt(p,
                  "a binding group starts its entries on the next line; write '%s (' then one 'name = value' "
                  "per indented line, or destructure with '%s [a, b] = value' or '%s {x, y} = value'",
                  kw, kw, kw));
    return false;
  }
  parse_next(p);
  return true;
}

/* One entry line of the group, at `indent` + 4. */
MS_NODISCARD static bool group_entry(Parser *p, MsToken keyword, const char *kw, uint32_t indent) {
  MsToken t = parse_peek(p);
  if (t.kind == MS_T_Eof) {
    if (!parse_need(p, MS_T_RParen))
      return false;
  } else if (t.pos.column != indent + 4) {
    parse_fail(p, t,
               parse_fmt(p, "binding group entries are indented four spaces past the '%s' line, to column %u",
                         kw, indent + 4));
    return false;
  }
  if (!parse_push_binding(p, true, &keyword.pos, parse_peek(p).pos))
    return false;
  if (parse_kind(p) == MS_T_Comma) {
    parse_fail(p, parse_peek(p),
               parse_fmt(p,
                         "a binding group holds one 'name = value' per line, not a comma list; to "
                         "destructure write '%s [a, b] = value' or '%s {x, y} = value'",
                         kw, kw));
    return false;
  }
  /* A block lambda value ends at its dedent, which also ends the line. */
  return parse_previous(p).kind == MS_T_Dedent || parse_need(p, MS_T_Newline);
}

/* The `( ... )` after a consumed `var`. The lexer ends each line of the group with a newline. */
MS_NODISCARD bool parse_binding_group(Parser *p, MsToken keyword, MsStmts *out) {
  const uint32_t indent = group_indent(p, keyword);
  const char *kw = ms_tok_str((MsTok)keyword.kind);
  if (!group_open(p, kw))
    return false;
  size_t m = parse_mark(p);
  uint32_t count = 0;
  for (;;) {
    parse_newlines(p);
    MsToken t = parse_peek(p);
    if (t.kind == MS_T_RParen) {
      if (t.pos.column != indent) {
        parse_fail(p, t,
                   parse_fmt(p, "the closing ')' of a binding group aligns with its '%s' line, at column %u",
                             kw, indent));
        return false;
      }
      break;
    }
    if (!group_entry(p, keyword, kw, indent))
      return false;
    count++;
  }
  if (count == 0) {
    parse_fail(
        p, parse_peek(p),
        ms_span_of_text("a binding group cannot be empty; add 'name = value' lines or remove the group"));
    return false;
  }
  if (!parse_need(p, MS_T_RParen) || !parse_end(p))
    return false;
  MsStmts result;
  result.ptr = parse_finish(p, m, &result.len, sizeof(void *), _Alignof(void *));
  *out = result;
  return true;
}

/* Parses one statement, plus the rest of its bindings for a group, onto the open scratch list. */
MS_NODISCARD bool parse_statements(Parser *p, bool allow_value) {
  MsStmt *s = NULL;
  if (!parse_statement(p, allow_value, &s))
    return false;
  parse_push_ptr(p, s);
  for (uint32_t i = 0; i < p->nqueued; i++) {
    parse_push_ptr(p, p->queued[i]);
  }
  p->queued = NULL;
  p->nqueued = 0;
  return true;
}

static bool plain_index(const MsExpr *e) {
  switch (e->kind) {
  case MS_E_NAME:
  case MS_E_NUMBER:
    return true;
  case MS_E_MEMBER:
    return plain_index(e->u.member.left);
  case MS_E_TEXT:
    for (uint32_t i = 0; i < e->u.text.len; i++) {
      if (e->u.text.ptr[i].expr != NULL) {
        return false;
      }
    }
    return true;
  default:
    return false;
  }
}

static bool plain_chain(const MsExpr *e) {
  for (;;) {
    if (e->kind == MS_E_MEMBER) {
      e = e->u.member.left;
    } else if (e->kind == MS_E_INDEX && plain_index(e->u.bin.right)) {
      e = e->u.bin.left;
    } else if (e->kind == MS_E_APPLY && e->u.apply.value != NULL && e->u.apply.types.len == 1 &&
               plain_index(e->u.apply.value)) {
      e = e->u.apply.left;
    } else {
      return e->kind == MS_E_NAME;
    }
  }
}

bool ms_plain_index_target(const MsExpr *left, const MsExpr *index) {
  return plain_chain(left) && plain_index(index);
}

static MsTypeRef *copy_type(Parser *p, const MsTypeRef *t);

MsTypeRefs parse_copy_types(Parser *p, MsTypeRefs types) {
  MsTypeRefs out = {NULL, types.len};
  out.ptr = MS_ARENA_NEW_ARRAY(p->arena, MsTypeRef *, types.len ? types.len : 1);
  for (uint32_t i = 0; i < types.len; i++) {
    out.ptr[i] = copy_type(p, types.ptr[i]);
  }
  return out;
}

static MsTypeRef *copy_type(Parser *p, const MsTypeRef *t) {
  MsTypeRef *c = MS_ARENA_NEW(p->arena, MsTypeRef);
  c->id = parse_new_id(p);
  c->pos = t->pos;
  c->kind = t->kind;
  if (t->kind == MS_TYPE_NAMED) {
    c->name = t->name;
    c->args = parse_copy_types(p, t->args);
  } else {
    c->params.len = t->params.len;
    c->params.ptr = MS_ARENA_NEW_ARRAY(p->arena, MsParam *, t->params.len ? t->params.len : 1);
    for (uint32_t i = 0; i < t->params.len; i++) {
      const MsParam *q = t->params.ptr[i];
      MsParam *m = MS_ARENA_NEW(p->arena, MsParam);
      m->id = parse_new_id(p);
      m->pos = q->pos;
      m->name = q->name;
      m->ty = q->ty != NULL ? copy_type(p, q->ty) : NULL;
      m->def = q->def; /* the Rust clone keeps the same ids too */
      m->is_mutable = q->is_mutable;
      m->moving = q->moving;
      c->params.ptr[i] = m;
    }
    c->result = copy_type(p, t->result);
    c->result_moves = t->result_moves;
  }
  return c;
}

MsExpr *parse_clone_chain(Parser *p, const MsExpr *e) {
  MsExpr *c = MS_ARENA_NEW(p->arena, MsExpr);
  c->id = parse_new_id(p);
  c->pos = e->pos;
  c->end = e->end;
  c->kind = e->kind;
  c->op = e->op;
  c->u = e->u;
  switch (e->kind) {
  case MS_E_MEMBER:
    c->u.member.left = parse_clone_chain(p, e->u.member.left);
    break;
  case MS_E_INDEX:
    c->u.bin.left = parse_clone_chain(p, e->u.bin.left);
    c->u.bin.right = parse_clone_chain(p, e->u.bin.right);
    break;
  case MS_E_APPLY:
    c->u.apply.left = parse_clone_chain(p, e->u.apply.left);
    c->u.apply.types = parse_copy_types(p, e->u.apply.types);
    c->u.apply.value = e->u.apply.value != NULL ? parse_clone_chain(p, e->u.apply.value) : NULL;
    break;
  default:
    break;
  }
  return c;
}

bool ms_is_index_store(const MsNames *names, const MsExpr *call) {
  const MsExpr *callee = call->u.call.callee;
  if (callee->kind != MS_E_MEMBER) {
    return false;
  }
  const MsSpan name = ms_names_span(names, callee->u.member.name);
  return ms_span_is_text(name, MS_INDEX_SET);
}

/* `xs[i] = value` (the receiver `left` and `index` of the target at `pos`) as the call of the member `[]=`.
 * With `reread`, the value reads the same element, so a name or field key is cloned for the store. */
MsExpr *parse_index_set(Parser *p, MsPos pos, MsExpr *left, MsExpr *index, MsExpr *value, bool reread) {
  if (reread && (index->kind == MS_E_NAME || index->kind == MS_E_MEMBER)) {
    MsExpr *receiver = parse_clone_chain(p, index);
    MsName name = parse_intern(p, "clone");
    MsExpr *callee = parse_mk_member(p, index->pos, receiver, name);
    MsExpr *c = MS_ARENA_NEW(p->arena, MsExpr);
    c->id = parse_new_id(p);
    c->pos = index->pos;
    c->end = index->end;
    c->kind = MS_E_CALL;
    c->u.call.callee = callee;
    index = c;
  }
  MsExpr *member = parse_mk_member(p, pos, left, parse_intern(p, MS_INDEX_SET));
  MsArg *args = MS_ARENA_NEW_ARRAY(p->arena, MsArg, 2);
  args[0] = (MsArg){index->pos, false, 0, index};
  args[1] = (MsArg){value->pos, false, 0, value};
  return parse_mk_call(p, pos, member, args, 2);
}

MS_NODISCARD bool parse_assign_target(Parser *p, MsToken start, MsExpr *e, MsStmt *st) {
  if (e->kind == MS_E_NAME) {
    MsSpan n = ms_names_span(p->names, e->u.sym);
    if (!ms_span_is_text(n, "self") && !ms_span_is_text(n, "fixture")) {
      st->u.assign.member_target = false;
      st->u.assign.name = e->u.sym;
      return true;
    }
  } else if (e->kind == MS_E_MEMBER) {
    st->u.assign.member_target = true;
    st->u.assign.target = e;
    return true;
  }
  parse_fail(p, start,
             ms_span_of_text("assignment requires a local binding name or type field; the left side of '=' "
                             "must be a name or a.field; to change a collection element, write xs[index] = "
                             "value on a List or m[key] = value on a Map"));
  return false;
}

bool parse_compound_assignment(const Parser *p) {
  MsBinaryOp op;
  if (parse_arith_op(parse_kind(p), &op) && p->at + 1 < p->ntokens) {
    MsToken nx = p->tokens[p->at + 1];
    return nx.kind == MS_T_Assign && parse_peek(p).end.offset == nx.pos.offset;
  }
  return false;
}

static MsExpr *mk_binary_at(Parser *p, MsToken op, MsBinaryOp bop, MsExpr *left, MsExpr *right) {
  MsExpr *e = MS_ARENA_NEW(p->arena, MsExpr);
  e->id = parse_new_id(p);
  e->pos = op.pos;
  e->end = right->end;
  e->kind = MS_E_BINARY;
  e->op = (uint8_t)bop;
  e->u.bin.left = left;
  e->u.bin.right = right;
  return e;
}

/* `target op= value` as the assignment `target = target op value`. */
MS_NODISCARD bool parse_compound(Parser *p, MsToken start, MsExpr *e, MsStmt *st) {
  MsToken op = parse_peek(p);
  MsToken equal = parse_ahead(p, 1);
  bool plain = plain_chain(e);
  MsExpr *copy = plain ? parse_clone_chain(p, e) : NULL;
  MsExpr *l = NULL, *ix = NULL;
  MsBinaryOp bop;
  if (copy != NULL && ms_expr_index(e, &l, &ix)) {
    p->at += 2;
    parse_arith_op((MsTok)op.kind, &bop);
    MsExpr *right = NULL;
    if (!parse_expression(p, 0, &right))
      return false;
    MsExpr *value = mk_binary_at(p, op, bop, copy, right);
    st->kind = MS_S_CALL;
    st->u.expr = parse_index_set(p, e->pos, l, ix, value, true);
    return true;
  }
  if (!parse_assign_target(p, start, e, st))
    return false;
  if (copy == NULL) {
    MsDiag *d =
        parse_diag(p, op.pos,
                   parse_fmt(p,
                             "compound assignment '%s=' needs a name or a.field target whose receiver is "
                             "names only; bind the receiver to a name first, or write the assignment out",
                             ms_tok_str((MsTok)op.kind)));
    d->has_end = true;
    d->end = equal.end;
    return false;
  }
  p->at += 2;
  parse_arith_op((MsTok)op.kind, &bop);
  MsExpr *right = NULL;
  if (!parse_expression(p, 0, &right))
    return false;
  MsExpr *value = mk_binary_at(p, op, bop, copy, right);
  st->kind = MS_S_ASSIGN;
  st->u.assign.has_compound = true;
  st->u.assign.compound = (uint8_t)bop;
  st->u.assign.value = value;
  return true;
}
