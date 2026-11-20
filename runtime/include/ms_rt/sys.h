/* ms_rt/sys.h: the operating-system layer. runtime/sys is the only code that makes system calls for our own
 * runtime; everything above it calls these functions.
 *
 * Rules: include only freestanding headers; declare the few OS functions a file needs by hand next to the
 * constants it passes, so one source builds for glibc, musl, macOS and mingw without a C library's headers.
 * One implementation per OS family: sys/posix (Linux and macOS, constants selected by __APPLE__) and
 * sys/windows. Every function here has the same contract on both.
 *
 * These are internal to the runtime: programs never call them, so they are not natives and have no recorded
 * signature. A function listed in runtime/symbols/sys.txt is defined in C and its Rust definition
 * in ms-rt/src/sys*.rs is compiled out.
 */
#ifndef MS_RT_SYS_H
#define MS_RT_SYS_H

#include "ms_rt/base.h"
#include "ms_rt/safe.h"

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

/* sys/thread.c (libuv) and sys/{posix,windows}/yield.c */

/* Starts a thread running start(arg). stack 0 takes the default size, else it is the stack size in bytes.
 * Returns a handle for ms_sys_thread_join, or NULL on failure. */
typedef void (*MsSysThreadFn)(void *);
typedef struct MsSysThread MsSysThread;
MS_NODISCARD MsSysThread *ms_sys_thread_spawn(size_t stack, MsSysThreadFn start, void *arg);
/* Waits for a thread started by ms_sys_thread_spawn and releases its handle. */
void ms_sys_thread_join(MsSysThread *thread);
/* Lets another thread run: the wait of a spin lock. */
void ms_sys_yield(void);
/* Blocks the calling thread for ms milliseconds. */
void ms_sys_sleep_ms(uint32_t ms);

/* ---- descriptors (the reactor's door to the system) ---- */

/* Sets *on to whether fd is in non-blocking mode; false when the system refuses. Unix only; Windows reports false. */
MS_NODISCARD bool ms_sys_fd_get_nonblocking(int fd, bool *on);
/* Puts fd in or out of non-blocking mode; false when the system refuses (a best-effort restore may ignore it). */
bool ms_sys_fd_set_nonblocking(int fd, bool on);
/* Whether a read of fd would not block right now (data, the end or an error is there). Windows: always true. */
bool ms_sys_fd_readable_now(int fd);
/* Sleeps until fd is readable or timeout_ns pass, with nanosecond resolution; a signal or an error ends it early.
 * False where the system has no such wait (only Linux does), so the caller waits another way. */
MS_NODISCARD bool ms_sys_fd_wait_readable(int fd, int64_t timeout_ns);
/* Makes the process's environ agree with the C library's own copy. A static library built without -fPIC makes the
 * linker copy environ into the program, and glibc fills only its own, so readers of the copy would see an empty
 * environment (issue #4647). Linux only; a no-op elsewhere. */
void ms_sys_sync_environ(void);

/* ---- faults ---- */

/* Called on the faulting thread, on its alternate stack, with the address the faulting access touched. It
 * ends the process for a fault it owns (a stack overflow) and returns for any other, which then crashes as it
 * would have without a handler. */
typedef void (*MsSysFaultFn)(uintptr_t address);
/* Gives the calling thread an alternate signal stack and routes the process's memory-access faults (SIGSEGV,
 * SIGBUS) to on_fault, so a stack overflow can be reported by name; call it on each thread that may overflow.
 * The alternate stack lives as long as the process. Linux and macOS only: Windows reports false. */
MS_NODISCARD bool ms_sys_fault_handler_install(MsSysFaultFn on_fault);

/* sys/{posix,windows}/report.c: how a fault reaches the outside. None of these allocates or takes a lock, so a fault
 * that cannot allocate can still be reported. */

/* Writes `bytes` to standard error, all of it unless the system refuses; errors are ignored (nothing else can be
 * done with them). */
void ms_sys_stderr_write(MsBytes bytes);
/* Ends the process at once with `status`: no handlers, no flushing, no cleanup of any kind. */
MS_NORETURN void ms_sys_exit_now(int status);
/* The id of this process, which a fault record carries so the CLI ignores a record a descendant left behind. */
uint32_t ms_sys_process_id(void);
/* Creates or truncates the file the MS_FAULT_RECORD environment variable names and writes `bytes` to it; nothing
 * happens when the variable is unset or the file cannot be written. */
void ms_sys_fault_record_write(MsBytes bytes);

#ifdef _WIN32
/* sys/windows/frames.c: generated code does not keep its frame register on its own frame record, so the walk starts
 * from the native unwind data of the runtime's own frames and then scans for records (ms_frames_scan_record). */

/* The first frame of generated code above the function at `anchor`: its pc, stack pointer and frame register, and
 * the number of logical frames the walk may still visit (accounting begins with the anchor's callers). `is_source`
 * says whether a pc lies in generated code. False when native unwind data ends before one is found. */
typedef struct MsSysNativeStart {
    uintptr_t pc;
    uintptr_t sp;
    uintptr_t fp;
    size_t budget;
} MsSysNativeStart;
MS_NODISCARD bool ms_sys_native_start(uintptr_t anchor, bool (*is_source)(uintptr_t, void *), void *context,
                                      size_t budget, MsSysNativeStart *start);
/* Whether native unwind data covers `pc`: the runtime and the system have it, generated code does not. */
bool ms_sys_has_unwind_data(uintptr_t pc);
/* The bounds of the calling thread's stack. */
void ms_sys_stack_bounds(uintptr_t *low, uintptr_t *high);
#endif

#endif
