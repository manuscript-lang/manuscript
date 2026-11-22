/* Owns the lint entry point of lint.h: runs each rule group and orders what they found. Port of lint_modules in
 * crates/ms-tooling/src/lint/mod.rs. */
#include "tooling/lint.h"

#include "base/sort.h"

MsLintFinding *ms_lint_add(MsLintFindingList *findings, const char *code, MsSpan file, MsPos pos, MsSpan message) {
  const MsLintRule *rule = ms_lint_rule(ms_span_of_text(code));
  const MsLintFinding finding = {.code = code,
                                 .severity = rule == NULL ? MS_LINT_ERROR : rule->severity,
                                 .file = file,
                                 .pos = pos,
                                 .message = message};
  ms_lint_finding_list_push(findings, finding);
  return &findings->ptr[findings->len - 1];
}

static int compare_spans(MsSpan a, MsSpan b) {
  const size_t common = a.len < b.len ? a.len : b.len;
  const int order = common == 0 ? 0 : __builtin_memcmp(a.ptr, b.ptr, common);
  if (order != 0) {
    return order < 0 ? -1 : 1;
  }
  return a.len == b.len ? 0 : (a.len < b.len ? -1 : 1);
}

/* Semantic findings by file, offset and code, as the Rust rules sort them before the final merge. */
static int64_t compare_semantic(uint8_t *env, const uint8_t *left, const uint8_t *right) {
  (void)env;
  const MsLintFinding *a = (const void *)left;
  const MsLintFinding *b = (const void *)right;
  int order = compare_spans(a->file, b->file);
  if (order == 0) {
    order = a->pos.offset == b->pos.offset ? 0 : (a->pos.offset < b->pos.offset ? -1 : 1);
  }
  if (order == 0) {
    order = __builtin_strcmp(a->code, b->code);
  }
  return order < 0 ? -1 : order > 0;
}

static int64_t compare_position(uint8_t *env, const uint8_t *left, const uint8_t *right) {
  (void)env;
  const MsLintFinding *a = (const void *)left;
  const MsLintFinding *b = (const void *)right;
  int order = compare_spans(a->file, b->file);
  if (order == 0) {
    order = a->pos.line == b->pos.line ? 0 : (a->pos.line < b->pos.line ? -1 : 1);
  }
  if (order == 0) {
    order = a->pos.column == b->pos.column ? 0 : (a->pos.column < b->pos.column ? -1 : 1);
  }
  return order;
}

static bool is_standard(MsSpan file) {
  return ms_span_starts_with(file, ms_span_of_text("@std/"));
}

void ms_lint_modules(MsArena *arena, const MsCheckProgram *program, MsLintFindingList *findings) {
  for (size_t i = 0; i < program->modules.len; i++) {
    const MsModuleInfo *module = &program->modules.ptr[i];
    const MsSpan file = ms_names_span(program->names, module->file);
    if (!is_standard(file)) {
      ms_lint_source(arena, file, module->source, findings);
    }
  }
  if (program->diagnostics.len == 0) {
    const size_t lexical = findings->len;
    for (uint32_t i = 0; i < program->modules.len; i++) {
      if (!is_standard(ms_names_span(program->names, program->modules.ptr[i].file))) {
        ms_lint_imports(arena, program, i, findings);
        ms_lint_unreachable(arena, program, i, findings);
        ms_lint_matches(arena, program, i, findings);
        ms_lint_calls(arena, program, i, findings);
        ms_lint_promises(arena, program, i, findings);
        ms_lint_recursion(arena, program, i, findings);
      }
    }
    ms_lint_effects(arena, program, findings);
    ms_sort((uint8_t *)(findings->ptr + lexical), findings->len - lexical, sizeof(MsLintFinding), compare_semantic,
            NULL);
    size_t kept = lexical;
    for (size_t i = lexical; i < findings->len; i++) {
      if (!is_standard(findings->ptr[i].file)) {
        findings->ptr[kept++] = findings->ptr[i];
      }
    }
    findings->len = kept;
  }
  ms_sort((uint8_t *)findings->ptr, findings->len, sizeof(MsLintFinding), compare_position, NULL);
}
