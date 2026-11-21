/* The Windows half of runtime_stubs.c: the std tests run one task on no reactor, so the pipe calls the streams make
 * into the scheduler wait inline. Windows only; the POSIX natives need none of these. */
#ifdef _WIN32
#include <windows.h>

#include "ms_sched.h"

/* A pipe the test adopts is a blocking handle, and the tests run one task on no reactor, so a read or a write
 * blocks the thread instead of parking. */
bool ms_sched_pipe_adopt(intptr_t handle) { return handle != 0 && (HANDLE)handle != INVALID_HANDLE_VALUE; }

bool ms_sched_pipe_is_adopted(intptr_t handle) { return ms_sched_pipe_adopt(handle); }

MsPipeStatus ms_sched_pipe_read(intptr_t handle, uint8_t *buffer, size_t capacity, size_t *count, int32_t *os_error) {
    DWORD got = 0;
    if (!ReadFile((HANDLE)handle, buffer, (DWORD)capacity, &got, NULL)) {
        const DWORD error = GetLastError();
        if (error != ERROR_BROKEN_PIPE) { /* the writer closed: end of stream */
            *os_error = (int32_t)error;
            return MS_PIPE_ERROR;
        }
        got = 0;
    }
    *count = got;
    return MS_PIPE_OK;
}

MsPipeStatus ms_sched_pipe_write(intptr_t handle, const uint8_t *data, size_t length, int32_t *os_error) {
    DWORD put = 0;
    if (!WriteFile((HANDLE)handle, data, (DWORD)length, &put, NULL)) {
        *os_error = (int32_t)GetLastError();
        return MS_PIPE_ERROR;
    }
    return MS_PIPE_OK;
}

void ms_sched_pipe_close(intptr_t handle) { CloseHandle((HANDLE)handle); }

MsObjectWait ms_sched_object_wait(intptr_t handle, int64_t timeout_ns) {
    (void)handle;
    (void)timeout_ns;
    return MS_OBJECT_UNWATCHABLE;
}

void ms_sched_object_forget(intptr_t handle) { (void)handle; }
#endif
