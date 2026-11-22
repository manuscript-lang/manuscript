/* Owns findings.h. */
#include "driver/findings.h"

#include <stdio.h>

#include "base/file.h"
#include "base/path.h"
#include "base/sort.h"
#include "driver/snippet.h"


/* The parser lists lexical errors apart from syntax errors, so the graph's diagnostics are put in source order; the
 * checker's keep the order it found them in, which is the oracle's. */
void finding_add_graph(const MsGraph *graph, FindingList *findings) {
  const size_t first = findings->len;
  for (size_t i = 0; i < graph->diagnostic_count; i++) {
    const MsGraphDiag *diag = &graph->diagnostics[i];
    const char *phase = diag->phase == MS_GRAPH_PARSE ? "parse" : "resolution";
    finding_list_push(findings, (Finding){.file = diag->file, .phase = phase, .diag = diag->diag});
  }
  ms_sort((uint8_t *)(findings->ptr + first), findings->len - first, sizeof(Finding), finding_compare, NULL);
}

/* Diagnostics by file, line and column; the sort is stable, so ties keep the order the phases produced them in. */
int64_t finding_compare(uint8_t *env, const uint8_t *left, const uint8_t *right) {
  (void)env;
  const Finding *a = (const void *)left;
  const Finding *b = (const void *)right;
  const size_t common = a->file.len < b->file.len ? a->file.len : b->file.len;
  const int order = common == 0 ? 0 : __builtin_memcmp(a->file.ptr, b->file.ptr, common);
  if (order != 0) {
    return order < 0 ? -1 : 1;
  }
  if (a->file.len != b->file.len) {
    return a->file.len < b->file.len ? -1 : 1;
  }
  if (a->diag.pos.line != b->diag.pos.line) {
    return a->diag.pos.line < b->diag.pos.line ? -1 : 1;
  }
  return a->diag.pos.column < b->diag.pos.column ? -1 : a->diag.pos.column > b->diag.pos.column;
}

void finding_add_check(const MsCheckProgram *program, const MsNames *names, FindingList *findings) {
  for (size_t i = 0; i < program->diagnostics.len; i++) {
    const MsCheckDiag *issue = &program->diagnostics.ptr[i];
    const MsSpan file = ms_names_span(names, program->modules.ptr[issue->module].file);
    const char *phase = issue->phase == MS_CHECK_RESOLUTION ? "resolution" : "type";
    MsDiag diag = {.pos = issue->pos, .message = ms_string_span(&issue->message)};
    diag.has_end = issue->has_end;
    diag.end = issue->end;
    if (issue->has_fix) {
      diag.has_fix = true;
      diag.fix_pos = issue->fix_pos;
      diag.fix_end = issue->fix_end;
      diag.replacement = ms_string_span(&issue->fix_text);
    }
    finding_list_push(findings, (Finding){.file = file, .phase = phase, .diag = diag});
  }
}

/* Whether a diagnostic's file is a fetched package's: `@id/path`, which has no place in the project's directory. */
bool finding_is_package_file(MsSpan file) {
  return ms_span_starts_with(file, ms_span_of_text("@")) && !ms_span_starts_with(file, ms_span_of_text("@std/"));
}

/* The excerpt under a diagnostic: the file is read again from `root`, as the Rust CLI does. */
static void finding_excerpt(MsStrBuild *out, MsSpan root, const Finding *finding) {
  MsStrBuild path = ms_strbuild_new();
  ms_path_append_joined(&path, finding_is_package_file(finding->file) ? (MsSpan){0} : root, finding->file);
  MsBytes bytes = {0};
  if (ms_file_read(ms_strbuild_span(&path), &bytes)) {
    ms_snippet_excerpt(out, ms_bytes_span(&bytes), finding->diag.pos, finding->diag.has_end, finding->diag.end);
  }
  ms_bytes_free(&bytes);
  ms_strbuild_free(&path);
}

void finding_add_lint(const MsLintFindingList *lint, FindingList *findings) {
  for (size_t i = 0; i < lint->len; i++) {
    const MsLintFinding *item = &lint->ptr[i];
    MsDiag diag = {.pos = item->pos, .message = item->message};
    if (item->has_fix) {
      diag.has_fix = true;
      diag.fix_pos = item->fix_pos;
      diag.fix_end = item->fix_end;
      diag.replacement = item->replacement;
    }
    finding_list_push(findings, (Finding){.file = item->file, .phase = "", .diag = diag, .lint_code = item->code,
                                          .warning = item->severity == MS_LINT_WARNING});
  }
}

const char *finding_code(const Finding *finding) {
  return finding->lint_code != NULL ? finding->lint_code : ms_code_for(finding->phase, finding->diag.message);
}

bool finding_fails(const FindingList *findings, bool deny_warnings) {
  for (size_t i = 0; i < findings->len; i++) {
    if (!findings->ptr[i].warning || deny_warnings) {
      return true;
    }
  }
  return false;
}

void finding_terminal_text(MsStrBuild *err, MsSpan root, const FindingList *findings, bool deny_warnings) {
  size_t errors = 0;
  size_t warnings = 0;
  for (size_t i = 0; i < findings->len; i++) {
    const Finding *finding = &findings->ptr[i];
    ms_path_append_joined(err, finding_is_package_file(finding->file) ? (MsSpan){0} : root, finding->file);
    ms_strbuild_printf(err, ":%u:%u: ", finding->diag.pos.line, finding->diag.pos.column);
    if (finding->phase[0] != '\0') {
      ms_strbuild_append_text(err, finding->phase);
    } else {
      if (finding->warning) {
        ms_strbuild_append_text(err, "warning ");
      }
      ms_strbuild_append_text(err, finding->lint_code);
    }
    ms_strbuild_append_text(err, ": ");
    ms_strbuild_append(err, finding->diag.message);
    finding_excerpt(err, root, finding);
    ms_strbuild_append_byte(err, '\n');
    errors += finding->phase[0] != '\0';
    warnings += finding->warning;
  }
  if (errors != 0) {
    ms_strbuild_printf(err, "%zu %s; fix them and re-run (ms check <file> --json gives the same diagnostics as "
                            "structured data)\n",
                       errors, errors == 1 ? "error" : "errors");
  }
  if (warnings != 0) {
    ms_strbuild_printf(err, "%zu %s; %s\n", warnings, warnings == 1 ? "warning" : "warnings",
                       deny_warnings ? "failing because of --deny-warnings"
                                     : "warnings do not fail ms lint; pass --deny-warnings to fail on them");
  }
}
