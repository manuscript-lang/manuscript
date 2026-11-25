/* The Linux link: glibc 2.28 stand-ins, or static musl (see link.h). */
#include "base/path.h"
#include "compiler/link/glibc_stubs.h"
#include "compiler/link/link_job.h"

#if defined(__aarch64__)
#define LOADER_PATH "/lib/ld-linux-aarch64.so.1"
#else
#define LOADER_PATH "/lib64/ld-linux-x86-64.so.2"
#endif

static void push_all(LinkJob *job, const char *const *items, size_t count) {
  for (size_t index = 0; index < count; index++) {
    link_job_push_text(job, items[index]);
  }
}

static void push_common(LinkJob *job) {
  const LinkOptions *options = job->options;
  link_job_push(job, options->lld);
  const char *const common[] = {"-flavor", "gnu", "--gc-sections", "--eh-frame-hdr", "-o"};
  push_all(job, common, MS_COUNT_OF(common));
  link_job_push(job, job->request->output);
  if (options->strip) {
    link_job_push_text(job, "--strip-all");
  }
  if (options->quick) {
    link_job_push_text(job, "-O0");
    link_job_push_text(job, "--threads=1");
  }
  if (options->musl) {
    link_job_push_text(job, "-static");
    /* libunwind.a names dl and pthread as dependent libraries; musl has them inside libc.a. */
    link_job_push_text(job, "--no-dependent-libraries");
    link_job_push_in(job, options->files, "crt1.o");
    link_job_push_in(job, options->files, "crti.o");
    return;
  }
  const char *const dynamic[] = {"--dynamic-linker", LOADER_PATH, "-z", "now", "-z", "relro"};
  push_all(job, dynamic, MS_COUNT_OF(dynamic));
}

static void push_inputs(LinkJob *job) {
  const LinkRequest *request = job->request;
  link_job_push(job, request->object);
  link_job_push_text(job, "--start-group");
  for (size_t index = 0; index < request->input_count; index++) {
    link_job_push(job, request->inputs[index]);
  }
  link_job_push_in(job, job->options->files, "libunwind.a");
#if defined(__aarch64__)
  link_job_push_in(job, job->options->files, "libgcc.a");
#endif
  if (job->options->musl) {
    link_job_push_in(job, job->options->files, "libc.a");
  }
  link_job_push_text(job, "--end-group");
}

bool link_host_prepare(LinkJob *job, MsStrBuild *why) {
  MsString stubs = ms_string_empty();
  if (!job->options->musl && !link_glibc_stubs(job->options, &stubs, why)) {
    ms_string_release(&stubs);
    return false;
  }
  push_common(job);
  push_inputs(job);
  if (job->options->musl) {
    link_job_push_in(job, job->options->files, "crtn.o");
    return true;
  }
  link_job_push_text(job, "--as-needed");
  for (size_t index = 0; index < link_glibc_library_count; index++) {
    link_job_push_in(job, ms_string_span(&stubs), link_glibc_libraries[index]);
  }
  ms_string_release(&stubs);
  return true;
}

bool link_host_finish(LinkJob *job, bool linked, MsStrBuild *why) {
  (void)job;
  (void)linked;
  (void)why;
  return true;
}

void link_host_advice(MsSpan detail, bool musl, MsStrBuild *out) {
  link_foreign_advice(detail, out);
  if (!musl) {
    ms_strbuild_append_text(out, ". Programs link against glibc 2.28, so an object built against a newer glibc may "
                                "need symbols it lacks; pass --static to link musl instead");
  }
}
