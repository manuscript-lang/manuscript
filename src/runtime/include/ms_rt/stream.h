/* ms_rt/stream.h: the host stream over a file descriptor that @std/io reads and writes and @std/fs files and child
 * process pipes are (src/runtime/std/stream.c). Internal to the runtime: programs hold it as an object handle, so there
 * are no recorded signatures. A stream is an MsObj whose drop closes an owned descriptor and frees it. */
#ifndef MS_RT_STREAM_H
#define MS_RT_STREAM_H

#include "ms_rt/base.h"
#include "ms_rt/safe.h"
#include "ms_rt/sys_fs.h"

typedef struct MsStream MsStream;

/* A stream over `fd`, which it closes when `owned`; `name` (copied) appears in error messages. NULL when out of
 * memory. The result is an object with a header: release it with msrt_obj_drop. */
MsStream *ms_stream_new(MsSysFd fd, bool owned, MsBytes name);
/* Hands the descriptor of an owned stream to the caller and retires the stream without closing it; -1 when the
 * stream is closed or borrowed. */
int64_t ms_stream_take_fd(MsStream *stream);
/* Closes the stream's descriptor once; later calls do nothing. A borrowed stream just retires. */
void ms_stream_retire(MsStream *stream);

#endif
