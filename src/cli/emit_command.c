/* cli/emit_command.c: `ms emit <file.ms> [-o file] [--ir]`. A single file or a project entry: loaded, checked,
 * lowered, and printed as MIR text or as LLVM IR. Status 0 is printed, 1 a diagnostic or a back-end failure, 2 usage. */
#include "cli/files.h"
#include "cli/emit_command.h"

#include <stdio.h>

#include "base/cstr.h"
#include "base/file.h"
#include "compiler/lower/lower.h"
#include "compiler/mir/mir_pipeline.h"
#include "compiler/mir/mir_print.h"
#include "cli/backend.h"
#include "tooling/checked_input.h"
#include "base/env.h"
#include "compiler/opt/opt.h"
#include "cli/invocation.h"
#include "cli/pipeline.h"

enum { STATUS_FAILED = 1 };

/* Lowers and prints MIR after elaboration, so what is shown is what the later passes read. */
static bool print_mir(MsCheckProgram *program, uint32_t entry, bool optimize, MsStrBuild *out, MsStrBuild *why) {
  MirModule module;
  mir_module_init(&module);
  bool ok = ms_lower_program(program, entry, &module, why);
  MsString raw = ms_string_empty();
  if (ok && ms_env_get("MS_EMIT_RAW", &raw) && ms_string_span(&raw).len != 0) {
    mir_print_module(&module, out); /* what lowering made, before elaboration: its scope markers and unwind exits */
    ms_string_release(&raw);
    mir_module_free(&module);
    return true;
  }
  ms_string_release(&raw);
  const MirPipelineOptions pipeline = {.verify = true, .checks = true};
  ok = ok && mir_pipeline_prepare(&module, &pipeline, why);
  ok = ok && (!optimize || mir_optimize(&module, false, true, why));
  if (ok) {
    mir_print_module(&module, out);
  }
  mir_module_free(&module);
  return ok;
}

static int emit_program(MsCheckedInput *checked, const MsInvocation *invocation, bool ir, bool optimize, bool tests) {
  MsStrBuild out = ms_strbuild_new();
  MsStrBuild why = ms_strbuild_new();
  /* With --opt the options are a Release build's, so the IR shown is what `opt` receives. */
  const MsLinkRequest release = {.build_type = MS_BUILD_RELEASE, .tests = tests};
  const BackendOptions options = optimize ? ms_pipeline_backend_options(&release)
                                          : (BackendOptions){.verify = true, .tests = tests};
  const bool ok = ir ? ms_backend_ir(&checked->program, checked->entry, &options, &out, &why)
                     : print_mir(&checked->program, checked->entry, optimize, &out, &why);
  int status = STATUS_FAILED;
  if (ok) {
    status = ms_cli_write_output(invocation->output, ms_strbuild_span(&out));
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
  bool optimize = false;
  bool tests = false;
  int kept = 0;
  for (int index = 0; index < argc; index++) {
    if (ms_cstr_equal(argv[index], "--ir")) {
      ir = true;
    } else if (ms_cstr_equal(argv[index], "--tests")) {
      tests = true;
    } else if (ms_cstr_equal(argv[index], "--opt")) {
      optimize = true;
    } else {
      argv[kept++] = argv[index];
    }
  }
  MsArena arena = ms_arena_new();
  MsInvocation invocation = {0};
  int status = ms_invocation_parse(&arena, "emit", kept, argv, &invocation);
  if (status == 0) {
    MsCheckedInput checked = {0};
    if (ms_checked_input_load(&arena, &checked, invocation.filename, tests ? MS_INPUT_TESTS : MS_INPUT_PROGRAM)) {
      status = emit_program(&checked, &invocation, ir, optimize, tests);
    } else {
      status = invocation.json ? ms_checked_input_report_json(&checked) : ms_checked_input_report(&checked);
    }
    ms_checked_input_free(&checked);
  }
  ms_invocation_free(&invocation);
  ms_arena_free(&arena);
  return status;
}
