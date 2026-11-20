/* Address-space reservations on Windows: reserve with MEM_RESERVE, commit ranges on demand. */
#include "ms_sys.h"

__declspec(dllimport) void *__stdcall VirtualAlloc(void *addr, size_t len, uint32_t kind, uint32_t protect);
__declspec(dllimport) int __stdcall VirtualFree(void *addr, size_t len, uint32_t kind);

#define MEM_COMMIT 0x1000
#define MEM_RESERVE 0x2000
#define MEM_DECOMMIT 0x4000
#define MEM_RELEASE 0x8000
#define PAGE_NOACCESS 0x01
#define PAGE_READWRITE 0x04
#define PAGE_GUARD 0x100

uint8_t *mssys_map_anon(size_t len) { return (uint8_t *)VirtualAlloc(NULL, len, MEM_RESERVE, PAGE_NOACCESS); }

/* No usable huge-page advice for a lazily committed reservation: MEM_LARGE_PAGES needs SeLockMemoryPrivilege
 * and cannot be demand-committed (error 1314 even for an administrator, #3710, #3646). */
void mssys_prefer_huge_pages(uint8_t *p, size_t len) {
    (void)p;
    (void)len;
}

/* The window stack regions are placed in: 64 TiB from 32 TiB, above the heap and images and inside the user
 * address space of both x86-64 and Arm64 Windows. */
#define REGION_BASE ((uintptr_t)0x200000000000)
#define REGION_WINDOW ((uintptr_t)0x400000000000)

/* The window slot the next reservation tries first, shared by every thread. */
static size_t next_region;

/* Windows cannot trim a reservation, and releasing a double-size block to reserve its aligned part loses to
 * any thread that takes the range in between. Each thread claims a slot of the window from one shared counter
 * and reserves exactly that range, so the kernel arbitrates and an occupied slot only moves the counter on.
 * The counter wraps so ranges released at teardown are found again; NULL only when every slot is taken. */
uint8_t *mssys_map_region(size_t len) {
    size_t slots = REGION_WINDOW / len;
    for (size_t i = 0; i < slots; i++) {
        size_t n = __atomic_fetch_add(&next_region, 1, __ATOMIC_RELAXED);
        void *at = (void *)(REGION_BASE + n % slots * len);
        void *p = VirtualAlloc(at, len, MEM_RESERVE, PAGE_NOACCESS);
        if (p != NULL) {
            return (uint8_t *)p;
        }
    }
    return NULL;
}

/* The bottom of a reserved stack stays uncommitted and an access to it faults. */
bool mssys_guard(uint8_t *p, size_t len) {
    (void)p;
    (void)len;
    return true;
}

/* The thread environment block's StackLimit is at offset 0x10 on both architectures. */
static uintptr_t stack_limit(void) {
    uintptr_t v;
#if defined(__x86_64__)
    __asm__ volatile("movq %%gs:0x10, %0" : "=r"(v));
#elif defined(__aarch64__)
    __asm__ volatile("ldr %0, [x18, #0x10]" : "=r"(v));
#else
#error "unsupported Windows architecture"
#endif
    return v;
}

static void set_stack_limit(uintptr_t v) {
#if defined(__x86_64__)
    __asm__ volatile("movq %0, %%gs:0x10" : : "r"(v));
#else
    __asm__ volatile("str %0, [x18, #0x10]" : : "r"(v));
#endif
}

/* Commits the page at p as a guard page: the kernel commits the page below it when it is touched and moves
 * the guard down. Committing a guard page sets the calling thread's StackLimit to the page above it, whichever
 * stack the page belongs to. The guard goes under another task's stack while the caller runs on its own, so
 * the limit is put back: left at the other stack's value, a later stack probe (__chkstk) would walk into the
 * other stack's guard page, which the kernel reports as an unhandled guard-page violation (exit 0x80000001). */
bool mssys_commit_guard(uint8_t *p) {
    uintptr_t limit = stack_limit();
    bool ok = VirtualAlloc(p, 4096, MEM_COMMIT, PAGE_READWRITE | PAGE_GUARD) != NULL;
    set_stack_limit(limit);
    return ok;
}

bool mssys_commit(uint8_t *p, size_t len) { return VirtualAlloc(p, len, MEM_COMMIT, PAGE_READWRITE) != NULL; }

/* Decommits; mssys_commit makes the range usable again. */
void mssys_release(uint8_t *p, size_t len) { VirtualFree(p, len, MEM_DECOMMIT); }

void mssys_unmap(uint8_t *p, size_t len) {
    (void)len;
    VirtualFree(p, 0, MEM_RELEASE);
}
