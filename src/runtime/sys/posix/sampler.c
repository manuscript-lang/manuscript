/* The profiler's clock on Linux and macOS: ITIMER_PROF raises SIGPROF after each slice of the process's CPU time. The
 * kernel hands the signal to a thread that does not block it, so every thread but the sampled one blocks it
 * (ms_sys_sampler_exclude_thread), and the handler reads the interrupted registers from the signal context. */
#define _GNU_SOURCE
#ifdef __APPLE__
#define _DARWIN_C_SOURCE /* macOS declares ucontext_t and the thread-state accessors only outside a strict standard */
#endif

#include <errno.h>
#include <signal.h>
#include <stdatomic.h>
#include <sys/time.h>
#ifdef __APPLE__
#include <sys/ucontext.h> /* <ucontext.h> there demands _XOPEN_SOURCE, which hides the thread-state accessors */
#else
#include <ucontext.h>
#endif

#include <uv.h>

#include "runtime/sys/sys.h"

static _Atomic(MsSysSampleFn) sample_function;
static uint64_t started_cpu_ns;

static uint64_t process_cpu_ns(void) {
  uv_rusage_t usage;
  if (uv_getrusage(&usage) != 0) {
    return 0;
  }
  const uint64_t seconds = (uint64_t)usage.ru_utime.tv_sec + (uint64_t)usage.ru_stime.tv_sec;
  const uint64_t micros = (uint64_t)usage.ru_utime.tv_usec + (uint64_t)usage.ru_stime.tv_usec;
  return seconds * UINT64_C(1000000000) + micros * UINT64_C(1000);
}

#if defined(__APPLE__) && defined(__aarch64__)
static MsSysSample registers_of(const ucontext_t *context) {
  const _STRUCT_ARM_THREAD_STATE64 *const state = &context->uc_mcontext->__ss;
  return (MsSysSample){.pc = (uintptr_t)__darwin_arm_thread_state64_get_pc(*state),
                       .sp = (uintptr_t)__darwin_arm_thread_state64_get_sp(*state),
                       .fp = (uintptr_t)__darwin_arm_thread_state64_get_fp(*state)};
}
#elif defined(__APPLE__) && defined(__x86_64__)
static MsSysSample registers_of(const ucontext_t *context) {
  const _STRUCT_X86_THREAD_STATE64 *const state = &context->uc_mcontext->__ss;
  return (MsSysSample){.pc = (uintptr_t)state->__rip, .sp = (uintptr_t)state->__rsp, .fp = (uintptr_t)state->__rbp};
}
#elif defined(__linux__) && defined(__x86_64__)
static MsSysSample registers_of(const ucontext_t *context) {
  const greg_t *const registers = context->uc_mcontext.gregs;
  return (MsSysSample){.pc = (uintptr_t)registers[REG_RIP], .sp = (uintptr_t)registers[REG_RSP],
                       .fp = (uintptr_t)registers[REG_RBP]};
}
#elif defined(__linux__) && defined(__aarch64__)
static MsSysSample registers_of(const ucontext_t *context) {
  return (MsSysSample){.pc = (uintptr_t)context->uc_mcontext.pc, .sp = (uintptr_t)context->uc_mcontext.sp,
                       .fp = (uintptr_t)context->uc_mcontext.regs[29]};
}
#else
#error "no signal context layout for this platform"
#endif

static void on_profile_signal(int signal_number, siginfo_t *info, void *context) {
  (void)signal_number;
  (void)info;
  const int saved = errno;
  const MsSysSampleFn function = atomic_load_explicit(&sample_function, memory_order_acquire);
  if (function != NULL) {
    const MsSysSample sample = registers_of(context);
    function(&sample);
  }
  errno = saved;
}

static void set_timer(uint32_t hz) {
  const long micros = hz == 0 ? 0 : (long)(1000000 / hz);
  const struct timeval slice = {.tv_sec = micros / 1000000, .tv_usec = micros % 1000000};
  const struct itimerval timer = {.it_interval = slice, .it_value = slice};
  (void)setitimer(ITIMER_PROF, &timer, NULL);
}

static void block_signal(int how) {
  sigset_t set;
  sigemptyset(&set);
  sigaddset(&set, SIGPROF);
  (void)pthread_sigmask(how, &set, NULL);
}

bool ms_sys_sampler_start(uint32_t hz, MsSysSampleFn on_sample) {
  struct sigaction action = {0};
  action.sa_sigaction = on_profile_signal;
  action.sa_flags = SA_SIGINFO | SA_RESTART;
  sigemptyset(&action.sa_mask);
  atomic_store_explicit(&sample_function, on_sample, memory_order_release);
  if (sigaction(SIGPROF, &action, NULL) != 0) {
    atomic_store_explicit(&sample_function, NULL, memory_order_release);
    return false;
  }
  block_signal(SIG_UNBLOCK); /* this thread is the one that takes the samples */
  started_cpu_ns = process_cpu_ns();
  set_timer(hz);
  return true;
}

void ms_sys_sampler_stop(void) {
  set_timer(0);
  atomic_store_explicit(&sample_function, NULL, memory_order_release);
}

void ms_sys_sampler_exclude_thread(void) { block_signal(SIG_BLOCK); }

uint64_t ms_sys_sampler_span_ns(void) { return process_cpu_ns() - started_cpu_ns; }
