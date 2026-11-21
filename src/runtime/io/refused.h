/* The watcher of descriptors libuv refuses (src/runtime/io/refused.c). Loop thread only, except where noted. */
#ifndef MS_IO_REFUSED_H
#define MS_IO_REFUSED_H

#include <uv.h>

#include "ms_rt/safe.h"

typedef struct MsIoRefused MsIoRefused;

/* Called on the loop thread for each descriptor found ready, after its watch ended. Returns false when it cannot
 * take the report now (no room): the descriptor stays queued and the loop calls again on its next pass. */
typedef bool (*MsIoRefusedReady)(void *context, int fd);

/* Starts the thread and its async handle on `loop`; NULL when out of memory or threads. */
MS_NONNULL_ARGS(1, 2) MsIoRefused *ms_io_refused_open(uv_loop_t *loop, MsIoRefusedReady ready, void *context);
/* Watches `fd` once for readability (or writability); a descriptor already watched stays as it was. */
MS_NODISCARD MS_NONNULL bool ms_io_refused_add(MsIoRefused *refused, int fd, bool writes);
/* Ends the watch of `fd`. Returns when the thread is no longer polling it, so the caller may close it. */
MS_NONNULL void ms_io_refused_remove(MsIoRefused *refused, int fd);
/* Stops the thread and releases everything once the loop has run the handle's close; call before uv_loop_close. */
MS_NONNULL void ms_io_refused_close(MsIoRefused *refused);

#endif
