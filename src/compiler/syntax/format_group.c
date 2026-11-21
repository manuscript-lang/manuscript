/* syntax/format_group.c: statement grouping: wrapping the expressions of one statement. */
#include "base/sort.h"
#include "compiler/syntax/format_layout.h"
#include "compiler/syntax/walk.h"

/* ---- statement grouping ---- */

#define NO_PAIR UINT32_MAX

typedef struct Edit {
  size_t offset;
  size_t order;
  bool close; /* a `)` that goes before everything else at the offset */
  MsSpan text;
} Edit;
MS_LIST_DEFINE(InsertList, insert_list, Edit)

typedef struct Grouper {
  Fmt *fmt;
  MsSpan source;
  const MsToken *tokens;
  size_t ntokens;
  uint32_t *pairs; /* the close bracket's token index for each open bracket's, NO_PAIR elsewhere */
  InsertList insert;
  EditList remove;
  bool strip;
} Grouper;

/* The last token starting at `offset`, or FMT_NONE. */
static size_t group_start_of(const Grouper *g, uint32_t offset) {
  size_t low = 0;
  size_t high = g->ntokens;
  while (low < high) {
    const size_t mid = low + (high - low) / 2;
    if (g->tokens[mid].pos.offset <= offset) {
      low = mid + 1;
    } else {
      high = mid;
    }
  }
  if (low == 0 || g->tokens[low - 1].pos.offset != offset) {
    return FMT_NONE;
  }
  return low - 1;
}

/* The close bracket matching the open bracket token `open`, or FMT_NONE. */
static size_t group_pair(const Grouper *g, size_t open) {
  return g->pairs[open] == NO_PAIR ? FMT_NONE : g->pairs[open];
}

static void group_insert(Grouper *g, size_t offset, bool close, MsSpan text) {
  const Edit edit = {offset, g->insert.len, close, text};
  insert_list_push(&g->insert, edit);
}

/* The flat text of tokens [from, to), layout tokens skipped. */
static MsSpan group_flat(Grouper *g, size_t from, size_t to) {
  MsStrBuild flat = {0};
  TokenList code = {0};
  for (size_t i = from; i < to; i++) {
    const MsToken *t = &g->tokens[i];
    if (fmt_layout_token((MsTok)t->kind)) {
      continue;
    }
    token_list_push(&code, *t);
    const size_t n = code.len;
    if (n > 1 && fmt_token_space(code.ptr, n - 1)) {
      ms_strbuild_append_byte(&flat, (uint8_t)(' '));
    }
    fmt_put(&flat, fmt_token_text(g->source, t));
  }
  token_list_free(&code);
  return fmt_take(g->fmt, &flat);
}

/* Parentheses around a whole method chain only add a line; the layout pass restores them when the
 * chain cannot hug its last call. */
static void group_unwrap_chain(Grouper *g, size_t start) {
  const MsToken *tokens = g->tokens;
  const size_t close = group_pair(g, start);
  if (close == FMT_NONE || tokens[start].kind != MS_T_LParen) {
    return;
  }
  if (start > 0) {
    switch ((MsTok)tokens[start - 1].kind) {
    case MS_T_Assign:
    case MS_T_ColonAssign:
    case MS_T_Return:
    case MS_T_Newline:
    case MS_T_Indent:
    case MS_T_Dedent:
      break;
    default:
      return;
    }
  }
  if (close + 1 < g->ntokens) {
    switch ((MsTok)tokens[close + 1].kind) {
    case MS_T_Newline:
    case MS_T_Dedent:
    case MS_T_Colon:
    case MS_T_Eof:
      break;
    default:
      return;
    }
  }
  int depth = 0;
  int dots = 0;
  for (size_t i = start + 1; i < close; i++) {
    const MsTok k = (MsTok)tokens[i].kind;
    if (fmt_is_open(k)) {
      depth++;
    } else if (k == MS_T_RParen || k == MS_T_RBracket || k == MS_T_RBrace) {
      depth--;
    } else if (k == MS_T_Dot && depth == 0) {
      dots++;
    } else if (k == MS_T_Newline || k == MS_T_Indent || k == MS_T_Dedent || k == MS_T_Fn || k == MS_T_If ||
               k == MS_T_Else ||
               // an operator or flow step: the parentheses decide the grouping
               (depth == 0 && (k == MS_T_Pipe || k == MS_T_And || k == MS_T_Or || fmt_is_comparison(k) ||
                               fmt_is_arith(k)))) {
      return;
    }
  }
  const MsSpan inner = fmt_slice(g->source, tokens[start].hi, tokens[close].lo);
  if (dots >= 1 && !fmt_contains(inner, "//") && tokens[start + 1].kind != MS_T_Dot) {
    const FmtEdit edit = {tokens[start].lo, tokens[close].hi, group_flat(g, start + 1, close)};
    edit_list_push(&g->remove, edit);
  }
}

