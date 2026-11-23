/* compiler/check/match.c: `match` expressions: arm patterns bind a case's payload; the result is the first
 * typed arm value (or the expected type). */
#include "compiler/check/body.h"
#include "compiler/check/suggest.h"

/* The case an arm path names (`Case` or `Type.Case`) in the scrutinee's enum. */
static const MsTyCase *arm_case(Body *body, const MsExpr *path, MsTy scrutinee, uint32_t *index) {
  if (path == NULL) {
    return NULL;
  }
  const MsName name = path->kind == MS_E_MEMBER ? path->u.member.name : path->u.sym;
  if (path->kind != MS_E_MEMBER && path->kind != MS_E_NAME) {
    return NULL;
  }
  return body_case_of(body, scrutinee, name, index);
}

/* The payload field type of `kase` under the scrutinee's arguments. */
static MsTy payload(Body *body, MsTy scrutinee, const MsTyCase *kase, uint32_t at) {
  if (at >= kase->fields.len) {
    return MS_TY_NONE;
  }
  const MsTyRow *row = ms_ty_row(&body->program->types, scrutinee);
  const MsDef *def = body_def(body, scrutinee);
  if (def == NULL || def->variables.len != row->arg_count) {
    return kase->fields.ptr[at].ty;
  }
  return ms_ty_subst(&body->program->types, kase->fields.ptr[at].ty, def->variables.ptr,
                     ms_ty_args(&body->program->types, scrutinee), row->arg_count);
}

/* `value:` on an optional names the payload. */
static MsTy bare_payload(const Body *body, const MsArm *arm, MsTy scrutinee) {
  const MsTyTable *types = &body->program->types;
  return arm->bare && ms_ty_is(types, scrutinee, MS_BUILTIN_Optional) && ms_ty_arg_count(types, scrutinee) == 1
             ? ms_ty_args(types, scrutinee)[0]
             : MS_TY_NONE;
}

/* What the arms of one `match` have shown so far: the diagnostics that need every earlier arm. */
typedef struct ArmState {
  const MsExpr *match;
  MsTy scrutinee;
  bool contract;     /* an interface scrutinee: arms name implementing types */
  bool literal;      /* an Int, String or Bool scrutinee: literal arms */
  bool report;       /* a user module that is not quiet */
  bool wildcard;
  bool discarded;    /* a statement: arm values are dropped, so they need not agree */
  bool unknown_case;
  uint32_t index;    /* the arm being visited */
  MsName *seen;      /* case names, or literal spellings interned as names */
  uint32_t seen_len;
  uint32_t case_count;
} ArmState;

static bool state_seen(const ArmState *state, MsName name) {
  for (uint32_t index = 0; index < state->seen_len; index++) {
    if (state->seen[index] == name) {
      return true;
    }
  }
  return false;
}

static void state_add(ArmState *state, MsName name) {
  if (!state_seen(state, name)) {
    state->seen[state->seen_len++] = name;
  }
}

static void arm_report(Body *body, const MsArm *arm, MsCheckPhase phase, MsStrBuild text) {
  ms_check_report(body->program, body->module, arm->pos, phase, ms_strbuild_finish(&text));
}

static void arm_message(Body *body, const MsArm *arm, MsCheckPhase phase, const char *text) {
  MsStrBuild build = ms_strbuild_new();
  ms_strbuild_append_text(&build, text);
  arm_report(body, arm, phase, build);
}

static MsName path_name(const MsExpr *path) {
  if (path != NULL && path->kind == MS_E_MEMBER) {
    return path->u.member.name;
  }
  return path != NULL && path->kind == MS_E_NAME ? path->u.sym : MS_NAME_EMPTY;
}

/* Whether the qualifier of `Type.Case` or `Type[Args].Case` names the matched alternative. A bare generic name
 * stands for every instantiation; explicit arguments must be the matched type. A qualifier that is not a plain
 * type name is left to other passes. */
