/* ms_rt/streams.h: the descriptor stream table behind @std/io's ReadStream[Bytes] and WriteStream[Bytes] over
 * standard input, a child's pipes and adopted descriptors (runtime/std/streams.c). A stream id is
 * `generation << 32 | (slot + 1)`, so a closed stream's id never matches a reused slot.
 *
 * `read` answers a promise holding one chunk of Bytes, or no value at the end or after a failure. `write` never
 * waits: it appends to the entry's buffer, and `flush` answers a promise that finishes when the buffer has drained.
 * A failure is kept on the entry and read with ms_streams_error, so the Manuscript side builds the Error.
 *
 * ms_streams_* until the C promise table serves programs, when they become the msrt_streams_* ABI. */
#ifndef MS_RT_STREAMS_H
#define MS_RT_STREAMS_H

#include "ms_rt/base.h"
#include "ms_rt/desc.h"
#include "ms_rt/string.h"

/* Flags of ms_streams_open. */
enum {
    MS_STREAMS_READS = 1,    /* the entry reads */
    MS_STREAMS_WRITES = 2,   /* the entry writes */
    MS_STREAMS_OWNS = 4,     /* closing the entry closes the descriptor */
    MS_STREAMS_NONBLOCK = 8, /* put the descriptor in non-blocking mode (only one nothing else shares) */
};

/* Adds a stream over `fd` (on Windows 0, 1 and 2 name the standard handles) and answers its id. */
int64_t ms_streams_open(int64_t fd, int64_t flags);
/* A promise for the next chunk (take it with msrt_promise_take); a second read while one waits faults. */
int64_t ms_streams_read(int64_t stream);
/* Queues `data`: 0 admitted, 1 closed or not writable. */
int64_t ms_streams_write(int64_t stream, const MsList *data);
/* A promise that finishes when the buffer has drained. */
int64_t ms_streams_flush(int64_t stream);
/* Bytes accepted and not yet drained. */
int64_t ms_streams_buffered(int64_t stream);
/* The last read failure or the terminal write failure, or an empty string. */
void ms_streams_error(int64_t stream, MsStr *out);
/* Drains what is buffered, closes an owned descriptor and frees the entry; a gone id does nothing. */
void ms_streams_close(int64_t stream);

#endif
