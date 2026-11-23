/* The completion ring: how a libuv callback tells the scheduler that an operation finished.
 *
 * A callback never runs scheduler or Manuscript code (a guard jump must not cross a libuv frame). It pushes one
 * MsIoEvent, naming the descriptor or request and what happened, and the scheduler pops the events after uv_run
 * returns. One ring belongs to each scheduler thread's loop, so it needs no lock.
 *
 * The ring cannot grow inside a callback, so its capacity is fixed when the loop opens. A push that finds it full
 * is counted by ms_io_ring_dropped and never silently lost.
 */
#ifndef MS_RUNTIME_IO_RING_H
#define MS_RUNTIME_IO_RING_H

#include "base/safe.h"

typedef enum MsIoKind {
  MS_IO_READ = 1,    /* result: 0 when readable, or a negative libuv status */
  MS_IO_WRITE = 2,   /* result: 0 when writable, or a negative status */
  MS_IO_WORK = 7,    /* result: the return value of a function run on the thread pool (ms_io_work); the id is the caller's */
  MS_IO_RESOLVE = 8, /* result: 0 when the addresses are ready (ms_io_resolve), or a negative libuv status */
} MsIoKind;

typedef struct MsIoEvent {
  uint64_t id;    /* the descriptor, or the caller's id of a completion */
  int32_t result; /* meaning depends on kind */
  uint32_t kind;  /* an MsIoKind; a plain integer so the layout is the same everywhere */
} MsIoEvent;

_Static_assert(sizeof(MsIoEvent) == 16, "an event is sixteen bytes");

typedef struct MsIoRing MsIoRing;

/* A ring for at least `capacity` events (rounded up to a power of two), owned by the caller. */
MS_RETURNS_NONNULL MsIoRing *ms_io_ring_new(uint32_t capacity);
void ms_io_ring_free(MsIoRing *ring);

/* Appends `event`. False when the ring is full: the event is not stored and ms_io_ring_dropped counts it. */
MS_NONNULL bool ms_io_ring_push(MsIoRing *ring, MsIoEvent event);
/* Removes the oldest event into `*event`. False when the ring is empty and `*event` is untouched. */
MS_NODISCARD MS_NONNULL bool ms_io_ring_pop(MsIoRing *ring, MsIoEvent *event);
MS_NONNULL uint32_t ms_io_ring_length(const MsIoRing *ring);
/* How many events the ring holds when full. */
MS_NONNULL uint32_t ms_io_ring_capacity(const MsIoRing *ring);
MS_NONNULL uint32_t ms_io_ring_dropped(const MsIoRing *ring);

#endif
