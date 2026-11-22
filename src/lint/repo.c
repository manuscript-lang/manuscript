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

/* A path macOS and Windows can both create: printable ASCII, none of the characters Windows
 * rejects, no component ending in a dot or space, and no reserved device name (CON, NUL, COM1...). */
static bool bad_path_byte(unsigned char value) {
  if (value < 0x20 || value > 0x7e) return true;
  static const char WINDOWS_FORBIDDEN[] = "<>:\"|?*\\";
  for (size_t index = 0; index < sizeof WINDOWS_FORBIDDEN - 1; index++) {
    if ((unsigned char)WINDOWS_FORBIDDEN[index] == value) return true;
  }
  return false;
}

static char lower_ascii(char value) { return (value >= 'A' && value <= 'Z') ? (char)(value - 'A' + 'a') : value; }

/* True when the component [start, start + length) names a Windows device, with or without an extension. */
static bool reserved_name(const char *start, size_t length) {
  size_t stem = 0;
  while (stem < length && start[stem] != '.') stem++;
  if (stem == 3) {
    char text[4] = {lower_ascii(start[0]), lower_ascii(start[1]), lower_ascii(start[2]), 0};
    return lint_text_equal(text, "con") || lint_text_equal(text, "prn") || lint_text_equal(text, "aux") ||
           lint_text_equal(text, "nul");
  }
  if (stem != 4 || start[3] < '1' || start[3] > '9') return false;
  char text[4] = {lower_ascii(start[0]), lower_ascii(start[1]), lower_ascii(start[2]), 0};
  return lint_text_equal(text, "com") || lint_text_equal(text, "lpt");
}

static void check_portable_path(Lint *lint, const char *path) {
  size_t start = 0;
  for (size_t index = 0;; index++) {
    unsigned char value = (unsigned char)path[index];
    if (value != 0 && value != '/') {
      if (bad_path_byte(value)) {
        lint_report(lint, path, 0, "portable-path", "a path byte macOS or Windows cannot create: use printable ASCII without < > : \" | ? * \\");
        return;
      }
      continue;
    }
    size_t length = index - start;
    bool trailing = length > 0 && (path[index - 1] == '.' || path[index - 1] == ' ');
    if (trailing || reserved_name(path + start, length)) {
      lint_report(lint, path, 0, "portable-path", "a component ends in a dot or space, or is a Windows device name");
      return;
    }
    if (value == 0) return;
    start = index + 1;
  }
}

void lint_check_repo_file(Lint *lint, const char *path) {
  check_portable_path(lint, path);
  /* Vendored libraries keep the scripts they ship; they are not ours (src/third_party/README.md). */
  /* The frozen conformance corpus keeps the generator scripts it came with. */
  bool vendored = lint_text_starts_with(path, "src/third_party/") || lint_text_starts_with(path, "tests/");
  if (is_script(path) && !vendored && !in_baseline(lint, path)) {
    lint_report(lint, path, 0, "new-script", "no new Python, shell or batch scripts; use CMake or Manuscript");
  }
  if (lint_text_starts_with(path, ".github/workflows/c-") && lint_text_ends_with(path, ".yml")) {
    check_workflow(lint, path);
  }
}
