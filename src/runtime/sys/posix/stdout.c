/* Standard output on Linux and macOS. Declares the few system functions it calls by hand, so no C library header is
 * needed. */
#include "runtime/sys/sys.h"

extern long write(int fd, const void *buffer, unsigned long count);
extern int isatty(int fd);
#ifdef __APPLE__
extern int *__error(void); // NOLINT(bugprone-reserved-identifier): the C library's own name
#define SYSTEM_ERRNO() (*__error())
#else
extern int *__errno_location(void); // NOLINT(bugprone-reserved-identifier): the C library's own name
#define SYSTEM_ERRNO() (*__errno_location())
#endif

enum { STDOUT_FD = 1, ERROR_INTERRUPTED = 4, ERROR_BROKEN_PIPE = 32 };

int32_t ms_sys_stdout_write(MsSpan bytes, size_t *written) {
  *written = 0;
  for (;;) {
    const long count = write(STDOUT_FD, bytes.ptr, bytes.len);
    if (count >= 0) {
      *written = (size_t)count;
      return 0;
    }
    if (SYSTEM_ERRNO() != ERROR_INTERRUPTED) {
      return SYSTEM_ERRNO();
    }
  }
}

bool ms_sys_stdout_is_terminal(void) { return isatty(STDOUT_FD) != 0; }

bool ms_sys_error_is_broken_pipe(int32_t code) { return code == ERROR_BROKEN_PIPE; }
