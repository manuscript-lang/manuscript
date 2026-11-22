/* driver/watch.h: the polling that `--watch` runs between two runs of a command. */
#ifndef MS_DRIVER_WATCH_H
#define MS_DRIVER_WATCH_H

#include "base/intern.h"
#include "base/strbuild.h"
#include "compiler/project/project.h"

/* The wall-clock time in milliseconds; take it before a run and pass it to `watch_wait`. */
uint64_t watch_now_ms(void);

/* Blocks until a file or directory of `paths` differs from how it is now, then until the change has settled. A path
 * modified since `started_ms` may have been read before its edit, so that returns at once. */
void watch_wait(const MsSpanList *paths, uint64_t started_ms);

/* Polling for a change while something else runs: `watch_snapshot` records the state of `paths`; `watch_changed` is
 * true when they differ from it and records the new state. `watch_settle` returns once they stop changing. */
void watch_snapshot(const MsSpanList *paths, MsStrBuild *signature);
bool watch_changed(const MsSpanList *paths, MsStrBuild *signature);
void watch_settle(const MsSpanList *paths, MsStrBuild *signature);

/* Adds what a rerun of `input` depends on: the input, its manifest, the source root, every local module and the
 * directory of each, where a new file would appear. */
void watch_add_inputs(MsArena *arena, MsSpan input, const MsGraph *graph, MsSpanList *watched);

#endif
