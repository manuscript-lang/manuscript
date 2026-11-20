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

/* sys/{posix,windows}/mem.c: address-space reservations. */

/* Reserves len bytes of zeroed address space; mssys_commit makes ranges of it usable. NULL on failure. */
uint8_t *mssys_map_anon(size_t len);
/* Asks the OS to back a reservation with huge pages where it can (Linux only; a no-op elsewhere, #3710). */
void mssys_prefer_huge_pages(uint8_t *p, size_t len);
/* Reserves len bytes aligned to len (a power of two) for task stacks, without huge pages. NULL on failure. */
uint8_t *mssys_map_region(size_t len);
/* Makes len bytes at p (inside a reservation) usable and zeroed. */
bool mssys_commit(uint8_t *p, size_t len);
/* Makes the page at p a guard page below committed stack pages. */
bool mssys_commit_guard(uint8_t *p);
/* Gives the pages back to the system; they need no mssys_commit again on posix, they do on Windows. */
void mssys_release(uint8_t *p, size_t len);
/* Makes len bytes at p inaccessible (a stack guard). False when the OS refuses; the stack must then not be used. */
bool mssys_guard(uint8_t *p, size_t len);
/* Returns a whole reservation to the system. */
void mssys_unmap(uint8_t *p, size_t len);

/* sys/{posix,windows}/clock.c */

/* Monotonic clock in nanoseconds. */
int64_t mssys_monotonic_ns(void);

/* sys/{posix,windows}/thread.c */

/* Starts a thread running start(arg). stack 0 takes the default size, else it is the stack size in bytes.
 * Returns a handle for mssys_thread_join, or 0 on failure. */
typedef void (*mssys_thread_fn)(void *);
uintptr_t mssys_thread_spawn(size_t stack, mssys_thread_fn start, void *arg);
/* Waits for a thread started by mssys_thread_spawn and releases its handle. */
void mssys_thread_join(uintptr_t thread);
/* Blocks the calling thread for ms milliseconds. */
void mssys_sleep_ms(uint32_t ms);

#endif
