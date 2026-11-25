/* compiler/check/nullable_methods.c: a nullable `T?` has no methods. `x == null` and `x != null` replace `is_none` and
 * `is_some`, and `x or d` replaces `get_or`, `get_or_else` and `or_else`; each use is reported with the rewrite as its
 * machine fix. */
#include "compiler/check/body.h"
#include "compiler/check/call_internal.h"
#include "compiler/syntax/walk.h"

#include <string.h>

typedef enum Removed { REMOVED_NONE, REMOVED_IS_NULL, REMOVED_IS_PRESENT, REMOVED_OR, REMOVED_OR_CALL, REMOVED_UNWRAP, REMOVED_OK_OR, REMOVED_GET } Removed;

static Removed removed_kind(MsSpan name, size_t nargs) {
  if (ms_span_is_text(name, "is_none") && nargs == 0) {
    return REMOVED_IS_NULL;
  }
  if (ms_span_is_text(name, "is_some") && nargs == 0) {
    return REMOVED_IS_PRESENT;
  }
  if (ms_span_is_text(name, "get_or") && nargs == 1) {
    return REMOVED_OR;
  }
  if ((ms_span_is_text(name, "get_or_else") || ms_span_is_text(name, "or_else")) && nargs == 1) {
    return REMOVED_OR_CALL;
  }
  if ((ms_span_is_text(name, "map") || ms_span_is_text(name, "and_then") || ms_span_is_text(name, "ok_or_else")) && nargs == 1) {
    return REMOVED_UNWRAP;
  }
  if (ms_span_is_text(name, "get") && nargs == 0) {
    return REMOVED_GET;
  }
  if (ms_span_is_text(name, "ok_or") && nargs == 1) {
    return REMOVED_OK_OR;
  }
  return REMOVED_NONE;
}

static bool slice(const Body *body, const MsExpr *expr, MsSpan *out) {
  const MsPos start = ms_expr_start(expr);
  return expr->end.offset > start.offset && ms_span_slice(body->source, start.offset, expr->end.offset, out);
}

static bool blank(uint8_t c) {
  return c == ' ' || c == '\t';
}

/* Whether the source text before `end` ends with `word`. */
static bool ends_with(MsSpan source, size_t end, const char *word) {
  const MsSpan expected = ms_span_of_text(word);
  return end >= expected.len && end <= source.len &&
         ms_span_equal((MsSpan){source.ptr + end - expected.len, expected.len}, expected);
}

/* Whether the written call stands where a looser operator needs no parentheses: a statement, a condition, a binding or
 * an argument on its own. */
static bool stands_alone(const Body *body, const MsExpr *call, MsPos start) {
  const MsSpan source = body->source;
  size_t before = start.offset;
  while (before > 0 && blank(source.ptr[before - 1])) {
    before--;
  }
  size_t after = call->end.offset;
  while (after < source.len && blank(source.ptr[after])) {
    after++;
  }
  const bool open = before == 0 || source.ptr[before - 1] == '\n' || source.ptr[before - 1] == '(' ||
                    source.ptr[before - 1] == ',' || source.ptr[before - 1] == ':' || (source.ptr[before - 1] == '=' && before >= 2 && (source.ptr[before - 2] == ':' || blank(source.ptr[before - 2]))) ||
                    ends_with(source, before, "if") || ends_with(source, before, "while") || ends_with(source, before, "return");
  const bool close = after >= source.len || source.ptr[after] == '\n' || source.ptr[after] == ':' ||
                     source.ptr[after] == ')' || source.ptr[after] == ',';
  return open && close;
}

/* The written receiver with the parentheses around it, which the syntax tree does not record. `start` is where the
 * written receiver begins and `atomic` says whether it needs no further parentheses. */
