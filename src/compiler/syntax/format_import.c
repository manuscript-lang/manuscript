/* syntax/format_import.c: import grouping and wrapping. */
#include "base/sort.h"
#include "compiler/syntax/format_internal.h"
#include "compiler/syntax/walk.h"

/* Import section of a module path: public standard library, standard-library internals, then
 * everything else. `path` includes its opening quote. */
int fmt_import_section(MsSpan path) {
  if (fmt_starts(path, "\"@std/internal/")) {
    return 1;
  }
  return fmt_starts(path, "\"@std/") ? 0 : 2;
}

typedef struct ImportClause {
  MsSpan *names;
  size_t nnames;
  MsSpan path;
} ImportClause;
MS_LIST_DEFINE(ClauseList, clause_list, ImportClause)

typedef struct ImportStatement {
  size_t lo, hi;
  ImportClause *clauses;
  size_t nclauses;
  bool commented; /* a comment splits the runs around this import */
} ImportStatement;
MS_LIST_DEFINE(StatementList, statement_list, ImportStatement)

static int64_t str_order(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  const MsSpan *x = (const void *)a;
  const MsSpan *y = (const void *)b;
  return fmt_compare(*x, *y);
}

typedef struct MergedImport {
  MsSpan path;
  SpanList names;
} MergedImport;
MS_LIST_DEFINE(MergedList, merged_list, MergedImport)

static int64_t merged_order(uint8_t *env, const uint8_t *a, const uint8_t *b) {
  (void)env;
  const MergedImport *x = (const void *)a;
  const MergedImport *y = (const void *)b;
  const int sections = fmt_import_section(x->path) - fmt_import_section(y->path);
  return sections != 0 ? sections : str_order(env, (const uint8_t *)&x->path, (const uint8_t *)&y->path);
}

/* The names joined by ", ". */
static void fmt_put_joined(MsStrBuild *out, const MsSpan *names, size_t count) {
  for (size_t i = 0; i < count; i++) {
    if (i > 0) {
      ms_strbuild_append_text(out, ", ");
    }
    fmt_put(out, names[i]);
  }
}

static MsSpan fmt_render_imports(Fmt *f, MergedImport *merged, size_t count) {
  MsStrBuild out = {0};
  if (count == 1) {
    const MsSpan *names = merged[0].names.ptr;
    const size_t n = merged[0].names.len;
    MsStrBuild flat = {0};
    ms_strbuild_append_text(&flat, "import ");
    fmt_put_joined(&flat, names, n);
    ms_strbuild_append_text(&flat, " from ");
    fmt_put(&flat, merged[0].path);
    if (fmt_chars(fmt_tail(&flat, 0)) <= FMT_WIDTH) {
      return fmt_take(f, &flat);
    }
    ms_strbuild_free(&flat);
    ms_strbuild_append_text(&out, "import (\n");
    for (size_t i = 0; i < n; i++) {
      ms_strbuild_append_text(&out, "    ");
      fmt_put(&out, names[i]);
      ms_strbuild_append_text(&out, ",\n");
    }
    ms_strbuild_append_text(&out, ") from ");
    fmt_put(&out, merged[0].path);
    return fmt_take(f, &out);
  }
  ms_strbuild_append_text(&out, "import (\n");
  for (size_t k = 0; k < count; k++) {
    const MsSpan *names = merged[k].names.ptr;
    const size_t n = merged[k].names.len;
    MsStrBuild flat = {0};
    ms_strbuild_append_text(&flat, "    ");
    fmt_put_joined(&flat, names, n);
    ms_strbuild_append_text(&flat, " from ");
    fmt_put(&flat, merged[k].path);
    ms_strbuild_append_byte(&flat, (uint8_t)(','));
    if (fmt_chars(fmt_tail(&flat, 0)) <= FMT_WIDTH) {
      fmt_put(&out, fmt_tail(&flat, 0));
      ms_strbuild_append_byte(&out, (uint8_t)('\n'));
      ms_strbuild_free(&flat);
      continue;
    }
    ms_strbuild_free(&flat);
    // A clause too wide for a line puts one name on each line.
    for (size_t i = 0; i < n; i++) {
      ms_strbuild_append_text(&out, "    ");
      fmt_put(&out, names[i]);
      if (i + 1 == n) {
        ms_strbuild_append_text(&out, " from ");
        fmt_put(&out, merged[k].path);
      }
      ms_strbuild_append_text(&out, ",\n");
    }
  }
  ms_strbuild_append_byte(&out, (uint8_t)(')'));
  return fmt_take(f, &out);
}