static bool qualifier_matches(Body *body, const MsExpr *left, MsTy matched) {
  const bool applied = left->kind == MS_E_APPLY && left->u.apply.left->kind == MS_E_NAME && left->u.apply.types.len != 0;
  const MsExpr *named = applied ? left->u.apply.left : left;
  if (named->kind != MS_E_NAME) {
    return true;
  }
  const MsSymbol *symbol = body_find_local(body, named->u.sym) == NULL ? body_find_symbol(body, named->u.sym) : NULL;
  if (symbol == NULL || symbol->kind != MS_SYMBOL_TYPE || symbol->ty == MS_TY_NONE) {
    return false;
  }
  MsTyTable *types = &body->program->types;
  if (!applied) {
    return ms_ty_row(types, symbol->ty)->id == ms_ty_row(types, matched)->id;
  }
  MsTyList args = {0};
  for (uint32_t index = 0; index < left->u.apply.types.len; index++) {
    ms_ty_list_push(&args, resolver_type(&body->resolver, left->u.apply.types.ptr[index]));
  }
  const MsTy qualified = resolver_apply(body->program, symbol->ty, args.ptr, args.len);
  ms_ty_list_free(&args);
  return qualified == matched;
}

static void report_unknown_arm(Body *body, const MsArm *arm, MsName name, MsTy scrutinee) {
  MsCheckProgram *program = body->program;
  const MsDef *def = body_def(body, scrutinee);
  MsSpanList names = {0};
  for (size_t index = 0; def != NULL && index < def->cases.len; index++) {
    ms_span_list_push(&names, ms_names_span(program->names, def->cases.ptr[index].name));
  }
  const MsSpan text = ms_names_span(program->names, name);
  MsStrBuild out = ms_strbuild_new();
  const bool upper = text.len != 0 && text.ptr[0] >= 'A' && text.ptr[0] <= 'Z';
  if (arm->bare) {
    ms_strbuild_append_text(&out, "'");
    ms_strbuild_append(&out, ms_names_span(program->names, arm->bindings.ptr[0].name));
    ms_strbuild_append_text(&out, "' is not a case of ");
    ms_strbuild_append(&out, ms_names_span(program->names, ms_ty_row(&program->types, scrutinee)->name)); /* the type's own name, as the oracle writes it */
    ms_strbuild_append_text(&out, "; a lone lowercase name binds an Optional's payload, but this is not an Optional; use "
                                  "'_' for a catch-all arm, or one of the cases: ");
    ms_suggest_list(&out, &names, 12);
  } else if (text.len == 0) {
    ms_strbuild_append_text(&out, "a literal pattern cannot match ");
    ms_strbuild_append(&out, ms_names_span(program->names, ms_ty_row(&program->types, scrutinee)->name)); /* the type's own name, as the oracle writes it */
    ms_strbuild_append_text(&out, "; literals match only Int, String or Bool, so match one of the cases: ");
    ms_suggest_list(&out, &names, 12);
  } else if (arm->bindings.len == 0 && !upper) {
    ms_strbuild_append_text(&out, "'");
    ms_strbuild_append(&out, text);
    ms_strbuild_append_text(&out, "' is not a case of ");
    ms_strbuild_append(&out, ms_names_span(program->names, ms_ty_row(&program->types, scrutinee)->name)); /* the type's own name, as the oracle writes it */
    ms_strbuild_append_text(&out, "; use '_' for a catch-all arm (it cannot bind a name); cases: ");
    ms_suggest_list(&out, &names, 12);
  } else {
    ms_strbuild_append_text(&out, "unknown case ");
    ms_strbuild_append(&out, text);
    ms_strbuild_append_text(&out, " of ");
    ms_strbuild_append(&out, ms_names_span(program->names, ms_ty_row(&program->types, scrutinee)->name)); /* the type's own name, as the oracle writes it */
    ms_strbuild_append_text(&out, "; cases: ");
    ms_suggest_list(&out, &names, 12);
    (void)ms_suggest_did_you_mean(&out, text, &names);
  }
  arm_report(body, arm, MS_CHECK_RESOLUTION, out);
  ms_span_list_free(&names);
}

