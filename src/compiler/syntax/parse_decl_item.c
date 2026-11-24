/* Owns declaration pieces: test blocks, constants, enum variants and type members. */
#include "compiler/syntax/parse_internal.h"

/* ---- declarations ---- */

MS_NODISCARD bool parse_suite(Parser *p, MsStmts *out) {
  return parse_statement_suite(p, false, false, out);
}

MS_NODISCARD bool parse_method_signature(Parser *p, MsToken name, bool generics, bool body, bool mutating,
                                         MsPos var_at, MsMethod **out) {
  MsTypeParams tps = {NULL, 0};
  if (generics) {
    if (!parse_type_params(p, &tps))
      return false;
  }
  MsParams params = {0};
  if (!parse_parameters(p, true, false, &params))
    return false;
  MsTypeRef *result = NULL;
  bool result_moves = false;
  if (!parse_result_type(p, &result, &result_moves))
    return false;
  MsStmts stmts = {NULL, 0};
  if (body) {
    if (!parse_statement_suite(p, false, true, &stmts))
      return false;
  }
  MsMethod *m = MS_ARENA_NEW(p->arena, MsMethod);
  m->id = parse_new_id(p);
  m->pos = name.pos;
  m->var_at = var_at;
  m->func.name = parse_sym(p, name);
  m->func.type_params = tps;
  m->func.params = params;
  m->func.result = result;
  m->func.result_moves = result_moves;
  m->func.body = stmts;
  m->mutating = mutating;
  *out = m;
  return true;
}

/* The suite after `test "name":` or `bench "name":` (the keyword is consumed). */
MS_NODISCARD bool parse_single_line(Parser *p, MsToken token, const char *what) {
  MsSpan full = parse_text(p, token);
  if (ms_span_starts_with(full, ms_span_of_text("\"\"\"")) ||
      ms_span_starts_with(full, ms_span_of_text("r\"\"\""))) {
    parse_fail(p, token, parse_fmt(p, "%s are one-line text; write them with a single pair of quotes", what));
    return false;
  }
  return true;
}

/* The plain text of a one-line name or path, or NULL when it interpolates. */
bool parse_plain_text(TextParts parts, MsSpan *out) {
  if (parts.len == 1 && parts.ptr[0].expr == NULL) {
    *out = parts.ptr[0].lit;
    return true;
  }
  return false;
}

static bool parse_positive_i64(MsSpan s, int64_t *out) {
  if (s.len == 0) {
    return false;
  }
  uint64_t v = 0;
  for (uint32_t i = 0; i < s.len; i++) {
    if (s.ptr[i] < '0' || s.ptr[i] > '9') {
      return false;
    }
    if (v > (UINT64_MAX - (uint64_t)(s.ptr[i] - '0')) / 10) {
      return false;
    }
    v = v * 10 + (uint64_t)(s.ptr[i] - '0');
  }
  if (v == 0 || v > (uint64_t)INT64_MAX) {
    return false;
  }
  *out = (int64_t)v;
  return true;
}

MsDecl *parse_new_decl(Parser *p, MsPos pos, MsDeclKind k) {
  MsDecl *d = MS_ARENA_NEW(p->arena, MsDecl);
  d->id = parse_new_id(p);
  d->pos = pos;
  d->kind = (uint8_t)k;
  return d;
}

