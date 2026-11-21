/* How a fault reaches the outside on Linux and macOS: standard error, the process id, and the record file.
 * The functions allocate nothing, so a fault that ran out of memory can still be reported. */
#include "ms_rt/sys.h"
#include "ms_rt/sys_fs.h"

extern char *getenv(const char *name);
extern MS_NORETURN void _exit(int status); // NOLINT(bugprone-reserved-identifier,readability-identifier-naming): the C library's own name

enum { STDERR_FD = 2 };

/* Writes all of `bytes` to `fd`, stopping at the first error. */
static void write_all(MsSysFd fd, MsBytes bytes) {
    size_t done = 0;
    while (done < bytes.len) {
        size_t count = 0;
        if (ms_sys_fs_write(fd, bytes.ptr + done, bytes.len - done, &count) != 0 || count == 0) {
            return;
        }
        done += count;
    }
}

void ms_sys_stderr_write(MsBytes bytes) { write_all(STDERR_FD, bytes); }

void ms_sys_fault_record_write(MsBytes bytes) {
    /* The environment is not changed after start-up, so reading it here is safe. */
    // NOLINTNEXTLINE(concurrency-mt-unsafe)
    const char *const path = getenv("MS_FAULT_RECORD");
    if (path == NULL || path[0] == 0) {
        return;
    }
    MsSysFd fd = MS_SYS_FD_INVALID;
    if (ms_sys_fs_open(path, MS_SYS_O_WRITE | MS_SYS_O_CREATE | MS_SYS_O_TRUNCATE, 0644, &fd) != 0) {
        return;
    }
    write_all(fd, bytes);
    const MsSysError closed = ms_sys_fs_close(fd); /* the record is written; a failed close changes nothing */
    (void)closed;
}

void ms_sys_exit_now(int status) { _exit(status); }
