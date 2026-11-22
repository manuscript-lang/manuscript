/* Driver: the `ms-c` entry point.
 *
 * For every command it walks all phases and names each one that is not implemented, so a
 * run shows exactly what is missing. Exit status 70 means "not implemented". */
#include <stdbool.h>
#include <stdio.h>

#ifdef _WIN32
#include <fcntl.h>
#include <io.h>
#endif

#include "base/cstr.h"
#include "driver/bench_command.h"
#include "driver/build_command.h"
#include "driver/check_command.h"
#include "driver/emit_command.h"
#include "driver/explain_command.h"
#include "driver/fmt_command.h"
#include "driver/help_command.h"
#include "driver/init_command.h"
#include "driver/package_commands.h"
#include "driver/phases.h"
#include "driver/profile_command.h"
#include "driver/run_command.h"
#include "driver/test_command.h"
#include "driver/verify_command.h"

enum { EXIT_NOT_IMPLEMENTED = 70, EXIT_USAGE = 2 };

/* Commands the `ms` command line accepts (plan section 4, L5). Borrowed static strings. */
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
#ifdef _WIN32
  /* Recorded output is byte exact: no LF to CRLF translation on the standard streams. */
  (void)_setmode(_fileno(stdin), _O_BINARY);
  (void)_setmode(_fileno(stdout), _O_BINARY);
  (void)_setmode(_fileno(stderr), _O_BINARY);
#endif
  if (argc < 2 || ms_cstr_equal(argv[1], "--help") || ms_cstr_equal(argv[1], "-h")) {
    ms_help_print_top();
    return 0;
  }
  if (ms_cstr_equal(argv[1], "--version") || ms_cstr_equal(argv[1], "version")) {
    return ms_version_command(argv[1], argc - 2, argv + 2);
  }
  if (!is_command(argv[1])) {
    ms_help_unknown_command(ms_span_of_text(argv[1]));
    return EXIT_USAGE;
  }
  if (ms_help_requested(argc - 2, argv + 2)) {
    (void)fputs(ms_help_page(ms_span_of_text(argv[1])), stdout);
    return 0;
  }
  if (ms_cstr_equal(argv[1], "help")) return ms_help_command(argc - 2, argv + 2);
  if (ms_cstr_equal(argv[1], "explain")) return ms_explain_command(argc - 2, argv + 2);
  if (ms_cstr_equal(argv[1], "build")) return ms_build_command(argc - 2, argv + 2);
  if (ms_cstr_equal(argv[1], "run")) return ms_run_command(argc - 2, argv + 2);
  if (ms_cstr_equal(argv[1], "test")) return ms_test_command(argc - 2, argv + 2);
  if (ms_cstr_equal(argv[1], "bench")) return ms_bench_command(argc - 2, argv + 2);
  if (ms_cstr_equal(argv[1], "profile")) return ms_profile_command(argc - 2, argv + 2);
  if (ms_cstr_equal(argv[1], "fmt")) return ms_fmt_command(argc - 2, argv + 2);
  if (ms_cstr_equal(argv[1], "emit")) return ms_emit_command(argc - 2, argv + 2);
  if (ms_cstr_equal(argv[1], "check")) return ms_check_command(argc - 2, argv + 2);
  if (ms_cstr_equal(argv[1], "lint")) return ms_lint_command(argc - 2, argv + 2);
  if (ms_cstr_equal(argv[1], "verify")) return ms_verify_command(argc - 2, argv + 2);
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