/* The diagnostics of one arm of a match on an alternative. */
static void check_alternative_arm(Body *body, ArmState *state, const MsArm *arm) {
  MsCheckProgram *program = body->program;
  const MsTyTable *types = &program->types;
  const bool optional_binding = arm->bare && ms_ty_is(types, state->scrutinee, MS_BUILTIN_Optional);
  const MsName some = ms_names_intern(program->names, ms_span_of_text("some"));
  const MsName name = optional_binding ? some : path_name(arm->path);
  const size_t bindings = arm->bare && !optional_binding ? 0 : arm->bindings.len;
  const MsSpan text = ms_names_span(program->names, name);
  if (ms_span_is_text(text, "_")) {
    if (state->wildcard || state->index != state->match->u.match.arms.len - 1 || state->seen_len == state->case_count) {
      arm_message(body, arm, MS_CHECK_TYPE, "unreachable wildcard or wildcard is not last; keep one '_' arm at the end, "
                                            "and only when cases remain");
    }
    state->wildcard = true;
    return;
  }
  if (arm->path != NULL && arm->path->kind == MS_E_MEMBER && !qualifier_matches(body, arm->path->u.member.left, state->scrutinee)) {
    MsStrBuild out = ms_strbuild_new();
    ms_strbuild_append_text(&out, "pattern belongs to a different alternative; qualify arms with the matched type, ");
    ms_strbuild_append(&out, ms_names_span(program->names, ms_ty_row(types, state->scrutinee)->name));
    ms_strbuild_append_text(&out, ".<case>");
    arm_report(body, arm, MS_CHECK_TYPE, out);
  }
  uint32_t at = 0;
  const MsTyCase *kase = body_case_of(body, state->scrutinee, name, &at);
  if (kase == NULL) {
    state->unknown_case = true;
    report_unknown_arm(body, arm, name, state->scrutinee);
  }
  if (state_seen(state, name) || state->wildcard) {
    MsStrBuild out = ms_strbuild_new();
    ms_strbuild_append_text(&out, "duplicate or unreachable case ");
    ms_strbuild_append(&out, text);
    ms_strbuild_append_text(&out, "; each case may be matched once and before any '_' arm");
    arm_report(body, arm, MS_CHECK_TYPE, out);
  }
  state_add(state, name);
  if (kase != NULL && kase->fields.len != bindings) {
    MsStrBuild out = ms_strbuild_new();
    ms_strbuild_append_text(&out, "case payload arity mismatch; ");
    ms_strbuild_append(&out, text);
    ms_strbuild_printf(&out, " has %zu payload fields, found %zu bindings (use _ to ignore one)", (size_t)kase->fields.len,
                       bindings);
    arm_report(body, arm, MS_CHECK_TYPE, out);
  }
}

