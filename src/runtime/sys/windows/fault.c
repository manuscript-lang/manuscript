/* Stack-overflow reporting on Windows: one process-wide vectored exception handler. A task's stack grows by its
 * guard page; when the reservation is used up the kernel raises STATUS_STACK_OVERFLOW (or an access violation on
 * the uncommitted page below it) on the faulting thread. The handler gives the callback the stack pointer, or
 * the touched address, and the callback ends the process for a fault it owns; for any other exception, or if it
 * returns, the search goes on and the process ends as it would have without a handler. */
#include <stdatomic.h>
#include <windows.h>

#include "runtime/sys/sys.h"

enum { STACK_OVERFLOW_CODE = 0xC00000FDu, ACCESS_VIOLATION_CODE = 0xC0000005u };

static _Atomic(MsSysFaultFn) fault_callback;
static atomic_flag installed = ATOMIC_FLAG_INIT;

static LONG WINAPI on_exception(EXCEPTION_POINTERS *pointers) {
    const EXCEPTION_RECORD *const record = pointers->ExceptionRecord;
    MsSysFaultFn const callback = atomic_load_explicit(&fault_callback, memory_order_acquire);
    if (callback == NULL) {
        return EXCEPTION_CONTINUE_SEARCH;
    }
    if (record->ExceptionCode == STACK_OVERFLOW_CODE) {
#if defined(__x86_64__)
        callback((uintptr_t)pointers->ContextRecord->Rsp);
#else
        callback((uintptr_t)pointers->ContextRecord->Sp);
#endif
    } else if (record->ExceptionCode == ACCESS_VIOLATION_CODE && record->NumberParameters >= 2) {
        callback((uintptr_t)record->ExceptionInformation[1]);
    }
    return EXCEPTION_CONTINUE_SEARCH;
}

bool ms_sys_fault_handler_install(MsSysFaultFn callback) {
    atomic_store_explicit(&fault_callback, callback, memory_order_release);
    if (atomic_flag_test_and_set(&installed)) {
        return true;
    }
    return AddVectoredExceptionHandler(1, on_exception) != NULL;
}
