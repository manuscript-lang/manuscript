/* Stack-overflow reporting is not wired on Windows yet: the process ends with the system's own status. */
#include "runtime/sys/sys.h"

bool ms_sys_fault_handler_install(MsSysFaultFn on_fault) {
    (void)on_fault;
    return false;
}
