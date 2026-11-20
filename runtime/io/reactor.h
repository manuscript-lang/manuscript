/* The reactor: descriptor readiness on libuv, one loop per scheduler thread.
 * Callbacks only record (fd, bits) in a ready ring; no scheduler or Manuscript code runs inside
 * libuv, so a guard jump never crosses a libuv frame. Rust-side contract: crates/ms-rt/src/poller.rs. */
#ifndef MS_IO_REACTOR_H
#define MS_IO_REACTOR_H
#include <stddef.h>
#include <stdint.h>

#define MSIO_READ 1u
#define MSIO_WRITE 2u
#define MSIO_HUP 4u
#define MSIO_KEEP 32u

typedef struct {
    uintptr_t fd;
    uint32_t bits;
} msio_ready;

enum { MSIO_ARMED = 0, MSIO_ALWAYS = 1, MSIO_FAILED = -1 };

/* Opens this thread's loop. Returns the wake handle (for msio_wake from any thread), or NULL. */
void *msio_open(int is_main);
/* Closes this thread's loop and every row. */
void msio_close(int is_main);
/* Wakes the loop behind `wake`; safe from any thread and from a signal handler. */
void msio_wake(void *wake);
/* Wakes the main thread's loop; safe from a signal handler. */
void msio_kick(void);
/* One-shot, level-like interest in `fd`; `events` carries MSIO_* bits (MSIO_KEEP keeps the handle). */
int msio_watch(int fd, uint32_t events);
/* Disarms `fd`. */
void msio_unwatch(int fd);
/* Ends the kept handle of `fd` before its owner closes it. */
void msio_forget(int fd);
/* Waits up to `timeout_ns` (0 never blocks, <0 waits for an event); returns the number of ready
 * entries written to `out` (at most `cap`), or -1 when interrupted. */
long msio_wait(int64_t timeout_ns, msio_ready *out, size_t cap);
#endif
