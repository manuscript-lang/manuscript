/* compiler/check/nullable_methods.c: a nullable `T?` has no methods. `x == null` and `x != null` replace `is_none` and
 * `is_some`, and `x or d` replaces `get_or`, `get_or_else` and `or_else`; each use is reported with the rewrite as its
 * machine fix. */
#include "compiler/check/body.h"
#include "compiler/check/call_internal.h"
#include "compiler/syntax/walk.h"

#include <string.h>

typedef enum Removed { REMOVED_NONE, REMOVED_IS_NULL, REMOVED_IS_PRESENT, REMOVED_OR, REMOVED_OR_CALL } Removed;

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
  const size_t length = strlen(word);
  if (end < length) {
    return false;
  }
  for (size_t index = 0; index < length; index++) {
    if (source.ptr[end - length + index] != (uint8_t)word[index]) {
      return false;
    }
  }
  return true;
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
  const bool bare = stands_alone(body, call, start);
  ms_strbuild_append_text(out, bare ? "" : "(");
  append_operand(out, receiver_text, atomic);
  if (kind == REMOVED_IS_NULL || kind == REMOVED_IS_PRESENT) {
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

void body_reject_nullable_method(Body *body, const MsExpr *call, const Target *target) {
  const MsExpr *callee = call->u.call.callee;
  if (callee->kind != MS_E_MEMBER || target->receiver == NULL || !body_reports(body) || body->quiet) {
    return;
  }
  const MsTyTable *types = &body->program->types;
  const MsTy receiver = ms_facts_type(body->facts, target->receiver->id);
  if (receiver == MS_TY_NONE || !ms_ty_is(types, receiver, MS_BUILTIN_Optional) || ms_ty_arg_count(types, receiver) != 1) {
    return;
  }
  const MsSpan name = ms_names_span(body->program->names, callee->u.member.name);
  const Removed kind = removed_kind(name, call->u.call.args.len);
  if (kind == REMOVED_NONE) {
    return;
  }
  const char *write = kind == REMOVED_IS_NULL ? "x == null" : kind == REMOVED_IS_PRESENT ? "x != null" : kind == REMOVED_OR ? "x or d" : "x or compute()";
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, "a nullable has no method `");
  ms_strbuild_append(&text, name);
  ms_strbuild_append_text(&text, "`; write `");
  ms_strbuild_append_text(&text, write);
  ms_strbuild_append_text(&text, "`");
  ms_check_report(body->program, body->module, callee->pos, MS_CHECK_TYPE, ms_strbuild_finish(&text));
  MsSpan receiver_text = {0};
  MsPos start = {0};
  bool atomic = false;
  MsStrBuild fix = ms_strbuild_new();
  if (written_receiver(body, target->receiver, name, &receiver_text, &start, &atomic) &&
      fix_text(body, call, kind, target->receiver, start, receiver_text, atomic, &fix)) {
    ms_check_attach_fix(body->program, start, call->end, ms_strbuild_finish(&fix));
  } else {
    ms_strbuild_free(&fix);
  }
}
