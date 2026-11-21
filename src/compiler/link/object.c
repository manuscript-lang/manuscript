/* Owns the object step: write the IR, optimize it with `opt`, and have `llc` write the object (see object.h). */
#include "compiler/link/object.h"

#include "base/file.h"
#include "base/path.h"
#include "base/process.h"
#include "compiler/emit/emit.h"

/* Runs `argv` with its output in `log`; on failure `why` names `what` and holds the output. */
static bool run_tool(MsSpan what, const MsSpan *argv, size_t argc, MsSpan log, MsStrBuild *why) {
  MsProcessSpec spec = {.argv = argv, .argc = argc, .directory = ms_span_of(NULL, 0), .log_path = log};
  return ms_process_run_logged(what, &spec, why);
}

static MsString in_directory(MsSpan directory, const char *name) {
  MsStrBuild path = ms_strbuild_new();
  ms_path_append_joined(&path, directory, ms_span_of_text(name));
  return ms_strbuild_finish(&path);
}

/* `opt` over `input`, writing the bitcode to `bitcode`. */
static bool optimize(const ObjectOptions *options, MsSpan triple_flag, MsSpan input, MsSpan bitcode, MsSpan log,
                     MsStrBuild *why) {
  MsSpan argv[10];
  size_t argc = 0;
  argv[argc++] = options->opt;
  if (!options->vectorize) {
    argv[argc++] = ms_span_of_text("-vectorize-loops=false");
    argv[argc++] = ms_span_of_text("-vectorize-slp=false");
  }
  if (options->verify) {
    argv[argc++] = ms_span_of_text("-verify-each");
  }
  argv[argc++] = triple_flag;
  argv[argc++] = ms_span_of_text("-passes=default<O3>");
  argv[argc++] = input;
  argv[argc++] = ms_span_of_text("-o");
  argv[argc++] = bitcode;
  return run_tool(ms_span_of_text("opt (LLVM optimizer)"), argv, argc, log, why);
}

/* Whether the IR holds a function the emitter marked `optnone`, which is how a size tier shows. */
static bool has_optnone(MsSpan ir) {
  MsSpan needle = ms_span_of_text(" optnone");
  for (size_t at = 0; at + needle.len <= ir.len; at++) {
    if (ms_span_equal(ms_span_of(ir.ptr + at, needle.len), needle)) {
      return true;
    }
  }
  return false;
}

/* `llc` over `input`, writing the object. A module with an `optnone` function (a size tier, #3928) goes through
 * the fast code generator: llc's -O3 two-address and register-allocation passes are superlinear in one
 * function's size even when it is optnone. AArch64's -O0 GlobalISel Localizer pass is too (#5540), so the
 * selection-DAG path is used. */
static bool generate(const ObjectOptions *options, MsSpan triple_flag, MsSpan input, MsSpan object, MsSpan log,
                     bool size_tiered, MsStrBuild *why) {
  MsSpan argv[12];
  size_t argc = 0;
  argv[argc++] = options->llc;
  argv[argc++] = ms_span_of_text(options->speed && !size_tiered ? "-O3" : "-O0");
  if (size_tiered) {
    argv[argc++] = ms_span_of_text("-global-isel=0");
  }
  argv[argc++] = ms_span_of_text("-filetype=obj");
  argv[argc++] = ms_span_of_text("-relocation-model=pic");
  argv[argc++] = triple_flag;
#if defined(__x86_64__)
  argv[argc++] = ms_span_of_text("-align-loops=32");
  argv[argc++] = ms_span_of_text("-mcpu=x86-64");
#endif
  argv[argc++] = input;
  argv[argc++] = ms_span_of_text("-o");
  argv[argc++] = object;
  return run_tool(ms_span_of_text("llc (LLVM code generator)"), argv, argc, log, why);
}

bool link_make_object(const ObjectOptions *options, MsSpan ir, MsSpan object, MsStrBuild *why) {
  MsSpan triple = emit_host_triple();
  if (triple.len == 0) {
    ms_strbuild_append_text(why, "the C build is not ported to this host");
    return false;
  }
  MsStrBuild flag = ms_strbuild_new();
  ms_strbuild_append_text(&flag, "-mtriple=");
  ms_strbuild_append(&flag, triple);
  MsString triple_flag = ms_strbuild_finish(&flag);
  MsString text = in_directory(options->directory, "program.ll");
  MsString bitcode = in_directory(options->directory, "program.bc");
  MsString log = in_directory(options->directory, "tool.log");
  bool ok = ms_file_write(ms_string_span(&text), ir);
  if (!ok) {
    ms_strbuild_append_text(why, "cannot write ");
    ms_strbuild_append(why, ms_string_span(&text));
  }
  MsSpan input = ms_string_span(&text);
  if (ok && options->speed) {
    ok = optimize(options, ms_string_span(&triple_flag), input, ms_string_span(&bitcode), ms_string_span(&log), why);
    input = ms_string_span(&bitcode);
  }
  ok = ok && generate(options, ms_string_span(&triple_flag), input, object, ms_string_span(&log), has_optnone(ir), why);
  ms_path_remove(ms_string_span(&text));
  ms_path_remove(ms_string_span(&bitcode));
  ms_path_remove(ms_string_span(&log));
  ms_string_release(&text);
  ms_string_release(&bitcode);
  ms_string_release(&log);
  ms_string_release(&triple_flag);
  return ok;
}
