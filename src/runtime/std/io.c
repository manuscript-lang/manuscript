/* The @std/io natives (see io.h). */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "runtime/std/io.h"

#include <string.h>

#include "runtime/io/stdout.h"
#include "runtime/std/fail.h"
#include "runtime/std/stream.h"
#include "runtime/sys/fs.h"

enum { STANDARD_STREAMS = 3 };

uint8_t msstd_io_read(MsObj *handle, uint8_t has_max, int64_t max, MsBytes *out, MsString *err) {
  MsFail fail = ms_fail_new();
  MsBytes data = {0};
  bool eof = false;
  if (!ms_stream_read((MsStream *)handle, has_max != 0, max, &data, &eof, &fail)) {
    return ms_fail_finish(&fail, err);
  }
  if (eof) {
    ms_fail_status(&fail, MS_STATUS_NONE);
    ms_bytes_free(&data);
  } else {
    *out = data;
  }
  return ms_fail_finish(&fail, err);
}

static uint8_t write_to(MsObj *handle, MsSpan data, MsString *err) {
  MsFail fail = ms_fail_new();
  (void)ms_stream_write((MsStream *)handle, data, &fail);
  return ms_fail_finish(&fail, err);
}

uint8_t msstd_io_write_bytes(MsObj *handle, const MsBytes *data, MsString *err) {
  return write_to(handle, ms_bytes_span(data), err);
}

uint8_t msstd_io_write(MsObj *handle, const MsString *data, MsString *err) {
  return write_to(handle, ms_string_span(data), err);
}

uint8_t msstd_io_close(MsObj *handle, MsString *err) {
  MsFail fail = ms_fail_new();
  (void)ms_stream_close((MsStream *)handle, &fail);
  return ms_fail_finish(&fail, err);
}

uint8_t msstd_io_redirect_null(int64_t which, MsString *err) {
  MsFail fail = ms_fail_new();
  if (which < 0 || which >= STANDARD_STREAMS) {
    ms_fail_status(&fail, MS_STATUS_INVALID_INPUT);
    return ms_fail_finish(&fail, err);
  }
  ms_stdout_flush();
  const int code = ms_sys_fs_redirect_null((int)which);
  if (code != 0) {
    ms_fail_uv_text(&fail, code, "redirect", ms_span_of_text("standard stream"));
  }
  return ms_fail_finish(&fail, err);
}

uint8_t msstd_io_stdout_status(uint8_t flush, MsString *err) {
  MsFail fail = ms_fail_new();
  if (flush != 0) {
    ms_stdout_flush();
  }
  const int32_t code = ms_stdout_error();
  if (code != 0) {
    ms_fail_text(&fail, strerror(code));
  }
  return ms_fail_finish(&fail, err);
}
