/* runtime/std/io.h: the @std/io natives over a host stream (stream.h): read, write and close of a handle, the redirect of
 * a standard stream, and the status of writing standard output. A failure of a transfer is MS_STATUS_FAILED with its
 * text. */
#ifndef MS_RUNTIME_STD_IO_H
#define MS_RUNTIME_STD_IO_H

#include "abi/status.h"
#include "base/bytes.h"
#include "base/desc.h"
#include "base/string.h"

/* One read of up to `max` bytes; MS_STATUS_NONE at the end of the stream. */
/* ms-sig: msstd_io_read(handle h: *mut ObjCell<Stream>, has_max: HasRaw, max: i64, out: *mut VecVal, err: ErrSlot) -> u8 @domain=I/O */
uint8_t msstd_io_read(MsObj *handle, uint8_t has_max, int64_t max, MsBytes *out, MsString *err);
/* ms-sig: msstd_io_write(handle h: *mut ObjCell<Stream>, data: *const StrVal, err: ErrSlot) -> u8 @domain=I/O */
uint8_t msstd_io_write(MsObj *handle, const MsString *data, MsString *err);
/* ms-sig: msstd_io_write_bytes(handle h: *mut ObjCell<Stream>, data: *const VecVal, err: ErrSlot) -> u8 @domain=I/O */
uint8_t msstd_io_write_bytes(MsObj *handle, const MsBytes *data, MsString *err);
/* ms-sig: msstd_io_close(handle h: *mut ObjCell<Stream>, err: ErrSlot) -> u8 @domain=I/O */
uint8_t msstd_io_close(MsObj *handle, MsString *err);
/* Points standard stream `which` (0 input, 1 output, 2 error) at the null device, after writing what is buffered. */
/* ms-sig: msstd_io_redirect_null(which: i64, err: ErrSlot) -> u8 @domain=I/O */
uint8_t msstd_io_redirect_null(int64_t which, MsString *err);
/* The result of writing standard output: with `flush`, the buffer is written first; the first write that failed is
 * returned as an error. */
/* ms-sig: msstd_io_stdout_status(flush: u8, err: ErrSlot) -> u8 @domain=I/O */
uint8_t msstd_io_stdout_status(uint8_t flush, MsString *err);

#endif
