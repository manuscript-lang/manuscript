/* sweep.h: the cancellation sweep's hooks (see sweep.c); empty outside the counting runtime. Internal to src/runtime/core. */
#ifndef MS_CORE_SWEEP_H
#define MS_CORE_SWEEP_H

#include <stdbool.h>
#include <stdint.h>

/* Counts one park of the running task; true when it is the one to report a cancellation. */
bool ms_sweep_cancel_here(void);
/* Marks the thread's next park as the scheduler's own (a worker's idle root park): neither counted nor cancelled. */
void ms_sweep_internal(bool on);
/* Parks counted so far. */
uint64_t ms_sweep_parks(void);

#endif
