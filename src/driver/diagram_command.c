/* driver/diagram_command.c: `ms diagram`. Port of `diagram` in crates/ms-cli/src/engine/tooling.rs. */
#include "driver/diagram_command.h"

#include <stdio.h>

#include "base/file.h"
#include "driver/checked_input.h"
#include "driver/invocation.h"
#include "tooling/inspect.h"

enum { STATUS_FAILED = 1 };

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

static int call_graph(MsArena *arena, const MsCheckedInput *checked, const MsInvocation *invocation) {
  MsInspection inspection = {0};
  ms_inspect_collect(arena, &checked->program, false, &inspection);
  MsStrBuild text = ms_strbuild_new();
  if (ms_span_is_text(invocation->format, "mermaid")) {
    ms_diagram_mermaid(&inspection, arena, &text);
  } else {
    ms_diagram_ascii(&inspection, arena, &text);
  }
  const int status = write_output(invocation->output, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  ms_inspection_free(&inspection);
  return status;
}

static int diagram(MsArena *arena, const MsCheckedInput *checked, const MsInvocation *invocation) {
  return call_graph(arena, checked, invocation);
}

int ms_diagram_command(int argc, char **argv) {
  MsArena arena = ms_arena_new();
  MsInvocation invocation = {0};
  int status = ms_invocation_parse(&arena, "diagram", argc, argv, &invocation);
  if (status == 0) {
    MsCheckedInput checked = {0};
    if (ms_checked_input_load(&arena, &checked, invocation.filename, MS_INPUT_ANALYSIS)) {
      status = diagram(&arena, &checked, &invocation);
    } else {
      status = invocation.json ? ms_checked_input_report_json(&checked) : ms_checked_input_report(&checked);
    }
    ms_checked_input_free(&checked);
  }
  ms_invocation_free(&invocation);
  ms_arena_free(&arena);
  return status;
}
