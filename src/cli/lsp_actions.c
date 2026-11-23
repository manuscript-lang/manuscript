/* cli/lsp_actions.c: code actions over one checked document. */
#include "cli/lsp_actions.h"

#include <stdlib.h>

#include "cli/findings.h"
#include "compiler/syntax/format.h"
#include "tooling/lint.h"

typedef struct Actions {
  const LspDocList *docs;
  const LspDoc *doc;
  MsSpan source;
  LspRange requested;
  const MsSpan *only;
  size_t only_count;
  MsStrBuild *out;
  bool first;
} Actions;

static bool wanted(const Actions *actions, const char *kind) {
  if (actions->only_count == 0) return true;
  const MsSpan have = ms_span_of_text(kind);
  for (size_t i = 0; i < actions->only_count; i++) {
    const MsSpan want = actions->only[i];
    if (ms_span_equal(have, want)) return true;
    if (have.len > want.len && ms_span_starts_with(have, want) && have.ptr[want.len] == '.') return true;
  }
  return false;
}

static bool eligible(const Actions *actions, LspRange range) {
  return range.start.line <= actions->requested.end.line && range.end.line >= actions->requested.start.line;
}

static void write_range(MsStrBuild *out, LspRange range) {
  ms_strbuild_printf(out, "{\"start\":{\"line\":%zu,\"character\":%zu},\"end\":{\"line\":%zu,\"character\":%zu}}",
                     range.start.line, range.start.character, range.end.line, range.end.character);
}

/* One text edit as JSON. */
static void append_edit(MsStrBuild *edits, LspRange range, MsSpan text) {
  if (ms_strbuild_span(edits).len > 0) ms_strbuild_append_byte(edits, ',');
  ms_strbuild_append_text(edits, "{\"range\":");
  write_range(edits, range);
  ms_strbuild_append_text(edits, ",\"newText\":");
  lsp_json_string(edits, text);
  ms_strbuild_append_byte(edits, '}');
}

/* A diagnostic as the server published it, for an action to pair with. */
static void append_diagnostic(MsStrBuild *out, LspRange range, MsSpan message, MsSpan code, const char *source) {
  ms_strbuild_append_text(out, "{\"range\":");
  write_range(out, range);
  ms_strbuild_append_text(out, ",\"message\":");
  lsp_json_string(out, message);
  ms_strbuild_append_text(out, ",\"code\":");
  lsp_json_string(out, code);
  ms_strbuild_append_text(out, ",\"source\":");
  lsp_json_string(out, ms_span_of_text(source));
  ms_strbuild_append_byte(out, '}');
}

static void emit(Actions *actions, MsSpan title, const char *kind, MsSpan edits, MsSpan diagnostic) {
  if (!wanted(actions, kind)) return;
  MsStrBuild *out = actions->out;
  if (!actions->first) ms_strbuild_append_byte(out, ',');
  actions->first = false;
  ms_strbuild_append_text(out, "{\"title\":");
  lsp_json_string(out, title);
  ms_strbuild_append_text(out, ",\"kind\":");
  lsp_json_string(out, ms_span_of_text(kind));
  ms_strbuild_append_text(out, ",\"edit\":{\"documentChanges\":[{\"textDocument\":{\"uri\":");
  lsp_json_string(out, ms_string_span(&actions->doc->uri));
  ms_strbuild_printf(out, ",\"version\":%lld},\"edits\":[", (long long)actions->doc->version);
  ms_strbuild_append(out, edits);
  ms_strbuild_append_text(out, "]}]}");
  if (diagnostic.len > 0) {
    ms_strbuild_append_text(out, ",\"diagnostics\":[");
    ms_strbuild_append(out, diagnostic);
    ms_strbuild_append_text(out, "],\"isPreferred\":true");
  }
  ms_strbuild_append_byte(out, '}');
}

static void format_action(Actions *actions) {
  MsArena arena = ms_arena_new();
  MsStrBuild formatted = ms_strbuild_new();
  MsDiag diag;
  if (ms_format(&arena, actions->source, &formatted, &diag) && !ms_span_equal(ms_strbuild_span(&formatted), actions->source)) {
    MsStrBuild edits = ms_strbuild_new();
    append_edit(&edits, (LspRange){{0, 0}, lsp_position(actions->source, actions->source.len)}, ms_strbuild_span(&formatted));
    emit(actions, ms_span_of_text("Format Manuscript document"), "source.fixAll.manuscript", ms_strbuild_span(&edits), (MsSpan){0});
    ms_strbuild_free(&edits);
  }
  ms_strbuild_free(&formatted);
  ms_arena_free(&arena);
}

