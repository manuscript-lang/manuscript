/* Address-space reservations on Linux and macOS. The kernel commits a page on first touch, so a reservation
 * is mapped readable and writable up front and ms_sys_commit has nothing to do. */
#include "runtime/sys/sys.h"

extern void *mmap(void *addr, size_t len, int prot, int flags, int fd, int64_t off);
extern int munmap(void *addr, size_t len);
extern int madvise(void *addr, size_t len, int advice);
extern int mprotect(void *addr, size_t len, int prot);

#define PROT_NONE 0
#define PROT_READ 1
#define PROT_WRITE 2
#define MAP_PRIVATE 0x02
/* mmap reports failure as (void *)-1; compared through the integer so no integer is turned into a pointer. */
#define MS_MAP_FAILED_ADDRESS ((intptr_t)-1)

#ifdef __APPLE__
#define MAP_ANONYMOUS 0x1000
#define MAP_NORESERVE 0x40
#define MADV_DONTNEED 5 /* MADV_FREE: macOS leaves MADV_DONTNEED a no-op */
#else
#define MAP_ANONYMOUS 0x20
#define MAP_NORESERVE 0x4000
#define MADV_DONTNEED 4
#define MADV_HUGEPAGE 14
#define MADV_NOHUGEPAGE 15
#define MADV_GUARD_INSTALL 102 /* Linux 6.13: a guard region that splits no mapping */
#endif

void *ms_sys_map_anon(size_t len) {
    void *const memory = mmap(NULL, len, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
    return (intptr_t)memory == MS_MAP_FAILED_ADDRESS ? NULL : memory;
}

/* macOS superpages exist only on Intel, are wired and cannot back a 256 GiB reservation; Apple Silicon
 * uses 16 KiB base pages. Windows large pages need SeLockMemoryPrivilege and are not demand-committed. */
void ms_sys_prefer_huge_pages(void *p, size_t len) {
#ifdef MADV_HUGEPAGE
    madvise(p, len, MADV_HUGEPAGE);
#else
    (void)p;
    (void)len;
#endif
}

void ms_sys_unmap(void *p, size_t len) { munmap(p, len); }

void *ms_sys_map_region(size_t len) {
    /* Map twice the size, then give back the unaligned head and tail. */
    size_t doubled = 0;
    if (!ms_size_mul(len, 2, &doubled)) {
        return NULL;
    }
    uint8_t *const raw = ms_sys_map_anon(doubled);
    if (raw == NULL) {
        return NULL;
    }
    const size_t misalignment = (uintptr_t)raw % len;
    const size_t head = misalignment == 0 ? 0 : len - misalignment;
    uint8_t *const region = raw + head;
    const size_t tail = len - head; /* the reservation is 2 * len: head + len + tail */
    if (head > 0) {
        munmap(raw, head);
    }
    if (tail > 0) {
        munmap(region + len, tail);
    }
#ifdef MADV_NOHUGEPAGE
    madvise(region, len, MADV_NOHUGEPAGE);
#endif
    return region;
}

bool ms_sys_commit(void *p, size_t len) { // NOLINT(readability-non-const-parameter): the Windows version writes through p
    (void)p;
    (void)len;
    return true;
}

bool ms_sys_commit_guard(void *p) { // NOLINT(readability-non-const-parameter): the Windows version writes through p
    (void)p;
    return true;
}

/* Linux zero-fills released pages; macOS frees them lazily and may keep the old contents. */
void ms_sys_release(void *p, size_t len) { madvise(p, len, MADV_DONTNEED); }

bool ms_sys_guard(void *p, size_t len) {
#ifdef MADV_GUARD_INSTALL
    if (madvise(p, len, MADV_GUARD_INSTALL) == 0) {
        return true;
    }
#endif
    /* Older kernels and macOS: mprotect splits the mapping and fails once vm.max_map_count is spent. */
    return mprotect(p, len, PROT_NONE) == 0;
}
