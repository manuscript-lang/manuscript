/* Threads and sleeping on Windows. */
#include "ms_sys.h"

__declspec(dllimport) void *__stdcall CreateThread(void *attrs, size_t stack, uint32_t(__stdcall *start)(void *), void *arg,
                                                   uint32_t flags, uint32_t *id);
__declspec(dllimport) uint32_t __stdcall WaitForSingleObject(void *h, uint32_t ms);
__declspec(dllimport) int __stdcall CloseHandle(void *h);
__declspec(dllimport) void __stdcall Sleep(uint32_t ms);
extern void *malloc(size_t size);
extern void free(void *p);

#define STACK_SIZE_PARAM_IS_A_RESERVATION 0x00010000
#define INFINITE 0xFFFFFFFFu

struct start {
    void (*fn)(void *);
    void *arg;
};

static uint32_t __stdcall trampoline(void *p) {
    struct start s = *(struct start *)p;
    free(p);
    s.fn(s.arg);
    return 0;
}

/* A stack size is the reservation; it is committed as the stack grows. */
uintptr_t mssys_thread_spawn(size_t stack, void (*start)(void *), void *arg) {
    struct start *s = malloc(sizeof *s);
    if (s == NULL) {
        return 0;
    }
    s->fn = start;
    s->arg = arg;
    void *h = CreateThread(NULL, stack, trampoline, s, stack == 0 ? 0 : STACK_SIZE_PARAM_IS_A_RESERVATION, NULL);
    if (h == NULL) {
        free(s);
    }
    return (uintptr_t)h;
}

void mssys_thread_join(uintptr_t thread) {
    WaitForSingleObject((void *)thread, INFINITE);
    CloseHandle((void *)thread);
}

void mssys_sleep_ms(uint32_t ms) { Sleep(ms); }
