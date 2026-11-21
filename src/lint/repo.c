/* Owns the repository-level rules of ms_lint: scripts and workflow steps (see lint.h). */
#include <stdio.h>

#include "lint/lint.h"
#include "lint/text.h"

enum { LINE_LENGTH = 1024 };

static bool is_script(const char *path) {
  static const char *const SUFFIXES[] = {".py", ".sh", ".bash", ".ps1", ".bat"};
  for (size_t index = 0; index < sizeof SUFFIXES / sizeof SUFFIXES[0]; index++) {
    if (lint_text_ends_with(path, SUFFIXES[index])) return true;
  }
  return false;
}

static bool in_baseline(const Lint *lint, const char *path) {
  char full[LINT_PATH_LENGTH];
  (void)snprintf(full, sizeof full, "%s/src/lint/script-baseline.txt", lint->root);
  FILE *file = fopen(full, "r");
  if (file == NULL) return false;
  char line[LINE_LENGTH];
  bool found = false;
  while (!found && fgets(line, sizeof line, file) != NULL) {
    lint_text_chomp(line);
    found = lint_text_equal(line, path);
  }
  (void)fclose(file);
  return found;
}

static void check_workflow(Lint *lint, const char *path) {
  char full[LINT_PATH_LENGTH];
  (void)snprintf(full, sizeof full, "%s/%s", lint->root, path);
  FILE *file = fopen(full, "r");
  if (file == NULL) return;
  char line[LINE_LENGTH];
  size_t line_number = 0;
  while (fgets(line, sizeof line, file) != NULL) {
    line_number++;
    lint_text_chomp(line);
    if (lint_text_ends_with(line, "run: |") || lint_text_ends_with(line, "run: >")) {
      lint_report(lint, path, line_number, "workflow-step", "a step is one line: call cmake, ctest or ms run");
    }
  }
  (void)fclose(file);
}

void lint_check_repo_file(Lint *lint, const char *path) {
  if (is_script(path) && !in_baseline(lint, path)) {
    lint_report(lint, path, 0, "new-script", "no new Python, shell or batch scripts; use CMake or Manuscript");
  }
  if (lint_text_starts_with(path, ".github/workflows/c-") && lint_text_ends_with(path, ".yml")) {
    check_workflow(lint, path);
  }
}
