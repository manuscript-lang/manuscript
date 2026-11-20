/* Threads and sleeping on Windows. */
#include "ms_rt/sys.h"

__declspec(dllimport) void *__stdcall CreateThread(void *attrs, size_t stack, uint32_t(__stdcall *start)(void *), void *arg,
                                                   uint32_t flags, uint32_t *id);
__declspec(dllimport) uint32_t __stdcall WaitForSingleObject(void *h, uint32_t ms);
__declspec(dllimport) int __stdcall CloseHandle(void *h);
__declspec(dllimport) void __stdcall Sleep(uint32_t ms);
extern void *malloc(size_t size);
extern void free(void *p);

#define STACK_SIZE_PARAM_IS_A_RESERVATION 0x00010000
#define INFINITE 0xFFFFFFFFu

/* What a new thread runs. Allocated by ms_sys_thread_spawn; the thread owns it from the start and frees it. */
typedef struct MsThreadStart {
    void (*function)(void *);
    void *argument;
} MsThreadStart;

static uint32_t __stdcall thread_trampoline(void *raw) {
    const MsThreadStart start = *(const MsThreadStart *)raw;
    free(raw);
    start.function(start.argument);
    return 0;
}

/* A stack size is the reservation; it is committed as the stack grows. */
uintptr_t ms_sys_thread_spawn(size_t stack, void (*start)(void *), void *arg) {
    MsThreadStart *const block = malloc(sizeof *block);
    if (block == NULL) {
        return 0;
    }
    *block = (MsThreadStart){.function = start, .argument = arg};
    const uint32_t flags = stack == 0 ? 0 : STACK_SIZE_PARAM_IS_A_RESERVATION;
    void *const handle = CreateThread(NULL, stack, thread_trampoline, block, flags, NULL);
    if (handle == NULL) {
        free(block);
    }
    return (uintptr_t)handle;
}

void ms_sys_thread_join(uintptr_t thread) {
    WaitForSingleObject((void *)thread, INFINITE);
    CloseHandle((void *)thread);
}

void ms_sys_sleep_ms(uint32_t ms) { Sleep(ms); }
