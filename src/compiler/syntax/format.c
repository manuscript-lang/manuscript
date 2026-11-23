/* syntax/format.c: paragraph breaks, the line pass and the entry point ms_format. */
#include "compiler/syntax/format.h"
#include "base/alloc.h"
#include "compiler/syntax/format_internal.h"
#include "compiler/syntax/walk.h"

typedef struct Paragraphs {
  Fmt *fmt;
  const MsSpan *lines;
  size_t nlines;
  bool *breaks; /* by line number */
} Paragraphs;

/* Keeps leading comments with the node they describe, ignoring authored blank lines. Stops at code
 * or a different indentation. */
static void para_before(Paragraphs *p, size_t line) {
  const size_t indent = fmt_indent_of(p->lines[line - 1]);
  while (line > 1) {
    const MsSpan previous = p->lines[line - 2];
    if (fmt_is_blank(previous)) {
      line--;
      continue;
    }
    if (!fmt_starts(fmt_trim(previous), "//") || fmt_indent_of(previous) != indent) {
      break;
    }
    line--;
  }
  p->breaks[line] = true;
}

static bool para_leading_comment(const Paragraphs *p, size_t line) {
  const size_t indent = fmt_indent_of(p->lines[line - 1]);
  for (size_t i = line - 1; i > 0; i--) {
    const MsSpan candidate = p->lines[i - 1];
    if (!fmt_is_blank(candidate)) {
      return fmt_starts(fmt_trim_start(candidate), "//") && fmt_indent_of(candidate) == indent;
    }
  }
  return false;
}

/* A binding that names something. `void value` is a binding of `_` and reads as a call. */
static bool para_is_binding(const Paragraphs *p, const MsStmt *s) {
  if (s->kind != MS_S_BIND) {
    return false;
  }
  const MsPattern *pattern = s->u.bind.pattern;
  return !(pattern->kind == MS_P_NAME && fmt_is(ms_names_span(p->fmt->names, pattern->u.name), "_"));
}

/* The line a binding starts on; a binding in a `var (...)` group starts on the group's keyword
 * line so the group moves as one unit. */
static size_t para_statement_line(const MsStmt *s) {
  return s->kind == MS_S_BIND && s->u.bind.has_group ? s->u.bind.group.line : s->pos.line;
}

static bool para_guard_statement(const MsStmt *s) {
  if (s->kind != MS_S_IF || s->u.branch.else_body.len != 0 || s->u.branch.body.len != 1) {
    return false;
  }
  const uint8_t kind = s->u.branch.body.ptr[0]->kind;
  return kind == MS_S_RETURN || kind == MS_S_BREAK || kind == MS_S_CONTINUE;
}

static bool para_block(const MsStmt *s) {
  // Single-step blocks belong to the surrounding cluster. Count syntax, rather than source
  // lines, so wrapping a header cannot add paragraphs on the next formatting pass.
  const MsExpr *value = fmt_statement_value(s);
  if (value != NULL) {
    while (value->kind == MS_E_UNARY) {
      value = value->u.bin.left;
    }
    if (fmt_is_written_match(value) || fmt_block_lambda(value)) {
      return true;
    }
    if (value->kind == MS_E_CALL) {
      for (uint32_t i = 0; i < value->u.call.args.len; i++) {
        if (fmt_block_lambda(value->u.call.args.ptr[i].value)) {
          return true;
        }
      }
    }
  }
  switch ((MsStmtKind)s->kind) {
  case MS_S_IF:
    return !para_guard_statement(s) && (s->u.branch.body.len > 1 || s->u.branch.else_body.len != 0 ||
                                        (s->u.branch.body.len == 1 && para_block(s->u.branch.body.ptr[0])));
  case MS_S_WHILE:
    return s->u.loop.body.len > 1 || (s->u.loop.body.len == 1 && para_block(s->u.loop.body.ptr[0]));
  case MS_S_FOR:
    return s->u.each.body.len > 1 || (s->u.each.body.len == 1 && para_block(s->u.each.body.ptr[0]));
  default:
    return false;
  }
}

