/* driver/watch.h: the polling that `--watch` runs between two runs of a command. */
#ifndef MS_DRIVER_WATCH_H
#define MS_DRIVER_WATCH_H

#include "base/intern.h"

/* The wall-clock time in milliseconds; take it before a run and pass it to `watch_wait`. */
uint64_t watch_now_ms(void);

/* Blocks until a file or directory of `paths` differs from how it is now, then until the change has settled. A path
 * modified since `started_ms` may have been read before its edit, so that returns at once. */
void watch_wait(const MsSpanList *paths, uint64_t started_ms);

#endif
