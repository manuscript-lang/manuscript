/* The profiler's clock on Windows, which has no profiling signal: a sampler thread wakes `hz` times a second, suspends
 * the sampled thread, reads its registers, hands them over and resumes it. The sampled thread is the one that called
 * ms_sys_sampler_start. Time is wall-clock, unlike the CPU-time signal of Linux and macOS. */
#include <stdatomic.h>

#include "runtime/sys/sys.h"
#include "runtime/sys/windows/context.h"
#include "runtime/sys/windows/winapi.h"

// NOLINTBEGIN(readability-identifier-naming): the names are Win32's
MS_WINAPI uintptr_t GetCurrentThread(void);
MS_WINAPI uintptr_t GetCurrentProcess(void);
MS_WINAPI int DuplicateHandle(uintptr_t from_process, uintptr_t handle, uintptr_t to_process, uintptr_t *out,
                              uint32_t access, int inherit, uint32_t options);
MS_WINAPI int CloseHandle(uintptr_t handle);
MS_WINAPI void Sleep(uint32_t milliseconds);
MS_WINAPI uint32_t SuspendThread(uintptr_t thread);
MS_WINAPI uint32_t ResumeThread(uintptr_t thread);
MS_WINAPI int GetThreadContext(uintptr_t thread, void *context);
// NOLINTEND(readability-identifier-naming)

enum { DUPLICATE_SAME_ACCESS = 2, MILLIS_PER_SECOND = 1000 };

static uintptr_t target; /* a real handle to the sampled thread, 0 when not sampling */
static MsSysThread *sampler;
static _Atomic bool running;
static MsSysSampleFn sample_function;
static uint32_t period_ms;
static int64_t started_ns;

static void sampler_main(void *argument) {
  (void)argument;
  while (atomic_load(&running)) {
    Sleep(period_ms);
    if (!atomic_load(&running)) {
      break;
    }
    if (SuspendThread(target) == (uint32_t)-1) {
      continue;
    }
    Context registers = {0};
    const uint32_t flags = CONTEXT_CONTROL_INTEGER;
    __builtin_memcpy(registers.bytes + CONTEXT_FLAGS_AT, &flags, sizeof flags);
    if (GetThreadContext(target, registers.bytes) != 0) {
      const MsSysSample sample = {.pc = context_word(&registers, CONTEXT_PC), .sp = context_word(&registers, CONTEXT_SP),
                                  .fp = context_word(&registers, CONTEXT_FP)};
      sample_function(&sample);
    }
    (void)ResumeThread(target);
  }
}

bool ms_sys_sampler_start(uint32_t hz, MsSysSampleFn on_sample) {
  const uintptr_t process = GetCurrentProcess();
  if (DuplicateHandle(process, GetCurrentThread(), process, &target, 0, 0, DUPLICATE_SAME_ACCESS) == 0) {
    return false;
  }
  period_ms = hz >= MILLIS_PER_SECOND ? 1 : MILLIS_PER_SECOND / hz;
  sample_function = on_sample;
  started_ns = ms_sys_monotonic_ns();
  atomic_store(&running, true);
  sampler = ms_sys_thread_spawn(0, sampler_main, NULL);
  if (sampler == NULL) {
    atomic_store(&running, false);
    (void)CloseHandle(target);
    target = 0;
    return false;
  }
  return true;
}

void ms_sys_sampler_stop(void) {
  if (target == 0) {
    return;
  }
  atomic_store(&running, false);
  ms_sys_thread_join(sampler);
  sampler = NULL;
  (void)CloseHandle(target);
  target = 0;
}

void ms_sys_sampler_exclude_thread(void) {}

uint64_t ms_sys_sampler_span_ns(void) { return (uint64_t)(ms_sys_monotonic_ns() - started_ns); }