static void para_visit_block(void *ctx, MsStmts body) {
  Paragraphs *p = ctx;
  for (uint32_t i = 1; i < body.len; i++) {
    const MsStmt *previous = body.ptr[i - 1];
    const MsStmt *current = body.ptr[i];
    const size_t line = para_statement_line(current);
    if (para_statement_line(previous) == line) {
      continue;
    }
    const bool lone_return = body.len == 2 && current->kind == MS_S_RETURN;
    if (para_block(previous) || para_block(current) ||
        (para_guard_statement(previous) && !para_guard_statement(current) && !lone_return) ||
        (!para_is_binding(p, previous) && para_is_binding(p, current)) || para_leading_comment(p, line)) {
      para_before(p, line);
    }
  }
}

enum { GROUP_NONE, GROUP_CONSTANT, GROUP_ALIAS, GROUP_IMPORT };

/* Breaks between top-level declarations and import sections. */
static void para_top_level(Paragraphs *p, const MsModule *module, size_t nlines) {
  Fmt *f = p->fmt;
  // Imports may be interleaved with declarations. Separate each import section while keeping
  // consecutive imports, constants and aliases together.
  uint8_t *group_of = MS_ARENA_NEW_ARRAY(f->arena, uint8_t, nlines + 2);
  memset(group_of, GROUP_NONE, nlines + 2);
  U32List top_level = {0};
  for (uint32_t i = 0; i < module->ndecls; i++) {
    const MsDecl *d = module->decls[i];
    u32_list_push(&top_level, d->pos.line);
    if (d->kind == MS_D_CONST) {
      group_of[d->pos.line] = GROUP_CONSTANT;
    } else if (d->kind == MS_D_ALIAS) {
      group_of[d->pos.line] = GROUP_ALIAS;
    }
  }
  for (uint32_t i = 0; i < module->nimports; i++) {
    const uint32_t line = module->imports[i].pos.line;
    if (group_of[line] == GROUP_NONE) {
      u32_list_push(&top_level, line);
    }
    group_of[line] = GROUP_IMPORT;
  }
  uint32_t *lines_sorted = top_level.ptr;
  const size_t ntop = top_level.len;
  // Insertion into a sorted order by line number.
  for (size_t i = 1; i < ntop; i++) {
    const uint32_t key = lines_sorted[i];
    size_t j = i;
    while (j > 0 && lines_sorted[j - 1] > key) {
      lines_sorted[j] = lines_sorted[j - 1];
      j--;
    }
    lines_sorted[j] = key;
  }
  for (size_t i = 1; i < ntop; i++) {
    const uint8_t a = group_of[lines_sorted[i - 1]];
    const uint8_t b = group_of[lines_sorted[i]];
    if (a == GROUP_NONE || a != b) {
      para_before(p, lines_sorted[i]);
    }
  }
  u32_list_free(&top_level);
}

/* Clauses of a grouped import are separated by section. */
static void para_import_clauses(Paragraphs *p, const MsModule *module) {
  Fmt *f = p->fmt;
  for (uint32_t i = 1; i < module->nimports; i++) {
    const MsImport *a = &module->imports[i - 1];
    const MsImport *b = &module->imports[i];
    if (a->pos.offset == b->pos.offset && a->pos.line == b->pos.line && a->pos.column == b->pos.column &&
        (a->clause.offset != b->clause.offset || a->clause.line != b->clause.line ||
         a->clause.column != b->clause.column)) {
      const MsSpan qa = ms_message_format(f->arena, "\"%S", a->path);
      const MsSpan qb = ms_message_format(f->arena, "\"%S", b->path);
      if (fmt_import_section(qa) != fmt_import_section(qb)) {
        para_before(p, b->clause.line);
      }
    }
  }
}

