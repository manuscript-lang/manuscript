/* Owns top-level declarations: types, methods, functions, constants and tests. */
#include "compiler/syntax/parse_internal.h"

static const char IMPL_REMOVED[] =
    "'impl' was removed: declare each method beside its type as 'fn Type.name(...)' ('fn var Type.name(...)' "
    "when it changes self); a type satisfies an interface by having methods that match it, so nothing "
    "declares "
    "it";

MS_NODISCARD static bool type_declaration(Parser *p, MsToken token, MsDecl **out) {
  p->at++;
  MsToken name_tok = {0};
  if (!parse_need_token(p, MS_T_Name, &name_tok))
    return false;
  MsName name = parse_sym(p, name_tok);
  MsTypeParams tps = {0};
  if (!parse_type_params(p, &tps))
    return false;
  if (token.kind == MS_T_Type && parse_take(p, MS_T_Assign)) {
    return parse_alias_declaration(p, token, name, tps, out);
  }
  if (!parse_need(p, MS_T_Colon))
    return false;
  bool no_members = (token.kind == MS_T_Interface || token.kind == MS_T_Type) && parse_take(p, MS_T_Ellipsis);
  if (no_members) {
    return parse_empty_declaration(p, token, name, tps, out);
  }
  if (!parse_declaration_body_start(p, token))
    return false;
  /* Only one of fields, cases and methods is ever collected for a given declaration kind. */
  size_t m = parse_mark(p);
  while (parse_kind(p) != MS_T_Dedent) {
    parse_newlines(p);
    if (parse_kind(p) == MS_T_Dedent) {
      break;
    }
    if (!parse_declaration_member(p, token, name, tps))
      return false;
  }
  if (!parse_need(p, MS_T_Dedent))
    return false;
  uint32_t count = 0;
  void **items = parse_finish(p, m, &count, sizeof(void *), _Alignof(void *));
  return parse_finish_declaration(p, token, name, tps, items, count, out);
}

/* The type parameters that stand for the receiver's own arguments in `fn Type[T: Bound].m()`. */
MS_NODISCARD static bool receiver_arguments(Parser *p, MsTypeParams *bounds, MsTypeRefs *args) {
  bool bounded = parse_kind(p) == MS_T_LBracket && parse_ahead(p, 1).kind == MS_T_Name &&
                 parse_ahead(p, 2).kind == MS_T_Colon;
  if (!bounded) {
    return !parse_take(p, MS_T_LBracket) || parse_type_args(p, args);
  }
  if (!parse_type_params(p, bounds))
    return false;
  args->ptr = MS_ARENA_NEW_ARRAY(p->arena, MsTypeRef *, bounds->len ? bounds->len : 1);
  args->len = bounds->len;
  for (uint32_t i = 0; i < bounds->len; i++) {
    MsTypeRefs none = {NULL, 0};
    args->ptr[i] = parse_mk_named_type(p, bounds->ptr[i]->pos, bounds->ptr[i]->name, none);
  }
  return true;
}

/* `fn [var] Type[T].name(...)`: one method of `Type`. */
MS_NODISCARD static bool method_declaration(Parser *p, MsToken token, MsDecl **out) {
  p->at++;
  bool consuming = parse_take_move(p, (const MsTok[]){MS_T_Var, MS_T_Name}, 2);
  bool mutating = parse_take(p, MS_T_Var);
  if (consuming && mutating) {
    parse_fail(
        p, parse_previous(p),
        ms_span_of_text("a method either takes its receiver with `move` or changes it with `var`, not both"));
    return false;
  }
  MsToken receiver_name = {0};
  if (!parse_need_token(p, MS_T_Name, &receiver_name))
    return false;
  MsTypeParams bounds = {NULL, 0};
  MsTypeRefs args = {NULL, 0};
  if (!receiver_arguments(p, &bounds, &args))
    return false;
  MsTypeRef *receiver = parse_mk_named_type(p, receiver_name.pos, parse_sym(p, receiver_name), args);
  if (!parse_need(p, MS_T_Dot))
    return false;
  MsToken name = {0};
  if (!parse_need_token(p, MS_T_Name, &name))
    return false;
  MsMethod *method = NULL;
  if (!parse_method_signature(p, name, true, true, mutating, receiver_name.pos, &method))
    return false;
  method->consuming = consuming;
  method->receiver_args = args;
  /* The Rust parser allocates the declaration's id after the method's. */
  MsDecl *d = parse_new_decl(p, token.pos, MS_D_IMPL);
  d->u.impl.receiver = receiver;
  d->u.impl.bounds = bounds;
  d->u.impl.methods.ptr = MS_ARENA_NEW_ARRAY(p->arena, MsMethod *, 1);
  d->u.impl.methods.ptr[0] = method;
  d->u.impl.methods.len = 1;
  *out = d;
  return true;
}