static bool written_receiver(const Body *body, const MsExpr *receiver, MsSpan name, MsSpan *text, MsPos *start,
                             bool *atomic) {
  const MsSpan source = body->source;
  *start = ms_expr_start(receiver);
  size_t begin = start->offset;
  size_t end = receiver->end.offset;
  *atomic = body_expr_is_atomic(receiver);
  if (end > source.len) { /* a bundled module keeps no source to rewrite */
    return false;
  }
  for (;;) {
    size_t before = begin;
    while (before > 0 && blank(source.ptr[before - 1])) {
      before--;
    }
    size_t after = end;
    while (after < source.len && blank(source.ptr[after])) {
      after++;
    }
    if (before == 0 || after >= source.len || source.ptr[before - 1] != '(' || source.ptr[after] != ')') {
      break;
    }
    start->column -= (uint32_t)(begin - (before - 1));
    begin = before - 1;
    end = after + 1;
    start->offset = (uint32_t)begin;
    *atomic = true;
  }
  /* what follows must be `.name`: a pipe stage or an odd layout has no receiver text to move */
  size_t dot = end;
  while (dot < source.len && blank(source.ptr[dot])) {
    dot++;
  }
  const bool member = dot + 1 + name.len <= source.len && source.ptr[dot] == '.' &&
                      ms_span_equal(ms_span_of(source.ptr + dot + 1, name.len), name);
  return member && end > begin && ms_span_slice(source, begin, end, text);
}

/* The receiver as an operand of `==`, `!=` or `or`: parenthesised unless it is a postfix chain. */
static void append_operand(MsStrBuild *out, MsSpan text, bool atomic) {
  const bool parens = !atomic;
  ms_strbuild_append_text(out, parens ? "(" : "");
  ms_strbuild_append(out, text);
  ms_strbuild_append_text(out, parens ? ")" : "");
}

/* The text a lambda `fn: body` with no parameters evaluates to, or an empty span. */
static MsSpan lambda_body(const Body *body, const MsExpr *lambda, MsSpan text) {
  MsSpan none = {0};
  if (lambda->kind != MS_E_LAMBDA || lambda->u.lambda.params.len != 0 || text.len < 4) {
    return none;
  }
  size_t colon = 0;
  while (colon < text.len && text.ptr[colon] != ':') {
    if (text.ptr[colon] == '\n') {
      return none;
    }
    colon++;
  }
  size_t start = colon + 1;
  while (start < text.len && blank(text.ptr[start])) {
    start++;
  }
  (void)body;
  return start < text.len ? (MsSpan){text.ptr + start, text.len - start} : none;
}

static bool fix_text(const Body *body, const MsExpr *call, Removed kind, const MsExpr *receiver, MsPos start,
                     MsSpan receiver_text, bool atomic, MsStrBuild *out) {
  (void)receiver;
  const bool bare = stands_alone(body, call, start) || kind == REMOVED_OK_OR;
  ms_strbuild_append_text(out, bare ? "" : "(");
  if (kind != REMOVED_OK_OR) {
    append_operand(out, receiver_text, atomic);
  }
  if (kind == REMOVED_OK_OR) {
    MsSpan arg_text = {0};
    if (!slice(body, call->u.call.args.ptr[0].value, &arg_text)) {
      return false;
    }
    ms_strbuild_append_text(out, "ok_or(");
    ms_strbuild_append(out, receiver_text);
    ms_strbuild_append_text(out, ", ");
    ms_strbuild_append(out, arg_text);
    ms_strbuild_append_text(out, ")");
    return true;
  }
  if (kind == REMOVED_GET) {
    ms_strbuild_append_text(out, " or panic(\"called Optional.get() on null\")");
  } else if (kind == REMOVED_IS_NULL || kind == REMOVED_IS_PRESENT) {
    ms_strbuild_append_text(out, kind == REMOVED_IS_NULL ? " == null" : " != null");
  } else {
    const MsExpr *arg = call->u.call.args.ptr[0].value;
    MsSpan arg_text = {0};
    if (!slice(body, arg, &arg_text)) {
      return false;
    }
    ms_strbuild_append_text(out, " or ");
    if (kind == REMOVED_OR_CALL) {
      const MsSpan inner = lambda_body(body, arg, arg_text);
      const bool plain = body_expr_is_atomic(arg);
      if (inner.len != 0) {
        ms_strbuild_append(out, inner);
      } else {
        ms_strbuild_append_text(out, plain ? "" : "(");
        ms_strbuild_append(out, arg_text);
        ms_strbuild_append_text(out, plain ? "()" : ")()");
      }
    } else {
      const bool wrap = !body_expr_is_atomic(arg) && (arg->kind != MS_E_BINARY || arg->op == MS_B_OR) &&
                        arg->kind != MS_E_NUMBER && arg->kind != MS_E_TEXT;
      ms_strbuild_append_text(out, wrap ? "(" : "");
      ms_strbuild_append(out, arg_text);
      ms_strbuild_append_text(out, wrap ? ")" : "");
    }
  }
  ms_strbuild_append_text(out, bare ? "" : ")");
  return true;
}

