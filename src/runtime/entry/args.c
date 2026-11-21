/* The program's arguments and exit hooks: msrt_argv, msrt_args, msrt_args_consume, msrt_process_on_exit. */
#include "base/alloc.h"
#include "base/string.h"
#include "runtime/entry/entry.h"

enum { MAX_EXIT_HOOKS = 8 };

MS_LIST_DEFINE(StringList, string_list, MsString)

static int argument_count;
static const char *const *argument_values; /* borrowed from main's caller, valid for the whole run */
static int arguments_skipped;              /* leading program arguments msrt_args hides: the test selector */

static MsExitHook exit_hooks[MAX_EXIT_HOOKS];

void ms_entry_set_arguments(int argc, const char *const *argv) {
  argument_count = argc;
  argument_values = argv;
  arguments_skipped = 0;
}

/* A list of the strings argv[first..argc), or an empty list. */
static void list_of_arguments(int first, MsList *out) {
  StringList list = {0};
  if (argument_values != NULL && argument_count > first) {
    string_list_reserve(&list, (size_t)(argument_count - first));
    for (int i = first; i < argument_count; i++) {
      string_list_push(&list, ms_string_from_span(ms_span_of_text(argument_values[i])));
    }
  }
  *out = *string_list_erased(&list);
}

/* The whole native argv, argv[0] included (`process.control().info().arguments`). */
void msrt_argv(MsList *out) { list_of_arguments(0, out); }

/* argv[1..], less the test selector once the test runner consumed it. */
void msrt_args(MsList *out) { list_of_arguments(1 + arguments_skipped, out); }

void msrt_args_consume(void) { arguments_skipped = 1; }

/* Hooks run after output is flushed and before the process ends, whether main returns or the program exits. Past the
 * table, later registrations are ignored. */
void msrt_process_on_exit(MsExitHook hook) {
  for (size_t i = 0; i < MAX_EXIT_HOOKS; i++) {
    if (exit_hooks[i] == NULL) {
      exit_hooks[i] = hook;
      return;
    }
  }
}

void ms_process_run_exit_hooks(void) {
  for (size_t i = 0; i < MAX_EXIT_HOOKS; i++) {
    const MsExitHook hook = exit_hooks[i];
    exit_hooks[i] = NULL; /* taken first: a hook that registers another finds a free slot */
    if (hook != NULL) {
      hook();
    }
  }
}
