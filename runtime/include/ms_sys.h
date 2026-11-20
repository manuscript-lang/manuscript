/* ms_sys.h: the memory interface of runtime/sys, the one door to the operating system for the allocator.
 *
 * Freestanding headers only. Functions are named mssys_* and are not part of the program ABI
 * (the ms_rt headers), so `cargo xtask symbols --check` ignores them. runtime/sys/mem.c implements them for
 * Linux, macOS and Windows; the OS-layer workstream grows this header, and may split it per module.
 */
#ifndef MS_SYS_H
#define MS_SYS_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/* Reserves len bytes of zeroed address space; mssys_commit makes ranges of it usable. NULL on failure. */
void *mssys_map(size_t len);
/* Makes len bytes at p (inside a mssys_map mapping) readable and writable. Unix does this in mssys_map. */
bool mssys_commit(void *p, size_t len);
/* Gives the pages back to the system but keeps the reservation. Windows needs mssys_commit again. */
void mssys_decommit(void *p, size_t len);
/* Returns a whole mssys_map mapping. Windows ignores len. */
void mssys_unmap(void *p, size_t len);
/* Advice: back this range with huge pages where the system can. A no-op where it cannot. */
void mssys_prefer_huge(void *p, size_t len);

/* The C library's allocator, for blocks the size classes do not serve. */
void *mssys_malloc(size_t size);
void *mssys_realloc(void *p, size_t size);
void mssys_free(void *p);
size_t mssys_malloc_size(void *p);

/* Lets another thread run: the wait of a spin lock. */
void mssys_yield(void);

/* ---- descriptors (runtime/sys/fd.c; the reactor's door to the system) ---- */

/* *on = whether `fd` is in non-blocking mode; false when the system refuses. Unix only; Windows reports false. */
bool mssys_fd_get_nonblocking(int fd, bool *on);
/* Puts `fd` in or out of non-blocking mode; false when the system refuses. */
bool mssys_fd_set_nonblocking(int fd, bool on);
/* Sleeps until `fd` is readable or `timeout_ns` pass, with nanosecond resolution; a signal or an error ends it
 * early. False where the system has no such wait (only Linux does), so the caller waits another way. */
bool mssys_fd_wait_readable(int fd, int64_t timeout_ns);
/* Makes the process's `environ` agree with the C library's own copy. A static library built without -fPIC makes
 * the linker copy `environ` into the program, and glibc fills only its own, so readers of the copy would see an
 * empty environment (issue #4647). Linux only; a no-op elsewhere. */
void mssys_sync_environ(void);

#endif
