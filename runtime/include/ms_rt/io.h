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

#endif