static void fmt_paragraph_breaks(Fmt *f, const MsModule *module, const MsSpan *lines, size_t nlines,
                                 bool *breaks) {
  Paragraphs p = {.fmt = f, .lines = lines, .nlines = nlines, .breaks = breaks};
  para_top_level(&p, module, nlines);
  para_import_clauses(&p, module);
  const MsVisitor visitor = {.ctx = &p, .block = para_visit_block};
  for (uint32_t i = 0; i < module->ndecls; i++) {
    const MsDecl *d = module->decls[i];
    // Implementation bodies are separate reading units. Interface signatures remain a compact
    // list of the contract's operations.
    if (d->kind == MS_D_IMPL) {
      for (uint32_t m = 1; m < d->u.impl.methods.len; m++) {
        para_before(&p, d->u.impl.methods.ptr[m]->pos.line);
      }
    }
    ms_walk_decl(&visitor, d);
  }
}

/* ---- the line pass ---- */

typedef enum LineStep { LINE_FAILED, LINE_DONE, LINE_AGAIN } LineStep;

/* The code tokens of a source (layout tokens left out), grouped by line: line `n` holds the run
 * of `count[n]` tokens starting at `code[first[n]]`. */
typedef struct LineTokens {
  MsToken *code;
  uint32_t *first, *count;
} LineTokens;

static LineTokens fmt_line_tokens(Fmt *f, const MsLexed *lexed, size_t nlines) {
  LineTokens index = {.code = MS_ARENA_NEW_ARRAY(f->arena, MsToken, lexed->ntokens + 1),
                      .first = MS_ARENA_NEW_ARRAY(f->arena, uint32_t, nlines + 3),
                      .count = MS_ARENA_NEW_ARRAY(f->arena, uint32_t, nlines + 3)};
  memset(index.count, 0, (nlines + 3) * sizeof *index.count);
  size_t ncode = 0;
  for (size_t i = 0; i < lexed->ntokens; i++) {
    const MsToken *t = &lexed->tokens[i];
    if (fmt_layout_token((MsTok)t->kind)) {
      continue;
    }
    if (index.count[t->pos.line] == 0) {
      index.first[t->pos.line] = (uint32_t)ncode;
    }
    index.count[t->pos.line]++;
    index.code[ncode++] = *t;
  }
  return index;
}

/* One line of code: token spacing, a wrapped import, and the trailing comment kept. */
static MsSpan fmt_code_line(Fmt *f, MsSpan source, MsSpan line, const MsToken *parts, size_t nparts) {
  MsStrBuild formatted = {0};
  fmt_spaces(&formatted, parts[0].pos.column - 1);
  for (size_t i = 0; i < nparts; i++) {
    if (i > 0 && fmt_token_space(parts, i)) {
      ms_strbuild_append_byte(&formatted, (uint8_t)(' '));
    }
    fmt_put(&formatted, fmt_token_text(source, &parts[i]));
  }
  const MsToken *last = &parts[nparts - 1];
  const size_t tail = last->pos.column - 1 + (last->hi - last->lo);
  MsSpan rows;
  if (fmt_wrap_import(f, parts, nparts, ms_strbuild_span(&formatted), source, &rows)) {
    ms_strbuild_clear(&formatted);
    fmt_put(&formatted, rows);
  }
  if (tail < line.len) {
    const size_t comment = fmt_find(fmt_slice(line, tail, line.len), ms_span_of_text("//"));
    if (comment != FMT_NONE) {
      ms_strbuild_append_text(&formatted, "  ");
      fmt_put(&formatted, fmt_trim_end_set(fmt_slice(line, tail + comment, line.len), " \t"));
    }
  }
  return fmt_take(f, &formatted);
}

/* A comment-only line: indentation snapped down to a multiple of four. */
static MsSpan fmt_comment_line(Fmt *f, MsSpan line) {
  const MsSpan stripped = fmt_trim_start_set(line, " ");
  MsStrBuild text = {0};
  fmt_spaces(&text, (size_t)((line.len - stripped.len) / 4) * 4);
  fmt_put(&text, fmt_trim_end_set(stripped, " \t"));
  return fmt_take(f, &text);
}

