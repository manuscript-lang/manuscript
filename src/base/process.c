/* Owns the host-independent part of running a child program (see process.h). */
#include "base/process.h"

#include "base/file.h"

static void append_trimmed_log(MsSpan log_path, MsStrBuild *out) {
  MsBytes text = {0};
  if (!ms_file_read(log_path, &text)) {
    return;
  }
  size_t end = text.len;
  while (end > 0 && (text.ptr[end - 1] == '\n' || text.ptr[end - 1] == '\r' || text.ptr[end - 1] == ' ')) {
    end--;
  }
  ms_strbuild_append(out, ms_span_of(text.ptr, end));
  ms_bytes_free(&text);
}

bool ms_process_run_logged(MsSpan what, const MsProcessSpec *spec, MsStrBuild *why) {
  int status = 0;
  MsStrBuild reason = ms_strbuild_new();
  if (!ms_process_run(spec, &status, &reason)) {
    ms_strbuild_append_text(why, "cannot run ");
    ms_strbuild_append(why, what);
    ms_strbuild_append_text(why, ": ");
    ms_strbuild_append(why, ms_strbuild_span(&reason));
    ms_strbuild_free(&reason);
    return false;
  }
  ms_strbuild_free(&reason);
  if (status == 0) {
    return true;
  }
  ms_strbuild_append(why, what);
  ms_strbuild_append_text(why, " failed: ");
  append_trimmed_log(spec->log_path, why);
  return false;
}