MS_NODISCARD bool parse_test_block(Parser *p, bool bench, MsDecl *d) {
  MsToken name = {0};
  if (!parse_need_token(p, MS_T_String, &name))
    return false;
  if (!parse_single_line(p, name, bench ? "bench names" : "test names"))
    return false;
  TextParts parts = {0};
  if (!parse_text_parts_of(p, name, &parts))
    return false;
  MsSpan plain;
  if (!parse_plain_text(parts, &plain)) {
    if (bench) {
      parse_fail(
          p, name,
          ms_span_of_text("bench names cannot interpolate; use plain text, e.g. bench \"sums a list\":"));
      return false;
    }
    parse_fail(p, name,
               ms_span_of_text("test names cannot interpolate; use plain text, e.g. test \"adds numbers\":"));
    return false;
  }
  int64_t per = 1;
  if (bench && parse_kind(p) == MS_T_Name && parse_text_is(p, parse_peek(p), "per")) {
    p->at++;
    MsToken count = {0};
    if (!parse_need_token(p, MS_T_Number, &count))
      return false;
    if (!parse_positive_i64(parse_text(p, count), &per)) {
      parse_fail(
          p, count,
          ms_span_of_text(
              "'per' takes a positive whole number of operations, e.g. bench \"sums a list\" per 1000:"));
      return false;
    }
  }
  MsStmts body = {0};
  p->bench_suite = bench;
  if (!parse_suite(p, &body))
    return false;
  d->kind = MS_D_TEST;
  d->u.test.name = plain;
  d->u.test.body = body;
  d->u.test.bench = bench;
  d->u.test.per = per;
  return true;
}

/* `const NAME = v` on one line: the range from the word through `=` and its replacement. */
bool parse_constant_fix(Parser *p, MsToken word, MsToken *first, MsToken *last, MsSpan *replacement) {
  MsToken name = parse_ahead(p, 1);
  if (name.kind != MS_T_Name || name.pos.line != word.pos.line) {
    return false;
  }
  for (size_t n = 2;; n++) {
    MsToken t = parse_ahead(p, n);
    if (t.pos.line != word.pos.line || t.kind == MS_T_Newline || t.kind == MS_T_Eof) {
      return false;
    }
    if (t.kind == MS_T_Assign) {
      /* head = src[name.lo..t.lo].trim_end() */
      size_t hi = t.lo;
      while (hi > name.lo && (p->source.ptr[hi - 1] == ' ' || p->source.ptr[hi - 1] == '\t' ||
                              p->source.ptr[hi - 1] == '\n' || p->source.ptr[hi - 1] == '\r')) {
        hi--;
      }
      *replacement = parse_fmt(p, "%S :=", ms_span_of(p->source.ptr + name.lo, hi - name.lo));
      *first = word;
      *last = t;
      return true;
    }
  }
}

/* Whether the `fn` at the cursor starts a receiver method (`fn [var] Type[T].name`). */
bool parse_receiver_method_ahead(const Parser *p) {
  size_t at = 1;
  if (parse_ahead(p, at).kind == MS_T_Name && parse_text_is(p, parse_ahead(p, at), "move") &&
      (parse_ahead(p, at + 1).kind == MS_T_Name || parse_ahead(p, at + 1).kind == MS_T_Var)) {
    at++;
  }
  if (parse_ahead(p, at).kind == MS_T_Var) {
    at++;
  }
  if (parse_ahead(p, at).kind != MS_T_Name) {
    return false;
  }
  at++;
  if (parse_ahead(p, at).kind == MS_T_LBracket) {
    size_t depth = 0;
    for (;;) {
      MsTok k = (MsTok)parse_ahead(p, at).kind;
      if (k == MS_T_LBracket) {
        depth++;
      } else if (k == MS_T_RBracket) {
        depth--;
        if (depth == 0) {
          at++;
          break;
        }
      } else if (k == MS_T_Newline || k == MS_T_Eof) {
        return false;
      }
      at++;
    }
  }
  return parse_ahead(p, at).kind == MS_T_Dot;
}

MS_NODISCARD bool parse_constant_value(Parser *p, MsPos *init_pos, MsExpr **out) {
  *init_pos = parse_peek(p).pos;
  return parse_expression(p, 0, out);
}

/* Consumes the `:=` of an immutable binding. A leftover `=` after a type annotation gets a fix-it. */
MS_NODISCARD bool parse_need_immutable_bind(Parser *p) {
  if (parse_kind(p) == MS_T_Assign) {
    parse_fail_fix(p, parse_peek(p),
                   ms_span_of_text("an immutable binding uses ':=' after its type: write 'x Type := value'; "
                                   "'=' binds only after 'var'"),
                   ms_span_of_text(":="));
    return false;
  }
  if (!parse_need(p, MS_T_ColonAssign))
    return false;
  return true;
}