/* The spelling that identifies a literal arm, or MS_NAME_EMPTY for any other pattern. */
static MsName literal_key(Body *body, const MsExpr *path) {
  MsNames *names = body->program->names;
  if (path == NULL) {
    return MS_NAME_EMPTY;
  }
  if (path->kind == MS_E_NUMBER) {
    return path->u.sym;
  }
  if (path->kind == MS_E_BOOL) {
    return ms_names_intern(names, ms_span_of_text(path->u.flag ? "true" : "false"));
  }
  if (path->kind == MS_E_TEXT && path->u.text.len == 1 && path->u.text.ptr[0].expr == NULL) {
    MsStrBuild key = ms_strbuild_new();
    ms_strbuild_append_text(&key, "\"");
    ms_strbuild_append(&key, path->u.text.ptr[0].lit);
    ms_strbuild_append_text(&key, "\"");
    const MsName name = ms_names_intern(names, ms_strbuild_span(&key));
    ms_strbuild_free(&key);
    return name;
  }
  if (path->kind == MS_E_UNARY && path->op == MS_U_NEG && path->u.bin.left->kind == MS_E_NUMBER) {
    MsStrBuild key = ms_strbuild_new();
    const MsSpan digits = ms_names_span(names, path->u.bin.left->u.sym);
    bool zero = true;
    for (size_t index = 0; index < digits.len; index++) {
      zero = zero && digits.ptr[index] == '0';
    }
    ms_strbuild_append_text(&key, zero ? "0" : "-");
    ms_strbuild_append(&key, zero ? (MsSpan){0} : digits);
    const MsName name = ms_names_intern(names, ms_strbuild_span(&key));
    ms_strbuild_free(&key);
    return name;
  }
  return MS_NAME_EMPTY;
}

/* The diagnostics of one arm of a match on Int, String or Bool. */
static void check_literal_arm(Body *body, ArmState *state, const MsArm *arm) {
  MsCheckProgram *program = body->program;
  const MsTyTable *types = &program->types;
  const bool bools = ms_ty_is(types, state->scrutinee, MS_BUILTIN_Bool);
  const MsName path = path_name(arm->path);
  if (arm->path != NULL && arm->path->kind == MS_E_NAME && ms_span_is_text(ms_names_span(program->names, path), "_")) {
    const MsName yes = ms_names_intern(program->names, ms_span_of_text("true"));
    const MsName no = ms_names_intern(program->names, ms_span_of_text("false"));
    const bool both = bools && state_seen(state, yes) && state_seen(state, no);
    if (state->wildcard || state->index != state->match->u.match.arms.len - 1 || both) {
      arm_message(body, arm, MS_CHECK_TYPE, "unreachable wildcard or wildcard is not last; keep one '_' arm at the end, "
                                            "and only when values remain");
    }
    state->wildcard = true;
  } else {
    const MsName key = literal_key(body, arm->path);
    if (key != MS_NAME_EMPTY) {
      (void)body_expr(body, arm->path, state->scrutinee);
      if (state_seen(state, key) || state->wildcard) {
        MsStrBuild out = ms_strbuild_new();
        ms_strbuild_append_text(&out, "duplicate or unreachable pattern ");
        ms_strbuild_append(&out, ms_names_span(program->names, key));
        ms_strbuild_append_text(&out, "; each value may be matched once and before any '_' arm");
        arm_report(body, arm, MS_CHECK_TYPE, out);
      }
      state_add(state, key);
    } else {
      MsStrBuild out = ms_strbuild_new();
      ms_strbuild_append_text(&out, "a match on ");
      ms_ty_show(&out, program->names, types, state->scrutinee);
      ms_strbuild_append_text(&out, " takes literal arms such as 1, \"text\" or true, and a final '_:' arm; to bind or "
                                    "compare computed values use if/else");
      arm_report(body, arm, MS_CHECK_TYPE, out);
    }
  }
  if (arm->bindings.len != 0) {
    arm_message(body, arm, MS_CHECK_TYPE, "a literal arm has no payload to bind");
  }
}

