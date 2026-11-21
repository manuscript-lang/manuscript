/* Stack-overflow reporting on Linux and macOS: an alternate signal stack and a SIGSEGV/SIGBUS handler that
 * runs on it. A thread that has overflowed has no stack left to run a handler on, so each thread that may
 * overflow gets its own alternate stack. The structures are declared by hand, as in the other files here,
 * so no C library header is needed (musl, glibc and macOS agree on these layouts). */
#include <stdatomic.h>

#include "runtime/sys/sys.h"

#define ALTERNATE_STACK_BYTES ((size_t)64 << 10)
#define SIGNAL_DEFAULT NULL

#ifdef __APPLE__
enum { SIGNAL_BUS = 10, SA_SIGINFO = 0x40, SA_ONSTACK = 0x1 };
#else
enum { SIGNAL_BUS = 7, SA_SIGINFO = 4, SA_ONSTACK = 0x08000000 };
#endif
enum { SIGNAL_SEGV = 11 };

/* The part of siginfo_t that is read: the faulting address. */
typedef struct {
    int number;
    int error;
    int code;
#ifdef __APPLE__
    int pid;
    unsigned user;
    int status;
#else
    int padding;
#endif
    uintptr_t address;
} MsSigInfo;

#ifdef __APPLE__
_Static_assert(offsetof(MsSigInfo, address) == 24, "si_addr is at byte 24 in macOS's siginfo_t");
#else
_Static_assert(offsetof(MsSigInfo, address) == 16, "si_addr is at byte 16 in Linux's siginfo_t");
#endif

typedef void (*MsSignalHandler)(int number, const MsSigInfo *info, void *context);

#ifdef __APPLE__
typedef struct {
    MsSignalHandler handler;
    uint32_t mask;
    int flags;
} MsSigAction;

typedef struct {
    void *base;
    size_t size;
    int flags;
} MsAltStack;
#else
typedef struct {
    MsSignalHandler handler;
    uint64_t mask[16];
    int flags;
    void (*restorer)(void);
} MsSigAction;

typedef struct {
    void *base;
    int flags;
    size_t size;
} MsAltStack;
#endif

extern int sigaction(int number, const MsSigAction *action, MsSigAction *previous);
extern int sigaltstack(const MsAltStack *stack, MsAltStack *previous);

static _Atomic(MsSysFaultFn) fault_callback;

/* Runs on the alternate stack. The callback does not return for a fault it owns; for any other fault the
 * default action is restored and the return makes the access fault again, ending the process as usual. */
static void on_fault(int number, const MsSigInfo *info, void *context) {
    (void)context;
    MsSysFaultFn const callback = atomic_load_explicit(&fault_callback, memory_order_acquire);
    if (callback != NULL) {
        callback(info->address);
    }
    const MsSigAction default_action = {.handler = SIGNAL_DEFAULT};
    (void)sigaction(number, &default_action, NULL);
}

bool ms_sys_fault_handler_install(MsSysFaultFn callback) {
    void *const memory = ms_sys_map_anon(ALTERNATE_STACK_BYTES);
    if (memory == NULL) {
        return false;
    }
    const MsAltStack stack = {.base = memory, .size = ALTERNATE_STACK_BYTES};
    if (sigaltstack(&stack, NULL) != 0) {
        ms_sys_unmap(memory, ALTERNATE_STACK_BYTES);
        return false;
    }
    atomic_store_explicit(&fault_callback, callback, memory_order_release);
    const MsSigAction action = {.handler = on_fault, .flags = SA_SIGINFO | SA_ONSTACK};
    return sigaction(SIGNAL_SEGV, &action, NULL) == 0 && sigaction(SIGNAL_BUS, &action, NULL) == 0;
}