/* The formatted lines of `lines`, with paragraph breaks. `*realigned` is set when a comment-only
 * line changed indentation: it can need the blank lines a dedent gets, which only the next pass
 * sees. */
static void fmt_format_lines(Fmt *f, MsSpan source, const MsSpan *lines, size_t nlines, const bool *breaks,
                             const LineTokens *index, SpanList *output, bool *realigned) {
  bool blank = true;
  for (size_t at = 0; at < nlines; at++) {
    const MsSpan line = lines[at];
    if (breaks[at + 1] && !blank) {
      span_list_push(output, ms_span_of_text(""));
      blank = true;
    }
    const size_t nparts = index->count[at + 1];
    if (nparts != 0) {
      span_list_push(output, fmt_code_line(f, source, line, &index->code[index->first[at + 1]], nparts));
      blank = false;
    } else if (!fmt_is_blank(line)) {
      *realigned = *realigned || fmt_indent_of(line) % 4 != 0;
      span_list_push(output, fmt_comment_line(f, line));
      blank = false;
    } else if (!blank && at > 0 && fmt_starts(fmt_trim(lines[at - 1]), "//")) {
      // A blank line after a comment-only line separates the comment block from what follows
      // (a module header from the first declaration's doc).
      span_list_push(output, ms_span_of_text(""));
      blank = true;
    }
  }
}

/* Reflows comments and lays out expressions in the formatted lines; false when the text stops
 * parsing. */
static bool fmt_finish_lines(Fmt *f, const SpanList *output, MsSpan *result) {
  size_t nout = output->len;
  while (nout > 0 && output->ptr[nout - 1].len == 0) {
    nout--;
  }
  if (nout == 0) {
    *result = ms_span_of_text("");
    return true;
  }
  SpanList wrapped = {0};
  fmt_wrap_comments(f, output->ptr, nout, &wrapped);
  MsStrBuild joined = {0};
  for (size_t i = 0; i < wrapped.len; i++) {
    fmt_put(&joined, wrapped.ptr[i]);
    ms_strbuild_append_byte(&joined, (uint8_t)('\n'));
  }
  span_list_free(&wrapped);
  const MsSpan joined_text = fmt_take(f, &joined);
  MsModule module;
  MsArena check = {0};
  const bool valid = fmt_expression_layout(f, joined_text, result) && fmt_parse(f, &check, *result, &module);
  ms_arena_free(&check);
  return valid;
}

/* The suite headers re-laid out by expression layout move their suites with them: the lines and
 * the lexed tokens are replaced. */
static bool fmt_realign_headers(Fmt *f, MsArena *scratch, SpanList *aligned, MsSpan *normalized,
                                MsLexed *lexed) {
  *normalized = fmt_join_lines(f, aligned->ptr, aligned->len);
  MsArena relex = {0};
  if (!fmt_lex(f, &relex, *normalized, lexed)) {
    ms_arena_free(&relex);
    return false;
  }
  // The new tokens live in `relex`, which replaces the first arena for the rest of the pass.
  ms_arena_free(scratch);
  *scratch = relex;
  return true;
}