static const char *write_text(Removed kind) {
  return kind == REMOVED_UNWRAP ? "if x != null:` and use `x"
         : kind == REMOVED_GET  ? "if x != null:` and use `x`, or `x or panic(\"...\")"
         : kind == REMOVED_OK_OR ? "ok_or(x, cause)"
         : kind == REMOVED_IS_NULL ? "x == null"
         : kind == REMOVED_IS_PRESENT ? "x != null"
         : kind == REMOVED_OR ? "x or d"
                              : "x or compute()";
}

/* The rewrite for a method a nullable once had, by name alone (the call is not resolved), or NULL when it never had one. */
const char *body_removed_nullable_method(MsSpan name) {
  for (size_t nargs = 0; nargs < 3; nargs++) {
    const Removed kind = removed_kind(name, nargs);
    if (kind != REMOVED_NONE) {
      return write_text(kind);
    }
  }
  return NULL;
}

static void attach_removed_fix(Body *body, const MsExpr *call, Removed kind, const MsExpr *receiver, MsSpan name) {
  MsSpan receiver_text = {0};
  MsPos start = {0};
  bool atomic = false;
  MsStrBuild fix = ms_strbuild_new();
  if (kind != REMOVED_UNWRAP && written_receiver(body, receiver, name, &receiver_text, &start, &atomic) &&
      fix_text(body, call, kind, receiver, start, receiver_text, atomic, &fix)) {
    ms_check_attach_fix(body->program, start, call->end, ms_strbuild_finish(&fix));
  } else {
    ms_strbuild_free(&fix);
  }
}

void body_reject_nullable_method(Body *body, const MsExpr *call, const Target *target) {
  const MsExpr *callee = call->u.call.callee;
  if (callee->kind != MS_E_MEMBER || target->receiver == NULL || !body_reports(body) || body->quiet) {
    return;
  }
  const MsTyTable *types = &body->program->types;
  const MsTy receiver = ms_facts_type(body->facts, target->receiver->id);
  if (receiver == MS_TY_NONE || !ms_ty_is(types, receiver, MS_BUILTIN_Optional) || ms_ty_arg_count(types, receiver) != 1 ||
      body_use_is_narrowed(body, target->receiver)) {
    return;
  }
  const MsSpan name = ms_names_span(body->program->names, callee->u.member.name);
  const Removed kind = removed_kind(name, call->u.call.args.len);
  if (kind == REMOVED_NONE) {
    return;
  }
  const char *write = write_text(kind);
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "a nullable has no method `");
  ms_strbuild_append(&text, name);
  ms_strbuild_append_text(&text, "`; write `");
  ms_strbuild_append_text(&text, write);
  ms_strbuild_append_text(&text, "`");
  ms_check_report(body->program, body->module, callee->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
  attach_removed_fix(body, call, kind, target->receiver, name);
}

/* A call of a removed method that did not resolve: the unknown-member report already stands, and gains the same fix. */
void body_fix_removed_nullable_call(Body *body, const MsExpr *call) {
  const MsExpr *callee = call->u.call.callee;
  if (callee->kind != MS_E_MEMBER || !body_reports(body) || body->quiet) {
    return;
  }
  const MsSpan name = ms_names_span(body->program->names, callee->u.member.name);
  const Removed kind = removed_kind(name, call->u.call.args.len);
  if (kind == REMOVED_NONE) {
    return;
  }
  body->quiet = true;
  const MsTy receiver = body_expr(body, callee->u.member.left, MS_TY_NONE);
  body->quiet = false;
  if (receiver != MS_TY_NONE && ms_ty_is(&body->program->types, receiver, MS_BUILTIN_Optional)) {
    attach_removed_fix(body, call, kind, callee->u.member.left, name);
  }
}

/* A narrowed local: an immutable nullable that `v != null` shows present at this use. */
static bool narrowed_name(const Body *body, const MsExpr *expr) {
  if (expr->kind != MS_E_NAME) {
    return false;
  }
  const MsLocal *local = body_find_local(body, expr->u.sym);
  return local != NULL && local->narrowed != MS_TY_NONE;
}