/* The clauses of the import statement that starts at tokens[first] and ends before tokens[end]. */
static ImportStatement fmt_read_import(Fmt *f, MsSpan source, const MsToken *tokens, size_t ntokens,
                                       size_t first, size_t end) {
  ImportStatement stmt = {.lo = tokens[first].lo, .hi = tokens[end - 1].hi};
  SpanList names = {0};
  ClauseList clauses = {0};
  for (size_t at = first + 1; at < end; at++) {
    const MsToken *t = &tokens[at];
    const bool clause_end = t->kind == MS_T_Name && fmt_is(fmt_token_text(source, t), "from") &&
                            at + 1 < ntokens && tokens[at + 1].kind == MS_T_String;
    if (clause_end) {
      ImportClause clause = {.nnames = names.len, .path = fmt_token_text(source, &tokens[at + 1])};
      clause.names = MS_ARENA_NEW_ARRAY(f->arena, MsSpan, clause.nnames);
      if (clause.nnames != 0) {
        memcpy(clause.names, names.ptr, clause.nnames * sizeof(MsSpan));
      }
      clause_list_push(&clauses, clause);
      names.len = 0;
      at++;
    } else if (t->kind == MS_T_Name) {
      span_list_push(&names, fmt_token_text(source, t));
    }
  }
  span_list_free(&names);
  stmt.nclauses = clauses.len;
  stmt.clauses = MS_ARENA_NEW_ARRAY(f->arena, ImportClause, stmt.nclauses);
  if (stmt.nclauses != 0) {
    memcpy(stmt.clauses, clauses.ptr, stmt.nclauses * sizeof(ImportClause));
  }
  clause_list_free(&clauses);
  stmt.commented = fmt_contains(fmt_slice(source, stmt.lo, stmt.hi), "//");
  return stmt;
}

/* Every top-level import statement, in source order. */
static void fmt_collect_imports(Fmt *f, MsSpan source, const MsToken *tokens, size_t ntokens,
                                StatementList *statements) {
  size_t i = 0;
  while (i < ntokens) {
    if (tokens[i].kind != MS_T_Import) {
      i++;
      continue;
    }
    size_t end = i + 1;
    while (end < ntokens && tokens[end].kind != MS_T_Newline && tokens[end].kind != MS_T_Eof) {
      end++;
    }
    statement_list_push(statements, fmt_read_import(f, source, tokens, ntokens, i, end));
    i = end;
  }
}

/* The merged import clause for `path`, added when new. */
static MergedImport *fmt_merged_for(MergedList *merged_buf, MsSpan path) {
  MergedImport *merged = merged_buf->ptr;
  const size_t nmerged = merged_buf->len;
  for (size_t m = 0; m < nmerged; m++) {
    if (fmt_eq(merged[m].path, path)) {
      return &merged[m];
    }
  }
  merged_list_push(merged_buf, ((MergedImport){.path = path}));
  return merged_list_last(merged_buf);
}

/* Sorts the names of a clause and drops duplicates. */
static void fmt_sort_names(SpanList *names) {
  MsSpan *items = names->ptr;
  const size_t n = names->len;
  if (n <= 1) {
    return;
  }
  ms_sort((uint8_t *)items, n, sizeof *items, str_order, NULL);
  size_t kept = 1;
  for (size_t j = 1; j < n; j++) {
    if (!fmt_eq(items[j], items[kept - 1])) {
      items[kept++] = items[j];
    }
  }
  names->len = kept;
}

/* The canonical text of the imports in list[from, to). */
static MsSpan fmt_render_run(Fmt *f, const ImportStatement *list, size_t from, size_t to) {
  MergedList merged_buf = {0};
  for (size_t s = from; s < to; s++) {
    for (size_t c = 0; c < list[s].nclauses; c++) {
      const ImportClause *clause = &list[s].clauses[c];
      MergedImport *target = fmt_merged_for(&merged_buf, clause->path);
      for (size_t n = 0; n < clause->nnames; n++) {
        span_list_push(&target->names, clause->names[n]);
      }
    }
  }
  MergedImport *merged = merged_buf.ptr;
  const size_t nmerged = merged_buf.len;
  for (size_t m = 0; m < nmerged; m++) {
    fmt_sort_names(&merged[m].names);
  }
  if (nmerged > 1) {
    ms_sort((uint8_t *)merged, nmerged, sizeof *merged, merged_order, NULL);
  }
  const MsSpan rendered = fmt_render_imports(f, merged, nmerged);
  for (size_t m = 0; m < nmerged; m++) {
    span_list_free(&merged[m].names);
  }
  merged_list_free(&merged_buf);
  return rendered;
}

