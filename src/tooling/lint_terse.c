/* Owns the expression rules of the terse family: longer spellings of shorter forms that mean the same thing
 * (MSL118 to MSL120, MSL127, MSL129 to MSL132, MSL134, MSL135). The statement rules are in lint_terse_stmts.c. Port
 * of crates/ms-tooling/src/lint/terse.rs. */
#include "tooling/lint_terse.h"

#include "base/message.h"
#include "compiler/syntax/parse.h"

bool terse_name_is(const TerseScan *scan, MsName name, const char *text) {
  return ms_span_is_text(ms_names_span(scan->program->names, name), text);
}

bool terse_span(const TerseScan *scan, size_t from, size_t to, MsSpan *out) {
  if (from > to || to > scan->module->source.len) {
    return false;
  }
  *out = ms_span_of(scan->module->source.ptr + from, to - from);
  return true;
}

/* Whether the delimiters in `text` pair up; a parenthesized expression's span leaves one side out. */
static bool balanced(MsSpan text) {
  int64_t open = 0;
  for (size_t i = 0; i < text.len; i++) {
    const uint8_t c = text.ptr[i];
    open += (c == '(' || c == '[' || c == '{') ? 1 : ((c == ')' || c == ']' || c == '}') ? -1 : 0);
    if (open < 0) {
      return false;
    }
  }
  return open == 0;
}

bool terse_expr_text(const TerseScan *scan, const MsExpr *expr, MsSpan *out) {
  if (!terse_span(scan, ms_expr_start(expr).offset, expr->end.offset, out) || !balanced(*out)) {
    return false;
  }
  for (size_t i = 0; i < out->len; i++) {
    if (out->ptr[i] == '\n') {
      return false;
    }
  }
  return true;
}

bool terse_type_is(const TerseScan *scan, MsNode node, MsBuiltin builtin) {
  const MsTy ty = ms_facts_type(&scan->module->facts, node);
  return ty != MS_TY_NONE && ms_ty_is(&scan->program->types, ty, builtin);
}

void terse_note(const TerseScan *scan, const char *code, MsSpan message, MsPos pos) {
  (void)ms_lint_add(scan->findings, code, scan->file, pos, message);
}

void terse_report(const TerseScan *scan, const char *code, MsSpan message, MsPos pos, size_t from, size_t to,
                  MsSpan replacement) {
  MsLintFinding *found = ms_lint_add(scan->findings, code, scan->file, pos, message);
  found->has_fix = true;
  found->fix_pos = ms_lint_pos_at(scan->module->source, from);
  found->fix_end = ms_lint_pos_at(scan->module->source, to);
  found->replacement = replacement;
}

MsSpan terse_keep(const TerseScan *scan, MsStrBuild *text) {
  const MsSpan kept = ms_arena_copy(scan->arena, ms_strbuild_span(text));
  ms_strbuild_free(text);
  return kept;
}

bool terse_is_path(const MsExpr *e) {
  return e->kind == MS_E_NAME || (e->kind == MS_E_MEMBER && terse_is_path(e->u.member.left));
}

static MsSpan text_of(const char *text) {
  return ms_span_of_text(text);
}

static bool is_collection(const TerseScan *scan, const MsExpr *e) {
  return terse_type_is(scan, e->id, MS_BUILTIN_String) || terse_type_is(scan, e->id, MS_BUILTIN_List) ||
         terse_type_is(scan, e->id, MS_BUILTIN_Map) || terse_type_is(scan, e->id, MS_BUILTIN_Set);
}

static bool is_scalar_builtin(MsBuiltin builtin) {
  return (builtin >= MS_BUILTIN_Int && builtin <= MS_BUILTIN_UInt64) ||
         (builtin >= MS_BUILTIN_Float && builtin <= MS_BUILTIN_Float64) || builtin == MS_BUILTIN_Bool;
}

/* A list whose elements copy (`Int`, `Float`, `Bool`): `xs[i]` can stand where `xs.get(i)` does. */
static bool is_copy_list(const TerseScan *scan, const MsExpr *e) {
  const MsTyTable *types = &scan->program->types;
  const MsTy ty = ms_facts_type(&scan->module->facts, e->id);
  return ty != MS_TY_NONE && ms_ty_is(types, ty, MS_BUILTIN_List) && ms_ty_arg_count(types, ty) > 0 &&
         is_scalar_builtin(ms_ty_builtin(types, ms_ty_args(types, ty)[0]));
}

