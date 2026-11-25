/* The Windows link: lld in its GNU flavor over mingw-w64's startup object and CRT, dropping unreachable
 * sections (the `/opt:ref` of the MSVC linker) and keeping DWARF in the image. The import libraries
 * (`libkernel32.a`, ...) are the ones llvm-mingw generates from the DLL export lists (see link.h). */
#include "base/file.h"
#include "base/path.h"
#include "compiler/link/link_job.h"

#if defined(__aarch64__)
#define MACHINE "arm64pe"
#else
#define MACHINE "i386pep"
#endif

static const char *const libraries[] = {
    "libmingw32.a", "libunwind.a", "libmoldname.a", "libmingwex.a", "libucrt.a", "libadvapi32.a",
    "libbcrypt.a", "libcrypt32.a", "libdbghelp.a", "libntdll.a", "libsecur32.a", "libshell32.a",
    "libuser32.a", "libuserenv.a", "libiphlpapi.a", "libpsapi.a", "libole32.a", "libws2_32.a",
    "libsynchronization.a", "libclang_rt.builtins.a", "libkernel32.a"};

bool link_host_prepare(LinkJob *job, MsStrBuild *why) {
  (void)why;
  const LinkOptions *options = job->options;
  link_job_push(job, options->lld);
  /* Identical inputs must link to identical bytes, hence no timestamp. */
  const char *const head[] = {"-flavor", "gnu", "-m", MACHINE, "--gc-sections", "--subsystem", "console",
                              "--no-insert-timestamp", "-o"};
  for (size_t index = 0; index < MS_COUNT_OF(head); index++) {
    link_job_push_text(job, head[index]);
  }
  link_job_push(job, job->request->output);
  if (options->strip) {
    link_job_push_text(job, "--strip-all");
  }
  link_job_push_in(job, options->files, "crt2.o");
  link_job_push(job, job->request->object);
  link_job_push_text(job, "--start-group");
  for (size_t index = 0; index < job->request->input_count; index++) {
    link_job_push(job, job->request->inputs[index]);
  }
  for (size_t index = 0; index < MS_COUNT_OF(libraries); index++) {
    link_job_push_in(job, options->files, libraries[index]);
  }
  link_job_push_text(job, "--end-group");
  return true;
}

/* Whether the last path component has an extension. */
static bool has_extension(MsSpan path) {
  MsSpan name = ms_path_file_name(path);
  for (size_t index = 0; index < name.len; index++) {
    if (name.ptr[index] == '.') {
      return true;
    }
  }
  return false;
}

/* Windows linkers add `.exe` to an output name without it; the build keeps the name it chose. */
bool link_host_finish(LinkJob *job, bool linked, MsStrBuild *why) {
  MsSpan output = job->request->output;
  if (!linked || ms_file_is_regular(output) || has_extension(output)) {
    return true;
  }
  MsStrBuild suffixed = ms_strbuild_new();
  ms_strbuild_append(&suffixed, output);
  ms_strbuild_append_text(&suffixed, ".exe");
  MsString renamed = ms_strbuild_finish(&suffixed);
  bool ok = !ms_file_is_regular(ms_string_span(&renamed)) || ms_file_rename(ms_string_span(&renamed), output);
  if (!ok) {
    ms_strbuild_append_text(why, "cannot place the executable ");
    ms_strbuild_append(why, output);
  }
  ms_string_release(&renamed);
  return ok;
}

void link_host_advice(MsSpan detail, bool musl, MsStrBuild *out) {
  (void)musl;
  link_foreign_advice(detail, out);
}
