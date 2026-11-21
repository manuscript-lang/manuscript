/* How the natives that call the operating system report a failure (fail.h). */
#define _POSIX_C_SOURCE 200809L /* libuv's headers need the POSIX types under -std=c17 */

#include "runtime/std/fail.h"

#include <uv.h>

#include "base/strbuild.h"
#include "runtime/core/unwind.h"
#include "runtime/io/pool.h"

MsFail ms_fail_new(void) { return (MsFail){.status = MS_STATUS_OK, .message = ms_string_empty()}; }

bool ms_fail_failed(const MsFail *fail) { return fail->status != MS_STATUS_OK; }

void ms_fail_free(MsFail *fail) {
  ms_string_release(&fail->message);
  fail->message = ms_string_empty();
}

void ms_fail_status(MsFail *fail, uint8_t status) {
  ms_fail_free(fail);
  fail->status = status;
}

void ms_fail_text(MsFail *fail, const char *text) {
  ms_fail_free(fail);
  fail->status = MS_STATUS_FAILED;
  fail->message = ms_string_from_span(ms_span_of_text(text));
}

uint8_t ms_fail_classify(int code) {
  switch (code) {
    case UV_ENOENT:
      return MS_STATUS_NOT_FOUND;
    case UV_EEXIST:
      return MS_STATUS_ALREADY_EXISTS;
    case UV_ENOTEMPTY:
      return MS_STATUS_NOT_EMPTY;
    case UV_ENOTDIR:
    case UV_EISDIR:
    case UV_EINVAL:
      return MS_STATUS_INVALID_INPUT;
    case UV_EACCES:
    case UV_EPERM:
      return MS_STATUS_PERMISSION_DENIED;
    case UV_ENOTSUP:
    case UV_ENOSYS:
      return MS_STATUS_UNSUPPORTED;
    default:
      return MS_STATUS_FAILED;
  }
}

void ms_fail_uv_text(MsFail *fail, int code, const char *operation, MsSpan name) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, operation);
  if (name.len != 0) {
    ms_strbuild_append_byte(&text, ' ');
    ms_strbuild_append(&text, name);
  }
  ms_strbuild_append_text(&text, ": ");
  ms_strbuild_append_text(&text, uv_strerror(code));
  ms_fail_free(fail);
  fail->status = MS_STATUS_FAILED;
  fail->message = ms_strbuild_finish(&text);
  ms_strbuild_free(&text);
}

void ms_fail_uv(MsFail *fail, int code, const char *operation, MsSpan name) {
  const uint8_t status = ms_fail_classify(code);
  if (status != MS_STATUS_FAILED) {
    ms_fail_status(fail, status);
    return;
  }
  ms_fail_uv_text(fail, code, operation, name);
}

bool ms_fail_cancel_requested(void) { return !ms_pool_on_thread() && ms_cancel_flag() != 0; }

bool ms_fail_poll_cancel(MsFail *fail) {
  if (!ms_fail_cancel_requested()) {
    return false;
  }
  ms_fail_text(fail, "cancelled");
  return true;
}

uint8_t ms_fail_finish_at(MsFail *fail, MsSpan detail, MsString *err) {
  const uint8_t status = fail->status;
  *err = ms_string_empty();
  if (status != MS_STATUS_OK && ms_fail_cancel_requested()) {
    ms_fail_free(fail);
    ms_cancelled(); /* the text is dropped first, while the cancel can still unwind */
  }
  if (status == MS_STATUS_FAILED) {
    *err = fail->message;
    fail->message = ms_string_empty();
  } else if (status != MS_STATUS_OK) {
    *err = ms_string_from_span(detail);
  }
  return status;
}

uint8_t ms_fail_finish(MsFail *fail, MsString *err) { return ms_fail_finish_at(fail, ms_span_of(NULL, 0), err); }