typedef struct Call {
  size_t open, close;
} Call;
MS_LIST_DEFINE(CallList, call_list, Call)

/* What a value expression is made of, at its top level. */
typedef struct WrapScan {
  size_t end;
  int booleans, dots, operators, pipes;
  CallList calls; /* the calls whose arguments could break */
} WrapScan;

/* Counts the operators of the value that starts at tokens[start] and ends before offset `limit`.
 * False when an indented suite makes the value impossible to wrap. */
static bool group_scan(Grouper *g, size_t start, uint32_t limit, WrapScan *scan) {
  const MsToken *tokens = g->tokens;
  scan->end = start;
  while (scan->end < g->ntokens && tokens[scan->end].pos.offset < limit) {
    const size_t at = scan->end;
    const size_t close = group_pair(g, at);
    if (close != FMT_NONE) {
      // A call with a trivial argument gains nothing from breaking.
      if (tokens[at].kind == MS_T_LParen && close > at + 3) {
        call_list_push(&scan->calls, ((Call){at, close}));
      }
      scan->end = close + 1;
      continue;
    }
    const MsTok kind = (MsTok)tokens[at].kind;
    if (fmt_layout_token(kind)) {
      return false; // an indented suite cannot be wrapped as a partial value
    }
    if (kind == MS_T_And || kind == MS_T_Or) {
      scan->booleans++;
    } else if (kind == MS_T_Dot) {
      // A line starting with `.` after a flow step applies to the whole flow, which
      // `| .name` spells out as a stage of its own.
      if (scan->pipes > 0 && at > start && tokens[at].pos.line != tokens[at - 1].pos.line &&
          tokens[at - 1].kind != MS_T_Pipe && tokens[at - 1].kind != MS_T_Try) {
        group_insert(g, tokens[at].lo, false, ms_span_of_text("| "));
        scan->pipes++;
      }
      scan->dots++;
    } else if (kind == MS_T_Pipe) {
      scan->pipes++;
    } else if (fmt_is_arith(kind) || fmt_is_comparison(kind)) {
      scan->operators++;
    }
    scan->end++;
  }
  return true;
}

/* Whether the opening parenthesis of one of the calls still fits on the first line, so the chain
 * can break inside that call rather than wrap whole. */
static bool group_hugs(const Grouper *g, size_t start, size_t column, const CallList *calls) {
  const MsToken *tokens = g->tokens;
  const Call *list = calls->ptr;
  for (size_t c = 0; c < calls->len; c++) {
    size_t head = column;
    TokenList code = {0};
    for (size_t i = start; i <= list[c].open; i++) {
      if (fmt_layout_token((MsTok)tokens[i].kind)) {
        continue;
      }
      token_list_push(&code, tokens[i]);
      const size_t n = code.len;
      if (n > 1 && fmt_token_space(code.ptr, n - 1)) {
        head += 1;
      }
      head += tokens[i].hi - tokens[i].lo;
    }
    token_list_free(&code);
    if (head <= FMT_WIDTH) {
      return true;
    }
  }
  return false;
}

static void group_wrap(Grouper *g, size_t start, uint32_t limit) {
  if (g->strip) {
    return;
  }
  const MsToken *tokens = g->tokens;
  WrapScan scan = {0};
  const bool wrappable = group_scan(g, start, limit, &scan);
  if (!wrappable || scan.end == start) {
    call_list_free(&scan.calls);
    return;
  }
  const size_t end = scan.end;
  const int operators = scan.booleans + scan.operators + scan.pipes;
  const MsSpan flat = group_flat(g, start, end);
  const size_t column = tokens[start].pos.column - 1;
  size_t width = column + fmt_chars(flat);
  if (end < g->ntokens && tokens[end].kind == MS_T_Colon) {
    width += 1; // the condition's suite colon occupies a column too
  }
  const bool hugs = operators == 0 && group_hugs(g, start, column, &scan.calls);
  call_list_free(&scan.calls);
  if ((scan.pipes >= 2 && width > FMT_FLOW_WIDTH) ||
      (width > FMT_WIDTH && !hugs && (operators > 0 || scan.dots >= 2))) {
    group_insert(g, tokens[start].lo, false, ms_span_of_text("("));
    group_insert(g, tokens[end - 1].hi, true, ms_span_of_text(")"));
  }
}

