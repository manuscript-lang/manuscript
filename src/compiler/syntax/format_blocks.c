/* syntax/format_blocks.c: the layout of braced blocks. A block that spans lines opens with `{` at the end
 * of a line and closes with `}` at the start of one, `} else {` joining a chain; a block written on one
 * line stays on it. Indentation follows block nesting, so it is computed here rather than kept. */
#include "base/alloc.h"
#include "compiler/syntax/format_internal.h"

enum { INDENT_STEP = 4 };

typedef struct Edge {
  size_t open;  /* token index of the `{` */
  size_t close; /* token index of the matching `}` */
  size_t chain; /* the first block of this block's `else` chain */
} Edge;

MS_LIST_DEFINE(EdgeList, edge_list, Edge)

static bool is_open(MsTok k) {
  return k == MS_T_LParen || k == MS_T_LBracket || k == MS_T_LBrace;
}

static bool is_close(MsTok k) {
  return k == MS_T_RParen || k == MS_T_RBracket || k == MS_T_RBrace;
}

/* Pairs every block brace, and links the blocks of one `if`/`else` chain. False when braces do not balance. */
static bool pair_blocks(const MsToken *tokens, size_t ntokens, EdgeList *edges, size_t **edge_of_open) {
  IndexList stack = {0}; /* open tokens: block opens carry their edge index in the high bit */
  size_t *of_open = ms_alloc_zeroed((ntokens + 1) * sizeof(size_t));
  for (size_t i = 0; i < ntokens; i++) {
    of_open[i] = FMT_NONE;
  }
  IndexList chain_pending = {0}; /* per stack depth: the chain head a following `else` continues */
  size_t pending = FMT_NONE;
  size_t pending_depth = 0;
  bool ok = true;
  for (size_t i = 0; i < ntokens && ok; i++) {
    const MsTok k = (MsTok)tokens[i].kind;
    if (k == MS_T_BlockOpen) {
      Edge e = {i, 0, edges->len};
      if (pending != FMT_NONE && pending_depth == stack.len) {
        e.chain = edges->ptr[pending].chain;
        pending = FMT_NONE;
      }
      index_list_push(&stack, edges->len | ((size_t)1 << 62));
      edge_list_push(edges, e);
      of_open[i] = edges->len - 1;
    } else if (is_open(k)) {
      index_list_push(&stack, i);
    } else if (k == MS_T_BlockClose) {
      if (stack.len == 0 || (stack.ptr[stack.len - 1] >> 62) == 0) {
        ok = false;
        break;
      }
      const size_t edge = stack.ptr[--stack.len] & ~((size_t)1 << 62);
      edges->ptr[edge].close = i;
      if (i + 1 < ntokens && tokens[i + 1].kind == MS_T_Else) {
        pending = edge;
        pending_depth = stack.len;
      }
    } else if (is_close(k)) {
      if (stack.len == 0 || (stack.ptr[stack.len - 1] >> 62) != 0) {
        ok = false;
        break;
      }
      stack.len--;
    }
  }
  index_list_free(&stack);
  index_list_free(&chain_pending);
  *edge_of_open = of_open;
  return ok && stack.len == 0;
}

/* Moves the first statement of a multi-line block to its own line and the closing brace to the start of
 * its line. True when the text changed. */
static bool split_blocks(Fmt *f, MsSpan text, const MsToken *tokens, const EdgeList *edges, MsSpan *out) {
  const size_t n = edges->len;
  bool *multi = ms_alloc_zeroed((n + 1) * sizeof(bool));
  bool *expand = ms_alloc_zeroed((n + 1) * sizeof(bool));
  for (size_t e = 0; e < n; e++) {
    const Edge *edge = &edges->ptr[e];
    multi[e] = tokens[edge->open].pos.line != tokens[edge->close].pos.line;
  }
  for (size_t e = 0; e < n; e++) {
    if (multi[e]) {
      for (size_t other = 0; other < n; other++) {
        if (edges->ptr[other].chain == edges->ptr[e].chain) {
          expand[other] = true;
        }
      }
    }
  }
  MsStrBuild result = {0};
  size_t copied = 0;
  bool changed = false;
  for (size_t e = 0; e < n; e++) {
    if (!expand[e]) {
      continue;
    }
    const Edge *edge = &edges->ptr[e];
    const MsToken *open = &tokens[edge->open];
    const MsToken *close = &tokens[edge->close];
    const size_t after = edge->open + 1;
    const bool nonempty = edge->close != after;
    /* A `...` body or an empty block stays as written. */
    if (nonempty && tokens[after].kind != MS_T_Newline && tokens[after].pos.line == open->pos.line &&
        !(tokens[after].kind == MS_T_Ellipsis && edge->close == after + 1)) {
      if (open->hi >= copied) {
        fmt_put(&result, fmt_slice(text, copied, open->hi));
        ms_strbuild_append_byte(&result, '\n');
        copied = open->hi;
        changed = true;
      }
    }
    const size_t before = edge->close - 1;
    if (nonempty && tokens[before].kind != MS_T_Newline && tokens[before].end.line == close->pos.line &&
        !(tokens[after].kind == MS_T_Ellipsis && edge->close == after + 1)) {
      size_t cut = close->lo;
      while (cut > copied && text.ptr[cut - 1] == ' ') {
        cut--;
      }
      if (cut >= copied) {
        fmt_put(&result, fmt_slice(text, copied, cut));
        ms_strbuild_append_byte(&result, '\n');
        copied = close->lo;
        changed = true;
      }
    }
  }
  ms_free(multi);
  ms_free(expand);
  if (!changed) {
    ms_strbuild_free(&result);
    return false;
  }
  fmt_put(&result, fmt_slice(text, copied, text.len));
  *out = fmt_take(f, &result);
  return true;
}

