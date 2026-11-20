/* stdout.h: buffered standard output, unbuffered standard error, and the per-test output captures, over ms_sys_fs_*.
 * Staged like fault_abi.h: not in the archive build until the flip moves it to runtime/core and lists the symbols
 * (msrt_io_write_stdout, msrt_io_write_stdout_line, msrt_io_write_stderr, msrt_test_capture_*) in
 * runtime/symbols, replacing crates/ms-rt/src/io.rs. Left in Rust for now: msrt_test_record, msrt_test_failure,
 * msrt_test_deadline and the fault records (msrt_test_capture_fault), which are test-runner machinery.
 *
 * The flip must provide ms_task_capture / ms_task_set_capture (the running task's capture id, 0 when none); the
 * tasks thread adds the field to MsTask. */
#ifndef MS_STAGED_STDOUT_H
#define MS_STAGED_STDOUT_H

#include <stdint.h>

#include "ms_rt/string.h"

/* The running task's output capture (0: standard output) and its setter; defined with the task record. */
uint64_t ms_task_capture(void);
void ms_task_set_capture(uint64_t id);

/* Appends `data` then `end` to the running task's capture, or to standard output, under one lock. */
void ms_stdout_write(const uint8_t *data, size_t length, const uint8_t *end, size_t end_length);

void msrt_io_write_stdout(const MsStr *text);
void msrt_io_write_stdout_line(const MsStr *text, const MsStr *end);
void msrt_io_write_stderr(const MsStr *text);

int64_t msrt_test_capture_new(void);
void msrt_test_capture_set(int64_t id);
int64_t msrt_test_capture_current(void);
void msrt_test_capture_take(int64_t id, MsStr *out);
void msrt_test_capture_free(int64_t id);

#endif