MS_NODISCARD static bool fn_declaration(Parser *p, MsToken token, MsDecl **out) {
  p->at++;
  if (parse_kind(p) == MS_T_Var && parse_ahead(p, 1).kind == MS_T_Name) {
    parse_fail(p, parse_peek(p),
               ms_span_of_text("'fn var' marks a method that changes its receiver, as in 'fn var "
                               "Counter.add(n: Int) Void:'; a free function takes 'var' on the parameter "
                               "instead: 'fn add(var counter: Counter, n: Int) Void:'"));
    return false;
  }
  MsToken name = {0};
  if (!parse_need_token(p, MS_T_Name, &name))
    return false;
  MsTypeParams tps = {0};
  if (!parse_type_params(p, &tps))
    return false;
  MsParams params = {0};
  if (!parse_parameters(p, true, false, &params))
    return false;
  MsTypeRef *result = NULL;
  bool result_moves = false;
  if (!parse_result_type(p, &result, &result_moves))
    return false;
  MsStmts body = {0};
  p->ellipsis_body = false;
  if (!parse_statement_suite(p, false, true, &body))
    return false;
  const bool bodiless = p->ellipsis_body;
  MsDecl *d = parse_new_decl(p, token.pos, MS_D_FN);
  d->u.fn.name = parse_sym(p, name);
  d->u.fn.type_params = tps;
  d->u.fn.params = params;
  d->u.fn.result = result;
  d->u.fn.result_moves = result_moves;
  d->u.fn.body = body;
  d->u.fn.bodiless = bodiless;
  *out = d;
  return true;
}

/* `extern type Name[T]` is a runtime-backed type; a ':' body gives it the fields a constructor takes,
 * as a `type` does (`extern type List[T]:` with its `reserve` field). */
MS_NODISCARD static bool extern_type_declaration(Parser *p, MsToken token, MsDecl **out) {
  const size_t keyword = p->at + 1;
  p->at += 2;
  MsToken name_tok = {0};
  if (!parse_need_token(p, MS_T_Name, &name_tok))
    return false;
  MsName name = parse_sym(p, name_tok);
  MsTypeParams tps = {0};
  if (!parse_type_params(p, &tps))
    return false;
  if (parse_kind(p) == MS_T_Colon) {
    p->at = keyword;
    if (!type_declaration(p, parse_peek(p), out))
      return false;
    (*out)->pos = token.pos; /* the declaration starts at `extern`, where its comment sits above */
    (*out)->u.type.external = true;
    return true;
  }
  if (!parse_end(p))
    return false;
  MsDecl *d = parse_new_decl(p, token.pos, MS_D_TYPE);
  d->u.type.name = name;
  d->u.type.type_params = tps;
  d->u.type.external = true;
  *out = d;
  return true;
}

MS_NODISCARD static bool extern_fn_declaration(Parser *p, MsToken token, MsDecl **out) {
  p->at++;
  if (!parse_need(p, MS_T_Fn))
    return false;
  MsToken name = {0};
  if (!parse_need_token(p, MS_T_Name, &name))
    return false;
  MsTypeParams tps = {0};
  if (!parse_type_params(p, &tps))
    return false;
  MsParams params = {0};
  if (!parse_parameters(p, true, false, &params))
    return false;
  MsTypeRef *result = NULL;
  bool result_moves = false;
  if (!parse_result_type(p, &result, &result_moves))
    return false;
  if (parse_kind(p) == MS_T_Colon) {
    parse_fail(p, parse_peek(p), ms_span_of_text("an extern fn has no body; remove the ':'"));
    return false;
  }
  if (!parse_end(p))
    return false;
  MsDecl *d = parse_new_decl(p, token.pos, MS_D_FN);
  d->u.fn.name = parse_sym(p, name);
  d->u.fn.type_params = tps;
  d->u.fn.params = params;
  d->u.fn.result = result;
  d->u.fn.result_moves = result_moves;
  d->u.fn.external = true;
  *out = d;
  return true;
}

/* `NAME := value` or `NAME: Type := value` at module level. */
MS_NODISCARD static bool constant_declaration(Parser *p, MsToken token, MsDecl **out) {
  MsToken name = {0};
  if (!parse_need_token(p, MS_T_Name, &name))
    return false;
  MsTypeRef *ty = NULL;
  if (parse_take(p, MS_T_Colon)) {
    if (!parse_typ(p, &ty))
      return false;
  }
  if (!parse_need_immutable_bind(p))
    return false;
  MsPos init_pos = {0};
  MsExpr *value = NULL;
  if (!parse_constant_value(p, &init_pos, &value))
    return false;
  if (!parse_end(p))
    return false;
  MsDecl *d = parse_new_decl(p, token.pos, MS_D_CONST);
  d->u.konst.name = parse_sym(p, name);
  d->u.konst.ty = ty;
  d->u.konst.value = value;
  d->u.konst.init_pos = init_pos;
  *out = d;
  return true;
}

MS_NODISCARD static bool test_declaration(Parser *p, MsToken token, bool bench, MsDecl **out) {
  p->at++;
  MsDecl block = {0};
  if (!parse_test_block(p, bench, &block))
    return false;
  MsDecl *d = parse_new_decl(p, token.pos, MS_D_TEST);
  d->u = block.u;
  *out = d;
  return true;
}

