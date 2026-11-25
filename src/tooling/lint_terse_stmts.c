/* Owns the statement rules of the terse family: a default then an override (MSL121), a counter written as a while
 * (MSL122), an index loop (MSL123), loops that append or add (MSL124, MSL125), a binding returned on the next line
 * (MSL126) and a final return the function already makes (MSL128); and the entry point that runs every terse rule
 * over a module. */
#include <stdlib.h>

#include "base/message.h"
#include "tooling/lint_terse.h"

static MsSpan text_of(const char *text) {
  return ms_span_of_text(text);
}

/* ---- how a name is used in a piece of the tree ---- */

typedef struct Uses {
  const TerseScan *scan;
  MsName name;
  size_t reads, writes;
} Uses;

static void uses_stmt(void *context, const MsStmt *s) {
  Uses *uses = context;
  if (s->kind == MS_S_ASSIGN && !s->u.assign.member_target && s->u.assign.name == uses->name) {
    uses->writes++;
  }
}

/* A `var` argument passes the variable for the callee to change. */
static void uses_call(Uses *uses, const MsExpr *e) {
  const MsCall *call = ms_facts_call(&uses->scan->module->facts, e->id);
  for (uint32_t i = 0; call != NULL && i < e->u.call.args.len; i++) {
    const MsExpr *value = e->u.call.args.ptr[i].value;
    for (uint32_t k = 0; k < call->arg_count; k++) {
      if (call->args[k].source == MS_ARG_WRITTEN && call->args[k].node.node == value->id &&
          (call->args[k].flags & MS_PARAM_VAR) != 0 && value->kind == MS_E_NAME && value->u.sym == uses->name) {
        uses->writes++;
      }
    }
  }
}

static void uses_expr(void *context, const MsExpr *e) {
  Uses *uses = context;
  if (e->kind == MS_E_NAME && e->u.sym == uses->name) {
    uses->reads++;
  } else if (e->kind == MS_E_CALL) {
    uses_call(uses, e);
  }
}

static Uses uses_in(const TerseScan *scan, MsName name, const MsStmt *const *stmts, size_t count) {
  Uses uses = {.scan = scan, .name = name};
  const MsVisitor visitor = {.ctx = &uses, .stmt = uses_stmt, .expr = uses_expr};
  for (size_t i = 0; i < count; i++) {
    ms_walk_stmt(&visitor, stmts[i]);
  }
  return uses;
}

static size_t expr_reads(const TerseScan *scan, MsName name, const MsExpr *e) {
  Uses uses = {.scan = scan, .name = name};
  const MsVisitor visitor = {.ctx = &uses, .stmt = uses_stmt, .expr = uses_expr};
  ms_walk_expr(&visitor, e);
  return uses.reads;
}

static void has_call_expr(void *context, const MsExpr *e) {
  if (e->kind == MS_E_CALL) {
    *(bool *)context = true;
  }
}

/* Whether any call runs inside `e`. */
static bool has_call(const MsExpr *e) {
  bool found = false;
  const MsVisitor visitor = {.ctx = &found, .expr = has_call_expr};
  ms_walk_expr(&visitor, e);
  return found;
}

static void has_probe_expr(void *context, const MsExpr *e) {
  if (e->kind == MS_E_PROBE || (e->kind == MS_E_UNARY && e->op == MS_U_TRY)) {
    *(bool *)context = true;
  }
}

/* Whether a `?` can leave the function from inside `s`: such a loop is no `map`, which cannot return early. */
static bool has_probe(const MsStmt *s) {
  bool found = false;
  const MsVisitor visitor = {.ctx = &found, .expr = has_probe_expr};
  ms_walk_stmt(&visitor, s);
  return found;
}

/* Whether the function being walked is called `name`: inside it the rewrite the rule suggests would call itself. */
static bool inside(const TerseScan *scan, const char *name) {
  return scan->enclosing != 0 && terse_name_is(scan, scan->enclosing, name);
}

