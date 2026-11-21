/* Owns the NUL-terminated copies and error messages that OS calls need (see ostext.h). */
#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L
#if defined(__APPLE__)
#define _DARWIN_C_SOURCE
#endif
#endif
#include "base/ostext.h"

#include <string.h>

#include "base/alloc.h"
#include "base/fatal.h"

MsOsText ms_os_text_new(MsSpan span) {
  size_t size = 0;
  if (!ms_size_add(span.len, 1, &size)) {
    ms_fatal(MS_FATAL_OVERFLOW, "os text size");
  }
  uint8_t *bytes = ms_alloc(size);
  if (span.len != 0) {
    __builtin_memcpy(bytes, span.ptr, span.len);
  }
  bytes[span.len] = 0;
  return (MsOsText){.ptr = (char *)bytes};
}

void ms_os_text_free(MsOsText *text) {
  ms_free(text->ptr);
  text->ptr = NULL;
}

void ms_os_error_text(int error_number, MsStrBuild *out) {
  char message[128] = "unknown error";
#ifdef _WIN32
  if (strerror_s(message, sizeof message, error_number) != 0) {
    ms_strbuild_append_text(out, "error ");
    ms_strbuild_append_i64(out, error_number);
    return;
  }
#else
  if (strerror_r(error_number, message, sizeof message) != 0) {
    ms_strbuild_append_text(out, "error ");
    ms_strbuild_append_i64(out, error_number);
    return;
  }
#endif
  ms_strbuild_append_text(out, message);
}
