/* Address-space reservations on Linux and macOS. The kernel commits a page on first touch, so a reservation
 * is mapped readable and writable up front and mssys_commit has nothing to do. */
#include "ms_rt/sys.h"

extern void *mmap(void *addr, size_t len, int prot, int flags, int fd, int64_t off);
extern int munmap(void *addr, size_t len);
extern int madvise(void *addr, size_t len, int advice);
extern int mprotect(void *addr, size_t len, int prot);

#define PROT_NONE 0
#define PROT_READ 1
#define PROT_WRITE 2
#define MAP_PRIVATE 0x02
#define MAP_FAILED ((void *)-1)

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

uint8_t *mssys_map_anon(size_t len) {
    void *p = mmap(NULL, len, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
    return p == MAP_FAILED ? NULL : (uint8_t *)p;
}

/* macOS superpages exist only on Intel, are wired and cannot back a 256 GiB reservation; Apple Silicon
 * uses 16 KiB base pages. Windows large pages need SeLockMemoryPrivilege and are not demand-committed. */
void mssys_prefer_huge_pages(uint8_t *p, size_t len) {
#ifdef MADV_HUGEPAGE
    madvise(p, len, MADV_HUGEPAGE);
#else
    (void)p;
    (void)len;
#endif
}

void mssys_unmap(uint8_t *p, size_t len) { munmap(p, len); }

uint8_t *mssys_map_region(size_t len) {
    uint8_t *raw = mssys_map_anon(2 * len);
    if (raw == NULL) {
        return NULL;
    }
    uintptr_t start = (uintptr_t)raw;
    uintptr_t base = (start + len - 1) / len * len;
    if (base > start) {
        munmap((void *)start, base - start);
    }
    uintptr_t end = start + 2 * len;
    if (end > base + len) {
        munmap((void *)(base + len), end - base - len);
    }
#ifdef MADV_NOHUGEPAGE
    madvise((void *)base, len, MADV_NOHUGEPAGE);
#endif
    return (uint8_t *)base;
}

bool mssys_commit(uint8_t *p, size_t len) {
    (void)p;
    (void)len;
    return true;
}

bool mssys_commit_guard(uint8_t *p) {
    (void)p;
    return true;
}

/* Linux zero-fills released pages; macOS frees them lazily and may keep the old contents. */
void mssys_release(uint8_t *p, size_t len) { madvise(p, len, MADV_DONTNEED); }

bool mssys_guard(uint8_t *p, size_t len) {
#ifdef MADV_GUARD_INSTALL
    if (madvise(p, len, MADV_GUARD_INSTALL) == 0) {
        return true;
    }
#endif
    /* Older kernels and macOS: mprotect splits the mapping and fails once vm.max_map_count is spent. */
    return mprotect(p, len, PROT_NONE) == 0;
}
