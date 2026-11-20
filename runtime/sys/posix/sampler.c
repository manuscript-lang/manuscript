/* The sampling profiler's clock on Linux and macOS: ITIMER_PROF raises SIGPROF on the thread that is using the
 * CPU, and the handler reads the program counter and frame pointer from the interrupted context. */
#ifdef __APPLE__
#define _DARWIN_C_SOURCE
#define _XOPEN_SOURCE 700 /* <ucontext.h> is an error without it */
#else
#define _GNU_SOURCE /* REG_RIP and the machine context of ucontext_t */
#endif

#include <signal.h>
#include <stdatomic.h>
#include <string.h>
#include <sys/time.h>
#include <ucontext.h>

#include "ms_rt/sys.h"

enum { MAX_HZ = 10000, MICROSECONDS = 1000000 };

static _Atomic(MsSysSampleFn) sample_fn;
static void *sample_context;

/* The registers of the interrupted code; false on an architecture this file does not know. */
static bool interrupted(const ucontext_t *context, uintptr_t *pc, uintptr_t *fp) {
#if defined(__linux__) && defined(__x86_64__)
    *pc = (uintptr_t)context->uc_mcontext.gregs[REG_RIP];
    *fp = (uintptr_t)context->uc_mcontext.gregs[REG_RBP];
#elif defined(__linux__) && defined(__aarch64__)
    *pc = (uintptr_t)context->uc_mcontext.pc;
    *fp = (uintptr_t)context->uc_mcontext.regs[29];
#elif defined(__APPLE__) && defined(__x86_64__)
    *pc = (uintptr_t)context->uc_mcontext->__ss.__rip;
    *fp = (uintptr_t)context->uc_mcontext->__ss.__rbp;
#elif defined(__APPLE__) && defined(__aarch64__)
    *pc = (uintptr_t)__darwin_arm_thread_state64_get_pc(context->uc_mcontext->__ss);
    *fp = (uintptr_t)__darwin_arm_thread_state64_get_fp(context->uc_mcontext->__ss);
#else
    (void)context;
    (void)pc;
    (void)fp;
    return false;
#endif
    return true;
}

static void on_signal(int signal_number, siginfo_t *info, void *context) {
    (void)signal_number;
    (void)info;
    const MsSysSampleFn fn = atomic_load(&sample_fn);
    uintptr_t pc = 0;
    uintptr_t fp = 0;
    if (fn != NULL && interrupted(context, &pc, &fp)) {
        fn(pc, fp, true, sample_context);
    }
}

static bool set_timer(int64_t microseconds) {
    const struct timeval period = {.tv_sec = (time_t)(microseconds / MICROSECONDS),
                                   .tv_usec = (suseconds_t)(microseconds % MICROSECONDS)};
    const struct itimerval timer = {.it_interval = period, .it_value = period};
    return setitimer(ITIMER_PROF, &timer, NULL) == 0;
}

bool ms_sys_sampler_start(int64_t hz, MsSysSampleFn on_sample, void *context) {
    if (hz < 1 || hz > MAX_HZ || on_sample == NULL || atomic_load(&sample_fn) != NULL) {
        return false;
    }
    struct sigaction action;
    memset(&action, 0, sizeof action);
    action.sa_sigaction = on_signal;
    action.sa_flags = SA_SIGINFO | SA_RESTART;
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGPROF, &action, NULL) != 0) {
        return false;
    }
    sample_context = context;
    atomic_store(&sample_fn, on_sample);
    if (!set_timer(MICROSECONDS / hz)) {
        atomic_store(&sample_fn, NULL);
        return false;
    }
    return true;
}

void ms_sys_sampler_stop(void) {
    (void)set_timer(0);
    atomic_store(&sample_fn, NULL);
}
