/* ms_rt/pipe.h: Pipe[T], an in-memory stream of whole values with any number of writers and one reader
 * (runtime/core/pipe.c). `pipe` is an id `generation << 32 | (cell + 1)`.
 *
 * The functions are ms_pipe_* while the Rust promise table still serves programs; the program ABI (msrt_pipe_*,
 * recorded in crates/ms-lower/rt_symbols.txt) takes these bodies when the C promise table replaces it. */
#ifndef MS_RT_PIPE_H
#define MS_RT_PIPE_H

#include "ms_rt/base.h"
#include "ms_rt/desc.h"
#include "ms_rt/safe.h"

/* Results of ms_pipe_write. */
enum {
    MS_PIPE_WRITTEN = 0, /* the value was taken */
    MS_PIPE_CLOSED = 1,  /* the reader is gone: the value was dropped */
    MS_PIPE_FULL = 2     /* queued, but the queue is above its capacity: wait on a flush */
};

/* A pipe whose writers' flush waits above `capacity` queued values. It starts with one writer (the Pipe value). */
int64_t ms_pipe_new(int64_t capacity);
/* Another writing end, like dup on a descriptor. */
void ms_pipe_add_writer(int64_t pipe);
/* Moves the owned value at `value` (of `desc`) into the pipe; never waits. */
int64_t ms_pipe_write(int64_t pipe, uint8_t *value, const MsTypeDesc *desc);
/* A promise for the next value (take it with msrt_promise_take), or no value once every writer has closed and the
 * queues are empty. A second read while one waits faults. */
int64_t ms_pipe_read(int64_t pipe);
/* Takes a queued value into `out` (writable memory for `desc`) and answers 1, or answers 0 when none is queued. */
uint8_t ms_pipe_try(int64_t pipe, const MsTypeDesc *desc, uint8_t *out);
/* Whether a read would finish with no value: every writer closed and nothing queued. */
int64_t ms_pipe_ended(int64_t pipe);
/* Lets a writer on another thread queue before the reader pays to park; answers 1 when a value is queued or the
 * pipe ended. */
int64_t ms_pipe_brief_wait(int64_t pipe);
/* A promise that finishes when no more than `capacity` values are queued or the reader is gone. */
int64_t ms_pipe_flush(int64_t pipe);
/* Closes one writing end; the last one ends a waiting read. */
void ms_pipe_close_writer(int64_t pipe);
/* Closes the reading end: queued values are dropped, flushes finish, later writes answer MS_PIPE_CLOSED. */
void ms_pipe_close_reader(int64_t pipe);

#endif
