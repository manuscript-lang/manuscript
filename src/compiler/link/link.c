/* Owns the steps every host's link shares: prepare, run lld, finish (see link.h). What differs per host is
 * in link_linux.c, link_macos.c and link_windows.c. */
#include "compiler/link/link.h"

#include "base/alloc.h"
#include "base/fatal.h"
#include "base/file.h"
#include "base/process.h"
#include "compiler/link/link_job.h"

static void job_free(LinkJob *job) {
  for (size_t index = 0; index < job->args.len; index++) {
    ms_string_release(&job->args.ptr[index]);
  }
  link_arg_list_free(&job->args);
  ms_string_release(&job->scratch);
}

static bool run_lld(LinkJob *job, MsStrBuild *why) {
  size_t argv_bytes = 0;
  if (!ms_size_mul(job->args.len, sizeof(MsSpan), &argv_bytes)) {
    ms_fatal(MS_FATAL_OVERFLOW, "argument count");
  }
  MsSpan *argv = ms_alloc(argv_bytes);
  for (size_t index = 0; index < job->args.len; index++) {
    argv[index] = ms_string_span(&job->args.ptr[index]);
  }
  MsStrBuild log_path = ms_strbuild_new();
  ms_strbuild_append(&log_path, job->request->output);
  ms_strbuild_append_text(&log_path, ".link.log");
  MsString log = ms_strbuild_finish(&log_path);
  MsProcessSpec spec = {.argv = argv, .argc = job->args.len, .directory = ms_span_of(NULL, 0),
                        .log_path = ms_string_span(&log)};
  MsStrBuild detail = ms_strbuild_new();
  bool ok = ms_process_run_logged(ms_span_of_text("the bundled linker"), &spec, &detail);
  if (!ok) {
    ms_strbuild_append_text(why, "linking failed; the linker output follows. ");
    link_host_advice(ms_strbuild_span(&detail), job->options->musl, why);
    ms_strbuild_append_text(why, ":\n");
    ms_strbuild_append(why, ms_strbuild_span(&detail));
  }
  ms_strbuild_free(&detail);
  ms_path_remove(ms_string_span(&log));
  ms_string_release(&log);
  ms_free(argv);
  return ok;
}

bool link_executable(const LinkOptions *options, const LinkRequest *request, MsStrBuild *why) {
  LinkJob job = {.options = options, .request = request, .scratch = ms_string_empty()};
  bool ok = link_host_prepare(&job, why);
  if (ok) {
    ok = run_lld(&job, why);
  }
  ok = link_host_finish(&job, ok, why) && ok;
  job_free(&job);
  return ok;
}
