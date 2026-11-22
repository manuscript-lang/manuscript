/* driver/emit_command.c: `ms emit <file.ms> [-o file] [--ir]`. A single file or a project entry: loaded, checked,
 * lowered, and printed as MIR text or as LLVM IR. Status 0 is printed, 1 a diagnostic or a back-end failure, 2 usage. */
#include "driver/emit_command.h"

#include <stdio.h>

#include "base/cstr.h"
#include "base/file.h"
#include "compiler/lower/lower.h"
#include "compiler/mir/mir_pipeline.h"
#include "compiler/mir/mir_print.h"
#include "driver/backend.h"
#include "driver/checked_input.h"
#include "driver/invocation.h"

enum { STATUS_FAILED = 1 };

/* Lowers and prints MIR after elaboration, so what is shown is what the later passes read. */
static bool print_mir(MsCheckProgram *program, uint32_t entry, MsStrBuild *out, MsStrBuild *why) {
  MirModule module;
  mir_module_init(&module);
  bool ok = ms_lower_program(program, entry, &module, why);
  const MirPipelineOptions pipeline = {.verify = false, .checks = true};
  ok = ok && mir_pipeline_prepare(&module, &pipeline, why);
  if (ok) {
    mir_print_module(&module, out);
  }
  mir_module_free(&module);
  return ok;
}

/* Writes the text to the file `-o` names, or to standard output. */
static int write_output(MsSpan output, MsSpan text) {
  if (output.len == 0) {
    (void)fwrite(text.ptr, 1, text.len, stdout);
    return 0;
  }
  if (!ms_file_write(output, text)) {
    (void)fprintf(stderr, "cannot write %.*s\n", (int)output.len, (const char *)output.ptr);
    return STATUS_FAILED;
  }
  return 0;
}

static int emit_program(MsCheckedInput *checked, const MsInvocation *invocation, bool ir) {
  MsStrBuild out = ms_strbuild_new();
  MsStrBuild why = ms_strbuild_new();
  const BackendOptions options = {.optimize = false, .verify = true};
  const bool ok = ir ? ms_backend_ir(&checked->program, checked->entry, &options, &out, &why)
                     : print_mir(&checked->program, checked->entry, &out, &why);
  int status = STATUS_FAILED;
  if (ok) {
    status = write_output(invocation->output, ms_strbuild_span(&out));
  } else {
    const MsSpan text = ms_strbuild_span(&why);
    (void)fwrite(text.ptr, 1, text.len, stderr);
  }
  ms_strbuild_free(&out);
  ms_strbuild_free(&why);
  return status;
}

int ms_emit_command(int argc, char **argv) {
  bool ir = false;
  int kept = 0;
  for (int index = 0; index < argc; index++) {
    if (ms_cstr_equal(argv[index], "--ir")) {
      ir = true;
    } else {
      argv[kept++] = argv[index];
    }
  }
  MsArena arena = ms_arena_new();
  MsInvocation invocation = {0};
  int status = ms_invocation_parse(&arena, "emit", kept, argv, &invocation);
  if (status == 0) {
    MsCheckedInput checked = {0};
    if (ms_checked_input_load(&arena, &checked, invocation.filename, MS_INPUT_PROGRAM)) {
      status = emit_program(&checked, &invocation, ir);
    } else {
      status = invocation.json ? ms_checked_input_report_json(&checked) : ms_checked_input_report(&checked);
    }
    ms_checked_input_free(&checked);
  }
  ms_invocation_free(&invocation);
  ms_arena_free(&arena);
  return status;
}
