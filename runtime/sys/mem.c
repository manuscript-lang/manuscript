/* Memory and thread-yield primitives for the allocator: the only place the allocator reaches the system.
 * Declares the few system functions it calls by hand, so no C library header is needed (see ms_rt/base.h). */
#include "ms_sys.h"

#if defined(_WIN32)

void *VirtualAlloc(void *addr, size_t len, unsigned long type, unsigned long protect);
int VirtualFree(void *addr, size_t len, unsigned long type);
int SwitchToThread(void);
void *malloc(size_t size);
void *realloc(void *p, size_t size);
void free(void *p);
size_t _msize(void *p);

#define MEM_COMMIT 0x1000UL
#define MEM_RESERVE 0x2000UL
#define MEM_DECOMMIT 0x4000UL
#define MEM_RELEASE 0x8000UL
#define PAGE_NOACCESS 0x01UL
#define PAGE_READWRITE 0x04UL

void *mssys_map(size_t len) {
    return VirtualAlloc(0, len, MEM_RESERVE, PAGE_NOACCESS);
}

bool mssys_commit(void *p, size_t len) {
    return VirtualAlloc(p, len, MEM_COMMIT, PAGE_READWRITE) != 0;
}

void mssys_decommit(void *p, size_t len) {
    VirtualFree(p, len, MEM_DECOMMIT);
}

void mssys_unmap(void *p, size_t len) {
    (void)len;
    VirtualFree(p, 0, MEM_RELEASE);
}

/* Windows large pages need SeLockMemoryPrivilege and cannot be demand-committed (#3710). */
void mssys_prefer_huge(void *p, size_t len) {
    (void)p;
    (void)len;
}

size_t mssys_malloc_size(void *p) {
    return _msize(p);
}

void mssys_yield(void) {
    SwitchToThread();
}

#else /* Linux and macOS */

void *mmap(void *addr, size_t len, int prot, int flags, int fd, int64_t off);
int munmap(void *addr, size_t len);
int madvise(void *addr, size_t len, int advice);
int sched_yield(void);
void *malloc(size_t size);
void *realloc(void *p, size_t size);
void free(void *p);

#define PROT_READ_WRITE 3
#define MAP_PRIVATE 0x2
#if defined(__APPLE__)
size_t malloc_size(const void *p);
#define MAP_ANONYMOUS 0x1000
#define MAP_NORESERVE 0x40
/* macOS leaves MADV_DONTNEED a no-op; MADV_FREE gives the pages back. */
#define MADV_RELEASE 5
#else
size_t malloc_usable_size(void *p);
#define MAP_ANONYMOUS 0x20
#define MAP_NORESERVE 0x4000
#define MADV_RELEASE 4
#define MADV_HUGEPAGE 14
#endif

void *mssys_map(size_t len) {
    void *p = mmap(0, len, PROT_READ_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
    return p == (void *)-1 ? 0 : p;
}

bool mssys_commit(void *p, size_t len) {
    (void)p;
    (void)len;
    return true;
}

void mssys_decommit(void *p, size_t len) {
    madvise(p, len, MADV_RELEASE);
}

void mssys_unmap(void *p, size_t len) {
    munmap(p, len);
}

/* macOS superpages are Intel-only and wired; Apple Silicon has 16 KiB base pages (#3710). */
void mssys_prefer_huge(void *p, size_t len) {
#if defined(MADV_HUGEPAGE)
    madvise(p, len, MADV_HUGEPAGE);
#else
    (void)p;
    (void)len;
#endif
}

size_t mssys_malloc_size(void *p) {
#if defined(__APPLE__)
    return malloc_size(p);
#else
    return malloc_usable_size(p);
#endif
}

void mssys_yield(void) {
    sched_yield();
}

#endif

void *mssys_malloc(size_t size) {
    return malloc(size);
}

void *mssys_realloc(void *p, size_t size) {
    return realloc(p, size);
}

void mssys_free(void *p) {
    free(p);
}
