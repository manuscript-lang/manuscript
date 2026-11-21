/* How a fault reaches the outside on Windows: standard error, the process id, and the record file. The functions
 * allocate nothing from the runtime, so a fault that ran out of memory can still be reported. */
#include "runtime/sys/sys.h"
#include "runtime/sys/windows/winapi.h"

// NOLINTBEGIN(readability-identifier-naming): the names are Win32's
MS_WINAPI uintptr_t GetStdHandle(uint32_t which);
MS_WINAPI int WriteFile(uintptr_t file, const void *buffer, uint32_t count, uint32_t *written, void *overlapped);
MS_WINAPI uint32_t GetCurrentProcessId(void);
MS_WINAPI uintptr_t GetCurrentProcess(void);
MS_WINAPI int TerminateProcess(uintptr_t process, uint32_t status);
MS_WINAPI uint32_t GetEnvironmentVariableW(const uint16_t *name, uint16_t *buffer, uint32_t capacity);
MS_WINAPI uintptr_t CreateFileW(const uint16_t *path, uint32_t access, uint32_t share, void *security,
                                uint32_t disposition, uint32_t attributes, uintptr_t template_file);
MS_WINAPI int CloseHandle(uintptr_t handle);
// NOLINTEND(readability-identifier-naming)

enum {
  GENERIC_WRITE = 0x40000000,
  FILE_SHARE_READ = 1,
  CREATE_ALWAYS = 2,
  FILE_ATTRIBUTE_NORMAL = 0x80,
  PATH_CAPACITY = 2048 /* UTF-16 units: a fault may run with little stack left, so the buffer stays small */
};

#define INVALID_HANDLE ((uintptr_t)-1)
#define STD_ERROR_HANDLE ((uint32_t)-12)

static void write_all(uintptr_t handle, MsSpan bytes) {
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

void ms_sys_stderr_write(MsSpan bytes) { write_all(GetStdHandle(STD_ERROR_HANDLE), bytes); }

uint32_t ms_sys_process_id(void) { return GetCurrentProcessId(); }

void ms_sys_fault_record_write(MsSpan bytes) {
  static const uint16_t name[] = {'M', 'S', '_', 'F', 'A', 'U', 'L', 'T', '_', 'R', 'E', 'C', 'O', 'R', 'D', 0};
  uint16_t path[PATH_CAPACITY];
  const uint32_t length = GetEnvironmentVariableW(name, path, PATH_CAPACITY);
  if (length == 0 || length >= PATH_CAPACITY) { /* unset, empty or too long */
    return;
  }
  const uintptr_t handle =
      CreateFileW(path, GENERIC_WRITE, FILE_SHARE_READ, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
  if (handle == INVALID_HANDLE) {
    return;
  }
  write_all(handle, bytes);
  (void)CloseHandle(handle); /* the record is written; a failed close changes nothing */
}

void ms_sys_exit_now(int status) {
  (void)TerminateProcess(GetCurrentProcess(), (uint32_t)status);
  for (;;) {
    /* TerminateProcess does not return for the calling process. */
  }
}
