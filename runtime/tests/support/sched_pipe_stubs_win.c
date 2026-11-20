/* The Windows half of runtime_stubs.c: the std tests run one task on no reactor, so a pipe was never adopted and a
 * pipe call that is reached is an error. Windows only; the POSIX natives need none of these. */
#ifdef _WIN32
#include "ms_sched.h"

bool ms_sched_pipe_adopt(intptr_t handle) {
    (void)handle;
    return false;
}

bool ms_sched_pipe_is_adopted(intptr_t handle) {
    (void)handle;
    return false;
}

MsPipeStatus ms_sched_pipe_read(intptr_t handle, uint8_t *buffer, size_t capacity, size_t *count, int32_t *os_error) {
    (void)handle;
    (void)buffer;
    (void)capacity;
    *count = 0;
    *os_error = 6; /* ERROR_INVALID_HANDLE */
    return MS_PIPE_ERROR;
}

MsPipeStatus ms_sched_pipe_write(intptr_t handle, const uint8_t *data, size_t length, int32_t *os_error) {
    (void)handle;
    (void)data;
    (void)length;
    *os_error = 6;
    return MS_PIPE_ERROR;
}

void ms_sched_pipe_close(intptr_t handle) { (void)handle; }

MsObjectWait ms_sched_object_wait(intptr_t handle, int64_t timeout_ns) {
    (void)handle;
    (void)timeout_ns;
    return MS_OBJECT_UNWATCHABLE;
}

void ms_sched_object_forget(intptr_t handle) { (void)handle; }
#endif