static void report_present(Body *body, const MsExpr *whole, const MsExpr *name, const char *what) {
  if (!body_reports(body) || body->quiet) {
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append(&text, ms_names_span(body->program->names, name->u.sym));
  ms_strbuild_append_text(&text, " is present here, so ");
  ms_strbuild_append_text(&text, what);
  ms_strbuild_append_text(&text, "; write ");
  ms_strbuild_append(&text, ms_names_span(body->program->names, name->u.sym));
  ms_check_report(body->program, body->module, whole->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
  MsSpan written = {0};
  if (slice(body, name, &written)) {
    MsStrBuild fix = ms_strbuild_new();
    ms_strbuild_append(&fix, written);
    ms_check_attach_fix(body->program, ms_expr_start(whole), whole->end, ms_strbuild_finish(&fix));
  }
}

bool body_present_get(Body *body, const MsExpr *call, MsTy *result) {
  const MsExpr *callee = call->u.call.callee;
  if (callee->kind != MS_E_MEMBER || call->u.call.args.len != 0 || !narrowed_name(body, callee->u.member.left) ||
      !ms_span_is_text(ms_names_span(body->program->names, callee->u.member.name), "get")) {
    return false;
  }
  *result = body_expr(body, callee->u.member.left, MS_TY_NONE);
  report_present(body, call, callee->u.member.left, "get() has nothing to unwrap");
  return true;
}

/* Whether `expr` reads a narrowed local, possibly through members and calls (`v.clone()`). */
static bool reads_narrowed(const Body *body, const MsExpr *expr) {
  while (expr->kind == MS_E_MEMBER || expr->kind == MS_E_CALL) {
    expr = expr->kind == MS_E_MEMBER ? expr->u.member.left : expr->u.call.callee;
  }
  return narrowed_name(body, expr);
}

bool body_redundant_or(Body *body, const MsExpr *expr) {
  if (!reads_narrowed(body, expr->u.bin.left)) {
    return false;
  }
  if (!body_reports(body) || body->quiet) {
    return true;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "the left of `or` is never null here, so the right is never used; write the left alone");
  ms_check_report(body->program, body->module, expr->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
  MsSpan written = {0};
  if (slice(body, expr->u.bin.left, &written)) {
    MsStrBuild fix = ms_strbuild_new();
    ms_strbuild_append(&fix, written);
    ms_check_attach_fix(body->program, ms_expr_start(expr), expr->end, ms_strbuild_finish(&fix));
  }
  return true;
}

/* `if v := x { ... }` over an Optional: the binding is written as a declaration and a `v != null` test, which narrows `v`. */
void body_report_if_unwrap(Body *body, const MsStmt *stmt) {
  const MsPattern *binding = stmt->u.branch.binding;
  if (!body_reports(body) || body->quiet || stmt->u.branch.is_mutable) {
    return;
  }
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "an Optional is tested with `!= null`, not unwrapped by `if v := x`; "
                                 "write `v := x` and then `if v != null { ... }`");
  ms_check_report(body->program, body->module, stmt->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
  const MsExpr *cond = stmt->u.branch.cond;
  MsSpan written = {0};
  if (binding->kind != MS_P_NAME || stmt->pos.offset >= binding->pos.offset || cond->end.offset <= binding->pos.offset ||
      !ms_span_slice(body->source, binding->pos.offset, cond->end.offset, &written)) {
    return;
  }
  size_t line = stmt->pos.offset;
  while (line > 0 && body->source.ptr[line - 1] != '\n') {
    line--;
  }
  for (size_t at = line; at < stmt->pos.offset; at++) {
    if (!blank(body->source.ptr[at])) {
      return; /* `else if`: no mechanical rewrite */
    }
  }
  MsStrBuild fix = ms_strbuild_new();
  ms_strbuild_append(&fix, written);
  ms_strbuild_append_text(&fix, "\n");
  MsSpan indent = {0};
  if (ms_span_slice(body->source, line, stmt->pos.offset, &indent)) {
    ms_strbuild_append(&fix, indent);
  }
  ms_strbuild_append_text(&fix, "if ");
  ms_strbuild_append(&fix, ms_names_span(body->program->names, binding->u.name));
  ms_strbuild_append_text(&fix, " != null");
  ms_check_attach_fix(body->program, stmt->pos, cond->end, ms_strbuild_finish(&fix));
}
