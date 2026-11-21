/* ms_rt/start.h: the process entry (src/runtime/entry/start.c, args.c): msrt_start runs the program, and the arguments, the
 * start time and the exit hooks are read through the rest. Symbols are listed in src/runtime/symbols/start.txt. */
/* ms: domain start */
#ifndef MS_RT_START_H
#define MS_RT_START_H

#include <stdint.h>
#include "ms_rt/base.h"

typedef struct MsTables MsTables;

/* The program's own main: returns its exit status. */
typedef int64_t (*MsMainFn)(void);
/* A function that runs when the process ends. */
typedef void (*MsExitHook)(void);

/* ms-sig: msrt_argv(out: *mut VecVal) */
void msrt_argv(MsVec *out);

/* ms-sig: msrt_start_nanos() -> i64 */
int64_t msrt_start_nanos(void);

/* ms-sig: msrt_args(out: *mut VecVal) */
void msrt_args(MsVec *out);

/* ms-sig: msrt_args_consume() */
void msrt_args_consume(void);

/* ms-sig: msrt_exit_frees() -> u8 @domain=unwind @leaf */
uint8_t msrt_exit_frees(void);

/* ms-sig: msrt_process_on_exit(hook: extern "C" fn()) */
void msrt_process_on_exit(MsExitHook hook);

/* ms-sig: msrt_process_exit(code: i64) -> ! */
void msrt_process_exit(int64_t code);

/* The worker-thread limit the program asks for and the one in force (src/runtime/entry/start.c). */
/* ms-sig: msrt_runtime_set_threads(n: i64) */
void msrt_runtime_set_threads(int64_t threads);
/* ms-sig: msrt_runtime_limit() -> i64 */
int64_t msrt_runtime_limit(void);

/* ms-sig: msrt_start(main_fn: extern "C-unwind" fn() -> i64, tables: *const Tables, argc: i32, argv: *const *const u8) -> i32 */
int msrt_start(MsMainFn main_fn, const MsTables *tables, int argc, const char *const *argv);

#endif
