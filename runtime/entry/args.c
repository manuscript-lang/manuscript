/* The program's arguments and exit hooks: msrt_argv, msrt_args, msrt_args_consume, msrt_process_on_exit. */
#include <stddef.h>
#include <string.h>

#include "entry.h"
#include "ms_rt/start.h"
#include "ms_rt/alloc.h"
#include "ms_rt/list.h"
#include "ms_rt/string.h"
#include "ms_rt/safe.h"

enum { MAX_EXIT_HOOKS = 8 };

static int argument_count;
static const char *const *argument_values; /* borrowed from main's caller, valid for the whole run */
static int arguments_skipped;              /* leading program arguments msrt_args hides: the test selector */

static void (*exit_hooks[MAX_EXIT_HOOKS])(void);

void ms_entry_set_arguments(int argc, const char *const *argv) {
    argument_count = argc;
    argument_values = argv;
    arguments_skipped = 0;
}

/* A list of the strings argv[first..argc), or an empty list. */
static void list_of_arguments(int first, MsVec *out) {
    const size_t count = argument_values != NULL && argument_count > first ? (size_t)(argument_count - first) : 0;
    if (count == 0) {
        *out = (MsVec){0};
        return;
    }
    size_t bytes = 0;
    if (!ms_size_mul(count, sizeof(MsStr), &bytes)) {
        *out = (MsVec){0};
        return;
    }
    MsStr *const items = msrt_alloc(bytes);
    for (size_t i = 0; i < count; i++) {
        const char *const text = argument_values[(size_t)first + i];
        msrt_string_from_bytes((const uint8_t *)text, strlen(text), &items[i]);
    }
    *out = (MsVec){.ptr = (uint8_t *)items, .len = count, .cap = count};
}

/* The whole native argv, argv[0] included (`process.control().info().arguments`). */
void msrt_argv(MsVec *out) { list_of_arguments(0, out); }

/* argv[1..], less the test selector once the test runner consumed it. */
void msrt_args(MsVec *out) { list_of_arguments(1 + arguments_skipped, out); }

void msrt_args_consume(void) { arguments_skipped = 1; }

/* Hooks run after output is flushed and before the process ends, whether main returns or the program exits. Past the
 * table, later registrations are ignored. */
void msrt_process_on_exit(void (*hook)(void)) {
    for (size_t i = 0; i < MAX_EXIT_HOOKS; i++) {
        if (exit_hooks[i] == NULL) {
            exit_hooks[i] = hook;
            return;
        }
    }
}

void ms_process_run_exit_hooks(void) {
    for (size_t i = 0; i < MAX_EXIT_HOOKS; i++) {
        void (*const hook)(void) = exit_hooks[i];
        exit_hooks[i] = NULL; /* taken first: a hook that registers another finds a free slot */
        if (hook != NULL) {
            hook();
        }
    }
}
