/* entry.h: what the process entry shares between its files and with the tests. Internal to runtime/entry. */
#ifndef MS_ENTRY_H
#define MS_ENTRY_H

#include <stdbool.h>
#include <stdint.h>

#include "../core/fault.h"
#include "ms_rt/desc.h"
#include "ms_rt/start.h"

/* The arguments msrt_start received; msrt_argv and msrt_args read them. */
void ms_entry_set_arguments(int argc, const char *const *argv);

/* Runs the exit hooks registered with msrt_process_on_exit, once each, in registration order. */
void ms_process_run_exit_hooks(void);

/* Standard output (runtime/core/stdout.c): writes out what the runtime buffered, and the OS code of the first failed
 * write (0 when none). Declared here, not through ms_sched.h, whose wait bits clash with core/task.h. */
void ms_sched_flush_stdout(void);
/* Writes what is buffered and frees the buffer (the end of the run, before the leak report); a later write buffers anew. */
void ms_sched_release_stdout(void);
int32_t ms_sched_stdout_error(void);

/* The profiler (runtime/entry/profile.c): sampling the program's stack and allocations while it runs. */
void ms_profile_start(void);
/* Gives the runtime thread its place in the profiler (the thread that runs main). */
void ms_profile_attach_runtime_thread(void);
/* Ends profiling and writes what the environment asked for. */
void ms_profile_finish(void);

/* The promise table calls this when a task that ran under a test output capture ended with a fault; the test runner
 * takes the record with msrt_test_capture_fault. */
void ms_test_keep_fault(uint64_t capture, const MsFaultText *text);

/* Gives the calling thread a reactor and scheduler without starting a program (Rust unit tests that run tasks). */
bool ms_start_attach_thread(void);

#endif
