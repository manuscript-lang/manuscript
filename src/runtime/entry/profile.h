/* entry/profile.h: the sampling profiler. `MS_PROFILE=<path>` makes the runtime sample the program's main thread
 * `MS_PROFILE_HZ` (default 1000, 1 to 10000) times a second and write folded stacks to <path> when the process ends. */
#ifndef MS_RUNTIME_ENTRY_PROFILE_H
#define MS_RUNTIME_ENTRY_PROFILE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "base/strbuild.h"

/* Reads the environment and prepares the sample buffer. The calling thread stops taking part in sampling (it is not the
 * thread that runs `main`). Call before the first thread starts. */
void ms_profile_start(void);

/* Starts sampling the calling thread, which must be the one that runs the program's `main`. No effect unless
 * ms_profile_start enabled profiling. */
void ms_profile_attach(void);

/* The calling thread takes no samples (a worker isolate). */
void ms_profile_exclude_thread(void);

/* Stops sampling and writes the folded stacks. Does nothing when profiling is off or the file was already written. */
void ms_profile_finish(void);

/* ---- folding, exposed for tests ---- */

/* Appends one folded line per distinct stack to `out`, `stack count\n` with frames outermost first, from `count`
 * samples of `stride` words each (the frame count, then the pcs innermost first). Names come from the installed
 * tables; an address outside them is `[runtime]`. */
void ms_profile_fold(const uintptr_t *samples, size_t count, size_t stride, MsStrBuild *out);

#endif
