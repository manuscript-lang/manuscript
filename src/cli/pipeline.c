/* cli/pipeline.c: see pipeline.h. */
#include "cli/pipeline.h"

#include "base/env.h"
#include "base/file.h"
#include "base/path.h"
#include "base/process.h"
#include "compiler/link/link.h"
#include "compiler/link/object.h"
#include "cli/backend.h"
#include "ms_runtime_paths.h"

#if defined(_WIN32)
enum { LIST_SEPARATOR = ';' };
#else
enum { LIST_SEPARATOR = ':' };
#endif

enum { MAX_INPUTS = 256 };

static MsString error_text = {.low_bits = 0, .tagged = UINT64_C(1) << MS_STRING_TAG_SHIFT}; /* what `ms_pipeline_link` last reported */

/* The build's scratch files go beside the output, never in the working directory: a `--watch` run watches the directory
 * of its input, and files appearing there would rerun it forever. */
static MsSpan scratch_parent(MsSpan output) {
  const MsSpan parent = ms_path_parent(output);
  return parent.len == 0 ? ms_span_of_text(".") : parent;
}

static bool fail(MsSpan *error, const char *message, MsSpan detail) {
  MsStrBuild text = ms_strbuild_new();
  ms_strbuild_append_text(&text, message);
  ms_strbuild_append(&text, detail);
  ms_string_release(&error_text);
  error_text = ms_strbuild_finish(&text);
  *error = ms_string_span(&error_text);
  return false;
}

/* The environment variable `name` or, without it, `fallback`. */
static MsSpan setting(const char *name, const char *fallback, MsString *storage) {
  *storage = ms_string_empty();
  if (ms_env_get(name, storage) && ms_string_span(storage).len != 0) {
    return ms_string_span(storage);
  }
  return ms_span_of_text(fallback);
}

/* `MS_COUNT_OPS` set to anything but 0 counts operations in every build. */
static bool ops_from_environment(void) {
  MsString value = ms_string_empty();
  const bool set = ms_env_get("MS_COUNT_OPS", &value) && !ms_span_is_text(ms_string_span(&value), "0");
  ms_string_release(&value);
  return set;
}

/* A value of more leaves than this lives in a stack cell in a Debug build, so recursion through a function with a big
 * record holds the record once, not once per register it spreads over. `MS_WIDE_LEAVES` sets another number (0: never). */
#define DEFAULT_WIDE_LEAVES 4u

static uint32_t wide_leaves(bool debug) {
  MsString value = ms_string_empty();
  uint32_t number = debug ? DEFAULT_WIDE_LEAVES : 0;
  if (ms_env_get("MS_WIDE_LEAVES", &value) && ms_string_span(&value).len != 0) {
    const MsSpan text = ms_string_span(&value);
    number = 0;
    for (size_t at = 0; at < text.len && text.ptr[at] >= '0' && text.ptr[at] <= '9'; at++) {
      number = number * 10 + (uint32_t)(text.ptr[at] - '0');
    }
  }
  ms_string_release(&value);
  return number;
}

/* The `MS_RUNTIME` archives followed by the request's own files. */
static size_t collect_inputs(const MsLinkRequest *request, MsSpan list, MsSpan *inputs) {
  size_t count = 0;
  size_t start = 0;
  for (size_t at = 0; at <= list.len; at++) {
    if (at == list.len || list.ptr[at] == LIST_SEPARATOR) {
      if (at > start && count < MAX_INPUTS) {
        inputs[count++] = ms_span_of(list.ptr + start, at - start);
      }
      start = at + 1;
    }
  }
  for (size_t index = 0; index < request->link_count && count < MAX_INPUTS; index++) {
    inputs[count++] = request->link[index];
  }
  return count;
}

static bool make_object(const MsLinkRequest *request, const BackendProgram *program, MsSpan ir, MsSpan directory,
                        MsSpan opt, MsSpan llc, MsSpan object, MsSpan *error) {
  const bool debug = request->build_type == MS_BUILD_DEBUG;
  const ObjectOptions options = {.opt = opt, .llc = llc, .directory = directory, .speed = true, .debug = debug,
                                 .vectorize = !debug,
                                 .module = &program->module, .tables = &program->tables};
  MsStrBuild why = ms_strbuild_new();
  const bool ok = link_make_object(&options, ir, object, &why);
  if (!ok) {
    (void)fail(error, "", ms_strbuild_span(&why));
  }
  ms_strbuild_free(&why);
  return ok;
}

bool ms_pipeline_link(const MsLinkRequest *request, MsSpan *error) {
  MsStrBuild ir = ms_strbuild_new();
  MsStrBuild why = ms_strbuild_new();
  const BackendOptions backend = {.optimize = true, .verify = false,
                                  .tests = request->tests, .bench = request->bench,
                                  .count_ops = request->count_ops || ops_from_environment(),
                                  .wide_leaves = wide_leaves(request->build_type == MS_BUILD_DEBUG)};
  BackendProgram program;
  bool ok = ms_backend_compile(request->program, request->entry, &backend, &ir, &program, &why) ||
            fail(error, "", ms_strbuild_span(&why));
  MsString opt_storage, llc_storage, lld_storage, files_storage, runtime_storage;
  MsString scratch = ms_string_empty();
  const MsSpan opt = setting("MS_OPT", "opt", &opt_storage);
  const MsSpan llc = setting("MS_LLC", "llc", &llc_storage);
  const MsSpan lld = setting("MS_LLD", "lld", &lld_storage);
  const MsSpan files = setting("MS_FILES", MS_BUILD_FILES, &files_storage);
  const MsSpan runtime = setting("MS_RUNTIME", request->static_libc ? MS_BUILD_RUNTIME_STATIC : MS_BUILD_RUNTIME, &runtime_storage);
  MsSpan inputs[MAX_INPUTS];
  const size_t count = ok ? collect_inputs(request, runtime, inputs) : 0;
  if (ok && !ms_dir_make_temp(scratch_parent(request->output), ms_span_of_text(".ms-build-"), &scratch)) {
    ok = fail(error, "cannot make a scratch directory beside the output", ms_span_of(NULL, 0));
  }
  MsStrBuild object = ms_strbuild_new();
  if (ok) {
    ms_path_append_joined(&object, ms_string_span(&scratch), ms_span_of_text("program.o"));
    ok = make_object(request, &program, ms_strbuild_span(&ir), ms_string_span(&scratch), opt, llc, ms_strbuild_span(&object),
                     error);
  }
  if (ok) {
    const LinkOptions link = {.lld = lld, .llc = llc, .files = files, .strip = request->build_type == MS_BUILD_MINSIZEREL,
                              .musl = request->static_libc};
    const LinkRequest job = {.object = ms_strbuild_span(&object), .inputs = inputs, .input_count = count,
                             .output = request->output};
    MsStrBuild link_why = ms_strbuild_new();
    ok = link_executable(&link, &job, &link_why) || fail(error, "", ms_strbuild_span(&link_why));
    ms_strbuild_free(&link_why);
  }
  if (ms_string_span(&scratch).len != 0) {
    ms_path_remove_tree(ms_string_span(&scratch));
  }
  ms_string_release(&scratch);
  ms_strbuild_free(&object);
  ms_string_release(&runtime_storage);
  ms_string_release(&files_storage);
  ms_string_release(&lld_storage);
  ms_string_release(&llc_storage);
  ms_string_release(&opt_storage);
  ms_backend_program_free(&program);
  ms_strbuild_free(&why);
  ms_strbuild_free(&ir);
  return ok;
}
