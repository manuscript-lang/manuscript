/* Owns type syntax: named, function and result types, type parameters and parameters. */
#include "compiler/syntax/parse_internal.h"

/* ---- types ---- */

MS_NODISCARD bool parse_named_type(Parser *p, MsTypeRef **out) {
  MsToken name = {0};
  if (!parse_need_token(p, MS_T_Name, &name))
    return false;
  MsName full = parse_sym(p, name);
  if (parse_kind(p) == MS_T_Dot) {
    size_t bm = p->bytes->len;
    MsSpan first = ms_names_span(p->names, full);
    parse_bytes_append(p, first);
    while (parse_take(p, MS_T_Dot)) {
      parse_bytes_byte(p, '.');
      MsToken part = {0};
      if (!parse_need_token(p, MS_T_Name, &part))
        return false;
      MsSpan t = parse_text(p, part);
      parse_bytes_append(p, t);
    }
    full = ms_names_intern(p->names, parse_bytes_since(p, bm));
    p->bytes->len = bm;
  }
  MsTypeRefs args = {NULL, 0};
  MsSpan full_s = ms_names_span(p->names, full);
  if (parse_kind(p) == MS_T_LBracket && p->speculative == 0 && ms_span_is_text(full_s, "Callable")) {
    parse_fail(p, parse_peek(p),
               parse_fmt(p,
                         "there is no %S[...] type; a function type is written fn(Int) Int: parameter types "
                         "in parentheses, then the result type",
                         full_s));
    return false;
  }
  if (parse_kind(p) == MS_T_LBracket && p->speculative == 0 && ms_span_is_text(full_s, "Optional")) {
    parse_fail(
        p, parse_peek(p),
        ms_span_of_text("there is no Optional[T] spelling; write T? instead, e.g. Int? or (fn(Int) Int)?"));
    return false;
  }
  if (parse_take(p, MS_T_LBracket)) {
    if (p->speculative > 0 && !parse_type_bracket(p, p->at - 1)) {
      return false;
    }
    if (!parse_type_args(p, &args))
      return false;
  }
  MsToken lt = parse_peek(p);
  if (lt.kind == MS_T_Lt && p->speculative == 0 && lt.pos.offset == parse_previous(p).end.offset &&
      args.len == 0) {
    parse_fail(
        p, lt,
        parse_fmt(p, "type arguments use square brackets, not angle brackets; write %S[T] instead of %S<T>",
                  full_s, full_s));
    return false;
  }
  *out = parse_mk_named_type(p, name.pos, full, args);
  return true;
}