/* `callee.name` as a member call: its receiver, or NULL. */
static const MsExpr *member_call(const TerseScan *scan, const MsExpr *e, const char *method, size_t arguments) {
  if (e->kind != MS_E_CALL || e->u.call.callee->kind != MS_E_MEMBER || e->u.call.args.len != arguments ||
      !terse_name_is(scan, e->u.call.callee->u.member.name, method)) {
    return NULL;
  }
  return e->u.call.callee->u.member.left;
}

/* `recv.length()` as its receiver. */
static const MsExpr *length_of(const TerseScan *scan, const MsExpr *e) {
  const MsExpr *receiver = member_call(scan, e, "length", 0);
  return receiver != NULL && is_collection(scan, receiver) ? receiver : NULL;
}

/* `x.length() == 0` and, in a condition, `x.length() != 0` / `> 0`. */
void terse_emptiness(const TerseScan *scan, const MsExpr *e, bool condition) {
  if (e->kind != MS_E_BINARY) {
    return;
  }
  if (e->op == MS_B_AND || e->op == MS_B_OR) {
    terse_emptiness(scan, e->u.bin.left, condition);
    terse_emptiness(scan, e->u.bin.right, condition);
    return;
  }
  const MsExpr *right = e->u.bin.right;
  const bool zero = right->kind == MS_E_NUMBER && terse_name_is(scan, right->u.sym, "0");
  const MsExpr *receiver = zero ? length_of(scan, e->u.bin.left) : NULL;
  MsSpan recv = {0};
  if (receiver == NULL || !terse_expr_text(scan, receiver, &recv)) {
    return;
  }
  const bool equal = e->op == MS_B_EQ && !condition;
  if (!equal && !((e->op == MS_B_NE || e->op == MS_B_GT) && condition)) {
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, equal ? "" : "not ");
  ms_strbuild_append(&text, recv);
  ms_strbuild_append_text(&text, ".is_empty()");
  terse_report(scan, "MSL118", text_of("Use is_empty() instead of comparing length() with 0"), e->pos,
               ms_expr_start(e).offset, right->end.offset, terse_keep(scan, &text));
}

