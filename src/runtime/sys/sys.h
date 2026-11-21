/* runtime/sys/sys.h: the operating-system layer. src/runtime/sys is the only code that makes system calls for
 * our own runtime; everything above it calls these functions.
 *
 * Rules: a sys file declares the few OS functions it needs by hand next to the constants it passes, so one
 * source builds for glibc, musl, macOS and mingw without a C library's headers. One implementation per OS
 * family: sys/posix (Linux and macOS, constants selected by __APPLE__) and sys/windows. Every function here
 * has the same contract on both. These are internal to the runtime: programs never call them. */
#ifndef MS_RUNTIME_SYS_SYS_H
#define MS_RUNTIME_SYS_SYS_H

#include "base/safe.h"

/* sys/{posix,windows}/mem.c: address-space reservations. */

/* Reserves len bytes of zeroed address space; ms_sys_commit makes ranges of it usable. NULL on failure. */
MS_NODISCARD void *ms_sys_map_anon(size_t len);
/* Asks the OS to back a reservation with huge pages where it can (Linux only; a no-op elsewhere, #3710). */
void ms_sys_prefer_huge_pages(void *p, size_t len);
/* Reserves len bytes aligned to len (a power of two) for task stacks, without huge pages. NULL on failure. */
MS_NODISCARD void *ms_sys_map_region(size_t len);
/* Makes len bytes at p (inside a reservation) usable and zeroed. */
MS_NODISCARD bool ms_sys_commit(void *p, size_t len);
/* Makes the page at p a guard page below committed stack pages. */
MS_NODISCARD bool ms_sys_commit_guard(void *p);
/* Gives the pages back to the system; they need no ms_sys_commit again on posix, they do on Windows. */
void ms_sys_release(void *p, size_t len);
/* Makes len bytes at p inaccessible (a stack guard). False when the OS refuses; the stack must then not be used. */
MS_NODISCARD bool ms_sys_guard(void *p, size_t len);
/* Returns a whole reservation to the system. */
void ms_sys_unmap(void *p, size_t len);

/* sys/{posix,windows}/heap.c: the C library's allocator, for blocks the size classes do not serve. */

MS_NODISCARD void *ms_sys_malloc(size_t size);
MS_NODISCARD void *ms_sys_realloc(void *ptr, size_t size);
void ms_sys_free(void *ptr);
/* The usable size of a block from ms_sys_malloc or ms_sys_realloc, which may exceed what was asked for. */
size_t ms_sys_malloc_size(void *ptr);

/* sys/{posix,windows}/clock.c */

/* Monotonic clock in nanoseconds. */
int64_t ms_sys_monotonic_ns(void);

/* sys/{posix,windows}/yield.c */

/* Lets another thread run: the wait of a spin lock. */
void ms_sys_yield(void);

/* ---- descriptors (the reactor's door to the system) ---- */

/* Sets *on to whether fd is in non-blocking mode; false when the system refuses. Unix only; Windows reports false. */
MS_NODISCARD bool ms_sys_fd_get_nonblocking(int fd, bool *on);
/* Puts fd in or out of non-blocking mode; false when the system refuses (a best-effort restore may ignore it). */
bool ms_sys_fd_set_nonblocking(int fd, bool on);
/* Whether a read of fd would not block right now (data, the end or an error is there). Windows: always true. */
bool ms_sys_fd_readable_now(int fd);
/* Sleeps until fd is readable or timeout_ns pass, with nanosecond resolution; a signal or an error ends it early.
 * False where the system has no such wait, so the caller waits another way. */
MS_NODISCARD bool ms_sys_fd_wait_readable(int fd, int64_t timeout_ns);
/* Sets *ready to whether fd can be read (or written, when `writes`) without blocking, a hang-up or error counting as
 * ready. False where the system cannot tell. Unix only; Windows reports false. */
MS_NODISCARD bool ms_sys_fd_ready(int fd, bool writes, bool *ready);
/* A descriptor of ms_sys_fd_wait_any. The layout is that of poll(2)'s entry on every Unix this runs on. */
typedef struct MsSysFdWait {
  int fd;
  int16_t wants; /* MS_SYS_WAIT_READ or MS_SYS_WAIT_WRITE */
  int16_t got;   /* set by the wait: nonzero when the descriptor is ready, has hung up or has failed */
} MsSysFdWait;
enum { MS_SYS_WAIT_READ = 1, MS_SYS_WAIT_WRITE = 4 };
/* Blocks until at least one of the `count` descriptors is ready and marks every ready one (`got`); a signal ends it
 * early with none marked. False when the system cannot wait (Windows). */
MS_NODISCARD bool ms_sys_fd_wait_any(MsSysFdWait *entries, size_t count);
/* A pipe that ends a ms_sys_fd_wait_any from another thread: wait on fds[0], signal through fds[1]. Both ends are
 * non-blocking and close-on-exec. False when the system has none (Windows). */
MS_NODISCARD bool ms_sys_wake_open(int fds[2]);
/* Makes fds[0] readable; a full pipe already is. */
void ms_sys_wake_send(int write_fd);
/* Empties the pipe so the next wait blocks again. */
void ms_sys_wake_drain(int read_fd);
/* Closes both ends. */
void ms_sys_wake_close(const int fds[2]);

/* ---- faults ---- */

/* Called on the faulting thread, on its alternate stack, with the address the faulting access touched. It
 * ends the process for a fault it owns (a stack overflow) and returns for any other, which then crashes as it
 * would have without a handler. */
typedef void (*MsSysFaultFn)(uintptr_t address);
/* Gives the calling thread an alternate signal stack and routes the process's memory-access faults (SIGSEGV,
 * SIGBUS) to on_fault, so a stack overflow can be reported by name; call it on each thread that may overflow.
 * Linux and macOS only: Windows reports false. */
MS_NODISCARD bool ms_sys_fault_handler_install(MsSysFaultFn on_fault);

/* sys/{posix,windows}/report.c: how a fault reaches the outside. None of these allocates or takes a lock, so a fault
 * that cannot allocate can still be reported. */

/* Writes `bytes` to standard error, all of it unless the system refuses; errors are ignored (nothing else can be
 * done with them). */
void ms_sys_stderr_write(MsSpan bytes);
/* A write to a closed pipe or socket must come back as an error (EPIPE), not end the process. Windows: nothing to do. */
void ms_sys_ignore_broken_pipe(void);
/* Ends the process at once with `status`: no handlers, no flushing, no cleanup of any kind. */
MS_NORETURN void ms_sys_exit_now(int status);
/* The id of this process, which a fault record carries so the CLI ignores a record a descendant left behind. */
uint32_t ms_sys_process_id(void);
/* Creates or truncates the file the MS_FAULT_RECORD environment variable names and writes `bytes` to it; nothing
 * happens when the variable is unset or the file cannot be written. */
void ms_sys_fault_record_write(MsSpan bytes);

#endif
