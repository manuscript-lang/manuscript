/* driver/diagram_command.c: `ms diagram`. Port of `diagram` in crates/ms-cli/src/engine/tooling.rs. */
#include "driver/diagram_command.h"

#include <stdio.h>

#include "base/file.h"
#include "driver/checked_input.h"
#include "compiler/syntax/diag_json.h"
#include "driver/invocation.h"
#include "tooling/inspect.h"
#include "tooling/views.h"

enum { STATUS_FAILED = 1, EXIT_USAGE = 2, EXIT_NOT_IMPLEMENTED = 70 };

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

/* The text of a view: the `--json` document, Mermaid, or the view's own or the generic outline. */
static void render_view(MsArena *arena, const MsFactModel *model, const MsInvocation *invocation, MsSpan view,
                        const MsViewNode *tree, MsStrBuild *text) {
  const int64_t depth = (int64_t)invocation->depth;
  if (invocation->json) {
    ms_strbuild_append_text(text, "{\n  \"format\": 1,\n  \"view\": ");
    ms_json_string(text, view);
    ms_strbuild_append_text(text, ",\n  \"entity\": ");
    ms_json_string(text, invocation->entity);
    ms_strbuild_append_text(text, ",\n  \"tree\": ");
    ms_view_json(tree, 1, text);
    ms_strbuild_append_text(text, "\n}\n\n"); /* the Rust CLI adds a newline to a line that already has one */
  } else if (ms_span_is_text(invocation->format, "mermaid")) {
    if (!ms_view_mermaid_custom(arena, model, view, invocation->entity, depth, text)) {
      ms_view_mermaid(tree, text);
    }
  } else if (!ms_view_ascii_custom(arena, model, view, invocation->entity, depth, text)) {
    ms_view_ascii(tree, text);
  }
}

static int view_command(MsArena *arena, MsCheckedInput *checked, const MsInvocation *invocation) {
  const MsSpan view = invocation->view.len == 0 ? ms_span_of_text("calls") : invocation->view;
  if (ms_span_is_text(invocation->format, "html")) {
    (void)fprintf(stderr, "ms diagram: --format html is not implemented in this build\n");
    return EXIT_NOT_IMPLEMENTED;
  }
  const MsFactModel model = ms_facts_collect(arena, &checked->program);
  MsViewNode *tree = NULL;
  MsSpan error = {0};
  if (!ms_build_view(arena, &model, view, invocation->entity, (int64_t)invocation->depth, &tree, &error)) {
    (void)fprintf(stderr, "ms diagram: %.*s\n", (int)error.len, (const char *)error.ptr);
    return EXIT_USAGE;
  }
  MsStrBuild text = ms_strbuild_new();
  render_view(arena, &model, invocation, view, tree, &text);
  const int status = write_output(invocation->output, ms_strbuild_span(&text));
  ms_strbuild_free(&text);
  return status;
}

static int diagram(MsArena *arena, MsCheckedInput *checked, const MsInvocation *invocation) {
  if (invocation->json || invocation->view.len > 0 || invocation->entity.len > 0 ||
      ms_span_is_text(invocation->format, "html")) {
    return view_command(arena, checked, invocation);
  }
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
