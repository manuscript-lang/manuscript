/* syntax/format_cuts.c: the suites of callbacks and calls that the layout keeps whole. */
#include "compiler/syntax/format_layout.h"
#include "compiler/syntax/walk.h"

/* ---- callbacks and calls that carry suites ---- */

typedef struct SuiteCuts {
  Fmt *fmt;
  MsSpan source;
  const MsToken *tokens;
  size_t ntokens;
  RangeList cuts;
  bool *suites;   /* by expression id: a lambda or match, or an expression holding one */
  FlagList stack; /* a bool per expression being walked */
} SuiteCuts;

static void cuts_expr(void *ctx, const MsExpr *e) {
  SuiteCuts *s = ctx;
  flag_list_push(&s->stack, e->kind == MS_E_LAMBDA || e->kind == MS_E_MATCH);
}

/* The number of tokens that start before `offset` (the tokens are in source order). */
static size_t lay_tokens_before(const MsToken *tokens, size_t ntokens, uint32_t offset) {
  size_t low = 0;
  size_t high = ntokens;
  while (low < high) {
    const size_t mid = low + (high - low) / 2;
    if (tokens[mid].pos.offset < offset) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  return low;
}

static void cuts_leave(void *ctx, const MsExpr *e) {
  SuiteCuts *s = ctx;
  const bool suite = (*flag_list_last(&s->stack));
  flag_list_truncate(&s->stack, s->stack.len - 1);
  if (suite) {
    s->suites[e->id] = true;
    if (s->stack.len != 0) {
      (*flag_list_last(&s->stack)) = true;
    }
  }
  if (e->kind != MS_E_CALL) {
    return;
  }
  for (uint32_t i = 0; i < e->u.call.args.len; i++) {
    const MsExpr *arg = e->u.call.args.ptr[i].value;
    if (arg->kind != MS_E_LAMBDA) {
      continue;
    }
    const MsStmts written = fmt_written_body(arg);
    if (written.len != 1 || written.ptr[0]->kind != MS_S_RETURN || written.ptr[0]->u.expr == NULL) {
      continue;
    }
    const MsStmt *body = written.ptr[0];
    // Nested suites retain indentation relative to this body.
    if (s->suites[body->u.expr->id]) {
      continue;
    }
    size_t start = lay_tokens_before(s->tokens, s->ntokens, body->pos.offset);
    const MsToken *colon = NULL;
    while (start > 0) {
      start--;
      if (!fmt_layout_token((MsTok)s->tokens[start].kind)) {
        colon = &s->tokens[start];
        break;
      }
    }
    if (colon == NULL) {
      continue;
    }
    const size_t from = colon->hi;
    const size_t to = body->pos.offset;
    // Interpolated expressions keep offsets local to their text, so the range can be reversed
    // or off a boundary.
    if (from > to || to > s->source.len ||
        (to < s->source.len && ms_utf8_is_continuation(s->source.ptr[to])) ||
        (from < s->source.len && ms_utf8_is_continuation(s->source.ptr[from]))) {
      continue;
    }
    const MsSpan gap = fmt_slice(s->source, from, to);
    if (colon->kind == MS_T_Colon && fmt_contains(gap, "\n") && fmt_is_blank(gap)) {
      range_list_push(&s->cuts, ((MsByteRange){from, to}));
    }
  }
}

static int range_order(const void *a, const void *b) {
  const MsByteRange *x = a;
  const MsByteRange *y = b;
  if (x->start != y->start) {
    return x->start < y->start ? -1 : 1;
  }
  if (x->end != y->end) {
    return x->end < y->end ? -1 : 1;
  }
  return 0;
}

/* Joining an explicit return to its callback header preserves its meaning. A bare call cannot be
 * joined: an inline body would implicitly return it. */
bool lay_compact_callback_suites(Fmt *f, const MsModule *module, const MsToken *tokens, size_t ntokens,
                                 MsSpan source, MsSpan *out) {
  MsArena scratch = {0};
  SuiteCuts s = {.fmt = f, .source = source, .tokens = tokens, .ntokens = ntokens};
  s.suites = MS_ARENA_NEW_ARRAY(&scratch, bool, (size_t)module->node_count + 1);
  memset(s.suites, 0, ((size_t)module->node_count + 1) * sizeof *s.suites);
  const MsVisitor visitor = {.ctx = &s, .expr = cuts_expr, .leave_expr = cuts_leave};
  for (uint32_t i = 0; i < module->ndecls; i++) {
    ms_walk_decl(&visitor, module->decls[i]);
  }
  ms_arena_free(&scratch);
  flag_list_free(&s.stack);
  const size_t count = s.cuts.len;
  if (count == 0) {
    range_list_free(&s.cuts);
    return false;
  }
  MsByteRange *cuts = s.cuts.ptr;
  qsort(cuts, count, sizeof *cuts, range_order);
  FmtEdit *edits = MS_ARENA_NEW_ARRAY(f->arena, FmtEdit, count);
  size_t kept = 0;
  for (size_t i = 0; i < count; i++) {
    if (i > 0 && cuts[i].start == cuts[i - 1].start && cuts[i].end == cuts[i - 1].end) {
      continue; // duplicate
    }
    edits[kept++] = (FmtEdit){cuts[i].start, cuts[i].end, ms_span_of_text(" ")};
  }
  *out = fmt_apply_edits(f, source, edits, kept);
  range_list_free(&s.cuts);
  return true;
}