/* The diagnostics of one arm of a match on an interface value: each arm names a concrete type once, then `_`. */
static void check_contract_arm(Body *body, ArmState *state, const MsArm *arm) {
  MsCheckProgram *program = body->program;
  MsTyTable *types = &program->types;
  if (arm->path != NULL && arm->path->kind == MS_E_NAME &&
      ms_span_is_text(ms_names_span(program->names, arm->path->u.sym), "_")) {
    if (state->wildcard || state->index != state->match->u.match.arms.len - 1) {
      arm_message(body, arm, MS_CHECK_TYPE, "wildcard must appear once and be last; keep a single '_' arm at the end");
    }
    state->wildcard = true;
    return;
  }
  const MsExpr *path = arm->path;
  const bool applied = path != NULL && path->kind == MS_E_APPLY && path->u.apply.left->kind == MS_E_NAME &&
                       path->u.apply.types.len != 0;
  const MsExpr *named = applied ? path->u.apply.left : path;
  const MsSymbol *symbol = named != NULL && named->kind == MS_E_NAME && body_find_local(body, named->u.sym) == NULL
                               ? body_find_symbol(body, named->u.sym)
                               : NULL;
  MsTy target = symbol != NULL && symbol->kind == MS_SYMBOL_TYPE ? symbol->ty : MS_TY_NONE;
  const MsTyKind kind = target == MS_TY_NONE ? MS_TY_INVALID : ms_ty_kind(types, target);
  if (kind == MS_TY_TYPE || kind == MS_TY_ALTERNATIVE) {
    const MsDef *def = body_def(body, target);
    if (def != NULL && def->variables.len > 0 && !applied) {
      arm_message(body, arm, MS_CHECK_TYPE, "concrete type pattern requires explicit type arguments; write e.g. Box[Int]");
    } else if (applied) {
      MsTyList args = {0};
      for (uint32_t index = 0; index < path->u.apply.types.len; index++) {
        ms_ty_list_push(&args, resolver_type(&body->resolver, path->u.apply.types.ptr[index]));
      }
      target = resolver_apply(program, target, args.ptr, args.len);
      ms_ty_list_free(&args);
    }
    if (!ms_check_implements(program, target, state->scrutinee)) {
      MsStrBuild out = ms_strbuild_new();
      ms_ty_show(&out, program->names, types, target);
      ms_strbuild_append_text(&out, " does not implement ");
      ms_ty_show(&out, program->names, types, state->scrutinee);
      arm_report(body, arm, MS_CHECK_TYPE, out);
    }
    if (state_seen(state, (MsName)target) || state->wildcard) {
      arm_message(body, arm, MS_CHECK_TYPE, "duplicate or unreachable concrete type pattern; match each type once and before '_'");
    }
    state_add(state, (MsName)target); /* types are keyed by their row, which fits a name's width */
  } else {
    arm_message(body, arm, MS_CHECK_TYPE, "contract pattern requires a concrete type or enum; name an implementing type like Circle, or use '_'");
  }
  if (arm->bare || arm->bindings.len != 1) {
    arm_message(body, arm, MS_CHECK_TYPE, "concrete type pattern requires exactly one receiver binding; write 'Type(name):' or 'Type(_):'");
  }
}

static void check_arm(Body *body, ArmState *state, const MsArm *arm) {
  if (!state->report) {
    /* Lowering reads the type of every literal arm, so it is recorded even where nothing is reported. */
    if (state->literal && literal_key(body, arm->path) != MS_NAME_EMPTY) {
      (void)body_expr(body, arm->path, state->scrutinee);
    }
    return;
  }
  if (state->contract) {
    check_contract_arm(body, state, arm);
  } else if (state->literal) {
    check_literal_arm(body, state, arm);
  } else {
    check_alternative_arm(body, state, arm);
  }
}

/* The type an arm names over an interface-typed scrutinee, or none for another arm or scrutinee. */
static MsTy contract_arm_type(Body *body, const MsArm *arm, MsTy scrutinee) {
  if (arm->path == NULL || arm->path->kind != MS_E_NAME || ms_ty_kind(&body->program->types, scrutinee) != MS_TY_CONTRACT ||
      arm->bindings.len != 1) {
    return MS_TY_NONE;
  }
  const MsSymbol *symbol = body_find_symbol(body, arm->path->u.sym);
  return symbol != NULL && symbol->kind == MS_SYMBOL_TYPE ? symbol->ty : MS_TY_NONE;
}

/* What an arm's statements declared, kept for its value: the oracle checks every arm's pattern and statements, then
 * exhaustiveness, then each arm's value. */
