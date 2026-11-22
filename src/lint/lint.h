/* ms_lint: the rules that read C files and the repository file list.
 *
 * Owns what `ms_lint` checks: banned libc calls, layering from src/layers.txt, file size,
 * portable paths (printable ASCII, no Windows-reserved names),
 * and scripts or workflow steps outside the baseline. Every violation is printed as
 * `path:line: rule: message` and counted. */
#ifndef MS_LINT_LINT_H
#define MS_LINT_LINT_H

#include <stdbool.h>
#include <stddef.h>

enum { LINT_MAX_LAYERS = 32, LINT_MAX_ALLOWED = 16, LINT_NAME_LENGTH = 48, LINT_PATH_LENGTH = 512 };

typedef struct LintLayer {
  char directory[LINT_NAME_LENGTH];
  char allowed[LINT_MAX_ALLOWED][LINT_NAME_LENGTH];
  size_t allowed_count;
} LintLayer;

typedef struct Lint {
  const char *root;  /* Borrowed: repository root. */
  LintLayer layers[LINT_MAX_LAYERS];
  size_t layer_count;
  size_t violations;
  size_t banned_calls;
  size_t layering;
} Lint;

/* Loads src/layers.txt under lint->root. False when the file cannot be read. */
bool lint_load_layers(Lint *lint);

/* Checks one file named by its repository-relative path. */
void lint_check_file(Lint *lint, const char *path);

/* Prints a violation and counts it. */
void lint_report(Lint *lint, const char *path, size_t line, const char *rule, const char *message);


/* Checks scripts and workflow steps: no new .py, .sh, .bash, .ps1 or .bat file outside
 * src/lint/script-baseline.txt, and no multi-line `run:` step in the C workflows. */
void lint_check_repo_file(Lint *lint, const char *path);

#endif