static LspRange fix_range(const Actions *actions, const MsDiag *diag) {
  return (LspRange){lsp_position(actions->source, diag->fix_pos.offset), lsp_position(actions->source, diag->fix_end.offset)};
}

/* The checker's machine-applicable fixes, the edits `ms check --fix` applies. */
static void checker_fixes(Actions *actions, LspAnalysis *analysis) {
  for (size_t i = 0; i < analysis->checked.findings.len; i++) {
    const Finding *finding = &analysis->checked.findings.ptr[i];
    if (finding->lint_code != NULL || !finding->diag.has_fix) continue;
    const MsSpan file = lsp_absolute_file(&analysis->arena, analysis->checked.graph.source_root, finding->file);
    if (!ms_span_equal(file, ms_string_span(&actions->doc->path))) continue;
    const MsDiag *diag = &finding->diag;
    const MsSpan code = ms_span_of_text(finding_code(finding));
    const bool prelude = ms_span_is_text(code, "MS2003");
    if (!prelude && ms_span_starts_with(diag->replacement, ms_span_of_text("import "))) continue; /* its own action */
    LspRange shown;
    if (prelude) {
      if (!diag->has_end) continue;
      shown = (LspRange){lsp_position(actions->source, diag->pos.offset), lsp_position(actions->source, diag->end.offset)};
    } else {
      shown = lsp_diagnostic_range(actions->source, diag->pos.offset);
    }
    if (!eligible(actions, shown)) continue;
    MsStrBuild title = ms_strbuild_new();
    if (prelude) {
      ms_strbuild_append_text(&title, "Remove redundant prelude import");
    } else if (diag->replacement.len == 0) {
      ms_strbuild_append_text(&title, "Remove the flagged text");
    } else {
      ms_strbuild_append_text(&title, diag->fix_pos.offset == diag->fix_end.offset ? "Insert `" : "Replace with `");
      ms_strbuild_append(&title, diag->replacement);
      ms_strbuild_append_byte(&title, '`');
    }
    MsStrBuild edits = ms_strbuild_new(), diagnostic = ms_strbuild_new();
    append_edit(&edits, fix_range(actions, diag), diag->replacement);
    append_diagnostic(&diagnostic, shown, diag->message, code, "manuscript");
    emit(actions, ms_strbuild_span(&title), "quickfix", ms_strbuild_span(&edits), ms_strbuild_span(&diagnostic));
    ms_strbuild_free(&title);
    ms_strbuild_free(&edits);
    ms_strbuild_free(&diagnostic);
  }
}

/* Trailing whitespace and the missing final newline. */
static void lexical_fixes(Actions *actions, MsArena *arena) {
  MsLintFindingList lint = {0};
  ms_lint_source(arena, ms_string_span(&actions->doc->path), actions->source, &lint);
  for (size_t i = 0; i < lint.len; i++) {
    const MsLintFinding *item = &lint.ptr[i];
    const bool trailing = ms_span_is_text(ms_span_of_text(item->code), "MSL001");
    if (!trailing && !ms_span_is_text(ms_span_of_text(item->code), "MSL002")) continue;
    const LspPosition at = lsp_position(actions->source, item->pos.offset);
    if (!eligible(actions, (LspRange){at, at})) continue;
    LspPosition end = at;
    const char *title = "Insert final newline";
    MsSpan text = ms_span_of_text("\n");
    if (trailing) {
      title = "Remove trailing whitespace";
      size_t n = item->pos.offset;
      while (n < actions->source.len && actions->source.ptr[n] != '\n') n++;
      if (n > item->pos.offset && actions->source.ptr[n - 1] == '\r') n--;
      end = lsp_position(actions->source, n);
      text = ms_span_of_text("");
    }
    MsStrBuild edits = ms_strbuild_new(), diagnostic = ms_strbuild_new();
    append_edit(&edits, (LspRange){at, end}, text);
    append_diagnostic(&diagnostic, (LspRange){at, at}, item->message, ms_span_of_text(item->code), "manuscript-lint");
    emit(actions, ms_span_of_text(title), "quickfix", ms_strbuild_span(&edits), ms_strbuild_span(&diagnostic));
    ms_strbuild_free(&edits);
    ms_strbuild_free(&diagnostic);
  }
  ms_lint_finding_list_free(&lint);
}

