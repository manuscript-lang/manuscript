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
  const MsToken *tokens;
  size_t ntokens;
  EditList edits;
  bool *else_ifs; /* by statement id: the `else if` of an enclosing `if` */
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

/* The offset of the line end at or after `at`. */
static bool compact_line_end(MsSpan source, size_t at, size_t *end) {
  if (at > source.len || (at < source.len && ms_utf8_is_continuation(source.ptr[at]))) {
    return false;
  }
  const size_t newline = fmt_find_byte(fmt_slice(source, at, source.len), '\n');
  *end = newline == FMT_NONE ? source.len : at + newline;
  return true;
}

/* The last non-layout token before offset `limit` (the first token at or after it ends the
 * search), or NULL. */
static const MsToken *compact_token_before(const Compact *c, uint32_t limit) {
  size_t start = 0;
  while (start < c->ntokens && c->tokens[start].pos.offset < limit) {
    start++;
  }
  while (start > 0) {
    start--;
    if (!fmt_layout_token((MsTok)c->tokens[start].kind)) {
      return &c->tokens[start];
    }
  }
  return NULL;
}

static void compact_edit(Compact *c, size_t from, size_t to, MsSpan text) {
  edit_list_push(&c->edits, ((FmtEdit){from, to, text}));
}

static bool compact_is_space_only(MsSpan s) {
  return fmt_is_blank(s);
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

/* The offset where the jump statement `only` (`return [value]`, `break`, `continue`) ends. */
static bool compact_jump_end(const Compact *c, const MsStmt *only, size_t *end_offset) {
  if (only->kind == MS_S_RETURN && only->u.expr != NULL) {
    *end_offset = only->u.expr->end.offset;
    return true;
  }
  if (only->kind != MS_S_RETURN && only->kind != MS_S_BREAK && only->kind != MS_S_CONTINUE) {
    return false;
  }
  size_t line_end;
  if (!compact_line_end(c->source, only->pos.offset, &line_end) || line_end < only->pos.offset) {
    return false;
  }
  const MsSpan text = fmt_trim_end(fmt_slice(c->source, only->pos.offset, line_end));
  if (!fmt_is(text, "return") && !fmt_is(text, "break") && !fmt_is(text, "continue")) {
    return false;
  }
  *end_offset = only->pos.offset + text.len;
  return true;
}

/* Whether the text holds a multi-line text placeholder, a newline or a comment. */
static bool compact_body_blocked(MsSpan body_text) {
  // A multi-line text literal reaches this pass as a private-use placeholder.
  for (size_t at = 0; at < body_text.len;) {
    uint32_t scalar;
    at += fmt_scalar_at(body_text, at, &scalar);
    if (scalar >= 0xE000 && scalar <= 0xF8FF) {
      return true;
    }
  }
  return fmt_contains(body_text, "\n") || fmt_contains(body_text, "//");
}

/* `if c { ... }` over a single `return`, `break` or `continue` line becomes one line. */
static void compact_inline_if(Compact *c, const MsStmt *s, MsStmts body) {
  if (body.len != 1) {
    return;
  }
  const MsStmt *only = body.ptr[0];
  size_t end_offset;
  if (!compact_jump_end(c, only, &end_offset)) {
    return;
  }
  const MsToken *colon = compact_token_before(c, only->pos.offset);
  if (colon == NULL) {
    return;
  }
  const size_t from = colon->hi;
  const size_t to = only->pos.offset;
  MsSpan gap;
  if (!compact_get(c->source, from, to, &gap)) {
    return;
  }
  if (colon->kind != MS_T_Colon || !fmt_contains(gap, "\n") || !compact_is_space_only(gap)) {
    return;
  }
  // The header must sit on one line, and nothing may follow the body on its line.
  const size_t if_start = s->pos.offset;
  MsSpan header;
  if (!compact_get(c->source, if_start, colon->hi, &header)) {
    return;
  }
  size_t line_end;
  if (!compact_line_end(c->source, end_offset, &line_end)) {
    return;
  }
  if (fmt_contains(header, "\n") || !fmt_is_blank(fmt_slice(c->source, end_offset, line_end))) {
    return;
  }
  MsSpan body_text;
  if (!compact_get(c->source, to, end_offset, &body_text)) {
    return;
  }
  if (compact_body_blocked(body_text)) {
    return;
  }
  const size_t line_break = fmt_rfind_byte(fmt_slice(c->source, 0, if_start), '\n');
  const size_t line_start = line_break == FMT_NONE ? 0 : line_break + 1;
  const size_t width = fmt_chars(fmt_slice(c->source, line_start, colon->hi)) + 1 + fmt_chars(body_text);
  if (width <= FMT_WIDTH) {
    compact_edit(c, from, to, ms_span_of_text(" "));
  }
}

static void compact_stmt(void *ctx, const MsStmt *s) {
  Compact *c = ctx;
  if (s->kind == MS_S_ASSIGN && !s->u.assign.has_compound) {
    compact_compound(c, s, s->u.assign.value);
  } else if (s->kind == MS_S_CALL) {
    compact_index_compound(c, s, s->u.expr);
  } else if (s->kind == MS_S_IF) {
    const MsStmts else_body = s->u.branch.else_body;
    if (else_body.len == 1 && else_body.ptr[0]->kind == MS_S_IF) {
      c->else_ifs[else_body.ptr[0]->id] = true;
    }
    if (else_body.len == 0 && !c->else_ifs[s->id]) {
      compact_inline_if(c, s, s->u.branch.body);
    }
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
  MsArena scratch = {0};
  MsLexed lexed;
  MsDiag ignored;
  if (!ms_lex(&scratch, source, &lexed, &ignored)) {
    ms_arena_free(&scratch);
    return false;
  }
  Compact c = {.fmt = f, .source = source, .tokens = lexed.tokens, .ntokens = lexed.ntokens};
  c.else_ifs = MS_ARENA_NEW_ARRAY(&scratch, bool, (size_t)module->node_count + 1);
  const MsVisitor visitor = {.ctx = &c, .stmt = compact_stmt};
  for (uint32_t i = 0; i < module->ndecls; i++) {
    ms_walk_decl(&visitor, module->decls[i]);
  }
  ms_arena_free(&scratch);
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
