/* cli/pipeline.c: see pipeline.h. */
#define _POSIX_C_SOURCE 200809L

#include "cli/pipeline.h"

#include <stdio.h>
#include <stdlib.h>

#include "base/clock.h"
#include "base/env.h"
#include "base/file.h"
#include "base/path.h"
#include "base/process.h"
#include "compiler/link/link.h"
#include "compiler/link/llvm_inproc.h"
#include "compiler/link/object.h"
#include "cli/backend.h"
#include "cli/install_layout.h"
#include "compiler/emit/emit.h"
#include "ms_runtime_paths.h"

/* Last: on Windows uv.h brings in windows.h, whose MK_ALT macro would break the MIR header. */
#include <uv.h>

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
static MsSpan setting(const char *name, MsSpan fallback, MsString *storage) {
  *storage = ms_string_empty();
  if (ms_env_get(name, storage) && ms_string_span(storage).len != 0) {
    return ms_string_span(storage);
  }
  return fallback;
}

/* The shared LLVM library ms optimizes and generates code with: `MS_LLVM` names one, otherwise the one installed beside
 * ms (a build tree: the one `make build` fetched, MS_BUILD_LLVM). */
static MsSpan choose_llvm(MsSpan installed, MsString *storage) {
  const MsSpan named = setting("MS_LLVM", ms_span_of_text(""), storage);
  return named.len != 0 ? named : installed;
}

/* `MS_COUNT_OPS` set to anything but 0 counts operations in every build. */
static bool ops_from_environment(void) {
  MsString value = ms_string_empty();
  const bool set = ms_env_get("MS_COUNT_OPS", &value) && !ms_span_is_text(ms_string_span(&value), "0");
  ms_string_release(&value);
  return set;
}

/* A value of more leaves than this lives in a stack cell, so recursion through a function with a big record holds
 * the record once, not once per register it spreads over, and a copy is one `memcpy` where a leaf bag is a load and a
 * store per leaf (a 66-leaf record copied 125 times made 8000 stores in one yaml function, and LLVM spent 21 s on the
 * module). A Debug build hides the cells from LLVM (volatile leaf loads) so frames stay small; an optimized build
 * leaves them to `sroa` and `memcpyopt`. `MS_WIDE_LEAVES` sets another number (0: never). */
#define DEBUG_WIDE_LEAVES 4u
#define RELEASE_WIDE_LEAVES 8u

