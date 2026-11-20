/* The reactor: descriptor readiness on libuv, one loop per scheduler thread.
 *
 * libuv callbacks only record (descriptor, bits) in a ready ring; no scheduler or Manuscript code runs inside
 * libuv, so a jump out of a task never crosses a libuv frame. The reactor is the readiness backend of
 * crates/ms-rt/src/poller.rs; the design is in the project's reactor-fit note.
 *
 * Every function other than ms_io_wake and ms_io_kick belongs to the scheduler thread that opened its reactor.
 */
#ifndef MS_IO_REACTOR_H
#define MS_IO_REACTOR_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "ms_rt/safe.h"

/* Interest and readiness bits; they equal the WAIT_* constants of the scheduler. */
enum {
    MS_IO_BIT_READ = 1,
    MS_IO_BIT_WRITE = 2,
    MS_IO_BIT_HUP = 4,
    /* Interest only: keep the descriptor's handle after the event instead of closing it on unwatch. */
    MS_IO_BIT_KEEP = 32,
};

/* A descriptor that became ready. The layout is shared with `Ready` in poller.rs. */
typedef struct MsIoReady {
    uintptr_t fd;
    uint32_t bits;
} MsIoReady;

/* What watching a descriptor came to. */
typedef enum MsIoWatch {
    MS_IO_WATCH_ARMED = 0,
    MS_IO_WATCH_ALWAYS = 1, /* cannot be polled (a regular file): ready at once */
    MS_IO_WATCH_FAILED = -1,
} MsIoWatch;

/* One thread's loop. Opaque; MsIoReactor pointers cross to other threads only for ms_io_wake. */
typedef struct MsIoReactor MsIoReactor;

/* Opens the calling thread's reactor. `is_main` also makes it the target of ms_io_kick. On success *reactor is
 * the new reactor, owned by the calling thread until ms_io_close. */
MS_NODISCARD MS_NONNULL bool ms_io_open(bool is_main, MsIoReactor **reactor);

/* Closes the calling thread's reactor and every descriptor handle it holds. */
void ms_io_close(bool is_main);

/* Interrupts the wait of `reactor`; safe from any thread and from a signal handler. The caller guarantees the
 * reactor is not closed meanwhile. */
MS_NONNULL void ms_io_wake(MsIoReactor *reactor);

/* ms_io_wake for the main thread's reactor; safe from a signal handler, a no-op while none is open. */
void ms_io_kick(void);

/* Watches `fd` once for the MS_IO_BIT_READ and MS_IO_BIT_WRITE bits of `events` (neither: reads), reporting it at once
 * if it is already ready. MS_IO_BIT_KEEP keeps the descriptor's handle across waits until ms_io_forget. */
MsIoWatch ms_io_watch(int fd, uint32_t events);

/* Stops watching `fd`. */
void ms_io_unwatch(int fd);

/* Ends the kept handle of `fd`; call it before the owner closes the descriptor. */
void ms_io_forget(int fd);

/* Waits up to `timeout_ns` (0 does not block, negative waits for an event) and writes the descriptors that became
 * ready to out[0..capacity). *count is how many. False when the calling thread has no reactor. A wake-up ends
 * the wait with *count possibly 0, so the caller looks for work again. */
MS_NODISCARD MS_NONNULL bool ms_io_wait(int64_t timeout_ns, MsIoReady *out, size_t capacity, size_t *count);

#ifdef _WIN32
/* ---- Windows: overlapped named pipes and waitable kernel objects (runtime/io/windows) ---- */

/* What a pipe read or write came to. */
typedef enum MsIoPipeStatus {
    MS_IO_PIPE_OK = 0,          /* *count bytes were read or taken */
    MS_IO_PIPE_WOULD_BLOCK = 1, /* nothing yet: wait for the pipe's key, then call again */
    MS_IO_PIPE_END = 2,         /* reads only: the other end closed and every byte was read */
    MS_IO_PIPE_FAILED = 3,      /* *os_code holds the system error */
    MS_IO_PIPE_NOT_FOUND = 4,   /* the handle is not an adopted pipe */
} MsIoPipeStatus;

/* Takes over the overlapped named pipe `handle`, which the reactor closes with ms_io_pipe_drop. False, and the handle
 * still the caller's, when it was not opened for overlapped I/O. Tasks wait on the handle to read and on the handle
 * plus one to write (handles are multiples of four). */
MS_NODISCARD bool ms_io_pipe_adopt(uintptr_t handle);
bool ms_io_pipe_adopted(uintptr_t handle);
/* One non-blocking read into `buffer`. */
MS_NODISCARD MS_NONNULL_ARGS(3, 4) MsIoPipeStatus ms_io_pipe_read(uintptr_t handle, MsBytesMut buffer, size_t *count, int32_t *os_code);
/* One non-blocking write from `data`: takes up to 64 KiB and reports WOULD_BLOCK while an earlier write is in flight. */
MS_NODISCARD MS_NONNULL_ARGS(3, 4) MsIoPipeStatus ms_io_pipe_write(uintptr_t handle, MsBytes data, size_t *count, int32_t *os_code);
/* Wakes the task parked on `key` (for reading) whenever the pipe becomes readable or writable. */
void ms_io_pipe_group(uintptr_t handle, uintptr_t key);
/* Closes the pipe and its handle; a pending operation is cancelled. */
void ms_io_pipe_drop(uintptr_t handle);

/* Watches the waitable kernel object `handle` (a process): a task waiting on it for reading wakes once it is
 * signalled. The caller keeps it open until ms_io_object_drop. False when the wait cannot be registered. */
MS_NODISCARD bool ms_io_object_watch(uintptr_t handle);
void ms_io_object_drop(uintptr_t handle);
#endif

#endif