/* Appends the type parameter list `[A, B]` of a declaration, or nothing when it has none. */
static void type_param_names(Parser *p, MsStrBuild *out, MsTypeParams tps) {
  if (tps.len == 0) {
    return;
  }
  ms_strbuild_append_byte(out, '[');
  for (uint32_t i = 0; i < tps.len; i++) {
    if (i > 0) {
      ms_strbuild_append_text(out, ", ");
    }
    ms_strbuild_append(out, ms_names_span(p->names, tps.ptr[i]->name));
  }
  ms_strbuild_append_byte(out, ']');
}

/* `type Name = A | B`: an alias for one or several types. */
MS_NODISCARD bool parse_alias_declaration(Parser *p, MsToken token, MsName name, MsTypeParams tps,
                                          MsDecl **out) {
  size_t m = parse_mark(p);
  if (!parse_push_typ(p))
    return false;
  while (parse_take(p, MS_T_Pipe)) {
    if (!parse_push_typ(p))
      return false;
  }
  MsTypeRefs targets;
  targets.ptr = parse_finish(p, m, &targets.len, sizeof(void *), _Alignof(void *));
  if (!parse_end(p))
    return false;
  MsDecl *d = parse_new_decl(p, token.pos, MS_D_ALIAS);
  d->u.alias.name = name;
  d->u.alias.type_params = tps;
  d->u.alias.targets = targets;
  *out = d;
  return true;
}

/* `interface Name: ...` or `type Name: ...`: a declaration with no members. */
MS_NODISCARD bool parse_empty_declaration(Parser *p, MsToken token, MsName name, MsTypeParams tps,
                                          MsDecl **out) {
  if (!parse_end(p))
    return false;
  MsDecl *d = parse_new_decl(p, token.pos, token.kind == MS_T_Interface ? MS_D_INTERFACE : MS_D_TYPE);
  if (token.kind == MS_T_Interface) {
    d->u.iface.name = name;
    d->u.iface.type_params = tps;
  } else {
    d->u.type.name = name;
    d->u.type.type_params = tps;
  }
  *out = d;
  return true;
}

/* `move fn` in an interface or type body. */
static bool at_move_fn(const Parser *p) {
  return parse_kind(p) == MS_T_Name && parse_text_is(p, parse_peek(p), "move") &&
         parse_ahead(p, 1).kind == MS_T_Fn;
}

static bool at_enum_variant_start(const Parser *p) {
  MsToken next = parse_ahead(p, 1);
  /* A payload's `(` touches the variant name; a field's parenthesized type follows a space. */
  bool payload = next.kind == MS_T_LParen && next.lo == parse_peek(p).hi;
  return parse_kind(p) == MS_T_Name &&
         (payload || next.kind == MS_T_Newline || next.kind == MS_T_BlockClose || next.kind == MS_T_Eof);
}

/* Rejects a member that does not belong in the body of this kind of declaration. */
static bool report_misplaced_member(Parser *p, MsToken token) {
  MsToken prefix;
  /* `case Int` in a type body is a field named `case`; only an enum body can carry the old prefix. */
  if (token.kind == MS_T_Type && at_enum_variant_start(p)) {
    parse_fail(p, token,
               ms_span_of_text("a type declared with 'type' cannot contain enum variants; replace 'type' "
                               "with 'enum' and remove any legacy 'case' prefixes"));
    return true;
  }
  if (token.kind == MS_T_Enum && parse_legacy_case_prefix(p, &prefix)) {
    parse_fail(
        p, prefix,
        ms_span_of_text(
            "enum variants do not use 'case'; remove the prefix and write 'Name' or 'Name(field Type)'"));
    return true;
  }
  if (token.kind == MS_T_Enum && parse_kind(p) != MS_T_Name) {
    parse_fail(p, parse_peek(p),
               ms_span_of_text("an enum contains only variants; write 'Name' or 'Name(field Type)', use "
                               "'type' for type fields, and write methods after the enum as 'fn Name.method(...)'"));
    return true;
  }
  if (token.kind == MS_T_Interface && !at_move_fn(p) && parse_kind(p) != MS_T_Fn &&
      parse_kind(p) != MS_T_Var) {
    parse_fail(p, parse_peek(p),
               ms_span_of_text("an interface contains only operation signatures; write 'fn name(...) Type' "
                               "and write each method body beside the type that provides it, as 'fn Type.name(...)'"));
    return true;
  }
  return false;
}

