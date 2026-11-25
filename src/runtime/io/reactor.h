/* The reactor: descriptor readiness and blocking work on libuv, one loop per scheduler thread.
 *
 * libuv callbacks only record events in a ring (ring.h); no scheduler or Manuscript code runs inside libuv, so a
 * jump out of a task never crosses a libuv frame. The reactor is the readiness backend the scheduler's MsPollOps
 * (core/task.h) are built on.
 *
 * Every function other than ms_io_wake and ms_io_kick belongs to the scheduler thread that opened its reactor.
 */
#ifndef MS_RUNTIME_IO_REACTOR_H
#define MS_RUNTIME_IO_REACTOR_H

#include "base/safe.h"
#include "runtime/io/ring.h"

/* Interest and readiness bits; they equal the MS_WAIT_* constants of the scheduler. */
enum {
  MS_IO_BIT_READ = 1,
  MS_IO_BIT_WRITE = 2,
  MS_IO_BIT_HUP = 4,
  /* Interest only: keep the descriptor's handle after the event instead of closing it on unwatch. */
  MS_IO_BIT_KEEP = 32,
  /* Interest only: the caller's system call just reported nothing more to take; report the next edge (edge.h). */
  MS_IO_BIT_EDGE = 256,
};

/* A descriptor that became ready. The layout equals MsPollReady (core/task.h). */
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

/* Opens the calling thread's reactor. `is_main` also makes it the target of ms_io_kick. On success *reactor is the
 * new reactor, owned by the calling thread until ms_io_close. */
MS_NODISCARD MS_NONNULL bool ms_io_open(bool is_main, MsIoReactor **reactor);

/* Closes the calling thread's reactor and every descriptor handle it holds. */
void ms_io_close(bool is_main);

/* Interrupts the wait of `reactor`; safe from any thread and from a signal handler. The caller guarantees the
 * reactor is not closed meanwhile. */
MS_NONNULL void ms_io_wake(MsIoReactor *reactor);

/* ms_io_wake for the main thread's reactor; safe from a signal handler, a no-op while none is open. */
void ms_io_kick(void);

/* Watches `fd` once for the MS_IO_BIT_READ and MS_IO_BIT_WRITE bits of `events` (neither: reads), reporting it at
 * once if it is already ready. MS_IO_BIT_KEEP keeps the descriptor's handle across waits until ms_io_forget. */
MsIoWatch ms_io_watch(int fd, uint32_t events);

/* Whether the calling thread's reactor registers descriptors edge-triggered (MS_IO_BIT_EDGE). */
bool ms_io_edge_supported(void);

/* Registers `fd` for `cookie` (a number that names this connection among the ones that ever had the descriptor
 * number) and clears the bits in `bits` of what edges reported. Call it before the system call whose "nothing more"
 * ends in a wait with MS_IO_BIT_EDGE. False when edges cannot be used for the descriptor. */
bool ms_io_edge_reset(int fd, uint64_t cookie, uint32_t bits);

/* Whether an edge for `bits` arrived since ms_io_edge_reset: the descriptor may have more to take. */
bool ms_io_edge_ready(int fd, uint32_t bits);

/* Stops watching `fd`. */
void ms_io_unwatch(int fd);

/* Ends the kept handle of `fd`; call it before the owner closes the descriptor. */
void ms_io_forget(int fd);

/* Waits up to `timeout_ns` (0 does not block, negative waits for an event) and writes the descriptors that became
 * ready to out[0..capacity). *count is how many. False when the calling thread has no reactor. A wake-up ends the
 * wait with *count possibly 0, so the caller looks for work again. */
MS_NODISCARD MS_NONNULL bool ms_io_wait(int64_t timeout_ns, MsIoReady *out, size_t capacity, size_t *count);

/* Completions: work that finishes elsewhere reports through the completion ring, never through a callback into the
 * scheduler. Each is submitted with the caller's 64-bit id and ends as one MsIoEvent, which ms_io_wait hands to the
 * completion sink (or ms_io_completion collects). At most MS_IO_MAX_COMPLETIONS are outstanding per reactor,
 * submitted or waiting to be collected; a submission past that returns false and the caller retries after collecting. */
enum { MS_IO_MAX_COMPLETIONS = 64 };

/* Runs work(argument) on libuv's thread pool, where it may block. The completion is MS_IO_WORK with the id and the
 * return value as the result. `argument` must stay valid until the completion is collected. */
typedef int32_t (*MsIoWorkFn)(void *argument);
MS_NODISCARD MS_NONNULL_ARGS(1) bool ms_io_work(MsIoWorkFn work, void *argument, uint64_t id);

/* Resolved addresses of one host. */
typedef struct MsIoAddresses MsIoAddresses;
typedef struct MsIoAddress {
  int32_t family;              /* AF_INET or AF_INET6 */
  uint32_t length;             /* bytes used in `socket_address` */
  uint8_t socket_address[128]; /* a sockaddr, ready for connect or bind */
} MsIoAddress;

/* Starts resolving `host` and `service` (a port number or name) for stream sockets, with the answer queued as
 * MS_IO_RESOLVE and the id. `*out` is set at once and stays unusable until that completion is collected; the caller
 * then reads it and releases it with ms_io_addresses_free, whatever the result. Nothing is allocated when this
 * returns false. */
MS_NODISCARD MS_NONNULL bool ms_io_resolve(const char *host, const char *service, uint64_t id, MsIoAddresses **out);
MS_NONNULL void ms_io_addresses_free(MsIoAddresses *addresses);

/* Takes the oldest queued completion into `*event`; false when there is none. */
MS_NODISCARD MS_NONNULL bool ms_io_completion(MsIoEvent *event);

/* A completion sink takes each completion as it is collected: ms_io_wait hands every queued completion to the calling
 * thread's sink, on that thread and after libuv has returned, so ms_io_completion then finds none. With no sink,
 * completions queue for ms_io_completion. */
typedef void (*MsIoCompletionSink)(uint64_t id, int32_t result, uint32_t kind);
void ms_io_set_completion_sink(MsIoCompletionSink sink);

/* Windows: watching waitable kernel objects (a child process). A task waiting on one for reading wakes once it is
 * signalled. Elsewhere they report false and do nothing. */
MS_NODISCARD bool ms_io_object_watch(uintptr_t handle);
void ms_io_object_drop(uintptr_t handle);

#endif
