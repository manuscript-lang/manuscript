/* How a fault reaches the outside on Windows: standard error, the process id, and the record file. The functions
 * allocate nothing from the runtime, so a fault that ran out of memory can still be reported. */
#include "ms_rt/sys.h"
#include "ms_rt/sys_fs.h"
#include "winapi.h"

// NOLINTBEGIN(readability-identifier-naming): the names are Win32's
MS_WINAPI uintptr_t GetStdHandle(uint32_t which);
MS_WINAPI int WriteFile(uintptr_t file, const void *buffer, uint32_t count, uint32_t *written, void *overlapped);
MS_WINAPI uint32_t GetCurrentProcessId(void);
MS_WINAPI uintptr_t GetCurrentProcess(void);
MS_WINAPI int TerminateProcess(uintptr_t process, uint32_t status);
MS_WINAPI uint32_t GetEnvironmentVariableW(const uint16_t *name, uint16_t *buffer, uint32_t capacity);
MS_WINAPI int WideCharToMultiByte(uint32_t page, uint32_t flags, const uint16_t *wide, int wide_length, char *out,
                                  int out_length, const char *default_char, int *used_default);
// NOLINTEND(readability-identifier-naming)

enum {
    STD_ERROR_HANDLE = (uint32_t)-12,
    CODE_PAGE_UTF8 = 65001,
    PATH_CAPACITY = 2048, /* UTF-16 units: a fault may run with little stack left, so the buffers stay small */
};

void ms_sys_stderr_write(MsBytes bytes) {
    const uintptr_t handle = GetStdHandle(STD_ERROR_HANDLE);
    size_t done = 0;
    while (done < bytes.len) {
        const size_t left = bytes.len - done;
        const uint32_t chunk = left > UINT32_MAX ? UINT32_MAX : (uint32_t)left;
        uint32_t written = 0;
        if (WriteFile(handle, bytes.ptr + done, chunk, &written, NULL) == 0 || written == 0) {
            return;
        }
        done += written;
    }
}

uint32_t ms_sys_process_id(void) { return GetCurrentProcessId(); }

/* The value of MS_FAULT_RECORD as UTF-8 in `path`; false when it is unset, empty or too long. */
static bool record_path(char *path, size_t capacity) {
    static const uint16_t name[] = {'M', 'S', '_', 'F', 'A', 'U', 'L', 'T', '_', 'R', 'E', 'C', 'O', 'R', 'D', 0};
    uint16_t wide[PATH_CAPACITY];
    const uint32_t length = GetEnvironmentVariableW(name, wide, PATH_CAPACITY);
    if (length == 0 || length >= PATH_CAPACITY || capacity > INT32_MAX) {
        return false;
    }
    const int used = WideCharToMultiByte(CODE_PAGE_UTF8, 0, wide, (int)length, path, (int)capacity - 1, NULL, NULL);
    if (used <= 0) {
        return false;
    }
    path[used] = 0;
    return true;
}

void ms_sys_fault_record_write(MsBytes bytes) {
    char path[4 * 1024];
    if (!record_path(path, sizeof path)) {
        return;
    }
    MsSysFd fd = MS_SYS_FD_INVALID;
    if (ms_sys_fs_open(path, MS_SYS_O_WRITE | MS_SYS_O_CREATE | MS_SYS_O_TRUNCATE, 0644, &fd) != 0) {
        return;
    }
    size_t done = 0;
    while (done < bytes.len) {
        size_t count = 0;
        if (ms_sys_fs_write(fd, bytes.ptr + done, bytes.len - done, &count) != 0 || count == 0) {
            break;
        }
        done += count;
    }
    const MsSysError closed = ms_sys_fs_close(fd); /* the record is written; a failed close changes nothing */
    (void)closed;
}

void ms_sys_exit_now(int status) {
    (void)TerminateProcess(GetCurrentProcess(), (uint32_t)status);
    for (;;) {
        /* TerminateProcess does not return for the calling process. */
    }
}
