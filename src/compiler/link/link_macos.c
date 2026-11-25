/* The macOS link: lld over generated SDK stubs, then a debug companion (see link.h and sdk_stubs.h). */
#include "base/file.h"
#include "base/path.h"
#include "base/process.h"
#include "compiler/link/link_job.h"
#include "compiler/link/sdk_stubs.h"

#if defined(__aarch64__)
#define ARCH "arm64"
#else
#define ARCH "x86_64"
#endif

MS_LIST_DEFINE(FileList, file_list, MsBytes)

/* The files of the link read into memory, so the symbol spans stay valid; owned. */
static void files_free(FileList *files) {
  for (size_t index = 0; index < files->len; index++) {
    ms_bytes_free(&files->ptr[index]);
  }
  file_list_free(files);
}

/* Reads the symbols of the object and every input. With `strict` an unreadable file is an error; without it
 * the file is skipped. */
static bool collect_symbols(const LinkJob *job, bool strict, FileList *files, MachoSymbols *symbols,
                            MsStrBuild *why) {
  const LinkRequest *request = job->request;
  for (size_t index = 0; index <= request->input_count; index++) {
    MsSpan path = index == 0 ? request->object : request->inputs[index - 1];
    MsBytes bytes = {0};
    if (!ms_file_read(path, &bytes)) {
      if (strict) {
        ms_strbuild_append_text(why, "cannot read ");
        ms_strbuild_append(why, path);
        return false;
      }
      continue;
    }
    file_list_push(files, bytes);
    macho_collect(ms_bytes_span(&files->ptr[files->len - 1]), symbols);
  }
  return true;
}

/* `path` made absolute without resolving links or `..`, so the linker and the debug companion see one
 * spelling. */
static MsString absolute(MsSpan path) {
  if (path.len > 0 && path.ptr[0] == '/') {
    return ms_string_from_span(path);
  }
  MsString current = ms_string_empty();
  if (!ms_dir_current(&current)) {
    return ms_string_from_span(path);
  }
  MsStrBuild joined = ms_strbuild_new();
  ms_path_append_joined(&joined, ms_string_span(&current), path);
  ms_string_release(&current);
  return ms_strbuild_finish(&joined);
}

static bool stage_stubs(LinkJob *job, MsStrBuild *why) {
  if (!ms_dir_make_temp(job->options->files, ms_span_of_text(".sdk-"), &job->scratch)) {
    ms_strbuild_append_text(why, "cannot stage the SDK stubs in ");
    ms_strbuild_append(why, job->options->files);
    return false;
  }
  FileList files = {0};
  MachoSymbols symbols = {0};
  bool ok = collect_symbols(job, true, &files, &symbols, why) &&
            link_sdk_stubs(ms_string_span(&job->scratch), &symbols, why);
  macho_free(&symbols);
  files_free(&files);
  return ok;
}

static void push_head(LinkJob *job) {
  link_job_push(job, job->options->lld);
  const char *const head[] = {"-flavor", "darwin", "-arch", ARCH, "-platform_version", "macos", "12.0", "12.0",
                              "-syslibroot"};
  for (size_t index = 0; index < MS_COUNT_OF(head); index++) {
    link_job_push_text(job, head[index]);
  }
  link_job_push(job, ms_string_span(&job->scratch));
  link_job_push_text(job, "-dead_strip");
  /* lld turns `adrp x10, got; ...; ldr x8, [x10, got]` into `adr x8` at the adrp, clobbering an x8 the code in
   * between still uses (a list of string literals stored a shift result). Workaround: remove once lld is
   * fixed (#1748). */
  link_job_push_text(job, "-ignore_optimization_hints");
  if (job->options->strip) {
    link_job_push_text(job, "-x");
  }
}

/* The directory part of `path` with its trailing separator, which `-oso_prefix` strips from debug names; a
 * sibling such as `stage-external` is never stripped. */
static MsSpan directory_with_separator(MsSpan path) {
  MsSpan parent = ms_path_parent(path);
  return parent.len == 0 ? parent : ms_span_of(parent.ptr, parent.len + 1);
}

bool link_host_prepare(LinkJob *job, MsStrBuild *why) {
  if (!stage_stubs(job, why)) {
    return false;
  }
  push_head(job);
  MsString object = absolute(job->request->object);
  MsString output = absolute(job->request->output);
  link_job_push_text(job, "-oso_prefix");
  link_job_push(job, directory_with_separator(ms_string_span(&object)));
  link_job_push_text(job, "-o");
  link_job_push(job, ms_string_span(&output));
  link_job_push(job, ms_string_span(&object));
  for (size_t index = 0; index < job->request->input_count; index++) {
    MsString input = absolute(job->request->inputs[index]);
    link_job_push(job, ms_string_span(&input));
    ms_string_release(&input);
  }
  const char *const tail[] = {"-lSystem", "-framework", "Security", "-framework", "CoreFoundation",
                              "-framework", "SystemConfiguration"};
  for (size_t index = 0; index < MS_COUNT_OF(tail); index++) {
    link_job_push_text(job, tail[index]);
  }
  ms_string_release(&object);
  ms_string_release(&output);
  return true;
}

/* The debug companion of the executable: macOS keeps source lines in a dSYM bundle once the object files are
 * removed. Without `dsymutil` (no Xcode tools) the executable still runs; it just has no source lines. */
static bool make_companion(LinkJob *job, MsStrBuild *why) {
  FileList files = {0};
  MachoSymbols symbols = {0};
  (void)collect_symbols(job, false, &files, &symbols, why);
  bool debug = symbols.debug;
  macho_free(&symbols);
  files_free(&files);
  if (!debug || !ms_process_find(ms_span_of_text("dsymutil"))) {
    return true;
  }
  MsString object = absolute(job->request->object);
  MsString output = absolute(job->request->output);
  MsStrBuild companion = ms_strbuild_new();
  ms_strbuild_append(&companion, ms_string_span(&output));
  ms_strbuild_append_text(&companion, ".dSYM");
  MsString companion_path = ms_strbuild_finish(&companion);
  MsStrBuild log = ms_strbuild_new();
  ms_strbuild_append(&log, ms_string_span(&output));
  ms_strbuild_append_text(&log, ".dsym.log");
  MsString log_path = ms_strbuild_finish(&log);
  MsSpan argv[] = {ms_span_of_text("dsymutil"), ms_string_span(&output), ms_span_of_text("-o"),
                   ms_string_span(&companion_path)};
  MsProcessSpec spec = {.argv = argv, .argc = MS_COUNT_OF(argv), .directory = ms_path_parent(ms_string_span(&object)),
                        .log_path = ms_string_span(&log_path)};
  bool ok = ms_process_run_logged(ms_span_of_text("dsymutil"), &spec, why);
  ms_path_remove(ms_string_span(&log_path));
  ms_string_release(&log_path);
  ms_string_release(&companion_path);
  ms_string_release(&object);
  ms_string_release(&output);
  return ok;
}

bool link_host_finish(LinkJob *job, bool linked, MsStrBuild *why) {
  if (!ms_string_is_empty(&job->scratch)) {
    ms_path_remove_tree(ms_string_span(&job->scratch));
  }
  return !linked || job->request->temporary || make_companion(job, why);
}

void link_host_advice(MsSpan detail, bool musl, MsStrBuild *out) {
  (void)musl;
  link_foreign_advice(detail, out);
}
