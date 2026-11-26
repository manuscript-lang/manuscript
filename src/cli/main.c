/* Driver: the `ms` entry point.
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
#include "cli/command_routes.h"
#include "cli/check_all_command.h"
#include "cli/fmt_command.h"
#include "cli/help_command.h"
#include "cli/init_command.h"
#include "lsp/lsp_command.h"
#include "cli/package_commands.h"
#include "cli/phases.h"
#include "cli/search_symbol_command.h"
#include "cli/bench_command.h"
#include "cli/test_command.h"

enum { EXIT_NOT_IMPLEMENTED = 70, EXIT_USAGE = 2 };

/* Commands the `ms` command line accepts. Borrowed static strings. */
static const char *const COMMANDS[] = {
    "check", "fmt",     "build",   "run",     "test", "bench", "map",  "init",
    "install", "add",   "remove",  "search",  "lsp",  "help",  "dev",
};

static bool is_command(const char *word) {
  for (size_t index = 0; index < sizeof COMMANDS / sizeof COMMANDS[0]; index++) {
    if (ms_cstr_equal(word, COMMANDS[index])) return true;
  }
  return false;
}

static int dispatch(int argc, char **argv);

/* Runs the command, then reports a standard output that could not be written (a full disk behind
 * `ms dev doc > file`, a closed descriptor): the buffered write fails only when the buffer is flushed, after the
 * command has succeeded, so without this check the truncated output would come with status 0. */
int main(int argc, char **argv) {
  const int status = dispatch(argc, argv);
  const bool flushed = fflush(stdout) == 0 && !ferror(stdout);
  if (!flushed) {
    (void)fprintf(stderr, "ms: cannot write to standard output; the output is incomplete\n");
    return status == 0 ? 1 : status;
  }
  return status;
}

static int dispatch(int argc, char **argv) {
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
  if (ms_cstr_equal(argv[1], "--version")) {
    return ms_version_command(argc - 2, argv + 2);
  }
  if (!is_command(argv[1])) {
    ms_help_unknown_command(ms_span_of_text(argv[1]));
    return EXIT_USAGE;
  }
  if (ms_help_requested(argc - 2, argv + 2)) {
    (void)fputs(ms_help_page(ms_span_of_text(argv[1])), stdout);
    return 0;
  }
  ms_check_all_set_program(argv[0]);
  if (ms_cstr_equal(argv[1], "help")) return ms_help_command(argc - 2, argv + 2);
  if (ms_cstr_equal(argv[1], "check")) return ms_check_command(argc - 2, argv + 2);
  if (ms_cstr_equal(argv[1], "fmt")) return ms_fmt_command(argc - 2, argv + 2);
  if (ms_cstr_equal(argv[1], "build")) return ms_build_route(argc - 2, argv + 2);
  if (ms_cstr_equal(argv[1], "run")) return ms_run_route(argc - 2, argv + 2);
  if (ms_cstr_equal(argv[1], "test")) return ms_test_command(argc - 2, argv + 2);
  if (ms_cstr_equal(argv[1], "bench")) return ms_bench_command(argc - 2, argv + 2);
  if (ms_cstr_equal(argv[1], "map")) return ms_map_command(argc - 2, argv + 2);
  if (ms_cstr_equal(argv[1], "dev")) return ms_dev_command(argc - 2, argv + 2);
  if (ms_cstr_equal(argv[1], "search")) return ms_search_symbol_command(argc - 2, argv + 2);
  if (ms_cstr_equal(argv[1], "lsp")) return ms_lsp_command(argc - 2, argv + 2);
  if (ms_cstr_equal(argv[1], "init")) return ms_init_command(argc - 2, argv + 2);
  if (ms_cstr_equal(argv[1], "install")) return ms_install_command(argc - 2, argv + 2);
  if (ms_cstr_equal(argv[1], "add")) return ms_add_command(argc - 2, argv + 2);
  if (ms_cstr_equal(argv[1], "remove")) return ms_remove_command(argc - 2, argv + 2);
  size_t count = 0;
  const MsPhase *phases = ms_phases(&count);
  size_t missing = 0;
  for (size_t index = 0; index < count; index++) {
    if (phases[index].run()) continue;
    (void)fprintf(stderr, "ms: not implemented: phase %s (%s), needed by `%s`\n",
                  phases[index].name, phases[index].layer, argv[1]);
    missing++;
  }
  return missing == 0 ? 0 : EXIT_NOT_IMPLEMENTED;
}
