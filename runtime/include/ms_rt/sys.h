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

/* sys/{posix,windows}/thread.c */

/* Starts a thread running start(arg). stack 0 takes the default size, else it is the stack size in bytes.
 * Returns a handle for ms_sys_thread_join, or 0 on failure. */
typedef void (*MsSysThreadFn)(void *);
MS_NODISCARD uintptr_t ms_sys_thread_spawn(size_t stack, MsSysThreadFn start, void *arg);
/* Waits for a thread started by ms_sys_thread_spawn and releases its handle. */
void ms_sys_thread_join(uintptr_t thread);
/* Lets another thread run: the wait of a spin lock. */
void ms_sys_yield(void);
/* Blocks the calling thread for ms milliseconds. */
void ms_sys_sleep_ms(uint32_t ms);

#endif
