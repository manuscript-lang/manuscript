/* The Windows half of ms_sched.h: overlapped named pipes and waitable kernel objects, over the reactor's
 * ms_io_pipe_* and ms_io_object_* (runtime/io/windows/platform.c). Replaces the
 * Windows modules of crates/ms-rt/src/glue/mod.rs. A pipe call that cannot finish parks the task on the pipe's key
 * (the handle to read, the handle plus one to write, as the reactor documents), so no thread blocks. A pending stop
 * request ends a call with MS_PIPE_CANCELLED before it touches the pipe, and the park itself ends on it. */
#ifdef _WIN32
#include "ms_sched.h"
#include "../reactor.h"

enum { ERROR_INVALID_HANDLE_CODE = 6 };

/* Parks until `key` is ready for `events`; false when a stop request ended the wait. */
static bool park(uintptr_t key, uint32_t events, int64_t timeout_ns, uint32_t *got) {
    *got = msrt_task_wait_fd((int32_t)key, events, timeout_ns);
    return (*got & MS_WAIT_CANCELLED) == 0;
}

bool ms_sched_pipe_adopt(intptr_t handle) { return ms_io_pipe_adopt((uintptr_t)handle); }

bool ms_sched_pipe_is_adopted(intptr_t handle) { return ms_io_pipe_adopted((uintptr_t)handle); }

MsPipeStatus ms_sched_pipe_read(intptr_t handle, uint8_t *buffer, size_t capacity, size_t *count, int32_t *os_error) {
    for (;;) {
        if (ms_sched_cancel_pending()) {
            return MS_PIPE_CANCELLED;
        }
        const MsIoPipeStatus status =
            ms_io_pipe_read((uintptr_t)handle, (MsBytesMut){.ptr = buffer, .len = capacity}, count, os_error);
        switch (status) {
        case MS_IO_PIPE_OK:
            return MS_PIPE_OK;
        case MS_IO_PIPE_END:
            *count = 0;
            return MS_PIPE_OK;
        case MS_IO_PIPE_WOULD_BLOCK: {
            uint32_t got = 0;
            if (!park((uintptr_t)handle, MS_WAIT_READ, -1, &got)) {
                return MS_PIPE_CANCELLED;
            }
            break;
        }
        case MS_IO_PIPE_NOT_FOUND:
            *os_error = ERROR_INVALID_HANDLE_CODE;
            return MS_PIPE_ERROR;
        case MS_IO_PIPE_FAILED:
        default:
            return MS_PIPE_ERROR;
        }
    }
}

MsPipeStatus ms_sched_pipe_write(intptr_t handle, const uint8_t *data, size_t length, int32_t *os_error) {
    size_t done = 0;
    while (done < length) {
        if (ms_sched_cancel_pending()) {
            return MS_PIPE_CANCELLED;
        }
        size_t count = 0;
        const MsIoPipeStatus status =
            ms_io_pipe_write((uintptr_t)handle, (MsBytes){.ptr = data + done, .len = length - done}, &count, os_error);
        if (status == MS_IO_PIPE_OK) {
            done += count;
        } else if (status == MS_IO_PIPE_WOULD_BLOCK) {
            uint32_t got = 0; /* the writer waits on the handle plus one, so a reader can wait at the same time */
            if (!park((uintptr_t)handle + 1, MS_WAIT_WRITE, -1, &got)) {
                return MS_PIPE_CANCELLED;
            }
        } else {
            if (status == MS_IO_PIPE_NOT_FOUND) {
                *os_error = ERROR_INVALID_HANDLE_CODE;
            }
            return MS_PIPE_ERROR;
        }
    }
    return MS_PIPE_OK;
}

void ms_sched_pipe_close(intptr_t handle) { ms_io_pipe_drop((uintptr_t)handle); }

MsObjectWait ms_sched_object_wait(intptr_t handle, int64_t timeout_ns) {
    if (!ms_io_object_watch((uintptr_t)handle)) {
        return MS_OBJECT_UNWATCHABLE;
    }
    uint32_t got = 0;
    if (!park((uintptr_t)handle, MS_WAIT_READ, timeout_ns, &got)) {
        return MS_OBJECT_CANCELLED;
    }
    return (got & MS_WAIT_TIMEOUT) != 0 ? MS_OBJECT_TIMED_OUT : MS_OBJECT_SIGNALLED;
}

void ms_sched_object_forget(intptr_t handle) { ms_io_object_drop((uintptr_t)handle); }
#endif