static uint32_t wide_leaves(bool debug) {
  MsString value = ms_string_empty();
  uint32_t number = debug ? DEBUG_WIDE_LEAVES : RELEASE_WIDE_LEAVES;
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

/* `MS_POISON_SLOTS` (any non-empty value): a stack cell is filled with 0xDD where its occupant is last read, so a view
 * that outlives its slot reads garbage in every build instead of what the optimizer reuses the cell for. It changes
 * the generated code, so use it to find such bugs, not to ship. */
static bool poison_from_environment(void) {
  MsString value = ms_string_empty();
  const bool on = ms_env_get("MS_POISON_SLOTS", &value) && ms_string_span(&value).len != 0;
  ms_string_release(&value);
  return on;
}

/* The `MS_RUNTIME` archives followed by the request's own files, after the `count` inputs already in `inputs` (the
 * objects of the program's other modules). */
static size_t collect_inputs(const MsLinkRequest *request, MsSpan list, MsSpan *inputs, size_t count) {
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

/* One module of the program on its way to an object, run on a thread of its own. */
typedef struct UnitJob {
  ObjectOptions options;
  MsSpan ir;
  MsSpan object;
  ObjectCode code;
  MsStrBuild why;
  bool ok;
} UnitJob;

static void generate_unit(void *arg) {
  UnitJob *const job = arg;
  job->ok = link_generate(&job->options, job->ir, job->object, &job->code, &job->why);
}

static void finish_unit(void *arg) {
  UnitJob *const job = arg;
  job->ok = link_finish(&job->options, job->object, &job->code, &job->why);
}

enum { THREAD_STACK_BYTES = 8 << 20 };

/* Runs `phase` on every job at once (the first on this thread) and returns when all are done. */
static void run_phase(UnitJob *jobs, uint32_t units, void (*phase)(void *)) {
  uv_thread_t threads[EMIT_MAX_UNITS];
  bool started[EMIT_MAX_UNITS] = {false};
  for (uint32_t unit = 1; unit < units; unit++) {
    /* LLVM recurses deep on a big function: a stack as large as the main thread's, not the system's default */
    const uv_thread_options_t stack = {.flags = UV_THREAD_HAS_STACK_SIZE, .stack_size = THREAD_STACK_BYTES};
    started[unit] = uv_thread_create_ex(&threads[unit], &stack, phase, &jobs[unit]) == 0;
  }
  phase(&jobs[0]);
  for (uint32_t unit = 1; unit < units; unit++) {
    if (started[unit]) {
      (void)uv_thread_join(&threads[unit]);
    } else {
      phase(&jobs[unit]); /* no thread to be had: this one runs here */
    }
  }
}

/* How many modules a program may be written as: `MS_UNITS` (and exactly that many, however small the program), or
 * one per core. A module below UNIT_BYTES of function text is not worth a thread: it parses the debug metadata again
 * and loses the folding of loads from the first module's static data. */
enum { UNIT_BYTES = 64 << 10 };

static void unit_limits(BackendOptions *backend) {
  MsString value = ms_string_empty();
  const bool set = ms_env_get("MS_UNITS", &value) && ms_string_span(&value).len != 0;
  uint32_t forced = 0;
  for (size_t at = 0; set && at < ms_string_span(&value).len && ms_string_span(&value).ptr[at] >= '0' &&
                      ms_string_span(&value).ptr[at] <= '9' && forced < 1000;
       at++) {
    forced = forced * 10 + (uint32_t)(ms_string_span(&value).ptr[at] - '0');
  }
  ms_string_release(&value);
  if (set) {
    backend->units = forced < 1 ? 1 : forced > EMIT_MAX_UNITS ? EMIT_MAX_UNITS : forced;
    backend->unit_bytes = 0;
    return;
  }
  const unsigned cores = uv_available_parallelism();
  backend->units = cores > EMIT_MAX_UNITS ? EMIT_MAX_UNITS : cores;
  backend->unit_bytes = UNIT_BYTES;
}

/* The objects of the program's modules, compiled at once: module `unit` goes to `objects[unit]`. */
static bool make_objects(const MsLinkRequest *request, const BackendProgram *program, const MsStrBuild *irs,
                         uint32_t units, MsSpan llvm,
                         const MsStrBuild *objects, MsSpan *error) {
  const bool debug = request->build_type == MS_BUILD_DEBUG;
  MsStrBuild load_why = ms_strbuild_new();
  const bool loaded = llvm_load(llvm, &load_why);
  if (!loaded) {
    (void)fail(error, "cannot load the LLVM library (MS_LLVM names it): ", ms_strbuild_span(&load_why));
  }
  ms_strbuild_free(&load_why);
  if (!loaded) {
    return false;
  }
  UnitJob jobs[EMIT_MAX_UNITS];
  for (uint32_t unit = 0; unit < units; unit++) {
    jobs[unit] = (UnitJob){.options = {.llvm = llvm, .speed = true,
                                      .debug = debug, .vectorize = !debug, .module = &program->module,
                                      .tables = &program->tables, .unit = unit, .units = units},
                           .ir = ms_strbuild_span(&irs[unit]), .object = ms_strbuild_span(&objects[unit]),
                           .why = ms_strbuild_new()};
  }
  /* LLVM's code generator reads process-wide options that differ between the phases, so no module starts the second
   * phase before all have finished the first. */
  run_phase(jobs, units, generate_unit);
  bool generated = true;
  for (uint32_t unit = 0; unit < units; unit++) {
    generated = generated && jobs[unit].ok;
  }
  if (generated) {
    run_phase(jobs, units, finish_unit);
  } else {
    for (uint32_t unit = 0; unit < units; unit++) {
      link_discard(&jobs[unit].code); /* the assembly of the modules that did generate */
    }
  }
  bool ok = true;
  MsSpan failure = ms_span_of(NULL, 0);
  for (uint32_t unit = 0; unit < units; unit++) {
    if (!jobs[unit].ok && ok) {
      ok = false;
      failure = ms_strbuild_span(&jobs[unit].why);
    }
  }
  if (!ok) {
    (void)fail(error, "", failure);
  }
  for (uint32_t unit = 0; unit < units; unit++) {
    ms_strbuild_free(&jobs[unit].why);
  }
  return ok;
}

/* The shared Cranelift library a Debug build generates code with, or empty for LLVM: `MS_CRANELIFT` names one (`off` or
 * `0` turns the route off), otherwise the one installed beside ms, or in a build tree the one `make build` fetched
 * (MS_BUILD_CRANELIFT), when the file exists. */
static MsSpan cranelift_library(void) {
  static MsString chosen;
  static bool known;
  if (known) {
    return ms_string_span(&chosen);
  }
  known = true;
  chosen = ms_string_empty();
  MsString named = ms_string_empty();
  if (ms_env_get("MS_CRANELIFT", &named)) {
    const MsSpan name = ms_string_span(&named);
    if (name.len != 0 && !ms_span_is_text(name, "off") && !ms_span_is_text(name, "0")) {
      chosen = ms_string_from_span(name);
    }
    ms_string_release(&named);
    return ms_string_span(&chosen);
  }
  MsStrBuild path = ms_strbuild_new();
  MsStrBuild root = ms_strbuild_new();
  if (ms_install_root(&root)) {
    ms_install_cranelift(ms_strbuild_span(&root), &path);
  } else {
    ms_strbuild_append_text(&path, MS_BUILD_CRANELIFT);
  }
  if (ms_strbuild_span(&path).len != 0 && ms_file_is_regular(ms_strbuild_span(&path))) {
    chosen = ms_strbuild_finish(&path);
  } else {
    ms_strbuild_free(&path);
  }
  ms_strbuild_free(&root);
  return ms_string_span(&chosen);
}

BackendOptions ms_pipeline_backend_options(const MsLinkRequest *request) {
  /* A Release build trusts the passes; a Debug build checks the finished module once. */
  return (BackendOptions){.optimize = true, .compact = request->build_type == MS_BUILD_DEBUG,
                          .verify_final = request->build_type == MS_BUILD_DEBUG,
                          .tests = request->tests, .bench = request->bench,
                          .count_ops = request->count_ops || ops_from_environment(),
                          .wide_leaves = wide_leaves(request->build_type == MS_BUILD_DEBUG),
                          .wide_hide = request->build_type == MS_BUILD_DEBUG,
                          .poison_slots = poison_from_environment(),
                          .cranelift = request->build_type == MS_BUILD_DEBUG ? cranelift_library() : ms_span_of(NULL, 0)};
}

/* `MS_BUILD_TIMES` set to anything but 0 prints how long each step of the back end took, in milliseconds. */
static bool times_from_environment(void) {
  MsString value = ms_string_empty();
  const bool set = ms_env_get("MS_BUILD_TIMES", &value) && !ms_span_is_text(ms_string_span(&value), "0");
  ms_string_release(&value);
  return set;
}

static void report_step(bool report, const char *step, int64_t *mark) {
  if (!report) {
    return;
  }
  const int64_t now = ms_clock_ns();
  (void)fprintf(stderr, "ms build: %-8s %7.1f ms\n", step, (double)(now - *mark) / 1e6);
  *mark = now;
}

bool ms_pipeline_link(const MsLinkRequest *request, MsSpan *error) {
  const bool report = times_from_environment();
  int64_t mark = ms_clock_ns();
  MsStrBuild ir[EMIT_MAX_UNITS] = {ms_strbuild_new()};
  uint32_t units = 1;
  MsStrBuild why = ms_strbuild_new();
  BackendOptions backend = ms_pipeline_backend_options(request);
  unit_limits(&backend);
  BackendProgram program;
  bool ok = ms_backend_compile(request->program, request->entry, &backend, ir, &units, &program, &why) ||
            fail(error, "", ms_strbuild_span(&why));
  report_step(report, "codegen", &mark);
  MsString lld_storage, files_storage, runtime_storage;
  MsStrBuild lld_installed = ms_strbuild_new();
  MsStrBuild files_installed = ms_strbuild_new(), runtime_installed = ms_strbuild_new();
  MsString scratch = ms_string_empty();
  /* Installed beside its files, ms uses those; a build tree keeps the paths it was built with and PATH. */
  MsStrBuild root = ms_strbuild_new();
  const bool installed = ms_install_root(&root);
  const MsSpan root_span = ms_strbuild_span(&root);
  MsSpan lld_fallback = ms_span_of_text("lld");
  MsSpan files_fallback = ms_span_of_text(MS_BUILD_FILES);
  MsSpan runtime_fallback = ms_span_of_text(request->static_libc ? MS_BUILD_RUNTIME_STATIC : MS_BUILD_RUNTIME);
  if (installed) {
    ms_install_tool(root_span, "lld", &lld_installed);
    ms_path_append_joined(&files_installed, root_span, ms_span_of_text("files"));
    (void)ms_install_runtime(root_span, request->static_libc, &runtime_installed);
    lld_fallback = ms_strbuild_span(&lld_installed);
    files_fallback = ms_strbuild_span(&files_installed);
    runtime_fallback = ms_strbuild_span(&runtime_installed);
  }
  MsString llvm_storage;
  MsStrBuild llvm_installed = ms_strbuild_new();
  if (installed) {
    ms_install_llvm(root_span, &llvm_installed);
  } else {
    ms_strbuild_append_text(&llvm_installed, MS_BUILD_LLVM); /* a build tree: the library `make build` fetched */
  }
  const MsSpan llvm = choose_llvm(ms_strbuild_span(&llvm_installed), &llvm_storage);
  const MsSpan lld = setting("MS_LLD", lld_fallback, &lld_storage);
  const MsSpan files = setting("MS_FILES", files_fallback, &files_storage);
  const MsSpan runtime = setting("MS_RUNTIME", runtime_fallback, &runtime_storage);
  if (ok && !ms_dir_make_temp(scratch_parent(request->output), ms_span_of_text(".ms-build-"), &scratch)) {
    ok = fail(error, "cannot make a scratch directory beside the output", ms_span_of(NULL, 0));
  }
  MsStrBuild object[EMIT_MAX_UNITS];
  for (uint32_t unit = 0; unit < units; unit++) {
    object[unit] = ms_strbuild_new();
    char name[32];
    snprintf(name, sizeof name, units > 1 ? "program.%u.o" : "program.o", unit);
    if (ok) {
      ms_path_append_joined(&object[unit], ms_string_span(&scratch), ms_span_of_text(name));
    }
  }
  MsSpan inputs[MAX_INPUTS];
  size_t count = 0;
  for (uint32_t unit = 1; ok && unit < units; unit++) {
    inputs[count++] = ms_strbuild_span(&object[unit]);
  }
  count = ok ? collect_inputs(request, runtime, inputs, count) : 0;
  if (ok && program.native) {
    ok = ms_file_write(ms_strbuild_span(&object[0]), ms_strbuild_span(&program.object)) ||
         fail(error, "cannot write the object file", ms_span_of(NULL, 0));
  } else if (ok) {
    ok = make_objects(request, &program, ir, units, llvm, object, error);
  }
  report_step(report, "object", &mark);
  if (ok) {
    const LinkOptions link = {.lld = lld, .llvm = llvm, .files = files, .strip = request->build_type == MS_BUILD_MINSIZEREL,
                              .quick = request->build_type == MS_BUILD_DEBUG,
                              .musl = request->static_libc};
    const LinkRequest job = {.object = ms_strbuild_span(&object[0]), .inputs = inputs, .input_count = count,
                             .output = request->output};
    MsStrBuild link_why = ms_strbuild_new();
    ok = link_executable(&link, &job, &link_why) || fail(error, "", ms_strbuild_span(&link_why));
    ms_strbuild_free(&link_why);
  }
  report_step(report, "link", &mark);
  if (ms_string_span(&scratch).len != 0) {
    ms_path_remove_tree(ms_string_span(&scratch));
  }
  ms_string_release(&scratch);
  for (uint32_t unit = 0; unit < units; unit++) {
    ms_strbuild_free(&object[unit]);
  }
  ms_string_release(&runtime_storage);
  ms_strbuild_free(&root);
  ms_strbuild_free(&runtime_installed);
  ms_strbuild_free(&files_installed);
  ms_strbuild_free(&lld_installed);
  ms_string_release(&files_storage);
  ms_string_release(&lld_storage);
  ms_string_release(&llvm_storage);
  ms_strbuild_free(&llvm_installed);
  ms_backend_program_free(&program);
  ms_strbuild_free(&why);
  for (uint32_t unit = 0; unit < units; unit++) {
    ms_strbuild_free(&ir[unit]);
  }
  return ok;
}