/* One run of the line passes. LINE_AGAIN means `*out` is a rewritten source to run them on again. */
static LineStep format_lines_step(Fmt *f, MsSpan source, MsSpan *out) {
  MsSpan normalized = fmt_normalize(f, source);
  SpanList line_list = {0};
  size_t nlines = fmt_split_lines(normalized, &line_list);
  const MsSpan *lines = line_list.ptr;
  MsArena scratch = {0};
  LineStep step = LINE_FAILED;
  SpanList aligned = {0};
  SpanList output = {0};
  MsModule module;
  MsLexed lexed;
  MsSpan changed;
  if (!fmt_parse(f, &scratch, normalized, &module)) {
    goto done;
  }
  if (fmt_compact(f, &module, normalized, &changed)) {
    MsArena probe = {0};
    MsModule compacted_module;
    const bool parses = fmt_parse(f, &probe, changed, &compacted_module);
    ms_arena_free(&probe);
    if (parses) {
      *out = changed;
      step = LINE_AGAIN;
      goto done;
    }
  }
  bool *breaks = MS_ARENA_NEW_ARRAY(f->arena, bool, nlines + 2);
  memset(breaks, 0, (nlines + 2) * sizeof *breaks);
  fmt_paragraph_breaks(f, &module, lines, nlines, breaks);
  if (!fmt_lex(f, &scratch, normalized, &lexed)) {
    goto done;
  }
  if (fmt_group_imports(f, normalized, lexed.tokens, lexed.ntokens, &changed)) {
    *out = changed;
    step = LINE_AGAIN;
    goto done;
  }
  if (fmt_align_suite_headers(f, lines, nlines, lexed.tokens, lexed.ntokens, &aligned)) {
    nlines = aligned.len;
    lines = aligned.ptr;
    if (!fmt_realign_headers(f, &scratch, &aligned, &normalized, &lexed)) {
      goto done;
    }
  }
  const LineTokens index = fmt_line_tokens(f, &lexed, nlines);
  bool realigned = false;
  fmt_format_lines(f, normalized, lines, nlines, breaks, &index, &output, &realigned);
  MsSpan result;
  if (!fmt_finish_lines(f, &output, &result)) {
    goto done;
  }
  *out = result;
  step = realigned && !fmt_eq(result, source) ? LINE_AGAIN : LINE_DONE;
done:
  ms_arena_free(&scratch);
  span_list_free(&aligned);
  span_list_free(&output);
  span_list_free(&line_list);
  return step;
}

FmtParsed *fmt_parsed_entry(Fmt *f, MsSpan source) {
  for (size_t index = 0; index < f->nparsed; index++) {
    if (fmt_eq(f->parsed[index].text, source)) {
      return &f->parsed[index];
    }
  }
  if (f->nparsed == f->cap_parsed) {
    const size_t cap = f->cap_parsed == 0 ? 16 : f->cap_parsed * 2;
    FmtParsed *grown = ms_realloc(f->parsed, cap * sizeof *grown);
    f->parsed = grown;
    f->cap_parsed = cap;
  }
  FmtParsed *entry = &f->parsed[f->nparsed++];
  *entry = (FmtParsed){.text = ms_arena_copy(&f->memo, source)};
  return entry;
}

void fmt_memo_free(Fmt *f) {
  ms_free(f->parsed);
  ms_arena_free(&f->memo);
}

bool fmt_lines(Fmt *f, MsSpan source, MsSpan *out) {
  for (;;) {
    const LineStep step = format_lines_step(f, source, out);
    if (step != LINE_AGAIN) {
      return step == LINE_DONE;
    }
    source = *out;
  }
}

/* ---- the entry point ---- */
bool ms_format(MsArena *result_arena, MsSpan source, MsStrBuild *out, MsDiag *diag) {
  MsArena arena = {0};
  MsNames names;
  ms_names_init(&names);
  Fmt f = {.arena = &arena, .names = &names};
  MsSpan text = source;
  bool ok = fmt_once(&f, text, &text);
  // Joining a multi-line header can make an `if` body eligible for the one-line form, which the
  // compact pass judged on the unjoined text, so the output is formatted again until the pass
  // has nothing left to do; a second run of `ms fmt` then changes nothing.
  for (int round = 0; ok && round < 4; round++) {
    MsArena scratch = {0};
    MsModule module;
    MsSpan compacted;
    const bool parsed = fmt_parse(&f, &scratch, text, &module);
    const bool again = parsed && fmt_compact(&f, &module, text, &compacted);
    ms_arena_free(&scratch);
    ok = parsed;
    if (!again) {
      break;
    }
    ok = fmt_once(&f, text, &text);
  }
  if (ok) {
    ms_strbuild_append(out, text);
  } else {
    *diag = f.diag;
    diag->message = ms_arena_copy(result_arena, f.diag.message);
    diag->replacement = ms_arena_copy(result_arena, f.diag.replacement);
  }
  fmt_memo_free(&f);
  ms_names_free(&names);
  ms_arena_free(&arena);
  return ok;
}