/* The start of the value of an index store, `xs[i] = value`, which is the call of `[]=`. */
static size_t group_call_value_start(const Grouper *g, const MsExpr *value, size_t start) {
  const MsToken *tokens = g->tokens;
  // `xs[i] = value` is a call of `[]=`; only the value wraps.
  size_t at = start;
  while (at < g->ntokens && tokens[at].pos.offset < value->end.offset) {
    const size_t end = group_pair(g, at);
    if (end != FMT_NONE) {
      at = end + 1;
      continue;
    }
    if (tokens[at].kind == MS_T_Assign) {
      start = at + 1;
      break;
    }
    at++;
  }
  return start;
}

/* The token index where the wrapped value of statement `s` starts, given the statement's first token. */
static size_t group_value_start(const Grouper *g, const MsStmt *s, const MsExpr *value, size_t start) {
  const MsToken *tokens = g->tokens;
  switch ((MsStmtKind)s->kind) {
  case MS_S_IF:
    start += 1;
    if (s->u.branch.binding != NULL) {
      // `if let name = value:` wraps only the value.
      while (tokens[start].kind != MS_T_Assign && tokens[start].kind != MS_T_ColonAssign) {
        start++;
      }
      start++;
    }
    break;
  case MS_S_WHILE:
    start += 1;
    break;
  case MS_S_RETURN:
    if (tokens[start].kind == MS_T_Return) {
      start += 1;
    }
    break;
  case MS_S_BIND:
    if (tokens[start].kind == MS_T_Void) {
      // `void value` is a binding of `_` with no `:=` token; only the value wraps.
      start += 1;
      break;
    }
    MS_FALLTHROUGH;
  case MS_S_ASSIGN:
  case MS_S_FOR: {
    const bool is_for = s->kind == MS_S_FOR;
    while (is_for ? tokens[start].kind != MS_T_In
                  : (tokens[start].kind != MS_T_Assign && tokens[start].kind != MS_T_ColonAssign)) {
      const size_t end = group_pair(g, start);
      if (end != FMT_NONE) {
        start = end;
      }
      start++;
    }
    start++;
    break;
  }
  case MS_S_CALL:
    return group_call_value_start(g, value, start);
  default:
    break;
  }
  return start;
}

static void group_stmt(void *ctx, const MsStmt *s) {
  Grouper *g = ctx;
  if (fmt_is_destructure_head(s)) {
    return;
  }
  const MsExpr *value = fmt_statement_value(s);
  if (value == NULL || fmt_suite_expression(value)) {
    return;
  }
  size_t start = group_start_of(g, s->pos.offset);
  if (start == FMT_NONE) {
    return;
  }
  const MsToken *tokens = g->tokens;
  if (tokens[start].kind == MS_T_String || tokens[start].kind == MS_T_Fn) {
    return;
  }
  group_wrap(g, group_value_start(g, s, value, start), value->end.offset);
}

static int64_t fmt_edit_order(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  const FmtEdit *x = (const void *)a;
  const FmtEdit *y = (const void *)b;
  if (x->from != y->from) {
    return x->from < y->from ? -1 : 1;
  }
  if (x->to != y->to) {
    return x->to < y->to ? -1 : 1;
  }
  return fmt_compare(x->text, y->text);
}

static int64_t insert_order(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  const Edit *x = (const void *)a;
  const Edit *y = (const void *)b;
  if (x->offset != y->offset) {
    return x->offset < y->offset ? -1 : 1;
  }
  return x->order < y->order ? -1 : 1;
}

