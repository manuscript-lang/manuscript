/* Owns the argument helpers and the advice text that every host's link shares (see link_job.h). */
#include "compiler/link/link_job.h"

#include "base/chars.h"
#include "base/path.h"
#include "base/search.h"

void link_job_push(LinkJob *job, MsSpan argument) {
  link_arg_list_push(&job->args, ms_string_from_span(argument));
}

void link_job_push_text(LinkJob *job, const char *literal) {
  link_job_push(job, ms_span_of_text(literal));
}

void link_job_push_in(LinkJob *job, MsSpan directory, const char *name) {
  MsStrBuild path = ms_strbuild_new();
  ms_path_append_joined(&path, directory, ms_span_of_text(name));
  link_job_push(job, ms_strbuild_span(&path));
  ms_strbuild_free(&path);
}

static bool is_runtime_symbol(MsSpan name) {
  return ms_span_starts_with(name, ms_span_of_text("msrt_")) ||
         ms_span_starts_with(name, ms_span_of_text("msstd_"));
}

/* The text after each `undefined symbol: ` marker, up to the end of its line without trailing spaces. */
static bool next_undefined(MsSpan *rest, MsSpan *name) {
  const MsSpan marker = ms_span_of_text("undefined symbol: ");
  size_t at = ms_find(rest->ptr, rest->len, marker.ptr, marker.len);
  if (at == SIZE_MAX) {
    return false;
  }
  size_t start = at + marker.len;
  size_t end = start;
  while (end < rest->len && rest->ptr[end] != '\n' && rest->ptr[end] != '\r') {
    end++;
  }
  *name = ms_span_of(rest->ptr + start, end - start);
  while (name->len > 0 && name->ptr[name->len - 1] == ' ') {
    name->len--;
  }
  *rest = ms_span_of(rest->ptr + end, rest->len - end);
  return true;
}

/* The first undefined symbol the linker names that is not the runtime's is an `extern fn` nobody linked. */
void link_foreign_advice(MsSpan detail, MsStrBuild *out) {
  MsSpan rest = detail;
  MsSpan name = ms_span_of(NULL, 0);
  while (next_undefined(&rest, &name)) {
    if (is_runtime_symbol(name)) {
      continue;
    }
    ms_strbuild_append(out, name);
    ms_strbuild_append_text(out, " is not part of the Manuscript runtime; if an extern fn declares it, pass the "
                                "object or static library that defines it with --link <file>");
    return;
  }
  ms_strbuild_append_text(out, "A missing symbol or library usually means a stale or mismatched runtime "
                              "(check MS_RT_LIB), not a source error");
}
