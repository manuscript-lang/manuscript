/* Threads and sleeping on Windows. */
#include "ms_rt/sys.h"
#include "winapi.h"

extern void *malloc(size_t size);
extern void free(void *p);

#define STACK_SIZE_PARAM_IS_A_RESERVATION 0x00010000
#define INFINITE 0xFFFFFFFFu

/* What a new thread runs. Allocated by ms_sys_thread_spawn; the thread owns it from the start and frees it. */
typedef struct MsThreadStart {
    void (*function)(void *);
    void *argument;
} MsThreadStart;

static uint32_t MS_WINAPI_CALLBACK thread_trampoline(void *raw) {
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
    const uintptr_t handle = CreateThread(NULL, stack, thread_trampoline, block, flags, NULL);
    if (handle == 0) {
        free(block);
    }
    return handle;
}

void ms_sys_thread_join(uintptr_t thread) {
    WaitForSingleObject(thread, INFINITE);
    CloseHandle(thread);
}

void ms_sys_yield(void) { SwitchToThread(); }

void ms_sys_sleep_ms(uint32_t ms) { Sleep(ms); }