static void unused_imports(Actions *actions, LspAnalysis *analysis) {
  MsLintFindingList lint = {0};
  ms_lint_modules(&analysis->arena, &analysis->checked.program, &lint);
  for (size_t i = 0; i < lint.len; i++) {
    const MsLintFinding *item = &lint.ptr[i];
    if (!item->has_fix || !ms_span_is_text(ms_span_of_text(item->code), "MSL102")) continue;
    const MsSpan file = lsp_absolute_file(&analysis->arena, analysis->checked.graph.source_root, item->file);
    if (!ms_span_equal(file, ms_string_span(&actions->doc->path))) continue;
    const LspPosition at = lsp_position(actions->source, item->pos.offset);
    if (!eligible(actions, (LspRange){at, at})) continue;
    MsStrBuild edits = ms_strbuild_new(), diagnostic = ms_strbuild_new();
    append_edit(&edits, (LspRange){lsp_position(actions->source, item->fix_pos.offset), lsp_position(actions->source, item->fix_end.offset)},
                item->replacement);
    append_diagnostic(&diagnostic, (LspRange){at, at}, item->message, ms_span_of_text(item->code), "manuscript-lint");
    emit(actions, ms_span_of_text("Remove unused import"), "quickfix", ms_strbuild_span(&edits), ms_strbuild_span(&diagnostic));
    ms_strbuild_free(&edits);
    ms_strbuild_free(&diagnostic);
  }
  ms_lint_finding_list_free(&lint);
}

/* ---- organize imports ---- */

typedef struct Statement {
  MsSpan text, path;
} Statement;

static int compare_statement(const void *left, const void *right) {
  const Statement *a = left, *b = right;
  const MsSpan pairs[2][2] = {{a->path, b->path}, {a->text, b->text}};
  for (size_t k = 0; k < 2; k++) {
    const MsSpan x = pairs[k][0], y = pairs[k][1];
    const size_t common = x.len < y.len ? x.len : y.len;
    for (size_t i = 0; i < common; i++) {
      if (x.ptr[i] != y.ptr[i]) return x.ptr[i] < y.ptr[i] ? -1 : 1;
    }
    if (x.len != y.len) return x.len < y.len ? -1 : 1;
  }
  return 0;
}

static int compare_offset(const void *left, const void *right) {
  const size_t a = *(const size_t *)left, b = *(const size_t *)right;
  return a == b ? 0 : (a < b ? -1 : 1);
}

static MsSpan trim(MsSpan text) {
  while (text.len > 0 && (text.ptr[0] == ' ' || text.ptr[0] == '\t' || text.ptr[0] == '\r' || text.ptr[0] == '\n')) {
    text.ptr++;
    text.len--;
  }
  while (text.len > 0 && (text.ptr[text.len - 1] == ' ' || text.ptr[text.len - 1] == '\t' || text.ptr[text.len - 1] == '\r' ||
                          text.ptr[text.len - 1] == '\n')) {
    text.len--;
  }
  return text;
}

/* The text after the last ` from ` of a statement, trimmed; empty when it has none. */
static MsSpan import_path(MsSpan statement) {
  MsSpan path = {0};
  size_t at;
  MsSpan rest = statement;
  while (ms_span_find(rest, ms_span_of_text(" from "), &at)) {
    rest = ms_span_of(rest.ptr + at + 6, rest.len - at - 6);
    path = rest;
  }
  return trim(path);
}

/* For each import statement of the module, the last line it occupies, indexed by its first line; SIZE_MAX elsewhere. */
static size_t *import_end_lines(MsSpan source, const MsModule *module, size_t line_count) {
  size_t *ends = malloc((line_count + 1) * sizeof *ends);
  for (size_t i = 0; i <= line_count; i++) ends[i] = (size_t)-1;
  size_t n = (size_t)module->nimports + module->ndecls + 1;
  size_t *boundaries = malloc(n * sizeof *boundaries);
  size_t count = 0;
  for (uint32_t i = 0; i < module->nimports; i++) boundaries[count++] = module->imports[i].pos.offset;
  for (uint32_t i = 0; i < module->ndecls; i++) boundaries[count++] = module->decls[i]->pos.offset;
  boundaries[count++] = source.len;
  qsort(boundaries, count, sizeof *boundaries, compare_offset);
  for (uint32_t i = 0; i < module->nimports; i++) {
    const size_t start = module->imports[i].pos.offset;
    const size_t line = module->imports[i].pos.line - 1;
    if (line >= line_count || ends[line] != (size_t)-1) continue;
    size_t end = source.len;
    bool found = false;
    for (size_t b = 0; b < count && !found; b++) {
      if (boundaries[b] > start) {
        end = boundaries[b];
        found = true;
      }
    }
    if (!found || start > source.len) continue;
    const MsSpan part = ms_span_of(source.ptr + start, end - start);
    LspTokenList tokens = {0};
    lsp_scan_tokens(part, &tokens);
    for (size_t t = 0; t < tokens.len; t++) {
      if (tokens.ptr[t].kind == LSP_TOKEN_STRING) {
        ends[line] = lsp_position(source, start + tokens.ptr[t].end).line;
        break;
      }
    }
    lsp_token_list_free(&tokens);
  }
  free(boundaries);
  return ends;
}

