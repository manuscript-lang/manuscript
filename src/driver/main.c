/* Driver: the `ms-c` entry point.
 *
 * For every command it walks all phases and names each one that is not implemented, so a
 * run shows exactly what is missing. Exit status 70 means "not implemented". */
#include <stdbool.h>
#include <stdio.h>

#include "base/cstr.h"
#include "driver/check_command.h"
#include "driver/emit_command.h"
#include "driver/fmt_command.h"
#include "driver/init_command.h"
#include "driver/package_commands.h"
#include "driver/phases.h"

enum { EXIT_NOT_IMPLEMENTED = 70, EXIT_USAGE = 64 };

/* Commands the `ms` front accepts (plan section 4, L5). Borrowed static strings. */
static const char *const COMMANDS[] = {
    "build",   "run",     "test",    "bench",   "emit",    "check",
    "lint",    "fmt",     "inspect", "diagram", "review",  "profile",
    "verify",  "init",    "install", "add",     "remove",  "explain",
    "search_symbol", "lsp", "help",  "version",
};

static bool is_command(const char *word) {
  for (size_t index = 0; index < sizeof COMMANDS / sizeof COMMANDS[0]; index++) {
    if (ms_cstr_equal(word, COMMANDS[index])) return true;
  }
  return false;
}

int main(int argc, char **argv) {
  if (argc < 2 || !is_command(argv[1])) {
    (void)fprintf(stderr, "usage: ms-c <command> [args]\n");
    return EXIT_USAGE;
  }
  if (ms_cstr_equal(argv[1], "fmt")) return ms_fmt_command(argc - 2, argv + 2);
  if (ms_cstr_equal(argv[1], "check")) return ms_check_command(argc - 2, argv + 2);
  if (ms_cstr_equal(argv[1], "emit")) return ms_emit_command(argc - 2, argv + 2);
  if (ms_cstr_equal(argv[1], "init")) return ms_init_command(argc - 2, argv + 2);
  if (ms_cstr_equal(argv[1], "install")) return ms_install_command(argc - 2, argv + 2);
  if (ms_cstr_equal(argv[1], "add")) return ms_add_command(argc - 2, argv + 2);
  if (ms_cstr_equal(argv[1], "remove")) return ms_remove_command(argc - 2, argv + 2);
  size_t count = 0;
  const MsPhase *phases = ms_phases(&count);
  size_t missing = 0;
  for (size_t index = 0; index < count; index++) {
    if (phases[index].run()) continue;
    (void)fprintf(stderr, "ms-c: not implemented: phase %s (%s), needed by `%s`\n",
                  phases[index].name, phases[index].layer, argv[1]);
    missing++;
  }
  return missing == 0 ? 0 : EXIT_NOT_IMPLEMENTED;
}
