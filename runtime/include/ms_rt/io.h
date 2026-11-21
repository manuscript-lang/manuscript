/* ms_rt/io.h: the @std/io natives (runtime/std/io.c) over the host stream (ms_rt/stream.h). Fallible functions
 * return a status (0 ok, STATUS_NONE at the end of a stream, otherwise the runtime's STATUS_* code; STATUS_FAILED
 * carries its text through `err`). Symbols are listed in runtime/symbols/io.txt. */
/* ms: domain I/O */
#ifndef MS_RT_IO_H
#define MS_RT_IO_H

#include "ms_rt/base.h"
#include "ms_rt/string.h"

/* ms-sig: msstd_io_close(handle h: *mut ObjCell<Stream>, err: ErrSlot) -> u8 @domain=I/O */
uint8_t msstd_io_close(void *handle, MsStr *err);
/* ms-sig: msstd_io_read(handle h: *mut ObjCell<Stream>, has_max: HasRaw, max: i64, out: *mut VecVal, err: ErrSlot) -> u8 @domain=I/O */
uint8_t msstd_io_read(void *handle, uint8_t has_max, int64_t max, MsVec *out, MsStr *err);
/* ms-sig: msstd_io_redirect_null(which: i64, err: ErrSlot) -> u8 @domain=I/O */
uint8_t msstd_io_redirect_null(int64_t which, MsStr *err);
/* ms-sig: msstd_io_stdout_status(flush: u8, err: ErrSlot) -> u8 @domain=I/O */
uint8_t msstd_io_stdout_status(uint8_t flush, MsStr *err);
/* ms-sig: msstd_io_write(handle h: *mut ObjCell<Stream>, data: *const StrVal, err: ErrSlot) -> u8 @domain=I/O */
uint8_t msstd_io_write(void *handle, const MsStr *data, MsStr *err);
/* ms-sig: msstd_io_write_bytes(handle h: *mut ObjCell<Stream>, data: *const VecVal, err: ErrSlot) -> u8 @domain=I/O */
uint8_t msstd_io_write_bytes(void *handle, const MsVec *data, MsStr *err);

/* Standard output, buffered in runtime/core/stdout.c; standard error flushes it first. */
/* Writes out what the runtime buffered for standard output, and the OS code of the first failed write (0 when none)
 * (runtime/core/stdout.c). Declared here, not in ms_sched.h, whose wait bits clash with core/task.h. */
void ms_sched_flush_stdout(void);
int32_t ms_sched_stdout_error(void);

/* ms-sig: msrt_io_write_stdout(s: *const StrVal) */
void msrt_io_write_stdout(const MsStr *text);

/* ms-sig: msrt_io_write_stdout_line(s: *const StrVal, end: *const StrVal) */
void msrt_io_write_stdout_line(const MsStr *text, const MsStr *end);

/* ms-sig: msrt_io_write_stderr(s: *const StrVal) */
void msrt_io_write_stderr(const MsStr *text);

/* ms-sig: msrt_io_write_bytes_stdout(v: *const VecVal) */
void msrt_io_write_bytes_stdout(const MsVec *bytes);

/* ms-sig: msrt_io_write_bytes_stderr(v: *const VecVal) */
void msrt_io_write_bytes_stderr(const MsVec *bytes);

/* ms-sig: msrt_io_flush() */
void msrt_io_flush(void);

#endif