MS_NODISCARD bool parse_type_args(Parser *p, MsTypeRefs *out) {
  size_t m = parse_mark(p);
  for (;;) {
    if (!parse_push_typ(p))
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
  MsTypeRefs r;
  r.ptr = parse_finish(p, m, &r.len, sizeof(void *), _Alignof(void *));
  *out = r;
  return true;
}

/* The type that follows a parameter list, rejecting the removed `->` and a missing type. */
MS_NODISCARD bool parse_result_type(Parser *p, MsTypeRef **out) {
  MsToken t = parse_peek(p);
  if (t.kind == MS_T_Arrow) {
    parse_fail_fix(
        p, t,
        ms_span_of_text(
            "result types follow the parameter list without an arrow; remove '->', e.g. fn f() Void:"),
        ms_span_of_text(""));
    return false;
  }
  if (t.kind == MS_T_LBrace) {
    parse_fail(p, t,
               ms_span_of_text("blocks are not braced and every fn declares its result type: write the "
                               "result type, then ':' and an indented body, e.g. fn f() Void: (Void when it "
                               "returns nothing), and remove the closing '}'"));
    return false;
  }
  if (t.kind == MS_T_Colon || t.kind == MS_T_Newline) {
    if (p->speculative > 0) {
      return false;
    }
    parse_fail(
        p, t,
        ms_span_of_text("every fn declares its result type after the parameter list, e.g. fn f() Void:"));
    return false;
  }
  return parse_typ(p, out);
}

/* Wraps `t` once per trailing suffix: `T?` is Optional[T], `T!` is Result[T, Error], and `T!E`
 * (E directly after the bang) is Result[T, E]. */
MS_NODISCARD static bool type_suffix(Parser *p, MsTypeRef *t, MsTypeRef **out) {
  for (;;) {
    MsPos pos = t->pos;
    const char *name;
    MsTypeRef *argv[2];
    uint32_t nargs;
    if (parse_take(p, MS_T_Question)) {
      name = "Optional";
      argv[0] = t;
      nargs = 1;
    } else if (parse_take(p, MS_T_Bang)) {
      MsToken bang = parse_previous(p);
      MsToken nx = parse_peek(p);
      MsTypeRef *error;
      if (nx.kind == MS_T_Name && nx.lo == bang.hi) {
        if (!parse_named_type(p, &error))
          return false;
      } else {
        MsTypeRefs none = {NULL, 0};
        error = parse_mk_named_type(p, pos, parse_intern(p, "Error"), none);
      }
      name = "Result";
      argv[0] = t;
      argv[1] = error;
      nargs = 2;
    } else {
      *out = t;
      return true;
    }
    MsTypeRefs args;
    args.ptr = MS_ARENA_NEW_ARRAY(p->arena, MsTypeRef *, nargs);
    args.len = nargs;
    __builtin_memcpy(args.ptr, argv, nargs * sizeof(MsTypeRef *));
    t = parse_mk_named_type(p, pos, parse_intern(p, name), args);
  }
}

/* Takes a contextual `move` marker: the word `move` followed by a token of one of the `next`
 * kinds, so a name `move` still reads as a name. */
bool parse_take_move(Parser *p, const MsTok *nexts, size_t n) {
  MsToken t = parse_peek(p);
  if (t.kind == MS_T_Name && parse_text_is(p, t, "move")) {
    MsTok k = (MsTok)parse_ahead(p, 1).kind;
    for (size_t i = 0; i < n; i++) {
      if (nexts[i] == k) {
        p->at++;
        return true;
      }
    }
  }
  return false;
}

/* `fn(T, var U) R`, after `first`, the `fn` token. */
MS_NODISCARD static bool fn_type(Parser *p, MsToken first, MsTypeRef **out) {
  MsParams params = {NULL, 0};
  p->at++;
  if (!parse_need(p, MS_T_LParen))
    return false;
  if (!parse_take(p, MS_T_RParen)) {
    size_t m = parse_mark(p);
    uint32_t count = 0;
    for (;;) {
      /* `fn(var List[Int]) Void`: a parameter the function changes in place. */
      bool moving = parse_take_move(p, (const MsTok[]){MS_T_Var, MS_T_Name, MS_T_Fn}, 3);
      bool is_mutable = parse_take(p, MS_T_Var);
      if (moving && is_mutable) {
        parse_fail(p, parse_previous(p),
                   ms_span_of_text("a parameter is either `move` (the callee takes it) or `var` (the "
                                   "callee changes it in place), not both"));
        return false;
      }
      MsTypeRef *ty = NULL;
      if (!parse_typ(p, &ty))
        return false;
      parse_push_ptr(
          p, parse_mk_param(p, ty->pos, parse_numbered_name(p, "_", count), ty, NULL, is_mutable, moving));
      count++;
      if (!parse_take(p, MS_T_Comma)) {
        break;
      }
      if (parse_kind(p) == MS_T_RParen) {
        break;
      }
    }
    if (!parse_need(p, MS_T_RParen))
      return false;
    params.ptr = parse_finish(p, m, &params.len, sizeof(void *), _Alignof(void *));
  }
  MsTypeRef *result = NULL;
  if (!parse_typ(p, &result))
    return false;
  MsTypeRef *t = MS_ARENA_NEW(p->arena, MsTypeRef);
  t->id = parse_new_id(p);
  t->pos = first.pos;
  t->kind = MS_TYPE_FN;
  t->params = params;
  t->result = result;
  *out = t;
  return true;
}

MS_NODISCARD static bool typ_inner(Parser *p, MsTypeRef **out) {
  MsToken first = parse_peek(p);
  if (first.kind == MS_T_Fn) {
    return fn_type(p, first, out);
  }
  MsTypeRef *t;
  if (parse_take(p, MS_T_LParen)) {
    if (!parse_typ(p, &t))
      return false;
    if (parse_kind(p) == MS_T_Comma && p->speculative == 0) {
      parse_fail(
          p, parse_peek(p),
          ms_span_of_text("Manuscript has no tuples; declare a type with 'type Pair:' and named fields to "
                          "return several values, or use a List when the items share one type"));
      return false;
    }
    if (!parse_need(p, MS_T_RParen))
      return false;
  } else {
    if (!parse_named_type(p, &t))
      return false;
  }
  return type_suffix(p, t, out);
}

MS_NODISCARD bool parse_typ(Parser *p, MsTypeRef **out) {
  if (!parse_enter(p))
    return false;
  MsTypeRef *r = NULL;
  if (!typ_inner(p, &r))
    return false;
  p->depth--;
  *out = r;
  return true;
}

/* The default of a `T?` parameter or field written without one: `none`. */
MsExpr *parse_implicit_none(Parser *p, const MsTypeRef *t) {
  if (t->kind != MS_TYPE_NAMED) {
    return NULL;
  }
  if (ms_span_is_text(ms_names_span(p->names, t->name), "Optional") && t->args.len == 1) {
    return parse_mk_name(p, t->pos, parse_intern(p, "none"));
  }
  return NULL;
}

MS_NODISCARD bool parse_type_params(Parser *p, MsTypeParams *out) {
  MsTypeParams result = {NULL, 0};
  if (!parse_take(p, MS_T_LBracket)) {
    *out = result;
    return true;
  }
  size_t m = parse_mark(p);
  for (;;) {
    MsToken name = {0};
    if (!parse_need_token(p, MS_T_Name, &name))
      return false;
    MsTypeRefs bounds = {NULL, 0};
    MsTypeRef *def = NULL;
    if (parse_take(p, MS_T_Colon)) {
      size_t bm = parse_mark(p);
      if (!parse_push_named_type(p))
        return false;
      while (parse_take(p, MS_T_Amp)) {
        if (!parse_push_named_type(p))
          return false;
      }
      bounds.ptr = parse_finish(p, bm, &bounds.len, sizeof(void *), _Alignof(void *));
      if (parse_kind(p) == MS_T_Plus || parse_kind(p) == MS_T_And) {
        parse_fail_fix(p, parse_peek(p),
                       ms_span_of_text("combine bounds with '&', as in T: Comparable & Clonable"),
                       ms_span_of_text("&"));
        return false;
      }
    }
    if (parse_take(p, MS_T_Assign)) {
      if (!parse_typ(p, &def))
        return false;
    }
    MsTypeParam *tp = MS_ARENA_NEW(p->arena, MsTypeParam);
    tp->id = parse_new_id(p);
    tp->pos = name.pos;
    tp->name = parse_sym(p, name);
    tp->bounds = bounds;
    tp->def = def;
    parse_push_ptr(p, tp);
    if (!parse_take(p, MS_T_Comma)) {
      break;
    }
    if (parse_kind(p) == MS_T_RBracket) {
      break;
    }
  }
  if (!parse_need(p, MS_T_RBracket))
    return false;
  result.ptr = parse_finish(p, m, &result.len, sizeof(void *), _Alignof(void *));
  *out = result;
  return true;
}

/* The colon after a parameter or field name; a missing one is usually a type written directly
 * after the name. */
MS_NODISCARD bool parse_need_name_colon(Parser *p, MsToken name) {
  MsToken t = parse_peek(p);
  if (t.kind == MS_T_Name && p->speculative == 0) {
    MsToken at = name;
    at.pos = name.end;
    at.end = name.end;
    MsSpan n = parse_text(p, name);
    parse_fail_fix(
        p, at,
        parse_fmt(p, "expected ':' between '%S' and its type; parameters and fields are written name: Type",
                  n),
        ms_span_of_text(":"));
    return false;
  }
  if ((t.kind == MS_T_Comma || t.kind == MS_T_RParen) && p->speculative == 0) {
    MsSpan n = parse_text(p, name);
    parse_fail(p, name,
               parse_fmt(p, "parameter '%S' has no type; every parameter is written name: Type, e.g. %S: Int",
                         n, n));
    return false;
  }
  if (!parse_need(p, MS_T_Colon))
    return false;
  return true;
}

/* One parameter: `[move|var] name[: Type][= default]`; it is pushed onto the open scratch list. */
MS_NODISCARD static bool parameter(Parser *p, bool defaults, bool inferred) {
  bool moving = parse_take_move(p, (const MsTok[]){MS_T_Var, MS_T_Name}, 2);
  bool is_mutable = parse_take(p, MS_T_Var);
  if (moving && is_mutable) {
    parse_fail(p, parse_previous(p),
               ms_span_of_text("a parameter is either `move` (the callee takes it) or `var` (the callee "
                               "changes it in place), not both"));
    return false;
  }
  MsToken name = {0};
  if (!parse_need_token(p, MS_T_Name, &name))
    return false;
  MsTypeRef *ty = NULL;
  MsExpr *def = NULL;
  if (parse_take(p, MS_T_Colon)) {
    if (parse_kind(p) == MS_T_Var) {
      MsToken t = parse_peek(p);
      MsSpan n = parse_text(p, name);
      MsSpan rep = parse_fmt(p, "var %S:", n);
      parse_fail_fix_range(
          p, name, t,
          parse_fmt(p, "'var' goes before the parameter name, not its type; write var %S: Type", n), rep);
      return false;
    }
    if (!parse_typ(p, &ty))
      return false;
  } else if (!inferred || parse_kind(p) == MS_T_Name) {
    if (!parse_need_name_colon(p, name))
      return false;
  }
  if (parse_take(p, MS_T_Assign)) {
    if (!defaults) {
      parse_fail(p, parse_previous(p),
                 ms_span_of_text("function types and case payloads cannot have defaults; put the default "
                                 "on a named function parameter or a type field instead"));
      return false;
    }
    if (!parse_expression(p, 0, &def))
      return false;
  } else if (defaults && ty != NULL) {
    def = parse_implicit_none(p, ty);
  }
  parse_push_ptr(p, parse_mk_param(p, name.pos, parse_sym(p, name), ty, def, is_mutable, moving));
  return true;
}

MS_NODISCARD bool parse_parameters(Parser *p, bool defaults, bool inferred, MsParams *out) {
  if (!parse_need(p, MS_T_LParen))
    return false;
  MsParams params = {NULL, 0};
  if (parse_take(p, MS_T_RParen)) {
    *out = params;
    return true;
  }
  size_t m = parse_mark(p);
  for (;;) {
    if (!parameter(p, defaults, inferred))
      return false;
    if (!parse_take(p, MS_T_Comma)) {
      break;
    }
    if (parse_kind(p) == MS_T_RParen) {
      break;
    }
  }
  if (!parse_need(p, MS_T_RParen))
    return false;
  params.ptr = parse_finish(p, m, &params.len, sizeof(void *), _Alignof(void *));
  *out = params;
  return true;
}