/* Matches each opening delimiter with its closing one: `pairs[open] = close`. */
static void group_match_pairs(Grouper *g, MsArena *scratch) {
  g->pairs = MS_ARENA_NEW_ARRAY(scratch, uint32_t, g->ntokens + 1);
  for (size_t i = 0; i < g->ntokens; i++) {
    g->pairs[i] = NO_PAIR;
  }
  IndexList stack = {0};
  for (size_t i = 0; i < g->ntokens; i++) {
    const MsTok k = (MsTok)g->tokens[i].kind;
    if (fmt_is_open(k)) {
      index_list_push(&stack, i);
    } else if ((k == MS_T_RParen || k == MS_T_RBracket || k == MS_T_RBrace) && stack.len != 0) {
      g->pairs[(*index_list_last(&stack))] = (uint32_t)i;
      index_list_truncate(&stack, stack.len - 1);
    }
  }
  index_list_free(&stack);
}

/* The source with the grouping parentheses of `g.insert` added: all the text inserted at one
 * offset is the `)` that go in front, then the rest in the order it was added. */
static MsSpan group_apply_inserts(Fmt *f, MsSpan source, Grouper *g) {
  const size_t count = g->insert.len;
  Edit *ops = g->insert.ptr;
  if (count > 1) {
    ms_sort((uint8_t *)ops, count, sizeof *ops, insert_order, NULL);
  }
  FmtEdit *edits = MS_ARENA_NEW_ARRAY(f->arena, FmtEdit, count + 1);
  size_t nedits = 0;
  for (size_t i = 0; i < count;) {
    size_t end = i;
    MsStrBuild text = {0};
    while (end < count && ops[end].offset == ops[i].offset) {
      if (ops[end].close) {
        ms_strbuild_append(&text, ms_span_of((const uint8_t *)(ops[end].text.ptr), ops[end].text.len));
      }
      end++;
    }
    for (size_t k = i; k < end; k++) {
      if (!ops[k].close) {
        ms_strbuild_append(&text, ms_span_of((const uint8_t *)(ops[k].text.ptr), ops[k].text.len));
      }
    }
    edits[nedits++] = (FmtEdit){ops[i].offset, ops[i].offset, fmt_take(f, &text)};
    i = end;
  }
  return fmt_apply_edits(f, source, edits, nedits);
}

/* Ordinary newlines cannot split ungrouped expressions. Adds grouping only around a statement's
 * complete value, retaining its precedence and inline suite. With `strip`, removes parentheses
 * around a whole method chain instead. */
bool fmt_group_statement_expressions(Fmt *f, MsSpan source, bool strip, MsSpan *out) {
  MsArena scratch = {0};
  MsModule module;
  MsLexed lexed;
  if (!fmt_parse(f, &scratch, source, &module) || !fmt_lex(f, &scratch, source, &lexed)) {
    ms_arena_free(&scratch);
    return false;
  }
  Grouper g = {.fmt = f, .source = source, .tokens = lexed.tokens, .ntokens = lexed.ntokens, .strip = strip};
  group_match_pairs(&g, &scratch);
  if (strip) {
    for (size_t start = 0; start < lexed.ntokens; start++) {
      group_unwrap_chain(&g, start);
    }
  }
  const MsVisitor visitor = {.ctx = &g, .stmt = group_stmt};
  for (uint32_t i = 0; i < module.ndecls; i++) {
    const MsDecl *d = module.decls[i];
    // A constant's synthetic statement starts at its initializer, which may be text, so it
    // bypasses the keyword and text-statement handling.
    if (d->kind == MS_D_CONST && !fmt_suite_expression(d->u.konst.value)) {
      const size_t start = group_start_of(&g, d->u.konst.init_pos.offset);
      if (start != FMT_NONE) {
        group_wrap(&g, start, d->u.konst.value->end.offset);
      }
    }
    ms_walk_decl(&visitor, d);
  }
  if (strip) {
    const size_t count = g.remove.len;
    FmtEdit *edits = g.remove.ptr;
    if (count > 1) {
      ms_sort((uint8_t *)edits, count, sizeof *edits, fmt_edit_order, NULL);
    }
    *out = fmt_apply_edits(f, source, edits, count);
  } else {
    *out = group_apply_inserts(f, source, &g);
  }
  insert_list_free(&g.insert);
  edit_list_free(&g.remove);
  ms_arena_free(&scratch);
  return true;
}

/* A grouped import is laid out one clause per line by `group_imports`; the item layout would
 * split inside a clause. */
