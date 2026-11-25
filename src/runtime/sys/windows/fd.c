/* Descriptor primitives on Windows: the reactor has no descriptor flags or ppoll here, so each reports "not available". */
#include <uv.h>
#include <windows.h>

#include "runtime/sys/sys.h"

bool ms_sys_fd_get_nonblocking(int fd, bool *on) {
    (void)fd;
    (void)on;
    return false;
}

bool ms_sys_fd_set_nonblocking(int fd, bool on) {
    (void)fd;
    (void)on;
    return false;
}

bool ms_sys_fd_wait_readable(int fd, int64_t timeout_ns) {
    (void)fd;
    (void)timeout_ns;
    return false;
}

/* Whether a read of the pipe `fd` would return at once (data, or the end or an error), or false for a pipe that would block;
 * *known is false for a descriptor that is no pipe. */
static bool pipe_has_data(int fd, bool *known) {
    const HANDLE handle = (HANDLE)uv_get_osfhandle(fd);
    *known = handle != INVALID_HANDLE_VALUE && GetFileType(handle) == FILE_TYPE_PIPE;
    if (!*known) {
        return true;
    }
    DWORD available = 0;
    if (!PeekNamedPipe(handle, NULL, 0, NULL, &available, NULL)) {
        return true; /* a broken pipe is the end of the stream, any other failure is the read's to report */
    }
    return available > 0;
}

/* No refused-descriptor thread runs here (it blocks in poll(2)), so the host cannot say: the reactor then calls the
 * descriptor ready at once and the caller asks it with ms_sys_fd_readable_now, polling when a read would block. */
bool ms_sys_fd_ready(int fd, bool writes, bool *ready) {
    (void)fd;
    (void)writes;
    *ready = true;
    return false;
}

bool ms_sys_fd_wait_any(MsSysFdWait *entries, size_t count) {
    (void)entries;
    (void)count;
    return false;
}

bool ms_sys_wake_open(int fds[2]) {
    (void)fds;
    return false;
}

void ms_sys_wake_send(int write_fd) { (void)write_fd; }

void ms_sys_wake_drain(int read_fd) { (void)read_fd; }

void ms_sys_wake_close(const int fds[2]) { (void)fds; }

/* A read of a pipe with nothing in it blocks its thread (there is no non-blocking mode here), so a pipe is asked first. */
bool ms_sys_fd_readable_now(int fd) {
    bool known = false;
    return pipe_has_data(fd, &known);
}
