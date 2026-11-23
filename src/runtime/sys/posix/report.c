/* How a fault reaches the outside on Linux and macOS: standard error, the process id, and the record file.
 * The functions allocate nothing, so a fault that ran out of memory can still be reported. */
#include "runtime/sys/sys.h"

extern char *getenv(const char *name);
extern int open(const char *path, int flags, ...);
extern long write(int fd, const void *buffer, unsigned long count);
extern int close(int fd);
extern MS_NORETURN void _exit(int status); // NOLINT(bugprone-reserved-identifier): the C library's own name

enum { STDERR_FD = 2, RECORD_MODE = 0644 };

#ifdef __APPLE__
enum { OPEN_WRITE_ONLY = 0x1, OPEN_CREATE = 0x200, OPEN_TRUNCATE = 0x400 };
#else
enum { OPEN_WRITE_ONLY = 01, OPEN_CREATE = 0100, OPEN_TRUNCATE = 01000 };
#endif

/* Writes all of `bytes` to `fd`, stopping at the first error. */
static void write_all(int fd, MsSpan bytes) {
  size_t done = 0;
  while (done < bytes.len) {
    const long count = write(fd, bytes.ptr + done, bytes.len - done);
    if (count <= 0) {
      return;
    }
    done += (size_t)count;
  }
}

void ms_sys_stderr_write(MsSpan bytes) { write_all(STDERR_FD, bytes); }

void ms_sys_fault_record_write(MsSpan bytes) {
  /* The environment is not changed after start-up, so reading it here is safe. */
  // NOLINTNEXTLINE(concurrency-mt-unsafe)
  const char *const path = getenv("MS_FAULT_RECORD");
  if (path == NULL || path[0] == 0) {
    return;
  }
  const int fd = open(path, OPEN_WRITE_ONLY | OPEN_CREATE | OPEN_TRUNCATE, RECORD_MODE);
  if (fd < 0) {
    return;
  }
  write_all(fd, bytes);
  (void)close(fd); /* the record is written; a failed close changes nothing */
}

void ms_sys_exit_now(int status) { _exit(status); }