/* The indentation of every line, from block nesting: a line that starts a statement or a block closer sits at
 * its block's depth, and a continuation line keeps its distance from the statement it continues. */
static bool reindent(Fmt *f, MsSpan text, const MsToken *tokens, size_t ntokens, MsSpan *out) {
  SpanList lines = {0};
  const size_t nlines = fmt_split_lines(text, &lines);
  int64_t *want = ms_alloc_zeroed((nlines + 2) * sizeof(int64_t));
  bool *known = ms_alloc_zeroed((nlines + 2) * sizeof(bool));
  IndexList stack = {0};  /* 1 for a block, 0 for another delimiter */
  IndexList blocks = {0}; /* per open block: the line of its `{` */
  IndexList stmts = {0};  /* per block level: the line of the current statement's first line */
  size_t stmt_line = 0;
  size_t last_line = 0;
  for (size_t i = 0; i < ntokens; i++) {
    const MsToken *t = &tokens[i];
    const MsTok k = (MsTok)t->kind;
    if (k == MS_T_Newline || k == MS_T_Eof) {
      continue;
    }
    const size_t line = t->pos.line;
    const bool first = line != last_line;
    last_line = line;
    const bool at_block = stack.len == 0 || stack.ptr[stack.len - 1] == 1;
    if (first && line >= 1 && line <= nlines) {
      const int64_t orig = (int64_t)fmt_indent_of(lines.ptr[line - 1]);
      const bool continues = k == MS_T_Dot || k == MS_T_Pipe;
      if (at_block && !continues) {
        int64_t base = 0;
        if (blocks.len > 0) {
          const size_t opener = blocks.ptr[blocks.len - 1];
          base = known[opener] ? want[opener] : (int64_t)fmt_indent_of(lines.ptr[opener - 1]);
          base += k == MS_T_BlockClose ? 0 : INDENT_STEP;
        }
        want[line] = base;
        known[line] = true;
        stmt_line = line;
      } else {
        const size_t s = stmt_line == 0 ? line : stmt_line;
        const int64_t s_orig = (int64_t)fmt_indent_of(lines.ptr[s - 1]);
        const int64_t s_want = known[s] ? want[s] : s_orig;
        int64_t base = orig + (s_want - s_orig);
        if (continues && at_block) {
          base = s_want + INDENT_STEP;
        }
        want[line] = base < 0 ? 0 : base;
        known[line] = true;
      }
    }
    if (k == MS_T_BlockOpen) {
      index_list_push(&stack, 1);
      index_list_push(&blocks, line);
      index_list_push(&stmts, stmt_line);
      stmt_line = 0;
    } else if (is_open(k)) {
      index_list_push(&stack, 0);
    } else if (k == MS_T_BlockClose) {
      if (stack.len > 0) {
        stack.len--;
      }
      if (blocks.len > 0) {
        blocks.len--;
      }
      if (stmts.len > 0) {
        stmt_line = stmts.ptr[--stmts.len];
      }
    } else if (is_close(k) && stack.len > 0) {
      stack.len--;
    }
  }
  /* Blank lines and comment lines take the shift of the next line with tokens. */
  int64_t next_shift = 0;
  bool have_shift = false;
  int64_t *shift = ms_alloc_zeroed((nlines + 2) * sizeof(int64_t));
  for (size_t line = nlines; line >= 1; line--) {
    if (known[line]) {
      next_shift = want[line] - (int64_t)fmt_indent_of(lines.ptr[line - 1]);
      have_shift = true;
      shift[line] = next_shift;
    } else if (!fmt_is_blank(lines.ptr[line - 1]) && have_shift) {
      shift[line] = next_shift;
    }
  }
  bool changed = false;
  MsStrBuild result = {0};
  for (size_t line = 1; line <= nlines; line++) {
    const MsSpan content = lines.ptr[line - 1];
    if (fmt_is_blank(content) || shift[line] == 0) {
      fmt_put(&result, content);
    } else {
      const int64_t indent = (int64_t)fmt_indent_of(content) + shift[line];
      fmt_spaces(&result, indent < 0 ? 0 : (size_t)indent);
      fmt_put(&result, fmt_trim_start_set(content, " "));
      changed = true;
    }
    if (line < nlines) {
      ms_strbuild_append_byte(&result, '\n');
    }
  }
  ms_free(want);
  ms_free(known);
  ms_free(shift);
  index_list_free(&stack);
  index_list_free(&blocks);
  index_list_free(&stmts);
  span_list_free(&lines);
  if (!changed) {
    ms_strbuild_free(&result);
    return false;
  }
  *out = fmt_take(f, &result);
  return true;
}

bool fmt_normalize_blocks(Fmt *f, MsSpan text, const MsToken *tokens, size_t ntokens, MsSpan *out) {
  EdgeList edges = {0};
  size_t *of_open = NULL;
  const bool balanced = pair_blocks(tokens, ntokens, &edges, &of_open);
  ms_free(of_open);
  bool changed = false;
  if (balanced && split_blocks(f, text, tokens, &edges, out)) {
    changed = true;
  } else if (reindent(f, text, tokens, ntokens, out)) {
    changed = true;
  }
  edge_list_free(&edges);
  return changed;
}
