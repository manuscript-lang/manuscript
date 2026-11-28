/* Statement compaction: rewrites that make a program
 * shorter without changing its meaning.
 *
 * Each rewrite is a source edit found on the parsed tree. A candidate that contains a comment,
 * spans several lines in an unexpected place, or would exceed the line width is left as written. */
#include "base/sort.h"
#include "compiler/syntax/format_internal.h"
#include "compiler/syntax/walk.h"

typedef struct Compact {
  Fmt *fmt;
  MsSpan source;
  EditList edits;
} Compact;

/* The text between two offsets, or false when they are reversed, past the end or inside a scalar
 * (offsets of interpolated expressions are local to their text). */
static bool compact_get(MsSpan source, size_t from, size_t to, MsSpan *out) {
  if (from > to || to > source.len) {
    return false;
  }
  const bool from_ok = from == source.len || !ms_utf8_is_continuation(source.ptr[from]);
  const bool to_ok = to == source.len || !ms_utf8_is_continuation(source.ptr[to]);
  if (!from_ok || !to_ok) {
    return false;
  }
  *out = fmt_slice(source, from, to);
  return true;
}

static void compact_edit(Compact *c, size_t from, size_t to, MsSpan text) {
  edit_list_push(&c->edits, ((FmtEdit){from, to, text}));
}

/* `target = target op rest` as `target op= rest`. */
static void compact_compound(Compact *c, const MsStmt *s, const MsExpr *value) {
  if (value->kind != MS_E_BINARY) {
    return;
  }
  char symbol;
  switch ((MsBinaryOp)value->op) {
  case MS_B_ADD:
    symbol = '+';
    break;
  case MS_B_SUB:
    symbol = '-';
    break;
  case MS_B_MUL:
    symbol = '*';
    break;
  case MS_B_DIV:
    symbol = '/';
    break;
  case MS_B_REM:
    symbol = '%';
    break;
  default:
    return;
  }
  const size_t from = s->pos.offset;
  const size_t to = ms_expr_start(value->u.bin.right).offset;
  MsSpan head;
  if (!compact_get(c->source, from, to, &head)) {
    return;
  }
  const size_t eq = fmt_find_byte(head, '=');
  if (eq == FMT_NONE) {
    return;
  }
  const MsSpan target = fmt_trim_end(fmt_slice(head, 0, eq));
  // The head with its whitespace squeezed out must be `target=targetOP`.
  MsStrBuild squeezed = {0};
  for (size_t at = 0; at < head.len;) {
    uint32_t scalar;
    const size_t width = fmt_scalar_at(head, at, &scalar);
    if (!ms_utf8_is_space(scalar)) {
      ms_strbuild_append(&squeezed, ms_span_of((const uint8_t *)(head.ptr + at), width));
    }
    at += width;
  }
  const MsSpan expected = ms_message_format(c->fmt->arena, "%S=%S%c", target, target, symbol);
  const bool matches = fmt_eq(ms_strbuild_span(&squeezed), expected);
  ms_strbuild_free(&squeezed);
  if (target.len == 0 || fmt_contains(head, "//") || !matches) {
    return;
  }
  compact_edit(c, from, to, ms_message_format(c->fmt->arena, "%S %c= ", target, symbol));
}

/* `xs[i] = xs[i] op rest` as `xs[i] op= rest`. An index store is the call of `[]=`. */
static void compact_index_compound(Compact *c, const MsStmt *s, const MsExpr *call) {
  if (call->kind != MS_E_CALL || call->u.call.callee->kind != MS_E_MEMBER || call->u.call.args.len != 2) {
    return;
  }
  const MsExpr *callee = call->u.call.callee;
  const MsExpr *index = call->u.call.args.ptr[0].value;
  const MsExpr *value = call->u.call.args.ptr[1].value;
  if (!fmt_is(ms_names_span(c->fmt->names, callee->u.member.name), MS_INDEX_SET) ||
      !ms_plain_index_target(callee->u.member.left, index) || value->kind != MS_E_BINARY) {
    return;
  }
  compact_compound(c, s, value);
}

static void compact_stmt(void *ctx, const MsStmt *s) {
  Compact *c = ctx;
  if (s->kind == MS_S_ASSIGN && !s->u.assign.has_compound) {
    compact_compound(c, s, s->u.assign.value);
  } else if (s->kind == MS_S_CALL) {
    compact_index_compound(c, s, s->u.expr);
  }
}

static int64_t compact_order(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  const FmtEdit *x = (const void *)a;
  const FmtEdit *y = (const void *)b;
  if (x->from != y->from) {
    return x->from < y->from ? -1 : 1;
  }
  return 0;
}

bool fmt_compact(Fmt *f, const MsModule *module, MsSpan source, MsSpan *out) {
  Compact c = {.fmt = f, .source = source};
  const MsVisitor visitor = {.ctx = &c, .stmt = compact_stmt};
  for (uint32_t i = 0; i < module->ndecls; i++) {
    ms_walk_decl(&visitor, module->decls[i]);
  }
  const size_t count = c.edits.len;
  if (count == 0) {
    edit_list_free(&c.edits);
    return false;
  }
  FmtEdit *edits = c.edits.ptr;
  ms_sort((uint8_t *)edits, count, sizeof *edits, compact_order, NULL);
  // Edits that start inside an earlier one are dropped.
  size_t kept = 0;
  size_t cursor = 0;
  for (size_t i = 0; i < count; i++) {
    if (edits[i].from < cursor) {
      continue;
    }
    edits[kept++] = edits[i];
    cursor = edits[i].to;
  }
  *out = fmt_apply_edits(f, source, edits, kept);
  edit_list_free(&c.edits);
  return true;
}
