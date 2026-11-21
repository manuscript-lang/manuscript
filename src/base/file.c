/* Owns the whole-file reads and writes and the temporary directory choice (see file.h). The directory
 * operations differ per host and live in file_posix.c and file_windows.c. */
#include "base/file.h"

#include <stdio.h>

#include "base/env.h"
#include "base/ostext.h"

enum { READ_CHUNK = 16384 };

bool ms_file_read(MsSpan path, MsBytes *out) {
  MsOsText name = ms_os_text_new(path);
  FILE *file = fopen(name.ptr, "rb"); /* NOLINT(android-cloexec-fopen): "e" is glibc-only */
  ms_os_text_free(&name);
  if (file == NULL) {
    return false;
  }
  MsBytes bytes = {0};
  size_t count = 0;
  do {
    uint8_t *room = ms_list_extend(&bytes, 1, READ_CHUNK);
    count = fread(room, 1, READ_CHUNK, file);
    bytes.len -= READ_CHUNK - count;
  } while (count == READ_CHUNK);
  bool ok = ferror(file) == 0;
  ok = fclose(file) == 0 && ok;
  if (!ok) {
    ms_bytes_free(&bytes);
    return false;
  }
  ms_bytes_free(out);
  *out = bytes;
  return true;
}

bool ms_file_write(MsSpan path, MsSpan data) {
  MsOsText name = ms_os_text_new(path);
  FILE *file = fopen(name.ptr, "wb"); /* NOLINT(android-cloexec-fopen): "e" is glibc-only */
  ms_os_text_free(&name);
  if (file == NULL) {
    return false;
  }
  bool ok = data.len == 0 || fwrite(data.ptr, 1, data.len, file) == data.len;
  return fclose(file) == 0 && ok;
}

MsString ms_temp_dir(void) {
  MsString value = ms_string_empty();
  if (ms_env_get("TMPDIR", &value) && !ms_string_is_empty(&value)) {
    return value;
  }
  ms_string_release(&value);
  if (ms_env_get("TEMP", &value) && !ms_string_is_empty(&value)) {
    return value;
  }
  ms_string_release(&value);
  return ms_string_from_span(ms_span_of_text("/tmp"));
}
