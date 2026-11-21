/* entry.h: what the process entry shares between its files and with the tests. Internal to src/runtime/entry. */
#ifndef MS_ENTRY_H
#define MS_ENTRY_H

#include <stdbool.h>
#include <stdint.h>

#include "../core/fault.h"
#include "ms_rt/desc.h"
#include "ms_rt/io.h"
#include "ms_rt/start.h"

/* The arguments msrt_start received; msrt_argv and msrt_args read them. */
void ms_entry_set_arguments(int argc, const char *const *argv);

/* Runs the exit hooks registered with msrt_process_on_exit, once each, in registration order. */
void ms_process_run_exit_hooks(void);

/* The profiler (src/runtime/entry/profile.c): sampling the program's stack and allocations while it runs. */
void ms_profile_start(void);
/* Gives the runtime thread its place in the profiler (the thread that runs main). */
void ms_profile_attach_runtime_thread(void);
/* Ends profiling and writes what the environment asked for. */
void ms_profile_finish(void);

/* Gives the calling thread a reactor and scheduler without starting a program (Rust unit tests that run tasks). */
bool ms_start_attach_thread(void);

#endif
