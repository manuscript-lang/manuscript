/* entry.h: the process entry (start.c, args.c, stop_hooks.c): msrt_start runs the program, and the arguments, the start
 * time and the exit hooks are read through the rest. */
#ifndef MS_RUNTIME_ENTRY_ENTRY_H
#define MS_RUNTIME_ENTRY_ENTRY_H

#include <stdint.h>

#include "base/list.h"
#include "runtime/core/frames.h"

/* The program's own main: returns its exit status. */
typedef int64_t (*MsMainFn)(void);
/* A function that runs when the process ends. */
typedef void (*MsExitHook)(void);

/* ms-sig: msrt_argv(out: *mut VecVal) */
void msrt_argv(MsList *out);

/* ms-sig: msrt_start_nanos() -> i64 */
int64_t msrt_start_nanos(void);

/* ms-sig: msrt_args(out: *mut VecVal) */
void msrt_args(MsList *out);

/* ms-sig: msrt_args_consume() */
void msrt_args_consume(void);

/* ms-sig: msrt_exit_frees() -> u8 @domain=unwind @leaf */
uint8_t msrt_exit_frees(void);

/* ms-sig: msrt_process_on_exit(hook: extern "C" fn()) */
void msrt_process_on_exit(MsExitHook hook);

/* ms-sig: msrt_process_exit(code: i64) -> ! */
MS_NORETURN void msrt_process_exit(int64_t code);

/* The worker-thread limit the program asks for and the one in force. */
/* ms-sig: msrt_runtime_set_threads(n: i64) */
void msrt_runtime_set_threads(int64_t threads);
/* ms-sig: msrt_runtime_limit() -> i64 */
int64_t msrt_runtime_limit(void);

/* ms-sig: msrt_start(main_fn: extern "C-unwind" fn() -> i64, tables: *const Tables, argc: i32, argv: *const *const u8) -> i32 */
int msrt_start(MsMainFn main_fn, const MsTables *tables, int argc, const char *const *argv);

/* The arguments msrt_start received; msrt_argv and msrt_args read them. */
void ms_entry_set_arguments(int argc, const char *const *argv);

/* Runs the exit hooks registered with msrt_process_on_exit, once each, in registration order. */
void ms_process_run_exit_hooks(void);

/* Stop hooks: functions the stop thread runs when the first stop request arrives (SIGINT, SIGTERM), before the
 * running task is cancelled. They may run on any thread and must not block. The stop hooks are an ABI of their own
 * (ms_on_stop_v1), used by library code that must interrupt a blocking system call. */
void ms_stop_hooks_run(void);
void *ms_on_stop_v1(void (*function)(void *argument), void *argument);
void ms_on_stop_remove_v1(void *hook);

#endif