static void organize_imports(Actions *actions, const MsModule *module) {
  const MsSpan source = actions->source;
  size_t line_count = 0;
  for (size_t i = 0; i < source.len; i++) line_count += source.ptr[i] == '\n';
  if (source.len > 0 && source.ptr[source.len - 1] != '\n') line_count++;
  size_t *starts = malloc((line_count + 1) * sizeof *starts);
  size_t at_line = 0;
  starts[0] = 0;
  for (size_t i = 0; i < source.len && at_line < line_count; i++) {
    if (source.ptr[i] == '\n') starts[++at_line] = i + 1;
  }
  starts[line_count] = source.len;
  size_t *ends = import_end_lines(source, module, line_count);
  MsStrBuild edits = ms_strbuild_new();
  bool crlf = false;
  for (size_t i = 1; i < source.len; i++) crlf |= source.ptr[i] == '\n' && source.ptr[i - 1] == '\r';
  size_t at = 0;
  while (at < line_count) {
    if (ends[at] == (size_t)-1) {
      at++;
      continue;
    }
    const size_t start = at;
    Statement *block = NULL;
    size_t count = 0;
    while (at < line_count && ends[at] != (size_t)-1 && ends[at] < line_count) {
      const size_t end = ends[at];
      block = realloc(block, (count + 1) * sizeof *block);
      block[count++] = (Statement){ms_span_of(source.ptr + starts[at], starts[end + 1] - starts[at]), {0}};
      at = end + 1;
    }
    const size_t from = starts[start], to = starts[at];
    const MsSpan before = ms_span_of(source.ptr + from, to - from);
    const bool missing = before.len > 0 && before.ptr[before.len - 1] != '\n';
    for (size_t i = 0; i < count; i++) block[i].path = import_path(block[i].text);
    qsort(block, count, sizeof *block, compare_statement);
    MsStrBuild after = ms_strbuild_new();
    for (size_t i = 0; i < count; i++) {
      ms_strbuild_append(&after, block[i].text);
      if (missing && block[i].text.len > 0 && block[i].text.ptr[block[i].text.len - 1] != '\n') {
        ms_strbuild_append_text(&after, crlf ? "\r\n" : "\n");
      }
    }
    MsSpan result = ms_strbuild_span(&after);
    if (missing && result.len > 0) result.len -= result.len > 1 && result.ptr[result.len - 2] == '\r' ? 2 : 1;
    if (!ms_span_equal(result, before)) {
      append_edit(&edits, (LspRange){lsp_position(source, from), lsp_position(source, to)}, result);
    }
    ms_strbuild_free(&after);
    free(block);
  }
  if (ms_strbuild_span(&edits).len > 0) emit(actions, ms_span_of_text("Organize imports"), "source.organizeImports", ms_strbuild_span(&edits), (MsSpan){0});
  ms_strbuild_free(&edits);
  free(ends);
  free(starts);
}

void lsp_code_actions(const LspDocList *docs, const LspDoc *doc, LspRange requested, const MsSpan *only, size_t count,
                      MsStrBuild *out) {
  Actions actions = {docs, doc, ms_string_span(&doc->text), requested, only, count, out, true};
  ms_strbuild_append_byte(out, '[');
  format_action(&actions);
  LspAnalysis analysis;
  lsp_analyze(docs, doc, &analysis);
  checker_fixes(&actions, &analysis);
  lexical_fixes(&actions, &analysis.arena);
  if (analysis.resolved) {
    unused_imports(&actions, &analysis);
    const MsCheckProgram *program = &analysis.checked.program;
    for (uint32_t m = 0; m < program->user_modules; m++) {
      if (ms_span_equal(analysis.paths[m], ms_string_span(&doc->path))) organize_imports(&actions, program->modules.ptr[m].tree);
    }
  }
  lsp_analysis_release(&analysis);
  ms_strbuild_append_byte(out, ']');
}