typedef struct ArmScope {
  MsLocal *locals;
  size_t count;
} ArmScope;

static ArmScope arm_statements(Body *body, const MsArm *arm, MsTy scrutinee, ArmState *state) {
  check_arm(body, state, arm);
  const size_t mark = body_scope_mark(body);
  uint32_t index = 0;
  const MsTyCase *kase = arm_case(body, arm->path, scrutinee, &index);
  if (kase != NULL) {
    /* The bindings are declared next, so their locals run from `next_local` in order. */
    body_set_ref(body, arm->id,
                 (MsRef){.kind = MS_REF_CASE, .index = index, .local = body->next_local, .owner = scrutinee});
  }
  if (kase == NULL && bare_payload(body, arm, scrutinee) != MS_TY_NONE) {
    body_set_ref(body, arm->id, (MsRef){.kind = MS_REF_CASE, .index = 1, .local = body->next_local, .owner = scrutinee});
  }
  /* An arm that names a type over an interface value (`Wrap(w):`) binds the value as that type when it has it. */
  const MsTy concrete = kase == NULL ? contract_arm_type(body, arm, scrutinee) : MS_TY_NONE;
  if (concrete != MS_TY_NONE) {
    body_set_ref(body, arm->id, (MsRef){.kind = MS_REF_TYPE, .local = body->next_local, .owner = scrutinee});
    body_set_type(body, arm->id, concrete);
  }
  for (uint32_t at = 0; at < arm->bindings.len; at++) {
    const MsTy ty = concrete != MS_TY_NONE ? concrete : kase != NULL ? payload(body, scrutinee, kase, at) : bare_payload(body, arm, scrutinee);
    (void)body_declare(body, arm->bindings.ptr[at].name, ty, MS_REF_LOCAL, false, arm->id, arm->pos);
    if (state->literal && arm->bare) {
      ms_local_list_last(&body->locals)->rejected = true; /* a literal match has no payload to bind: the name stays unbound */
    }
  }
  body_statements(body, arm->body); /* the arm's value reads the locals its statements declare */
  ArmScope kept = {.count = body->locals.len - mark};
  kept.locals = MS_ARENA_NEW_ARRAY(&body->program->arena, MsLocal, kept.count + 1);
  for (size_t at = 0; at < kept.count; at++) {
    kept.locals[at] = body->locals.ptr[mark + at];
  }
  body_scope_reset(body, mark);
  return kept;
}

/* The type of an arm's value, read where its statements left their locals. */
static MsTy arm_value(Body *body, const MsArm *arm, const ArmScope *kept, MsTy expected, const ArmState *state) {
  const size_t mark = body_scope_mark(body);
  for (size_t at = 0; at < kept->count; at++) {
    ms_local_list_push(&body->locals, kept->locals[at]);
  }
  /* an arm whose value differs from the type the match has so far is a mismatch, reported at that value */
  const bool settled = expected != MS_TY_NONE && !state->discarded && !body_has_foreign_variable(body, expected);
  const MsTy value = arm->value == NULL ? MS_TY_NONE
                     : settled          ? body_expect(body, arm->value, expected, (MsSpan){0})
                                        : body_expr(body, arm->value, expected);
  body_scope_reset(body, mark);
  return value;
}

/* Whether `ty` is known and a match cannot take it: not an alternative, an interface value, Int, String or Bool. */
static bool unmatchable(const Body *body, MsTy ty) {
  const MsTyTable *types = &body->program->types;
  const MsTyKind kind = (MsTyKind)ms_ty_kind(types, ty);
  if (ty == MS_TY_NONE || ms_ty_has_variable(types, ty) || ms_ty_is(types, ty, MS_BUILTIN_Never)) {
    return false;
  }
  if (kind == MS_TY_ALTERNATIVE || kind == MS_TY_CONTRACT || kind == MS_TY_INVALID || kind == MS_TY_INFERRED) {
    return false;
  }
  return !ms_ty_is(types, ty, MS_BUILTIN_Int) && !ms_ty_is(types, ty, MS_BUILTIN_String) &&
         !ms_ty_is(types, ty, MS_BUILTIN_Bool);
}