/* `opaque type` and `opaque enum`: the declaration after the modifier, marked opaque. */
MS_NODISCARD static bool opaque_declaration(Parser *p, MsToken token, MsDecl **out) {
  p->at++;
  MsDecl *decl = NULL;
  if (!type_declaration(p, parse_peek(p), &decl))
    return false;
  decl->pos = token.pos;
  if (decl->kind == MS_D_TYPE) {
    decl->u.type.opaque = true;
  } else if (decl->kind == MS_D_ENUM) {
    decl->u.enumeration.opaque = true;
  }
  *out = decl;
  return true;
}

/* A declaration keyword from another language, with the rewrite when there is one. */
static void report_foreign_declaration(Parser *p, MsToken token, MsSpan message, const char *replacement) {
  MsSpan word = parse_text(p, token);
  if (replacement == NULL &&
      (ms_span_is_text(word, "const") || ms_span_is_text(word, "val") || ms_span_is_text(word, "final"))) {
    MsToken first, last;
    MsSpan rewrite;
    if (parse_constant_fix(p, token, &first, &last, &rewrite)) {
      parse_fail_fix_range(p, first, last, message, rewrite);
      return;
    }
  }
  if (replacement != NULL) {
    parse_fail_fix(p, token, message, ms_span_of_text(replacement));
    return;
  }
  parse_fail(p, token, message);
}

static void report_misplaced_opaque(Parser *p, MsToken token) {
  MsSpan advice = ms_span_of_text("'opaque' applies only to a type or enum; write 'opaque type Name:' or "
                                  "'opaque enum Name:', optionally after 'export'");
  if (parse_ahead(p, 1).kind == MS_T_Export) {
    const char *kw = parse_ahead(p, 2).kind == MS_T_Enum ? "enum" : "type";
    advice = parse_fmt(p, "write 'export opaque %s Name:', with export first", kw);
  }
  parse_fail(p, token, parse_fmt(p, "misplaced 'opaque'; %S", advice));
}

/* Reports why `token` cannot start a module declaration. */
static void report_bad_declaration(Parser *p, MsToken token) {
  MsTok k = (MsTok)token.kind;
  if (k == MS_T_Impl) {
    parse_fail(p, token, ms_span_of_text(IMPL_REMOVED));
    return;
  }
  if (k == MS_T_Var && parse_ahead(p, 1).kind == MS_T_Fn) {
    /* `var fn T.m()` is the receiver-changing method spelled in the wrong order. */
    parse_fail_fix_range(
        p, token, parse_ahead(p, 1),
        ms_span_of_text(
            "a method that changes its receiver is written fn var Type.name(), with var after fn"),
        ms_span_of_text("fn var"));
    return;
  }
  MsSpan message;
  const char *replacement;
  if (parse_foreign_declaration(p, token, &message, &replacement)) {
    report_foreign_declaration(p, token, message, replacement);
    return;
  }
  if (k == MS_T_Export) {
    parse_fail_fix(p, token, ms_span_of_text("'export' appears twice; write it once before the declaration"),
                   ms_span_of_text(""));
    return;
  }
  if (k == MS_T_Name && parse_text_is(p, token, "opaque")) {
    report_misplaced_opaque(p, token);
    return;
  }
  MsSpan found = parse_describe(p, token);
  parse_fail(p, token,
             parse_fmt(p,
                       "expected a module declaration or import, found %S; top level holds only import, "
                       "constants (NAME := value), fn, type, enum, interface, impl, and test (optionally "
                       "prefixed by export), so put statements inside a fn",
                       found));
}

MS_NODISCARD bool parse_declaration(Parser *p, MsDecl **out) {
  MsToken token = parse_peek(p);
  MsTok k = (MsTok)token.kind;
  MsTok next_kind = (MsTok)parse_ahead(p, 1).kind;
  if (k == MS_T_Fn) {
    return parse_receiver_method_ahead(p) ? method_declaration(p, token, out) : fn_declaration(p, token, out);
  }
  if (k == MS_T_Extern) {
    return next_kind == MS_T_Type ? extern_type_declaration(p, token, out)
                                  : extern_fn_declaration(p, token, out);
  }
  if (k == MS_T_Name && (next_kind == MS_T_ColonAssign || next_kind == MS_T_Colon)) {
    return constant_declaration(p, token, out);
  }
  if (k == MS_T_Test) {
    return test_declaration(p, token, false, out);
  }
  if (k == MS_T_Name && parse_text_is(p, token, "bench") && next_kind == MS_T_String) {
    return test_declaration(p, token, true, out);
  }
  if (k == MS_T_Type || k == MS_T_Enum || k == MS_T_Interface) {
    return type_declaration(p, token, out);
  }
  if (k == MS_T_Name && parse_text_is(p, token, "opaque") &&
      (next_kind == MS_T_Type || next_kind == MS_T_Enum)) {
    return opaque_declaration(p, token, out);
  }
  report_bad_declaration(p, token);
  return false;
}
