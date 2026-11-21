/* The sampling profiler's clock on Windows, which has no profiling signal: a sampler thread suspends the target
 * thread at the sampling rate, reads its registers, and lets it run again. */
#include <stdatomic.h>

#include "context.h"
#include "ms_rt/sys.h"
#include "winapi.h"

// NOLINTBEGIN(readability-identifier-naming): the names are Win32's
MS_WINAPI uintptr_t GetCurrentProcess(void);
MS_WINAPI uintptr_t GetCurrentThread(void);
MS_WINAPI int DuplicateHandle(uintptr_t source_process, uintptr_t source, uintptr_t target_process, uintptr_t *target,
                              uint32_t access, int inherit, uint32_t options);
MS_WINAPI uint32_t SuspendThread(uintptr_t thread);
MS_WINAPI uint32_t ResumeThread(uintptr_t thread);
MS_WINAPI int GetThreadContext(uintptr_t thread, void *context);
MS_WINAPI int CloseHandle(uintptr_t handle);
// NOLINTEND(readability-identifier-naming)

enum { THREAD_SUSPEND_RESUME = 0x2, THREAD_GET_CONTEXT = 0x8, MAX_HZ = 10000, MILLISECONDS = 1000 };

static struct {
    uintptr_t target;
    MsSysThread *thread;
    MsSysSampleFn on_sample;
    void *context;
    uint32_t period_ms;
    atomic_bool running;
} sampler;

/* Suspends the target, reads its program counter and frame pointer, resumes it. False when it cannot be read. */
static bool read_target(uintptr_t *pc, uintptr_t *fp) {
    Context registers = {0};
    const uint32_t flags = CONTEXT_CONTROL_INTEGER;
    memcpy(registers.bytes + CONTEXT_FLAGS_AT, &flags, sizeof flags);
    if (SuspendThread(sampler.target) == UINT32_MAX) {
        return false;
    }
    const bool read = GetThreadContext(sampler.target, registers.bytes) != 0;
    (void)ResumeThread(sampler.target);
    if (read) {
        *pc = context_word(&registers, CONTEXT_PC);
        *fp = context_word(&registers, CONTEXT_FP);
    }
    return read;
}

static void run(void *argument) {
    (void)argument;
    while (atomic_load(&sampler.running)) {
        ms_sys_sleep_ms(sampler.period_ms);
        uintptr_t pc = 0;
        uintptr_t fp = 0;
        if (atomic_load(&sampler.running) && read_target(&pc, &fp)) {
            sampler.on_sample(pc, fp, false, sampler.context);
        }
    }
}

bool ms_sys_sampler_start(int64_t hz, MsSysSampleFn on_sample, void *context) {
    if (hz < 1 || hz > MAX_HZ || on_sample == NULL || sampler.thread != NULL) {
        return false;
    }
    /* The pseudo handle of the calling thread names whichever thread uses it, so the sampler needs a real one. */
    const uintptr_t self = GetCurrentProcess();
    if (DuplicateHandle(self, GetCurrentThread(), self, &sampler.target, THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT, 0, 0) == 0) {
        return false;
    }
    sampler.on_sample = on_sample;
    sampler.context = context;
    const int64_t period = MILLISECONDS / hz;
    sampler.period_ms = period < 1 ? 1 : (uint32_t)period;
    atomic_store(&sampler.running, true);
    sampler.thread = ms_sys_thread_spawn(0, run, NULL);
    if (sampler.thread == NULL) {
        atomic_store(&sampler.running, false);
        (void)CloseHandle(sampler.target);
        return false;
    }
    return true;
}

void ms_sys_sampler_stop(void) {
    if (sampler.thread == NULL) {
        return;
    }
    atomic_store(&sampler.running, false);
    ms_sys_thread_join(sampler.thread);
    sampler.thread = NULL;
    (void)CloseHandle(sampler.target);
}
