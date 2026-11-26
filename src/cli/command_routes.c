/* Owns the option routing of command_routes.h. Each route removes the option that chooses the implementation, then hands the
 * remaining arguments to that implementation, which validates them as before. */
#include "cli/command_routes.h"

#include <stdio.h>
#include <string.h>

#include "base/cstr.h"
#include "cli/build_command.h"
#include "cli/check_all_command.h"
#include "cli/check_command.h"
#include "cli/diagram_command.h"
#include "cli/doc_command.h"
#include "cli/emit_command.h"
#include "cli/fmt_command.h"
#include "cli/help_command.h"
#include "cli/inspect_command.h"
#include "cli/profile_command.h"
#include "cli/review_command.h"
#include "cli/run_command.h"

enum { STATUS_USAGE = 2 };

typedef enum { OPTION_ABSENT, OPTION_FOUND, OPTION_NEEDS_VALUE } OptionState;

/* Removes `--name value` or `--name=value` from `argv` (before any `--`), leaving the order of the rest. */
static OptionState take_value(int *argc, char **argv, const char *name, char **value) {
  const MsSpan flag = ms_span_of_text(name);
  for (int i = 0; i < *argc; i++) {
    if (ms_cstr_equal(argv[i], "--")) {
      break;
    }
    const MsSpan argument = ms_span_of_text(argv[i]);
    const bool joined = argument.len > flag.len && ms_span_equal(ms_span_of(argument.ptr, flag.len), flag) &&
                        argument.ptr[flag.len] == '=';
    if (!joined && !ms_cstr_equal(argv[i], name)) {
      continue;
    }
    int used = 1;
    if (joined) {
      *value = argv[i] + flag.len + 1;
    } else if (i + 1 < *argc) {
      *value = argv[i + 1];
      used = 2;
    } else {
      return OPTION_NEEDS_VALUE;
    }
    for (int j = i + used; j < *argc; j++) {
      argv[j - used] = argv[j];
    }
    *argc -= used;
    return OPTION_FOUND;
  }
  return OPTION_ABSENT;
}

static bool take_flag(int *argc, char **argv, const char *name) {
  for (int i = 0; i < *argc; i++) {
    if (ms_cstr_equal(argv[i], "--")) {
      break;
    }
    if (ms_cstr_equal(argv[i], name)) {
      for (int j = i + 1; j < *argc; j++) {
        argv[j - 1] = argv[j];
      }
      (*argc)--;
      return true;
    }
  }
  return false;
}

/* Puts `text` first. Callers have just removed an option, so the array has room. */
static void prepend(int *argc, char **argv, char *text) {
  memmove(argv + 1, argv, (size_t)*argc * sizeof argv[0]);
  argv[0] = text;
  (*argc)++;
}

static int usage(const char *message) {
  (void)fprintf(stderr, "%s\n", message);
  return STATUS_USAGE;
}

int ms_check_command(int argc, char **argv) {
  char *only = NULL;
  const OptionState state = take_value(&argc, argv, "--only", &only);
  if (state == OPTION_NEEDS_VALUE) {
    return usage("ms check: --only needs types, lint or fmt; run 'ms help check'");
  }
  if (state == OPTION_ABSENT) {
    return ms_check_all_command(argc, argv);
  }
  if (ms_cstr_equal(only, "types")) {
    return ms_check_types_command(argc, argv);
  }
  if (ms_cstr_equal(only, "lint")) {
    return ms_lint_command(argc, argv);
  }
  if (ms_cstr_equal(only, "fmt")) {
    prepend(&argc, argv, "--check");
    return ms_fmt_command(argc, argv);
  }
  (void)fprintf(stderr, "ms check: unknown --only %s; use types, lint or fmt, or leave it out to run all three\n", only);
  return STATUS_USAGE;
}

int ms_build_route(int argc, char **argv) {
  char *emit = NULL;
  const OptionState state = take_value(&argc, argv, "--emit", &emit);
  if (state == OPTION_NEEDS_VALUE) {
    return usage("ms build: --emit needs mir or ir; run 'ms help build'");
  }
  if (state == OPTION_ABSENT) {
    return ms_build_command(argc, argv);
  }
  if (ms_cstr_equal(emit, "mir")) {
    return ms_emit_command(argc, argv);
  }
  if (ms_cstr_equal(emit, "ir")) {
    prepend(&argc, argv, "--ir");
    return ms_emit_command(argc, argv);
  }
  (void)fprintf(stderr, "ms build: unknown --emit %s; use mir or ir\n", emit);
  return STATUS_USAGE;
}

int ms_run_route(int argc, char **argv) {
  if (take_flag(&argc, argv, "--profile")) {
    return ms_profile_command(argc, argv);
  }
  return ms_run_command(argc, argv);
}

int ms_map_command(int argc, char **argv) {
  char *view = NULL;
  const OptionState state = take_value(&argc, argv, "--view", &view);
  if (state == OPTION_NEEDS_VALUE) {
    return usage("ms map: --view needs a view name; run 'ms help map'");
  }
  if (state == OPTION_FOUND && ms_cstr_equal(view, "inspect")) {
    return ms_inspect_command(argc, argv);
  }
  if (state == OPTION_FOUND && ms_cstr_equal(view, "review")) {
    return ms_review_command(argc, argv);
  }
  if (state == OPTION_FOUND) {
    prepend(&argc, argv, view);
    prepend(&argc, argv, "--view");
  }
  return ms_diagram_command(argc, argv);
}

int ms_dev_command(int argc, char **argv) {
  if (argc >= 1 && ms_cstr_equal(argv[0], "doc")) {
    return ms_doc_command(argc - 1, argv + 1);
  }
  (void)fputs(ms_help_page(ms_span_of_text("dev")), argc == 0 ? stdout : stderr);
  return argc == 0 ? 0 : STATUS_USAGE;
}