/* The payload fields of an enum variant, `(field: Type, ...)`. */
MS_NODISCARD static bool variant_payload(Parser *p, MsToken variant, MsParams *payload) {
  if (!parse_parameters(p, false, false, payload))
    return false;
  for (uint32_t i = 0; i < payload->len; i++) {
    if (payload->ptr[i]->is_mutable) {
      parse_fail(
          p, parse_previous(p),
          ms_span_of_text(
              "case payload fields cannot be 'var'; mutability belongs to the binding that holds the value"));
      return false;
    }
  }
  if (payload->len == 0) {
    MsSpan n = parse_text(p, variant);
    parse_fail(p, variant,
               parse_fmt(p, "payloadless variants omit parentheses; write '%S' instead of '%S()'", n, n));
    return false;
  }
  return true;
}

/* One enum variant, pushed on the scratch stack. */
MS_NODISCARD static bool enum_variant(Parser *p) {
  MsToken cname = {0};
  if (!parse_need_token(p, MS_T_Name, &cname))
    return false;
  MsParams payload = {NULL, 0};
  if (parse_kind(p) == MS_T_LParen && !variant_payload(p, cname, &payload))
    return false;
  if (parse_kind(p) == MS_T_Colon) {
    parse_fail(p, parse_peek(p),
               ms_span_of_text("enum variants have no field or method bodies; write 'Name' or 'Name(field: "
                               "Type)', use 'type' for type fields, and write methods after the enum as 'fn Name.method(...)'"));
    return false;
  }
  if (parse_kind(p) == MS_T_Assign) {
    parse_fail(p, parse_peek(p),
               ms_span_of_text("enum variants cannot have defaults; write 'Name' or 'Name(field Type)' and "
                               "supply payload values when constructing a variant"));
    return false;
  }
  MsCase *c = MS_ARENA_NEW(p->arena, MsCase);
  c->id = parse_new_id(p);
  c->pos = cname.pos;
  c->name = parse_sym(p, cname);
  c->fields = payload;
  parse_push_ptr(p, c);
  return parse_end(p);
}

/* An interface operation `fn name(...) Type`; a `type` body may not hold one. */
MS_NODISCARD static bool member_signature(Parser *p, MsToken token, MsName name, MsTypeParams tps) {
  bool consuming = parse_take_move(p, (const MsTok[]){MS_T_Fn}, 1);
  bool mutating = parse_take(p, MS_T_Var);
  MsToken fn_token = {0};
  if (!parse_need_token(p, MS_T_Fn, &fn_token))
    return false;
  if (token.kind == MS_T_Type) {
    MsStrBuild names = ms_strbuild_new();
    type_param_names(p, &names, tps);
    MsSpan nt = ms_names_span(p->names, name);
    MsSpan msg =
        parse_fmt(p, "a type declares only fields; write its methods after it as 'fn %S%S.name(...)'", nt,
                  ms_strbuild_span(&names));
    ms_strbuild_free(&names);
    parse_fail(p, parse_previous(p), msg);
    return false;
  }
  MsToken mname = {0};
  if (!parse_need_token(p, MS_T_Name, &mname))
    return false;
  MsMethod *me = NULL;
  if (!parse_method_signature(p, mname, true, false, mutating, fn_token.pos, &me))
    return false;
  me->consuming = consuming;
  if (!parse_end(p))
    return false;
  parse_push_ptr(p, me);
  return true;
}