/* `xs.get(i)` on a list held in a name or field is `xs[i]`. */
static void list_get(const TerseScan *scan, const MsExpr *e) {
  const MsExpr *left = member_call(scan, e, "get", 1);
  if (left == NULL) {
    return;
  }
  const MsExpr *callee = e->u.call.callee;
  const MsArg *arg = &e->u.call.args.ptr[0];
  if (arg->has_name || (left->kind != MS_E_NAME && left->kind != MS_E_MEMBER) || !is_copy_list(scan, left)) {
    return;
  }
  MsSpan index = {0};
  const size_t name_at = callee->pos.offset;
  if (name_at == 0 || !terse_expr_text(scan, arg->value, &index)) {
    return;
  }
  const size_t dot = name_at - 1;
  /* `xs\n    .get(i)` would become `xs\n    [i]`, an indented line that opens no block. */
  if (dot >= scan->module->source.len || scan->module->source.ptr[dot] != '.' || left->end.offset != dot) {
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_byte(&text, '[');
  ms_strbuild_append(&text, index);
  ms_strbuild_append_byte(&text, ']');
  terse_report(scan, "MSL119", text_of("Index the list with xs[i] instead of xs.get(i)"), e->pos, dot, e->end.offset,
               terse_keep(scan, &text));
}

/* `m.get(k).get_or(d)` on a map is `m.get_or(k, d)`. */
static void map_get_chain(const TerseScan *scan, const MsExpr *e) {
  const MsExpr *inner = member_call(scan, e, "get_or", 1);
  const MsExpr *map = inner == NULL ? NULL : member_call(scan, inner, "get", 1);
  if (map == NULL || !terse_type_is(scan, map->id, MS_BUILTIN_Map)) {
    return;
  }
  const MsArg *fallback = &e->u.call.args.ptr[0];
  const MsArg *key = &inner->u.call.args.ptr[0];
  if (key->has_name || fallback->has_name) {
    return;
  }
  const size_t name_at = inner->u.call.callee->pos.offset;
  MsSpan k = {0};
  MsSpan d = {0};
  MsSpan between = {0};
  if (name_at == 0 || !terse_expr_text(scan, key->value, &k) || !terse_expr_text(scan, fallback->value, &d) ||
      !terse_span(scan, name_at - 1, e->end.offset, &between) || between.ptr[0] != '.') {
    return;
  }
  /* The edit replaces everything between the two calls, so a comment there would be lost. */
  size_t at = 0;
  if (ms_span_find(between, text_of("//"), &at) || ms_span_find(between, text_of("/*"), &at)) {
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, ".get_or(");
  ms_strbuild_append(&text, k);
  ms_strbuild_append_text(&text, ", ");
  ms_strbuild_append(&text, d);
  ms_strbuild_append_byte(&text, ')');
  terse_report(scan, "MSL120", text_of("Use map.get_or(key, default) instead of map.get(key).get_or(default)"), e->pos,
               name_at - 1, e->end.offset, terse_keep(scan, &text));
}

/* `xs.slice(a, b).get_or(fallback)` turns a range past the end into the fallback without a trace. */
static void slice_fallback(const TerseScan *scan, const MsExpr *e) {
  if (e->kind != MS_E_CALL || e->u.call.callee->kind != MS_E_MEMBER ||
      !terse_name_is(scan, e->u.call.callee->u.member.name, "get_or")) {
    return;
  }
  const MsExpr *inner = e->u.call.callee->u.member.left;
  if (inner->kind != MS_E_CALL || inner->u.call.callee->kind != MS_E_MEMBER ||
      !terse_name_is(scan, inner->u.call.callee->u.member.name, "slice") ||
      !terse_type_is(scan, inner->id, MS_BUILTIN_Result)) {
    return;
  }
  terse_note(scan, "MSL132",
             text_of("`slice(..).get_or(..)` returns the fallback for any bad range, including an end past the length; "
                     "use `?` to report it, or clamp the end with `min(end, xs.length())` first"),
             e->pos);
}

static bool is_void_call(const TerseScan *scan, const MsExpr *e) {
  return e->kind == MS_E_CALL && terse_type_is(scan, e->id, MS_BUILTIN_Void);
}

/* `print(xs.sort())` and `f"{xs.reverse()}"` print `void` instead of the changed list. */
static void printed_void(const TerseScan *scan, const MsExpr *e) {
  if (e->kind != MS_E_CALL || e->u.call.callee->kind != MS_E_NAME || e->u.call.args.len != 1 ||
      !terse_name_is(scan, e->u.call.callee->u.sym, "print")) {
    return;
  }
  const MsExpr *arg = e->u.call.args.ptr[0].value;
  if (is_void_call(scan, arg)) {
    terse_note(scan, "MSL134",
               text_of("this prints `void`: the call returns nothing, and sort() and reverse() change their receiver in "
                       "place; call it as a statement, then print the list"),
               arg->pos);
  }
}

/* `bytes.to_string()` renders `Bytes(104, 105)`, not the text; `decode_utf8()` reads the text. */
static void bytes_to_string(const TerseScan *scan, const MsExpr *e) {
  const MsExpr *left = member_call(scan, e, "to_string", 0);
  if (left != NULL && terse_type_is(scan, left->id, MS_BUILTIN_Bytes)) {
    terse_note(scan, "MSL135",
               text_of("`to_string()` on Bytes gives `Bytes(104, 105)`, not the text; `decode_utf8()` returns the text as "
                       "a `String?`, so write `.decode_utf8().ok_or(Error(\"not UTF-8\", kind: \"EBADMSG\"))?`"),
               e->pos);
  }
}

/* `ys := xs.sort()` binds Void: `sort` and `reverse` change the receiver in place and return nothing. */
static void bound_void(const TerseScan *scan, const MsStmt *s) {
  const MsPattern *pattern = s->u.bind.pattern;
  if (pattern->kind != MS_P_NAME || !is_void_call(scan, s->u.bind.value)) {
    return;
  }
  const MsSpan name = ms_names_span(scan->program->names, pattern->u.name);
  if (name.len > 0 && name.ptr[0] == '_') {
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_byte(&text, '`');
  ms_strbuild_append(&text, name);
  ms_strbuild_append_text(&text, "` would hold Void: the call returns nothing, and sort() and reverse() change their "
                                 "receiver in place; call it as a statement, or use sorted() or reversed() for a new "
                                 "list");
  terse_note(scan, "MSL134", terse_keep(scan, &text), s->u.bind.value->pos);
}

/* `print(call())` on a Result prints the wrapper, so the call's success value is what was meant. */
static void printed_result(const TerseScan *scan, const MsExpr *e) {
  if (e->kind != MS_E_CALL || e->u.call.callee->kind != MS_E_NAME || e->u.call.args.len != 1 ||
      !terse_name_is(scan, e->u.call.callee->u.sym, "print") ||
      !terse_type_is(scan, e->u.call.args.ptr[0].value->id, MS_BUILTIN_Result)) {
    return;
  }
  terse_note(scan, "MSL131",
             text_of("`print` of a Result shows the `ok(...)` wrapper; write `call()?` in a function that returns a "
                     "Result, or `if value := call():` to read the success"),
             e->pos);
}

/* The source offset where the chain `e` starts: the name its leftmost receiver is read from. */
static size_t leftmost(const MsExpr *e) {
  MsExpr *left = NULL;
  MsExpr *index = NULL;
  if (e->kind == MS_E_CALL) {
    return leftmost(e->u.call.callee);
  }
  if (e->kind == MS_E_MEMBER) {
    return leftmost(e->u.member.left);
  }
  return ms_expr_index(e, &left, &index) ? leftmost(left) : e->pos.offset;
}

/* A statement `r.get(null)` on a `Void!` is `void r`; a statement `r.get()` on a Result faults on error, so it is
 * `r?` where the function can return one. */
static void statement_get(const TerseScan *scan, const MsExpr *e) {
  if (e->kind != MS_E_CALL || e->u.call.callee->kind != MS_E_MEMBER) {
    return;
  }
  const MsExpr *left = e->u.call.callee->u.member.left;
  const bool get = terse_name_is(scan, e->u.call.callee->u.member.name, "get");
  if (!get && !terse_name_is(scan, e->u.call.callee->u.member.name, "get_or")) {
    return;
  }
  const MsTyTable *types = &scan->program->types;
  const MsTy ty = ms_facts_type(&scan->module->facts, left->id);
  MsSpan receiver = {0};
  if (ty == MS_TY_NONE || !ms_ty_is(types, ty, MS_BUILTIN_Result) || !terse_expr_text(scan, left, &receiver)) {
    return;
  }
  if (!get && e->u.call.args.len == 1) {
    const MsArg *arg = &e->u.call.args.ptr[0];
    MsSpan written = {0};
    if (!arg->has_name && terse_expr_text(scan, arg->value, &written) && ms_span_is_text(written, "null") &&
        ms_ty_arg_count(types, ty) > 0 && ms_ty_is(types, ms_ty_args(types, ty)[0], MS_BUILTIN_Void)) {
      MsStrBuild text = ms_strbuild_new();
      ms_strbuild_append_text(&text, "void ");
      ms_strbuild_append(&text, receiver);
      terse_report(scan, "MSL129",
                   text_of("Use `void result` to ignore a Void! outcome instead of result.get_or(null)"), e->pos,
                   leftmost(left), e->end.offset, terse_keep(scan, &text));
    }
  } else if (get && e->u.call.args.len == 0) {
    terse_note(scan, "MSL130",
               text_of("A statement `result.get()` faults when the call fails; write `call()?` in a function that "
                       "returns a Result (`main` can return `Void!`), or `void call()` to ignore the outcome"),
               e->pos);
  }
}

/* `m[k.clone()] = m.get(k).get() op rest` on a map is `m[k] op= rest`: both fault when the key is missing, and the
 * compound form needs no clone of the key. */
static void map_update(const TerseScan *scan, const MsStmt *s) {
  const MsExpr *call = s->u.expr;
  const MsExpr *map = call == NULL ? NULL : member_call(scan, call, MS_INDEX_SET, 2);
  if (map == NULL || call->u.call.args.ptr[0].has_name || !terse_is_path(map) ||
      !terse_type_is(scan, map->id, MS_BUILTIN_Map)) {
    return;
  }
  const MsExpr *value = call->u.call.args.ptr[1].value;
  static const char *const SYMBOLS[] = {[MS_B_ADD] = "+=", [MS_B_SUB] = "-=", [MS_B_MUL] = "*=", [MS_B_DIV] = "/=",
                                        [MS_B_REM] = "%="};
  if (value->kind != MS_E_BINARY || value->op < MS_B_ADD || value->op > MS_B_REM) {
    return;
  }
  /* `map.get(key).get()` */
  const MsExpr *lookup = member_call(scan, value->u.bin.left, "get", 0);
  const MsExpr *again = lookup == NULL ? NULL : member_call(scan, lookup, "get", 1);
  if (again == NULL) {
    return;
  }
  const MsArg *key = &lookup->u.call.args.ptr[0];
  if (key->has_name || !terse_is_path(key->value)) {
    return;
  }
  MsSpan map_text = {0};
  MsSpan again_text = {0};
  MsSpan key_text = {0};
  MsSpan index_text = {0};
  MsSpan rest = {0};
  if (!terse_expr_text(scan, map, &map_text) || !terse_expr_text(scan, again, &again_text) ||
      !terse_expr_text(scan, key->value, &key_text) ||
      !terse_expr_text(scan, call->u.call.args.ptr[0].value, &index_text) ||
      !terse_expr_text(scan, value->u.bin.right, &rest)) {
    return;
  }
  MsStrBuild cloned = ms_strbuild_new();
  ms_strbuild_append(&cloned, key_text);
  ms_strbuild_append_text(&cloned, ".clone()");
  const bool same_index = ms_span_equal(index_text, key_text) || ms_span_equal(index_text, ms_strbuild_span(&cloned));
  ms_strbuild_free(&cloned);
  const size_t from = s->pos.offset;
  const size_t to = value->u.bin.right->end.offset;
  MsSpan whole = {0};
  size_t at = 0;
  if (!ms_span_equal(map_text, again_text) || !same_index || !terse_span(scan, from, to, &whole) ||
      ms_span_find(whole, text_of("//"), &at) || ms_span_find(whole, text_of("\n"), &at)) {
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append(&text, map_text);
  ms_strbuild_append_byte(&text, '[');
  ms_strbuild_append(&text, key_text);
  ms_strbuild_printf(&text, "] %s ", SYMBOLS[value->op]);
  ms_strbuild_append(&text, rest);
  terse_report(scan, "MSL127", text_of("Update the map entry in place with `m[k] op= value`"), s->pos, from, to,
               terse_keep(scan, &text));
}

void terse_stmt(const TerseScan *scan, const MsStmt *s) {
  if (s->kind == MS_S_IF && s->u.branch.binding == NULL) {
    terse_emptiness(scan, s->u.branch.cond, true);
  } else if (s->kind == MS_S_WHILE) {
    terse_emptiness(scan, s->u.loop.cond, true);
  } else if (s->kind == MS_S_RETURN && s->u.expr != NULL) {
    terse_emptiness(scan, s->u.expr, true);
  } else if (s->kind == MS_S_CALL) {
    statement_get(scan, s->u.expr);
    printed_result(scan, s->u.expr);
  } else if (s->kind == MS_S_BIND) {
    bound_void(scan, s);
  }
  if (s->kind == MS_S_CALL) {
    map_update(scan, s);
  }
}

void terse_expr(const TerseScan *scan, const MsExpr *e) {
  if (e->kind == MS_E_BINARY && e->op == MS_B_EQ) {
    terse_emptiness(scan, e, false);
  }
  map_get_chain(scan, e);
  slice_fallback(scan, e);
  printed_void(scan, e);
  bytes_to_string(scan, e);
  list_get(scan, e);
}
