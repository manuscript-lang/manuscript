/* ms_lint entry point: `ms_lint <repository root> <file list>`.
 *
 * The file list holds one repository-relative path per line (CMake writes it). Prints each
 * violation, then the counts `conform-c` reports. Exit status 1 when there is any violation. */
#include <stdio.h>

#include "lint/lint.h"
#include "lint/text.h"

enum { LINE_LENGTH = 1024 };

int main(int argc, char **argv) {
  if (argc != 3) {
    (void)fprintf(stderr, "usage: ms_lint <repository root> <file list>\n");
    return 64;
  }
  static Lint lint;
  lint.root = argv[1];
  if (!lint_load_layers(&lint)) {
    (void)fprintf(stderr, "ms_lint: cannot read src/layers.txt under %s\n", argv[1]);
    return 66;
  }
  FILE *list = fopen(argv[2], "r");
  if (list == NULL) {
    (void)fprintf(stderr, "ms_lint: cannot read %s\n", argv[2]);
    return 66;
  }
  char path[LINE_LENGTH];
  while (fgets(path, sizeof path, list) != NULL) {
    lint_text_chomp(path);
    if (path[0] == '\0') continue;
    lint_check_repo_file(&lint, path);
    lint_check_file(&lint, path);
  }
  (void)fclose(list);
  (void)printf("ms_lint: %zu violations (banned calls %zu, layering %zu)\n", lint.violations,
               lint.banned_calls, lint.layering);
  return lint.violations == 0 ? 0 : 1;
}
