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
#include "ring.h"

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
/* ---- Windows: waitable kernel objects (runtime/io/windows) ---- */

/* Watches the waitable kernel object `handle` (a process): a task waiting on it for reading wakes once it is
 * signalled. The caller keeps it open until ms_io_object_drop. False when the wait cannot be registered. */
MS_NODISCARD bool ms_io_object_watch(uintptr_t handle);
void ms_io_object_drop(uintptr_t handle);
#endif

/* Completions: work that finishes elsewhere reports through the completion ring, never through a callback into
 * the scheduler. Each is submitted with the caller's 64-bit id and ends as one MsIoEvent, which the scheduler
 * collects with ms_io_completion after ms_io_wait returns (a completion ends the wait). At most
 * MS_IO_MAX_COMPLETIONS are outstanding per reactor, submitted or waiting to be collected; a submission past that
 * returns false and the caller retries after collecting. */
enum { MS_IO_MAX_COMPLETIONS = 64 };

/* Runs work(argument) on libuv's thread pool, where it may block. The completion is MS_IO_WORK with the id and
 * the return value as the result. `argument` must stay valid until the completion is collected. */
typedef int32_t (*MsIoWorkFn)(void *argument);
MS_NODISCARD bool ms_io_work(MsIoWorkFn work, void *argument, uint64_t id);

/* Resolved addresses of one host. */
typedef struct MsIoAddresses MsIoAddresses;
typedef struct {
    int32_t family;     /* AF_INET or AF_INET6 */
    uint32_t length;    /* bytes used in `socket_address` */
    uint8_t socket_address[128]; /* a sockaddr, ready for connect or bind */
} MsIoAddress;

/* Starts resolving `host` and `service` (a port number or name) for stream sockets, with the answer queued as
 * MS_IO_RESOLVE and the id. `*out` is set at once and stays unusable until that completion is collected; the
 * caller then reads it and releases it with ms_io_addresses_free, whatever the result. Nothing is allocated when
 * this returns false. */
MS_NODISCARD MS_NONNULL bool ms_io_resolve(const char *host, const char *service, uint64_t id, MsIoAddresses **out);
/* How many addresses a completed resolution found; 0 after an error. */
size_t ms_io_addresses_count(const MsIoAddresses *addresses);
/* Copies the address at `index` into `*out`; false past the end. */
MS_NODISCARD MS_NONNULL bool ms_io_addresses_at(const MsIoAddresses *addresses, size_t index, MsIoAddress *out);
void ms_io_addresses_free(MsIoAddresses *addresses);

/* Takes the oldest queued completion into `*event`; false when there is none. */
MS_NODISCARD MS_NONNULL bool ms_io_completion(MsIoEvent *event);

/* A completion sink takes each completion as it is collected: ms_io_wait hands every queued completion to the
 * calling thread's sink, on that thread and after libuv has returned, so ms_io_completion then finds none. The
 * scheduler installs one that posts the result to the token named by the id, which wakes the task parked on it
 * (see ms_sched_post_completion in runtime/core). With no sink, completions queue for ms_io_completion. */
typedef void (*MsIoCompletionSink)(uint64_t id, int32_t result, uint32_t kind);
void ms_io_set_completion_sink(MsIoCompletionSink sink);

/* Gives up on a resolution the caller will not wait for (the park timed out or was cancelled) before its completion
 * was collected. libuv is asked to cancel it and the record is released once it ends, so the caller must not use
 * `addresses` afterwards and must not call ms_io_addresses_free. After the completion has been collected, use
 * ms_io_addresses_free instead. */
void ms_io_addresses_abandon(MsIoAddresses *addresses);

#endif
