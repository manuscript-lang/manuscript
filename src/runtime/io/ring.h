/* The completion ring: how a libuv callback tells the scheduler that an operation finished.
 *
 * A callback never runs scheduler or Manuscript code (a guard jump must not cross a libuv frame). It pushes
 * one MsIoEvent, naming the connection row and what happened, and the scheduler pops the events after
 * uv_run returns. One ring and one scratch read buffer belong to each scheduler thread's loop, so neither
 * needs a lock. An idle connection owns neither: a buffer is lent only for the length of one read.
 *
 * The ring cannot grow inside a callback, so its capacity is fixed when the loop opens. Size it to the
 * most operations that can be in flight at once (two per connection row: one read, one write); a push
 * that finds it full is a programming error, counted by ms_io_ring_dropped and never silently lost.
 *
 * Readiness is level-triggered and libuv polls several times per loop pass, so a row nobody has served yet is
 * reported again. The pusher keeps one flag per row ("event queued", cleared when the row is served) and does not
 * push a second event; without it a loop pass with many readable rows overflows any fixed capacity.
 */
#ifndef MS_IO_RING_H
#define MS_IO_RING_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef enum {
    MS_IO_READ = 1,    /* result: 0 when the row is readable, or a negative libuv status; the scheduler then reads into the scratch buffer */
    MS_IO_WRITE = 2,   /* result: bytes the socket took, or a negative status */
    MS_IO_ACCEPT = 3,  /* result: 0; the new socket is in the listener's accept queue */
    MS_IO_CONNECT = 4, /* result: 0 connected, or a negative status */
    MS_IO_CLOSED = 5,  /* result: 0; the row's handle is closed and the row may be reused */
    MS_IO_TIMER = 6,   /* result: 0; the row's deadline passed */
    MS_IO_WORK = 7,    /* result: the return value of a function run on the thread pool (ms_io_work); the id is the caller's */
    MS_IO_RESOLVE = 8, /* result: 0 when the addresses are ready (ms_io_resolve), or a negative libuv status */
} MsIoKind;

typedef struct {
    uint64_t id;     /* connection handle: generation in the high half, row index in the low half */
    int32_t result;  /* meaning depends on kind */
    uint32_t kind;   /* an MsIoKind; a plain integer so the layout is the same everywhere */
} MsIoEvent;

_Static_assert(sizeof(MsIoEvent) == 16, "an event is sixteen bytes");

typedef struct MsIoRing MsIoRing;

/* A ring for at least `capacity` events (rounded up to a power of two); NULL when out of memory. The caller
 * owns it and releases it with ms_io_ring_free. */
MsIoRing *ms_io_ring_new(uint32_t capacity);
void ms_io_ring_free(MsIoRing *ring);

/* Appends `event`. False when the ring is full: the event is not stored and ms_io_ring_dropped counts it. */
bool ms_io_ring_push(MsIoRing *ring, MsIoEvent event);
/* Removes the oldest event into `*event`. False when the ring is empty and `*event` is untouched. */
bool ms_io_ring_pop(MsIoRing *ring, MsIoEvent *event);
uint32_t ms_io_ring_length(const MsIoRing *ring);
uint32_t ms_io_ring_dropped(const MsIoRing *ring);

/* The loop's shared read buffer. The scheduler reads into it when it pops a readable row, and the bytes are
 * consumed (parsed, or copied into the row's stash) before the next row is served, so one buffer serves any
 * number of connections. A callback must not read into it: several callbacks run per loop pass. */
typedef struct {
    uint8_t *data; /* owned */
    size_t size;
} MsIoScratch;

/* False when out of memory; `*scratch` is then untouched. Release with ms_io_scratch_release. */
bool ms_io_scratch_init(MsIoScratch *scratch, size_t size);
void ms_io_scratch_release(MsIoScratch *scratch);

#endif
