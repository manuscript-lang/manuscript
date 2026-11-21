/* The Windows half of runtime_stubs.c: the std tests run one task on no reactor, so the pipe calls the streams make
 * into the scheduler wait inline. Windows only; the POSIX natives need none of these. */
#ifdef _WIN32
#include <windows.h>

#include "ms_sched.h"

/* A pipe the test adopts is used with blocking calls: the tests run one task on no reactor, so a read or a write
 * waits on its own overlapped request instead of parking. */
bool ms_sched_pipe_adopt(intptr_t handle) { return handle != 0 && (HANDLE)handle != INVALID_HANDLE_VALUE; }

bool ms_sched_pipe_is_adopted(intptr_t handle) { return ms_sched_pipe_adopt(handle); }

/* Waits for the overlapped request on `handle`; the byte count, or false with `os_error`. */
static bool wait_request(HANDLE handle, BOOL started, OVERLAPPED *request, DWORD *count, int32_t *os_error) {
    DWORD error = started ? ERROR_SUCCESS : GetLastError();
    if (!started && error == ERROR_IO_PENDING) {
        error = GetOverlappedResult(handle, request, count, TRUE) ? ERROR_SUCCESS : GetLastError();
    } else if (started) {
        (void)GetOverlappedResult(handle, request, count, TRUE);
    }
    CloseHandle(request->hEvent);
    *os_error = (int32_t)error;
    return error == ERROR_SUCCESS;
}

MsPipeStatus ms_sched_pipe_read(intptr_t handle, uint8_t *buffer, size_t capacity, size_t *count, int32_t *os_error) {
    OVERLAPPED request = {.hEvent = CreateEventW(NULL, TRUE, FALSE, NULL)};
    DWORD got = 0;
    const BOOL started = ReadFile((HANDLE)handle, buffer, (DWORD)capacity, NULL, &request);
    const bool ok = wait_request((HANDLE)handle, started, &request, &got, os_error);
    *count = got;
    if (!ok && *os_error == ERROR_BROKEN_PIPE) {
        *count = 0; /* the writer closed: end of stream */
        return MS_PIPE_OK;
    }
    return ok ? MS_PIPE_OK : MS_PIPE_ERROR;
}

MsPipeStatus ms_sched_pipe_write(intptr_t handle, const uint8_t *data, size_t length, int32_t *os_error) {
    OVERLAPPED request = {.hEvent = CreateEventW(NULL, TRUE, FALSE, NULL)};
    DWORD put = 0;
    const BOOL started = WriteFile((HANDLE)handle, data, (DWORD)length, NULL, &request);
    return wait_request((HANDLE)handle, started, &request, &put, os_error) ? MS_PIPE_OK : MS_PIPE_ERROR;
}

void ms_sched_pipe_close(intptr_t handle) { CloseHandle((HANDLE)handle); }

MsObjectWait ms_sched_object_wait(intptr_t handle, int64_t timeout_ns) {
    (void)handle;
    (void)timeout_ns;
    return MS_OBJECT_UNWATCHABLE;
}

void ms_sched_object_forget(intptr_t handle) { (void)handle; }
#endif