/* One `name: Type [= default]` field of a type, pushed on the scratch stack. */
MS_NODISCARD static bool type_field(Parser *p) {
  MsToken names[MS_GROUP_MAX];
  size_t nnames = 1;
  if (!parse_member_name(p, &names[0]))
    return false;
  if (!parse_group_names(p, names, &nnames))
    return false;
  const size_t type_at = p->at;
  size_t end = type_at;
  for (size_t i = 0; i < nnames; i++) {
    /* `width, height Int = 0`: every name reads the same type and default. */
    p->at = type_at;
    MsTypeRef *ty = NULL;
    if (!parse_name_type(p, names[i], &ty))
      return false;
    MsExpr *def = NULL;
    if (parse_take(p, MS_T_Assign)) {
      if (!parse_expression(p, 0, &def))
        return false;
    } else {
      def = parse_implicit_none(p, ty);
    }
    end = p->at;
    parse_push_ptr(p, parse_mk_param(p, names[i].pos, parse_sym(p, names[i]), ty, def, false, false));
  }
  p->at = end;
  return parse_end(p);
}

/* One member of the indented body, pushed on the scratch stack. */
MS_NODISCARD bool parse_declaration_member(Parser *p, MsToken token, MsName name, MsTypeParams tps) {
  if (report_misplaced_member(p, token)) {
    return false;
  }
  if (token.kind == MS_T_Enum) {
    return enum_variant(p);
  }
  bool starts_signature = parse_kind(p) == MS_T_Fn || at_move_fn(p) ||
                          (parse_kind(p) == MS_T_Var && parse_ahead(p, 1).kind == MS_T_Fn);
  return starts_signature ? member_signature(p, token, name, tps) : type_field(p);
}

/* The declaration of `token`'s kind built from the collected members. */
MS_NODISCARD bool parse_finish_declaration(Parser *p, MsToken token, MsName name, MsTypeParams tps,
                                           void **items, uint32_t count, MsDecl **out) {
  if (token.kind == MS_T_Interface && count == 0) {
    parse_fail(p, token,
               ms_span_of_text("declaration body cannot be empty; an interface needs at least one 'fn "
                               "name(...) Type' operation"));
    return false;
  }
  if (token.kind == MS_T_Enum && count == 0) {
    parse_fail(
        p, token,
        ms_span_of_text("an enum must declare at least one variant; add 'Name' or 'Name(field Type)'"));
    return false;
  }
  MsDecl *d = NULL;
  if (token.kind == MS_T_Interface) {
    d = parse_new_decl(p, token.pos, MS_D_INTERFACE);
    d->u.iface.name = name;
    d->u.iface.type_params = tps;
    d->u.iface.methods.ptr = (MsMethod **)items;
    d->u.iface.methods.len = count;
  } else if (token.kind == MS_T_Enum) {
    d = parse_new_decl(p, token.pos, MS_D_ENUM);
    d->u.enumeration.name = name;
    d->u.enumeration.type_params = tps;
    d->u.enumeration.cases.ptr = (MsCase **)items;
    d->u.enumeration.cases.len = count;
  } else {
    d = parse_new_decl(p, token.pos, MS_D_TYPE);
    d->u.type.name = name;
    d->u.type.type_params = tps;
    d->u.type.fields.ptr = (MsParam **)items;
    d->u.type.fields.len = count;
  }
  *out = d;
  return true;
}

/* The header of a declaration with members, through its indent; false after reporting a problem. */
MS_NODISCARD bool parse_declaration_body_start(Parser *p, MsToken token) {
  if (token.kind == MS_T_Enum && parse_kind(p) == MS_T_Ellipsis) {
    parse_fail(
        p, parse_peek(p),
        ms_span_of_text(
            "an enum must declare at least one variant; replace '...' with 'Name' or 'Name(field Type)'"));
    return false;
  }
  if (token.kind == MS_T_Enum && parse_kind(p) == MS_T_BlockClose) {
    parse_fail(p, parse_peek(p),
               ms_span_of_text("an enum must declare at least one variant; write 'Name' or 'Name(field "
                               "Type)' inside the braces"));
    return false;
  }
  return true;
}
