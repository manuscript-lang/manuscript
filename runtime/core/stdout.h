/* stdout.h: buffered standard output, unbuffered standard error, and the per-test output captures (stdout.c), over
 * ms_sys_fs_*. The exported natives are declared in ms_rt/io.h and ms_rt/test.h; the running task's capture is
 * ms_task_capture (task.h). */
#ifndef MS_CORE_STDOUT_H
#define MS_CORE_STDOUT_H

#include <stdint.h>

#include <stddef.h>

/* Appends `data` then `end` to the running task's capture, or to standard output, under one lock. */
void ms_stdout_write(const uint8_t *data, size_t length, const uint8_t *end, size_t end_length);
/* Writes what is buffered and frees the buffer (the end of the run, before the leak report); a later write buffers anew. */
void ms_sched_release_stdout(void);

#endif