/* ---- small helpers ---- */

static bool is_trim_space(uint8_t c) {
  return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

static bool blank(MsSpan text) {
  for (size_t i = 0; i < text.len; i++) {
    if (!is_trim_space(text.ptr[i])) {
      return false;
    }
  }
  return true;
}

static bool contains(MsSpan text, const char *part) {
  size_t at = 0;
  return ms_span_find(text, ms_span_of_text(part), &at);
}

static bool plain_number(const TerseScan *scan, const MsExpr *e) {
  MsSpan text = {0};
  if (e->kind != MS_E_NUMBER || !terse_span(scan, ms_expr_start(e).offset, e->end.offset, &text) || text.len == 0) {
    return false;
  }
  for (size_t i = 0; i < text.len; i++) {
    if (text.ptr[i] < '0' || text.ptr[i] > '9') {
      return false;
    }
  }
  return true;
}

static bool is_name(const MsExpr *e, MsName name) {
  return e->kind == MS_E_NAME && e->u.sym == name;
}

/* The statement as a `var`/`let` of a plain name: its name, or 0. */
static MsName bound_name(const MsStmt *s) {
  return s->kind == MS_S_BIND && s->u.bind.pattern->kind == MS_P_NAME ? s->u.bind.pattern->u.name : 0;
}

static bool is_mutable_binding(const TerseScan *scan, const MsExpr *name) {
  const MsRef *ref = ms_facts_ref(&scan->module->facts, name->id);
  if (ref == NULL || (ref->kind != MS_REF_LOCAL && ref->kind != MS_REF_PARAM)) {
    return false;
  }
  for (size_t i = 0; i < scan->mutable_count; i++) {
    if (scan->mutable_ids[i] == ref->decl.node) {
      return true;
    }
  }
  return false;
}

static const MsStmt *const *stmts_from(MsStmts body, size_t from) {
  return (const MsStmt *const *)body.ptr + from;
}

/* `var x = a` then `if c { x = b }` is `x := if c { b } else { a }`. */
static void default_then_reassign(const TerseScan *scan, MsStmts body, size_t at) {
  if (at + 1 >= body.len) {
    return;
  }
  const MsStmt *first = body.ptr[at];
  const MsStmt *second = body.ptr[at + 1];
  const MsName name = bound_name(first);
  if (name == 0 || !first->u.bind.is_mutable || first->u.bind.ty != NULL || first->u.bind.has_group ||
      second->kind != MS_S_IF || second->u.branch.binding != NULL || second->u.branch.body.len != 1 ||
      second->u.branch.else_body.len != 0) {
    return;
  }
  const MsExpr *def = first->u.bind.value;
  const MsExpr *cond = second->u.branch.cond;
  const MsStmt *only = second->u.branch.body.ptr[0];
  if (only->kind != MS_S_ASSIGN || only->u.assign.member_target || only->u.assign.has_compound) {
    return;
  }
  const MsExpr *replacement = only->u.assign.value;
  bool simple = def->kind == MS_E_NUMBER || def->kind == MS_E_BOOL || def->kind == MS_E_NAME;
  if (def->kind == MS_E_TEXT) {
    simple = true;
    for (uint32_t i = 0; i < def->u.text.len; i++) {
      simple = simple && def->u.text.ptr[i].expr == NULL;
    }
  }
  const bool scalar = terse_type_is(scan, def->id, MS_BUILTIN_String) || terse_type_is(scan, def->id, MS_BUILTIN_Int) ||
                      terse_type_is(scan, def->id, MS_BUILTIN_Float) || terse_type_is(scan, def->id, MS_BUILTIN_Bool);
  /* `x := if c { b } else { a }` reads `a` after `c` runs; a call in `c` can change a `var` `a`. */
  const bool moves = def->kind == MS_E_NAME && is_mutable_binding(scan, def) && has_call(cond);
  const Uses later = uses_in(scan, name, stmts_from(body, at + 2), body.len - at - 2);
  const size_t in_cond = expr_reads(scan, name, cond) + expr_reads(scan, name, replacement);
  if (only->u.assign.name != name || !simple || !scalar || moves || later.writes > 0 || in_cond > 0) {
    return;
  }
  const size_t from = first->pos.offset;
  const MsSpan source = scan->module->source;
  size_t to = replacement->end.offset; /* the `if` ends at the brace that closes its single statement */
  while (to < source.len && (source.ptr[to] == ' ' || source.ptr[to] == '\t' || source.ptr[to] == '\n' || source.ptr[to] == '\r')) {
    to++;
  }
  if (to >= source.len || source.ptr[to] != '}') {
    return;
  }
  to++;
  MsSpan whole = {0};
  MsSpan a = {0};
  MsSpan c = {0};
  MsSpan b = {0};
  if (!terse_span(scan, from, to, &whole) || !terse_expr_text(scan, def, &a) || !terse_expr_text(scan, cond, &c) ||
      !terse_expr_text(scan, replacement, &b) || contains(whole, "//")) {
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append(&text, ms_names_span(scan->program->names, name));
  ms_strbuild_append_text(&text, " := if ");
  ms_strbuild_append(&text, c);
  ms_strbuild_append_text(&text, " { ");
  ms_strbuild_append(&text, b);
  ms_strbuild_append_text(&text, " } else { ");
  ms_strbuild_append(&text, a);
  ms_strbuild_append_text(&text, " }");
  terse_report(scan, "MSL121", text_of("Write the default and the override as one `x := if c { b } else { a }`"), first->pos,
               from, to, terse_keep(scan, &text));
}

/* `ok()` or `ok(void)`. */
static bool ok_unit(const TerseScan *scan, const MsExpr *e) {
  if (e->kind != MS_E_CALL || e->u.call.callee->kind != MS_E_NAME ||
      !terse_name_is(scan, e->u.call.callee->u.sym, "ok")) {
    return false;
  }
  const size_t count = e->u.call.args.len;
  return count == 0 || (count == 1 && !e->u.call.args.ptr[0].has_name && e->u.call.args.ptr[0].value->kind == MS_E_VOID);
}

static bool is_void_type(const TerseScan *scan, const MsTypeRef *type) {
  return type != NULL && type->kind == MS_TYPE_NAMED && terse_name_is(scan, type->name, "Void");
}

/* A final `return ok(unit)` in a `Void!` function, or `return` in a `Void` one: the end of the body already
 * returns it. */
static void terse_trailing_return(TerseScan *scan, const MsFunc *func) {
  const MsTypeRef *result_type = func->result;
  if (result_type == NULL || result_type->kind != MS_TYPE_NAMED) {
    return;
  }
  const bool result = terse_name_is(scan, result_type->name, "Result") && result_type->args.len == 2 &&
                      is_void_type(scan, result_type->args.ptr[0]);
  if (func->body.len < 2 || !(result || is_void_type(scan, result_type))) {
    return;
  }
  const MsStmt *last = func->body.ptr[func->body.len - 1];
  if (last->kind != MS_S_RETURN) {
    return;
  }
  const MsExpr *value = last->u.expr;
  const bool redundant = value == NULL || value->kind == MS_E_VOID ? !result : (result && ok_unit(scan, value));
  if (!redundant) {
    return;
  }
  const MsSpan source = scan->module->source;
  size_t from = last->pos.offset;
  size_t to = value == NULL ? from + 6 : value->end.offset;
  while (from > 0 && source.ptr[from - 1] == ' ') {
    from--;
  }
  if (to < source.len && source.ptr[to] == '\r' && to + 1 < source.len && source.ptr[to + 1] == '\n') {
    to += 2;
  } else if (to < source.len && source.ptr[to] == '\n') {
    to += 1;
  }
  MsSpan line = {0};
  if (!terse_span(scan, from, to, &line) || contains(line, "//") || from == 0 || source.ptr[from - 1] != '\n') {
    return;
  }
  terse_report(scan, "MSL128", text_of("Drop the final return: the end of the function already returns it"), last->pos,
               from, to, (MsSpan){0});
}

/* `let x = e` directly followed by `return x` is `return e`. */
static void temp_return(const TerseScan *scan, MsStmts body, size_t at) {
  if (at + 1 >= body.len) {
    return;
  }
  const MsStmt *first = body.ptr[at];
  const MsStmt *second = body.ptr[at + 1];
  const MsName name = bound_name(first);
  if (name == 0 || first->u.bind.ty != NULL || first->u.bind.has_group || second->kind != MS_S_RETURN ||
      second->u.expr == NULL || !is_name(second->u.expr, name)) {
    return;
  }
  const size_t from = first->pos.offset;
  const size_t to = second->u.expr->end.offset;
  MsSpan whole = {0};
  MsSpan value = {0};
  if (!terse_span(scan, from, to, &whole) || !terse_expr_text(scan, first->u.bind.value, &value) ||
      contains(whole, "//")) {
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "return ");
  ms_strbuild_append(&text, value);
  terse_report(scan, "MSL126", text_of("Return the value directly instead of binding it first"), first->pos, from, to,
               terse_keep(scan, &text));
}

/* The index just past the last '\n' before `offset`, or 0. */
static size_t line_start(MsSpan source, size_t offset) {
  while (offset > 0 && source.ptr[offset - 1] != '\n') {
    offset--;
  }
  return offset;
}

static MsSpan trim_start(MsSpan text) {
  size_t i = 0;
  while (i < text.len && is_trim_space(text.ptr[i])) {
    i++;
  }
  return ms_span_of(text.ptr + i, text.len - i);
}

/* The statement is `name += 1` or `name = name + 1`; the step expression, or NULL. */
static const MsExpr *counter_step(const TerseScan *scan, const MsStmt *last, MsName name) {
  if (last->kind != MS_S_ASSIGN || last->u.assign.member_target || last->u.assign.name != name) {
    return NULL;
  }
  const MsExpr *step = last->u.assign.value;
  MsSpan one = {0};
  if (step->kind != MS_E_BINARY || step->op != MS_B_ADD || !is_name(step->u.bin.left, name) ||
      !terse_expr_text(scan, step->u.bin.right, &one) || !ms_span_is_text(one, "1")) {
    return NULL;
  }
  return step;
}

/* The `var i = 0` statement before the loop at `at`, as an index into `body`, or SIZE_MAX. */
static size_t counter_bind(MsStmts body, size_t at, MsName name) {
  for (size_t i = at; i-- > 0;) {
    if (bound_name(body.ptr[i]) == name) {
      return i;
    }
  }
  return SIZE_MAX;
}

/* `var i = 0` / `while i < n { ... }` ... `i += 1` is `for i in 0..n { ... }`. */
static void counter_while(const TerseScan *scan, MsStmts body, size_t at) {
  const MsStmt *loop = body.ptr[at];
  if (loop->kind != MS_S_WHILE || loop->u.loop.cond->kind != MS_E_BINARY || loop->u.loop.cond->op != MS_B_LT ||
      loop->u.loop.cond->u.bin.left->kind != MS_E_NAME || loop->u.loop.body.len == 0) {
    return;
  }
  const MsExpr *bound = loop->u.loop.cond->u.bin.right;
  const MsName name = loop->u.loop.cond->u.bin.left->u.sym;
  const size_t bind_at = counter_bind(body, at, name);
  if (bind_at == SIZE_MAX) {
    return;
  }
  const MsStmt *first = body.ptr[bind_at];
  if (!first->u.bind.is_mutable || first->u.bind.ty != NULL || first->u.bind.has_group ||
      !plain_number(scan, first->u.bind.value)) {
    return;
  }
  const MsExpr *start = first->u.bind.value;
  const Uses between = uses_in(scan, name, stmts_from(body, bind_at + 1), at - bind_at - 1);
  if (between.reads + between.writes > 0) {
    return;
  }
  const MsStmts inner = {.ptr = loop->u.loop.body.ptr, .len = loop->u.loop.body.len - 1};
  const MsStmt *last = loop->u.loop.body.ptr[inner.len];
  const MsExpr *step = counter_step(scan, last, name);
  if (step == NULL) {
    return;
  }
  const bool invariant = plain_number(scan, bound) ||
                         (bound->kind == MS_E_NAME &&
                          uses_in(scan, bound->u.sym, stmts_from(inner, 0), inner.len).writes == 0);
  const Uses inside = uses_in(scan, name, stmts_from(inner, 0), inner.len);
  const Uses after = uses_in(scan, name, stmts_from(body, at + 1), body.len - at - 1);
  const MsSpan source = scan->module->source;
  const size_t while_at = loop->pos.offset;
  const size_t bind_line = line_start(source, first->pos.offset);
  const bool bind_alone = blank(ms_span_of(source.ptr + bind_line, first->pos.offset - bind_line));
  const size_t bind_end = start->end.offset;
  size_t bind_eol = bind_end;
  while (bind_eol < source.len && source.ptr[bind_eol] != '\n') {
    bind_eol++;
  }
  MsSpan s_text = {0};
  MsSpan n_text = {0};
  if (!terse_expr_text(scan, start, &s_text) || !terse_expr_text(scan, bound, &n_text) || bind_eol >= source.len) {
    return;
  }
  const MsSpan colon = trim_start(ms_span_of(source.ptr + bound->end.offset, source.len - bound->end.offset));
  const size_t header_end = source.len - colon.len + 1;
  const size_t last_line = line_start(source, last->pos.offset);
  const bool last_alone = blank(ms_span_of(source.ptr + last_line, last->pos.offset - last_line));
  const size_t step_end = step->end.offset;
  size_t eol = step_end;
  while (eol < source.len && source.ptr[eol] != '\n') {
    eol++;
  }
  MsSpan whole = {0};
  if (!terse_span(scan, bind_line, step_end, &whole) || !invariant || inside.writes > 0 ||
      after.reads + after.writes > 0 || colon.len == 0 || colon.ptr[0] != ':' || !bind_alone ||
      !blank(ms_span_of(source.ptr + bind_end, bind_eol - bind_end)) || !last_alone ||
      !blank(ms_span_of(source.ptr + step_end, eol - step_end)) || contains(whole, "//") ||
      contains(whole, "continue") || header_end > last_line) {
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append(&text, ms_span_of(source.ptr + bind_eol + 1, while_at - (bind_eol + 1)));
  ms_strbuild_append_text(&text, "for ");
  ms_strbuild_append(&text, ms_names_span(scan->program->names, name));
  ms_strbuild_append_text(&text, " in ");
  ms_strbuild_append(&text, s_text);
  ms_strbuild_append_text(&text, "..");
  ms_strbuild_append(&text, n_text);
  ms_strbuild_append_byte(&text, ':');
  ms_strbuild_append(&text, ms_span_of(source.ptr + header_end, last_line - header_end));
  MsSpan whole_text = ms_strbuild_span(&text);
  while (whole_text.len > 0 && (whole_text.ptr[whole_text.len - 1] == '\r' || whole_text.ptr[whole_text.len - 1] == '\n')) {
    whole_text.len--;
  }
  size_t tail = eol;
  while (tail > step_end && source.ptr[tail - 1] == '\r') {
    tail--;
  }
  const MsSpan replacement = ms_arena_copy(scan->arena, whole_text);
  ms_strbuild_free(&text);
  /* The line's own `\r` stays in place, so the break keeps its CRLF. */
  terse_report(scan, "MSL122",
               text_of("Count with `for i in start..end { ... }` instead of a `var` and a `while` with `i += 1`"), first->pos,
               bind_line, tail, replacement);
}

/* The furthest end offset of any expression below a statement. */
static void ends_expr(void *context, const MsExpr *e) {
  size_t *end = context;
  *end = e->end.offset > *end ? e->end.offset : *end;
}

static size_t body_end(MsStmts body) {
  size_t end = 0;
  for (uint32_t i = 0; i < body.len; i++) {
    size_t stmt_end = body.ptr[i]->pos.offset;
    const MsVisitor visitor = {.ctx = &stmt_end, .expr = ends_expr};
    ms_walk_stmt(&visitor, body.ptr[i]);
    end = stmt_end > end ? stmt_end : end;
  }
  return end;
}

static bool name_char(uint8_t c) {
  return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' || c >= 0x80;
}

/* How often `pattern` occurs in `text`, without overlaps. */
static size_t count_in(MsSpan text, MsSpan pattern) {
  size_t count = 0;
  for (size_t i = 0; pattern.len > 0 && i + pattern.len <= text.len;) {
    if (ms_span_equal(ms_span_of(text.ptr + i, pattern.len), pattern)) {
      count++;
      i += pattern.len;
    } else {
      i++;
    }
  }
  return count;
}

/* `for i in 0..xs.length() { ... }` that only reads `xs[i]` is `for x in xs { ... }`. */
static void index_loop(const TerseScan *scan, const MsStmt *s) {
  if (s->kind != MS_S_FOR) {
    return;
  }
  MsSpan text = {0};
  if (!terse_expr_text(scan, s->u.each.iter, &text) || !ms_span_starts_with(text, text_of("0..")) ||
      !ms_span_ends_with(text, text_of(".length()"))) {
    return;
  }
  const MsSpan list = ms_span_of(text.ptr + 3, text.len >= 12 ? text.len - 12 : 0);
  bool plain = list.len > 0;
  for (size_t i = 0; i < list.len; i++) {
    plain = plain && name_char(list.ptr[i]);
  }
  if (!plain) {
    return;
  }
  const MsName name = s->u.each.name;
  const Uses uses = uses_in(scan, name, stmts_from(s->u.each.body, 0), s->u.each.body.len);
  MsSpan region = {0};
  MsStrBuild pattern = ms_strbuild_new();
  ms_strbuild_append(&pattern, list);
  ms_strbuild_append_byte(&pattern, '[');
  ms_strbuild_append(&pattern, ms_names_span(scan->program->names, name));
  ms_strbuild_append_byte(&pattern, ']');
  const size_t indexed = terse_span(scan, s->pos.offset, body_end(s->u.each.body), &region)
                             ? count_in(region, ms_strbuild_span(&pattern))
                             : 0;
  ms_strbuild_free(&pattern);
  if (uses.reads > 0 && uses.reads == indexed && !inside(scan, "for_each")) {
    MsStrBuild message = ms_strbuild_new();
    ms_strbuild_append_text(&message, "Loop over the list directly: `for item in ");
    ms_strbuild_append(&message, list);
    ms_strbuild_append_text(&message, ":` instead of indexing ");
    ms_strbuild_append(&message, list);
    ms_strbuild_append_byte(&message, '[');
    ms_strbuild_append(&message, ms_names_span(scan->program->names, name));
    ms_strbuild_append_byte(&message, ']');
    terse_note(scan, "MSL123", terse_keep(scan, &message), s->pos);
  }
}

/* `name.append(x)` as a statement. */
static bool appends_to(const TerseScan *scan, const MsStmt *s, MsName name) {
  if (s->kind != MS_S_CALL || s->u.expr == NULL || s->u.expr->kind != MS_E_CALL) {
    return false;
  }
  const MsExpr *callee = s->u.expr->u.call.callee;
  return callee->kind == MS_E_MEMBER && s->u.expr->u.call.args.len == 1 &&
         terse_name_is(scan, callee->u.member.name, "append") && is_name(callee->u.member.left, name);
}

/* Whether `e` is a range `a..b`, which parses as a call of the name `..`. */
static bool is_range(const TerseScan *scan, const MsExpr *e) {
  return e->kind == MS_E_CALL && e->u.call.callee->kind == MS_E_NAME &&
         terse_name_is(scan, e->u.call.callee->u.sym, "..");
}

/* A loop whose whole body appends one value to, or adds one value into, a fresh accumulator. */
static void accumulate_loop(const TerseScan *scan, MsStmts body, size_t at) {
  if (at + 1 >= body.len) {
    return;
  }
  const MsStmt *first = body.ptr[at];
  const MsStmt *second = body.ptr[at + 1];
  const MsName name = bound_name(first);
  if (name == 0 || !first->u.bind.is_mutable || second->kind != MS_S_FOR || second->u.each.body.len != 1 ||
      has_probe(second)) {
    return;
  }
  const MsExpr *value = first->u.bind.value;
  const MsStmt *only = second->u.each.body.ptr[0];
  MsSpan written = {0};
  const bool empty_list = (value->kind == MS_E_LIST && value->u.list.len == 0) ||
                          (terse_expr_text(scan, value, &written) && ms_span_starts_with(written, text_of("List[")) &&
                           ms_span_ends_with(written, text_of("]()")));
  const bool guarded = only->kind == MS_S_IF && only->u.branch.binding == NULL && only->u.branch.else_body.len == 0 &&
                       only->u.branch.body.len == 1 && appends_to(scan, only->u.branch.body.ptr[0], name);
  if (empty_list && (appends_to(scan, only, name) || guarded) && !inside(scan, "map") && !inside(scan, "filter")) {
    terse_note(scan, "MSL124",
               text_of("Build the list with `xs.map(x => ...)` or `xs.filter(x => ...)` instead of a loop that "
                       "appends"),
               first->pos);
  } else if (value->kind == MS_E_NUMBER && only->kind == MS_S_ASSIGN && !only->u.assign.member_target &&
             only->u.assign.name == name && only->u.assign.has_compound && only->u.assign.compound == MS_B_ADD &&
             !is_range(scan, second->u.each.iter) && !inside(scan, "sum")) {
    terse_note(scan, "MSL124",
               text_of("Total with `xs.sum()` or `xs.map(...).sum()` instead of a loop that adds"), first->pos);
  }
}

/* `for x in xs: out.append(x)` is `out.extend(xs)`. */
static void append_all(const TerseScan *scan, const MsStmt *s) {
  if (s->kind != MS_S_FOR || s->u.each.body.len != 1) {
    return;
  }
  const MsStmt *only = s->u.each.body.ptr[0];
  if (only->kind != MS_S_CALL || only->u.expr == NULL || only->u.expr->kind != MS_E_CALL ||
      only->u.expr->u.call.callee->kind != MS_E_MEMBER || only->u.expr->u.call.args.len != 1) {
    return;
  }
  const MsExpr *call = only->u.expr;
  const MsExpr *arg = call->u.call.args.ptr[0].value;
  const MsName name = s->u.each.name;
  bool element = is_name(arg, name);
  if (arg->kind == MS_E_CALL && arg->u.call.args.len == 0 && arg->u.call.callee->kind == MS_E_MEMBER) {
    element = terse_name_is(scan, arg->u.call.callee->u.member.name, "clone") &&
              is_name(arg->u.call.callee->u.member.left, name);
  }
  if (element && terse_name_is(scan, call->u.call.callee->u.member.name, "append") && !inside(scan, "extend")) {
    terse_note(scan, "MSL125", text_of("Append every element with `out.extend(xs)` instead of a loop"), s->pos);
  }
}

/* The rules over a statement list and a function, in lint_terse_stmts.c. */
static void terse_block(TerseScan *scan, MsStmts body) {
  for (size_t at = 0; at < body.len; at++) {
    default_then_reassign(scan, body, at);
    temp_return(scan, body, at);
    counter_while(scan, body, at);
    accumulate_loop(scan, body, at);
    index_loop(scan, body.ptr[at]);
    append_all(scan, body.ptr[at]);
  }
}

/* ---- the module ---- */

static void visit_block(void *context, MsStmts body) {
  terse_block(context, body);
}

static void visit_stmt(void *context, const MsStmt *s) {
  terse_stmt(context, s);
}

static void visit_expr(void *context, const MsExpr *e) {
  terse_expr(context, e);
}

/* The nodes `var` bindings and parameters are declared at. */
typedef struct Mutable {
  uint32_t *ids;
  size_t count, capacity;
} Mutable;

static void mutable_add(Mutable *set, uint32_t id) {
  if (set->count == set->capacity) {
    set->capacity = set->capacity == 0 ? 16 : set->capacity * 2;
    set->ids = realloc(set->ids, set->capacity * sizeof(uint32_t));
    if (set->ids == NULL) {
      abort();
    }
  }
  set->ids[set->count++] = id;
}

static void mutable_params(Mutable *set, MsParams params) {
  for (uint32_t i = 0; i < params.len; i++) {
    if (params.ptr[i]->is_mutable) {
      mutable_add(set, params.ptr[i]->id);
    }
  }
}

static void mutable_stmt(void *context, const MsStmt *s) {
  if (s->kind == MS_S_BIND && s->u.bind.is_mutable) {
    mutable_add(context, s->u.bind.pattern->id);
  }
}

static void mutable_expr(void *context, const MsExpr *e) {
  if (e->kind == MS_E_LAMBDA) {
    mutable_params(context, e->u.lambda.params);
  }
}

static void collect_mutable(Mutable *set, const MsModule *tree) {
  const MsVisitor visitor = {.ctx = set, .stmt = mutable_stmt, .expr = mutable_expr};
  for (uint32_t i = 0; i < tree->ndecls; i++) {
    const MsDecl *decl = tree->decls[i];
    if (decl->kind == MS_D_FN) {
      mutable_params(set, decl->u.fn.params);
    } else if (decl->kind == MS_D_IMPL) {
      for (uint32_t m = 0; m < decl->u.impl.methods.len; m++) {
        mutable_params(set, decl->u.impl.methods.ptr[m]->func.params);
      }
    }
    ms_walk_decl(&visitor, decl);
  }
}

void ms_lint_terse(MsArena *arena, const MsCheckProgram *program, uint32_t module_index,
                   MsLintFindingList *findings) {
  const MsModuleInfo *module = &program->modules.ptr[module_index];
  if (module->tree == NULL) {
    return;
  }
  Mutable set = {0};
  collect_mutable(&set, module->tree);
  TerseScan scan = {.arena = arena, .program = program, .module = module,
                    .file = ms_names_span(program->names, module->file), .findings = findings,
                    .mutable_ids = set.ids, .mutable_count = set.count};
  for (uint32_t i = 0; i < module->tree->ndecls; i++) {
    const MsDecl *decl = module->tree->decls[i];
    if (decl->kind == MS_D_FN) {
      terse_trailing_return(&scan, &decl->u.fn);
    }
    for (uint32_t m = 0; decl->kind == MS_D_IMPL && m < decl->u.impl.methods.len; m++) {
      terse_trailing_return(&scan, &decl->u.impl.methods.ptr[m]->func);
    }
  }
  const MsVisitor visitor = {.ctx = &scan, .block = visit_block, .stmt = visit_stmt, .expr = visit_expr};
  for (uint32_t i = 0; i < module->tree->ndecls; i++) {
    const MsDecl *decl = module->tree->decls[i];
    scan.enclosing = decl->kind == MS_D_FN ? decl->u.fn.name
                     : decl->kind == MS_D_IMPL && decl->u.impl.methods.len == 1 ? decl->u.impl.methods.ptr[0]->func.name
                                                                                : 0;
    ms_walk_decl(&visitor, decl);
  }
  free(set.ids);
}