/* The end of the run of imports that starts at list[from]: nothing but whitespace between them. */
static size_t fmt_import_run_end(MsSpan source, const ImportStatement *list, size_t count, size_t from) {
  size_t run = from + 1;
  while (run < count && fmt_is_blank(fmt_slice(source, list[run - 1].hi, list[run].lo))) {
    run++;
  }
  return run;
}

/* Rewrites each run of adjacent top-level imports (nothing but whitespace between them) into one
 * canonical form: clauses merged per module, names sorted, clauses ordered by section (standard
 * library, internals, other) and path, with a blank line between sections. A single clause that
 * fits on a line is a bare `import names from "path"`; anything else is a grouped `import (...)`
 * with one `names from "path"` clause per line. An import with a comment, inside or after it,
 * stays as written. False when nothing changes. */
bool fmt_group_imports(Fmt *f, MsSpan source, const MsToken *tokens, size_t ntokens, MsSpan *out) {
  StatementList statements = {0};
  fmt_collect_imports(f, source, tokens, ntokens, &statements);
  const ImportStatement *list = statements.ptr;
  const size_t count = statements.len;
  MsStrBuild result = {0};
  size_t copied = 0;
  bool changed = false;
  for (size_t k = 0; k < count;) {
    const size_t first = k;
    const size_t run = fmt_import_run_end(source, list, count, first);
    k = run;
    bool commented = false;
    for (size_t s = first; s < run; s++) {
      commented = commented || list[s].commented;
    }
    if (commented) {
      continue;
    }
    const size_t start = list[first].lo;
    const size_t end = list[run - 1].hi;
    const MsSpan rendered = fmt_render_run(f, list, first, run);
    if (!fmt_eq(fmt_slice(source, start, end), rendered)) {
      fmt_put(&result, fmt_slice(source, copied, start));
      fmt_put(&result, rendered);
      copied = end;
      changed = true;
    }
  }
  statement_list_free(&statements);
  if (!changed) {
    ms_strbuild_free(&result);
    return false;
  }
  fmt_put(&result, fmt_slice(source, copied, source.len));
  *out = fmt_take(f, &result);
  return true;
}

/* A bare import list wider than the line wraps into the parenthesized form, one name per line with
 * a trailing comma. Parenthesized imports keep the author's layout, so a second pass leaves the
 * wrapped form unchanged. */
bool fmt_wrap_import(Fmt *f, const MsToken *parts, size_t nparts, MsSpan flat, MsSpan source, MsSpan *out) {
  if (nparts < 2 || parts[0].kind != MS_T_Import || parts[1].kind == MS_T_LParen ||
      fmt_chars(flat) <= FMT_WIDTH) {
    return false;
  }
  // `from` is also a valid imported name, so the clause boundary is the token just before the
  // path, not the first token spelled `from`.
  size_t path = 0;
  while (path < nparts && parts[path].kind != MS_T_String) {
    path++;
  }
  if (path == nparts || path == 0) {
    return false;
  }
  const size_t from = path - 1;
  if (from == 0 || !fmt_is(fmt_token_text(source, &parts[from]), "from") || from + 1 >= nparts) {
    return false;
  }
  MsStrBuild text = {0};
  const size_t indent = parts[0].pos.column - 1;
  fmt_spaces(&text, indent);
  ms_strbuild_append_text(&text, "import (\n");
  for (size_t i = 1; i < from; i++) {
    if (parts[i].kind == MS_T_Name) {
      fmt_spaces(&text, indent + 4);
      fmt_put(&text, fmt_token_text(source, &parts[i]));
      ms_strbuild_append_text(&text, ",\n");
    }
  }
  fmt_spaces(&text, indent);
  ms_strbuild_append_text(&text, ") from ");
  fmt_put(&text, fmt_token_text(source, &parts[from + 1]));
  *out = fmt_take(f, &text);
  return true;
}

/* ---- comment reflow ---- */
