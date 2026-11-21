/* Standard output on Windows. */
#include "runtime/sys/sys.h"
#include "runtime/sys/windows/winapi.h"

// NOLINTBEGIN(readability-identifier-naming): the names are Win32's
MS_WINAPI uintptr_t GetStdHandle(uint32_t which);
MS_WINAPI int WriteFile(uintptr_t file, const void *buffer, uint32_t count, uint32_t *written, void *overlapped);
MS_WINAPI int GetConsoleMode(uintptr_t console, uint32_t *mode);
MS_WINAPI uint32_t GetLastError(void);
// NOLINTEND(readability-identifier-naming)

#define STD_OUTPUT_HANDLE ((uint32_t)-11)

enum { WIN_ERROR_BROKEN_PIPE = 109, WIN_ERROR_NO_DATA = 232, WIN_ERROR_GENERAL = 31 };

int32_t ms_sys_stdout_write(MsSpan bytes, size_t *written) {
  *written = 0;
  const uint32_t chunk = bytes.len > UINT32_MAX ? UINT32_MAX : (uint32_t)bytes.len;
  uint32_t done = 0;
  if (WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), bytes.ptr, chunk, &done, NULL) == 0) {
    const uint32_t error = GetLastError();
    return error == 0 ? WIN_ERROR_GENERAL : (int32_t)error;
  }
  *written = done;
  return 0;
}

bool ms_sys_stdout_is_terminal(void) {
  uint32_t mode = 0;
  return GetConsoleMode(GetStdHandle(STD_OUTPUT_HANDLE), &mode) != 0;
}

bool ms_sys_error_is_broken_pipe(int32_t code) { return code == WIN_ERROR_BROKEN_PIPE || code == WIN_ERROR_NO_DATA; }
