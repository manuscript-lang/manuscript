/* syntax/format_layout.c: the layout pass entry point. */
#include "compiler/syntax/format_layout.h"
#include "compiler/syntax/walk.h"

/* ---- the layout pass ---- */

typedef struct FlagsCtx {
  Layout *layout;
} FlagsCtx;

static void flags_expr(void *ctx, const MsExpr *e) {
  Layout *l = ((FlagsCtx *)ctx)->layout;
  switch ((MsExprKind)e->kind) {
  case MS_E_CALL: {
    if (e->u.call.args.len == 0) {
      return;
    }
    // Interpolation is part of one atomic string token.
    const int32_t g = lay_lookup(l, l->by_item, e->u.call.args.ptr[0].pos.offset);
    if (g < 0) {
      return;
    }
    lay_group_at(l, (size_t)g)->items = true;
    for (uint32_t i = 0; i < e->u.call.args.len; i++) {
      if (fmt_block_lambda(e->u.call.args.ptr[i].value)) {
        lay_group_at(l, (size_t)g)->force = true;
      }
    }
    break;
  }
  case MS_E_LIST: {
    const int32_t g = lay_lookup(l, l->by_open, e->pos.offset);
    if (g >= 0) {
      lay_group_at(l, (size_t)g)->list = true;
    }
    break;
  }
  case MS_E_LAMBDA:
    lay_parameters(l, e->u.lambda.params);
    break;
  default:
    break;
  }
}

static bool lay_import_clauses(MsSpan text, Nodes nodes, size_t index, const Group *g) {
  if (g->open.kind != MS_T_LParen || index < 1 || nodes.ptr[index - 1].tok.kind != MS_T_Import) {
    return false;
  }
  for (size_t k = 0; k < g->nodes.len; k++) {
    if (g->nodes.ptr[k].tok.kind == MS_T_Name && fmt_is(fmt_token_text(text, &g->nodes.ptr[k].tok), "from")) {
      return true;
    }
  }
  return false;
}

/* The width that follows group `index` on its closing line. Only a method call in a chain counts
 * what follows it; other groups (type arguments, clause patterns) keep their own line. */
static size_t lay_group_following(const Layout *l, MsSpan text, Nodes nodes, size_t index, const Group *g) {
  if (g->open.kind != MS_T_LParen) {
    return 0;
  }
  if (index >= 2 && nodes.ptr[index - 1].tok.kind == MS_T_Name && nodes.ptr[index - 2].tok.kind == MS_T_Dot) {
    return lay_following_width(l, (Nodes){nodes.ptr + index + 1, nodes.len - index - 1}, true);
  }
  if (index >= 1 && nodes.ptr[index - 1].tok.kind == MS_T_Import) {
    // The `from "path"` clause shares the closing line.
    const MsSpan rest = fmt_slice(text, g->close.hi, text.len);
    const size_t end = fmt_find_byte(rest, '\n');
    return fmt_chars(end == FMT_NONE ? rest : fmt_slice(rest, 0, end));
  }
  return 0;
}

/* Parses and lexes `*text`. */
static bool layout_parse(Fmt *f, MsArena *scratch, MsSpan *text, MsModule *module, MsLexed *lexed) {
  return fmt_parse(f, scratch, *text, module) && fmt_lex(f, scratch, *text, lexed);
}

/* Renders every group of `nodes` flat or broken into `output`, copying the text between them. */
static void layout_render(const Layout *l, MsSpan text, Nodes nodes, MsStrBuild *output) {
  size_t offset = 0;
  for (size_t index = 0; index < nodes.len; index++) {
    if (nodes.ptr[index].group < 0) {
      continue;
    }
    const size_t gid = (size_t)nodes.ptr[index].group;
    const Group *g = lay_group_at(l, gid);
    if (lay_import_clauses(text, nodes, index, g)) {
      continue;
    }
    fmt_put(output, fmt_slice(text, offset, g->open.lo));
    const MsSpan so_far = fmt_tail(output, 0);
    const size_t newline = fmt_rfind_byte(so_far, '\n');
    const MsSpan line = newline == FMT_NONE ? so_far : fmt_slice(so_far, newline + 1, so_far.len);
    lay_group(l, gid, fmt_indent_of(line), fmt_chars(line), lay_group_following(l, text, nodes, index, g),
              output);
    offset = g->close.hi;
  }
  fmt_put(output, fmt_slice(text, offset, text.len));
}

bool fmt_expression_layout(Fmt *f, MsSpan source, MsSpan *out) {
  MsSpan text;
  if (!fmt_group_statement_expressions(f, source, true, &text) ||
      !fmt_group_statement_expressions(f, text, false, &text)) {
    return false;
  }
  MsArena scratch = {0};
  MsModule module;
  MsLexed lexed;
  if (!layout_parse(f, &scratch, &text, &module, &lexed)) {
    ms_arena_free(&scratch);
    return false;
  }
  MsArena tree = {0};
  SpanList line_buf = {0};
  size_t start = 0;
  for (size_t i = 0; i <= text.len; i++) {
    if (i == text.len || text.ptr[i] == '\n') {
      const MsSpan line = fmt_slice(text, start, i);
      span_list_push(&line_buf, line);
      start = i + 1;
    }
  }
  Layout l = {.fmt = f, .arena = &tree, .src = text, .lines = line_buf.ptr, .nlines = line_buf.len};
  l.by_open = MS_ARENA_NEW_ARRAY(&tree, uint32_t, text.len + 2);
  l.by_item = MS_ARENA_NEW_ARRAY(&tree, uint32_t, text.len + 2);
  memset(l.by_open, 0, (text.len + 2) * sizeof *l.by_open);
  memset(l.by_item, 0, (text.len + 2) * sizeof *l.by_item);
  size_t ntokens;
  const MsToken *with_comments = lay_layout_tokens(&l, lexed.tokens, lexed.ntokens, &ntokens);
  TokenList code = {0};
  size_t at = 0;
  const Nodes nodes = lay_sequence_tree(&l, with_comments, ntokens, &at, &code, -1);
  token_list_free(&code);
  FlagsCtx flags = {&l};
  const MsVisitor visitor = {.ctx = &flags, .expr = flags_expr};
  for (uint32_t i = 0; i < module.ndecls; i++) {
    lay_declaration(&l, module.decls[i]);
    ms_walk_decl(&visitor, module.decls[i]);
  }
  MsStrBuild output = {0};
  layout_render(&l, text, nodes, &output);
  *out = fmt_take(f, &output);
  span_list_free(&line_buf);
  group_list_free(&l.groups);
  ms_arena_free(&tree);
  ms_arena_free(&scratch);
  return true;
}
