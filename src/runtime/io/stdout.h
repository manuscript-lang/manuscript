/* stdout.h: buffered standard output, unbuffered standard error, and the per-test output captures (stdout.c). The
 * running task's capture is ms_task_capture (core/task.h). */
#ifndef MS_RUNTIME_IO_STDOUT_H
#define MS_RUNTIME_IO_STDOUT_H

#include <stdint.h>

#include "base/list.h"
#include "base/string.h"

/* Writes what is buffered. The scheduler calls it before it blocks, and the process before it ends. */
void ms_stdout_flush(void);
/* Writes what is buffered and frees the buffer (the end of the run); a later write buffers anew. */
void ms_stdout_release(void);
/* The system error code of the first write that failed for a reason other than a closed reader; 0 when none. */
int32_t ms_stdout_error(void);

/* ms-sig: msrt_io_write_stdout(s: *const StrVal) */
void msrt_io_write_stdout(const MsString *text);
/* `print`: the text and its ending as one write, with no joined copy. */
/* ms-sig: msrt_io_write_stdout_end(s: *const StrVal, end: *const StrVal) */
void msrt_io_write_stdout_end(const MsString *text, const MsString *end);
/* ms-sig: msrt_io_write_stderr(s: *const StrVal) */
void msrt_io_write_stderr(const MsString *text);
/* ms-sig: msrt_io_write_bytes_stdout(v: *const VecVal) */
void msrt_io_write_bytes_stdout(const MsList *bytes);
/* ms-sig: msrt_io_write_bytes_stderr(v: *const VecVal) */
void msrt_io_write_bytes_stderr(const MsList *bytes);
/* ms-sig: msrt_io_flush() */
void msrt_io_flush(void);

/* ms-sig: msrt_test_capture_new() -> i64 */
int64_t msrt_test_capture_new(void);
/* ms-sig: msrt_test_capture_set(id: i64) */
void msrt_test_capture_set(int64_t id);
/* ms-sig: msrt_test_capture_current() -> i64 */
int64_t msrt_test_capture_current(void);
/* ms-sig: msrt_test_capture_take(id: i64, out: *mut StrVal) */
void msrt_test_capture_take(int64_t id, MsString *out_text);
/* ms-sig: msrt_test_capture_free(id: i64) */
void msrt_test_capture_free(int64_t id);

#endif