/* Reports a scrutinee no match can take; true when it did, and the arms are then left unreported. */
static bool check_scrutinee(Body *body, const MsExpr *expr, MsTy ty) {
  if (body->quiet || !body_reports(body) || !unmatchable(body, ty)) {
    return false;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "match requires an alternative, contract view, Int, String or Bool, found ");
  ms_ty_show(&text, body->program->names, &body->program->types, ty);
  ms_strbuild_append_text(&text, "; match on a type with cases, or use if/else");
  ms_check_report(body->program, body->module, expr->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
  return true;
}

/* A match over a user enum that names none of the cases it misses and has no `_` arm: the cases it misses, the
 * arms that would cover them. Arms that are not known cases leave the match to their own diagnostics. */
static void check_exhaustive(Body *body, const MsExpr *expr, MsTy scrutinee) {
  const MsDef *def = body_def(body, scrutinee);
  MsCheckProgram *program = body->program;
  if (body->quiet || !body_reports(body) || def == NULL || def->kind != MS_TY_ALTERNATIVE ||
      ms_ty_kind(&program->types, scrutinee) != MS_TY_ALTERNATIVE) {
    return;
  }
  const MsDecl *home = program->symbols.ptr[def->symbol].decl;
  if (home == NULL || home->kind != MS_D_ENUM) {
    return;
  }
  uint8_t *seen = MS_ARENA_NEW_ARRAY(&body->program->arena, uint8_t, def->cases.len + 1);
  for (uint32_t index = 0; index < expr->u.match.arms.len; index++) {
    const MsArm *arm = expr->u.match.arms.ptr[index];
    uint32_t at = 0;
    if (arm->path != NULL && arm->path->kind == MS_E_NAME &&
        ms_span_is_text(ms_names_span(program->names, arm->path->u.sym), "_")) {
      return;
    }
    if (arm->bare && ms_ty_is(&program->types, scrutinee, MS_BUILTIN_Optional)) { /* a lone name binds the payload */
      for (uint32_t kase = 0; kase < def->cases.len; kase++) {
        if (ms_span_is_text(ms_names_span(program->names, def->cases.ptr[kase].name), "some")) {
          seen[kase] = 1;
        }
      }
      continue;
    }
    if (arm_case(body, arm->path, scrutinee, &at) == NULL) {
      return;
    }
    seen[at] = 1;
  }
  MsSpanList names = {0};
  MsStrBuild arms = ms_strbuild_new();
  size_t shown = 0;
  for (size_t index = 0; index < def->cases.len; index++) {
    if (seen[index]) {
      continue;
    }
    const MsTyCase *kase = &def->cases.ptr[index];
    ms_span_list_push(&names, ms_names_span(program->names, kase->name));
    if (shown++ >= 12) {
      continue;
    }
    ms_strbuild_append_text(&arms, shown > 1 ? ", '" : "'");
    ms_strbuild_append(&arms, ms_names_span(program->names, kase->name));
    for (size_t field = 0; field < kase->fields.len; field++) {
      ms_strbuild_append_text(&arms, field == 0 ? "(" : ", ");
      ms_strbuild_append(&arms, ms_names_span(program->names, kase->fields.ptr[field].name));
    }
    ms_strbuild_append_text(&arms, kase->fields.len != 0 ? "):'" : ":'");
  }
  if (names.len != 0) {
    MsStrBuild text = ms_strbuild_new();
    ms_strbuild_append_text(&text, "non-exhaustive match; missing cases: ");
    ms_suggest_list(&text, &names, 12);
    ms_strbuild_append_text(&text, ", or add a final '_:' arm; add the arms ");
    ms_strbuild_append(&text, ms_strbuild_span(&arms));
    ms_strbuild_append_text(&text, names.len > 12 ? ", ..." : "");
    ms_check_report(program, body->module, expr->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
  }
  ms_strbuild_free(&arms);
  ms_span_list_free(&names);
}

MsTy body_match(Body *body, const MsExpr *expr, MsTy expected) {
  const MsTy scrutinee = body_expr(body, expr->u.match.scrutinee, MS_TY_NONE);
  const bool outer_quiet = body->quiet;
  body->quiet = check_scrutinee(body, expr, scrutinee) || outer_quiet;
  const MsTyTable *types = &body->program->types;
  const bool alternative = ms_ty_kind(types, scrutinee) == MS_TY_ALTERNATIVE;
  if (alternative) {
    (void)body_opaque_denied(body, expr->pos, scrutinee, ms_span_of_text("its cases cannot be matched here"));
  }
  const MsDef *def = alternative ? body_def(body, scrutinee) : NULL;
  ArmState state = {.match = expr, .scrutinee = scrutinee,
                    .literal = scrutinee != MS_TY_NONE && (ms_ty_is(types, scrutinee, MS_BUILTIN_Int) ||
                                                           ms_ty_is(types, scrutinee, MS_BUILTIN_String) ||
                                                           ms_ty_is(types, scrutinee, MS_BUILTIN_Bool)),
                    .case_count = def == NULL ? 0 : (uint32_t)def->cases.len};
  state.discarded = body->statement_match == expr;
  state.contract = ms_ty_kind(types, scrutinee) == MS_TY_CONTRACT;
  state.report = !body->quiet && body_reports(body) && (state.literal || def != NULL || state.contract);
  state.seen = MS_ARENA_NEW_ARRAY(&body->program->arena, MsName, expr->u.match.arms.len + 1);
  /* An expected type that still names an open variable guides the arms but is not the result: the arms decide it. */
  MsTy result = expected != MS_TY_NONE && body_has_foreign_variable(body, expected) ? MS_TY_NONE : expected;
  ArmScope *kept = MS_ARENA_NEW_ARRAY(&body->program->arena, ArmScope, expr->u.match.arms.len + 1);
  for (uint32_t index = 0; index < expr->u.match.arms.len; index++) {
    state.index = index;
    kept[index] = arm_statements(body, expr->u.match.arms.ptr[index], scrutinee, &state);
  }
  if (state.report && state.literal) {
    const MsName yes = ms_names_intern(body->program->names, ms_span_of_text("true"));
    const MsName no = ms_names_intern(body->program->names, ms_span_of_text("false"));
    const bool both = ms_ty_is(types, scrutinee, MS_BUILTIN_Bool) && state_seen(&state, yes) && state_seen(&state, no);
    if (!state.wildcard && !both) {
      MsStrBuild text = ms_strbuild_new();
      ms_strbuild_append_text(&text, "non-exhaustive match on ");
      ms_ty_show(&text, body->program->names, types, scrutinee);
      ms_strbuild_append_text(&text, "; add a final '_:' arm");
      ms_check_report(body->program, body->module, expr->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
    }
  }
  if (state.report && state.contract && !state.wildcard) {
    ms_check_report(body->program, body->module, expr->pos, MS_CHECK_TYPE,
                    ms_string_from_span(ms_span_of_text("contract match requires a final wildcard for other implementations; add a last '_' arm")));
  }
  check_exhaustive(body, expr, scrutinee);
  for (uint32_t index = 0; index < expr->u.match.arms.len; index++) {
    const MsTy value = arm_value(body, expr->u.match.arms.ptr[index], &kept[index], result == MS_TY_NONE ? expected : result, &state);
    result = result == MS_TY_NONE ? value : result;
  }
  body->quiet = outer_quiet;
  return result;
}
